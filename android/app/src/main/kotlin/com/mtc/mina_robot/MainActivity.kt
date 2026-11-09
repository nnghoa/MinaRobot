package com.mtc.mina_robot

import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.AudioTrack
import android.media.MediaRecorder
import android.media.audiofx.AcousticEchoCanceler
import android.media.audiofx.NoiseSuppressor
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.atomic.AtomicBoolean

class MainActivity : FlutterActivity() {
    companion object {
        private const val AUDIO_METHOD_CHANNEL = "com.mtc.mina_robot/audio"
        private const val MIC_STREAM_CHANNEL = "com.mtc.mina_robot/mic_stream"
        private const val HARDWARE_CHANNEL = "com.mtc.mina_robot/hardware"
        private const val USB_SERIAL_CHANNEL = "com.mtc.mina_robot/usb_serial"
        private const val USB_SERIAL_EVENTS = "com.mtc.mina_robot/usb_serial_events"
    }

    private var usbSerial: UsbSerialBridge? = null

    private var wakeLock: PowerManager.WakeLock? = null

    // Thu âm 16kHz Mono PCM 16-bit (chuẩn chung cho cả Sherpa-ONNX và XiaoZhi Opus)
    private val isRecording = AtomicBoolean(false)
    private var audioRecord: AudioRecord? = null
    private var recordThread: Thread? = null
    private var micEventSink: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    // Phát âm thanh PCM thời gian thực từ XiaoZhi (mặc định 16kHz hoặc 24kHz Mono 16-bit)
    private var audioTrack: AudioTrack? = null
    private var currentPlaySampleRate = 0
    private val playQueue = LinkedBlockingQueue<ByteArray>()
    private val isPlayerRunning = AtomicBoolean(false)
    private var playerThread: Thread? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        acquireWakeLock()

        // Preload native Sherpa-ONNX & Opus cho kiến trúc ARMv7 (Allwinner A33) / ARM64
        try {
            System.loadLibrary("onnxruntime")
            System.loadLibrary("sherpa-onnx-c-api")
        } catch (_: Throwable) {
        }
        try {
            System.loadLibrary("opus")
        } catch (_: Throwable) {
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // 1. EventChannel đẩy luồng PCM 16kHz liên tục từ mảng 4 Mic (ZNJ Voice Array) lên Flutter
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, MIC_STREAM_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    micEventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    micEventSink = null
                }
            })

        // 2. MethodChannel điều khiển Thu âm & Phát PCM độ trễ thấp + Âm lượng loa
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, AUDIO_METHOD_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startMic" -> {
                        val ok = startMicCapture()
                        result.success(ok)
                    }
                    "stopMic" -> {
                        stopMicCapture()
                        result.success(true)
                    }
                    "initPlayer" -> {
                        val sampleRate = call.argument<Int>("sampleRate") ?: 24000
                        initPcmPlayer(sampleRate)
                        result.success(true)
                    }
                    "writePcm" -> {
                        val pcm = call.argument<ByteArray>("pcm")
                        if (pcm != null && pcm.isNotEmpty()) {
                            playQueue.offer(pcm)
                        }
                        result.success(true)
                    }
                    "stopPlayer" -> {
                        clearPcmPlayer()
                        result.success(true)
                    }
                    "setVolume" -> {
                        val percent = (call.argument<Int>("percent") ?: 80).coerceIn(0, 100)
                        setSystemVolume(percent)
                        result.success(percent)
                    }
                    "getVolume" -> {
                        result.success(getSystemVolume())
                    }
                    else -> result.notImplemented()
                }
            }

        // 3. MethodChannel hỗ trợ phần cứng Robot (Cấp quyền cổng UART trên board Allwinner root, quét cổng /dev/tty*, gửi Broadcast)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, HARDWARE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "listSerialPorts" -> {
                        val devDir = File("/dev")
                        val ports = devDir.listFiles()
                            ?.map { it.absolutePath }
                            ?.filter {
                                it.startsWith("/dev/ttyS") ||
                                    it.startsWith("/dev/ttyUSB") ||
                                    it.startsWith("/dev/ttyACM") ||
                                    it.startsWith("/dev/ttyMT") ||
                                    it.startsWith("/dev/ttyAMA")
                            }
                            ?.sorted()
                            ?: listOf("/dev/ttyS1", "/dev/ttyS0", "/dev/ttyS2", "/dev/ttyUSB0")
                        result.success(ports)
                    }
                    "prepareSerialPort" -> {
                        val path = call.argument<String>("path") ?: "/dev/ttyS1"
                        val baudrate = call.argument<Int>("baudrate") ?: 9600
                        val prepared = prepareSerialPortPermissions(path, baudrate)
                        result.success(prepared)
                    }
                    "sendRobotBroadcast" -> {
                        val action = call.argument<String>("action") ?: ""
                        val code = call.argument<String>("code") ?: ""
                        if (action.isNotEmpty()) {
                            val intent = Intent(action).apply {
                                putExtra("robonova_code", code)
                            }
                            sendBroadcast(intent)
                        }
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }

        // 4. Cổng serial qua USB OTG (CP2102 / CH340...) cho điện thoại Android nối mạch MR-C3024FX
        val usb = UsbSerialBridge(applicationContext)
        usbSerial = usb
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, USB_SERIAL_EVENTS)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    usb.setEventSink(events)
                }

                override fun onCancel(arguments: Any?) {
                    usb.setEventSink(null)
                }
            })
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, USB_SERIAL_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "list" -> result.success(usb.listDevices())
                    "open" -> usb.open(call.argument<Int>("baudrate") ?: 9600, result)
                    "write" -> {
                        val bytes = call.argument<ByteArray>("bytes")
                        result.success(bytes != null && usb.write(bytes))
                    }
                    "close" -> {
                        usb.close()
                        result.success(true)
                    }
                    "isOpen" -> result.success(usb.isOpen)
                    else -> result.notImplemented()
                }
            }
    }

    private fun startMicCapture(): Boolean {
        if (isRecording.get()) return true
        val sampleRate = 16000
        val channelConfig = AudioFormat.CHANNEL_IN_MONO
        val audioFormat = AudioFormat.ENCODING_PCM_16BIT
        val minBuf = AudioRecord.getMinBufferSize(sampleRate, channelConfig, audioFormat)
        if (minBuf <= 0) return false

        // 1920 bytes = 960 samples = đúng 1 khung 60ms ở 16kHz (chuẩn Opus XiaoZhi & rất mượt cho Sherpa-ONNX)
        val frameBytes = 1920
        val bufferSize = maxOf(minBuf * 2, frameBytes * 4)

        val record = try {
            AudioRecord(
                MediaRecorder.AudioSource.VOICE_RECOGNITION,
                sampleRate,
                channelConfig,
                audioFormat,
                bufferSize
            )
        } catch (_: Throwable) {
            AudioRecord(
                MediaRecorder.AudioSource.MIC,
                sampleRate,
                channelConfig,
                audioFormat,
                bufferSize
            )
        }

        if (record.state != AudioRecord.STATE_INITIALIZED) {
            record.release()
            return false
        }

        // Bật khử vọng (AEC) & lọc ồn phần cứng nếu chip âm thanh A33 / ZNJ hỗ trợ
        try {
            if (AcousticEchoCanceler.isAvailable()) {
                AcousticEchoCanceler.create(record.audioSessionId)?.enabled = true
            }
            if (NoiseSuppressor.isAvailable()) {
                NoiseSuppressor.create(record.audioSessionId)?.enabled = true
            }
        } catch (_: Throwable) {
        }

        audioRecord = record
        isRecording.set(true)
        record.startRecording()

        recordThread = Thread({
            val buf = ByteArray(frameBytes)
            while (isRecording.get()) {
                var offset = 0
                while (offset < frameBytes && isRecording.get()) {
                    val read = record.read(buf, offset, frameBytes - offset)
                    if (read > 0) {
                        offset += read
                    } else {
                        break
                    }
                }
                if (offset == frameBytes && isRecording.get()) {
                    val copy = buf.copyOf()
                    mainHandler.post {
                        micEventSink?.success(copy)
                    }
                }
            }
        }, "MinaMicThread").apply {
            priority = Thread.MAX_PRIORITY
            start()
        }
        return true
    }

    private fun stopMicCapture() {
        isRecording.set(false)
        try {
            recordThread?.join(300)
        } catch (_: Throwable) {
        }
        recordThread = null
        try {
            audioRecord?.stop()
        } catch (_: Throwable) {
        }
        try {
            audioRecord?.release()
        } catch (_: Throwable) {
        }
        audioRecord = null
    }

    private fun initPcmPlayer(sampleRate: Int) {
        if (audioTrack != null && currentPlaySampleRate == sampleRate && isPlayerRunning.get()) {
            return
        }
        stopPcmPlayerInternal()
        currentPlaySampleRate = sampleRate

        val minBuf = AudioTrack.getMinBufferSize(
            sampleRate,
            AudioFormat.CHANNEL_OUT_MONO,
            AudioFormat.ENCODING_PCM_16BIT
        )
        val bufferSize = maxOf(minBuf * 2, sampleRate / 2)

        val track = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            AudioTrack(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build(),
                AudioFormat.Builder()
                    .setSampleRate(sampleRate)
                    .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                    .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                    .build(),
                bufferSize,
                AudioTrack.MODE_STREAM,
                AudioManager.AUDIO_SESSION_ID_GENERATE
            )
        } else {
            @Suppress("DEPRECATION")
            AudioTrack(
                AudioManager.STREAM_MUSIC,
                sampleRate,
                AudioFormat.CHANNEL_OUT_MONO,
                AudioFormat.ENCODING_PCM_16BIT,
                bufferSize,
                AudioTrack.MODE_STREAM
            )
        }

        audioTrack = track
        track.play()
        isPlayerRunning.set(true)

        playerThread = Thread({
            while (isPlayerRunning.get()) {
                try {
                    val chunk = playQueue.poll(50, java.util.concurrent.TimeUnit.MILLISECONDS)
                    if (chunk != null && chunk.isNotEmpty()) {
                        track.write(chunk, 0, chunk.size)
                    }
                } catch (_: InterruptedException) {
                    break
                } catch (_: Throwable) {
                }
            }
        }, "MinaPcmPlayerThread").apply {
            priority = Thread.MAX_PRIORITY
            start()
        }
    }

    private fun clearPcmPlayer() {
        playQueue.clear()
        try {
            audioTrack?.pause()
            audioTrack?.flush()
            audioTrack?.play()
        } catch (_: Throwable) {
        }
    }

    private fun stopPcmPlayerInternal() {
        isPlayerRunning.set(false)
        playQueue.clear()
        try {
            playerThread?.interrupt()
            playerThread?.join(200)
        } catch (_: Throwable) {
        }
        playerThread = null
        try {
            audioTrack?.stop()
        } catch (_: Throwable) {
        }
        try {
            audioTrack?.release()
        } catch (_: Throwable) {
        }
        audioTrack = null
    }

    private fun prepareSerialPortPermissions(path: String, baudrate: Int): Boolean {
        val file = File(path)
        val sttyCmd = "(stty -F $path $baudrate cs8 -cstopb -parenb cread clocal -crtscts raw -echo || " +
            "busybox stty -F $path $baudrate cs8 -cstopb -parenb cread clocal raw -echo)"
        if (file.canRead() && file.canWrite()) {
            try {
                Runtime.getRuntime().exec(arrayOf("sh", "-c", sttyCmd)).waitFor()
            } catch (_: Throwable) {
            }
            return true
        }
        // Các board Android nhúng Allwinner A33 thường có sẵn su để cấp quyền /dev/ttyS* và cấu hình 8N1 2 chiều
        return try {
            val cmd = "chmod 666 $path && $sttyCmd"
            val proc = Runtime.getRuntime().exec(arrayOf("su", "-c", cmd))
            proc.waitFor()
            file.canRead() && file.canWrite()
        } catch (_: Throwable) {
            file.canWrite()
        }
    }

    private fun setSystemVolume(percent: Int) {
        val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val maxVol = am.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
        val target = ((percent / 100.0) * maxVol).toInt().coerceIn(0, maxVol)
        am.setStreamVolume(AudioManager.STREAM_MUSIC, target, 0)
    }

    private fun getSystemVolume(): Int {
        val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val maxVol = am.getStreamMaxVolume(AudioManager.STREAM_MUSIC).coerceAtLeast(1)
        val cur = am.getStreamVolume(AudioManager.STREAM_MUSIC)
        return ((cur * 100.0) / maxVol).toInt()
    }

    private fun acquireWakeLock() {
        try {
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = pm.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "MinaRobot::BackgroundVoiceWakeLock"
            ).apply {
                acquire()
            }
        } catch (_: Throwable) {
        }
    }

    override fun onDestroy() {
        usbSerial?.dispose()
        usbSerial = null
        stopMicCapture()
        stopPcmPlayerInternal()
        try {
            if (wakeLock?.isHeld == true) {
                wakeLock?.release()
            }
        } catch (_: Throwable) {
        }
        super.onDestroy()
    }
}
