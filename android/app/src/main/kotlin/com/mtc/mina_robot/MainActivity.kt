package com.mtc.mina_robot

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.SurfaceTexture
import android.hardware.Camera
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.AudioTrack
import android.media.MediaPlayer
import android.media.MediaRecorder
import android.media.audiofx.AcousticEchoCanceler
import android.media.audiofx.NoiseSuppressor
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.atomic.AtomicBoolean

class MainActivity : FlutterActivity() {
    companion object {
        private const val AUDIO_METHOD_CHANNEL = "com.mtc.mina_robot/audio"
        private const val MIC_STREAM_CHANNEL = "com.mtc.mina_robot/mic_stream"
        private const val PLATFORM_CHANNEL = "com.mtc.mina_robot/platform"
    }

    private var wakeLock: PowerManager.WakeLock? = null

    private val robotCmdReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action != "com.mtc.mina_visbot.ROBOT_CMD") return
            if (!VisbotMotorController.isInitialized && context != null) {
                VisbotMotorController.init(context)
            }
            val moveDir = intent.getStringExtra("move")
            val headAct = intent.getStringExtra("head")
            val dur = intent.getLongExtra("durationMs", 1500L)
            val btByte = intent.getIntExtra("btByte", -1)
            val btConnectAddr = intent.getStringExtra("btConnect")
            if (!moveDir.isNullOrEmpty()) {
                android.util.Log.i("VisbotMotor", "Broadcast move($moveDir) -> " + VisbotMotorController.move(moveDir, dur))
            }
            if (!headAct.isNullOrEmpty()) {
                android.util.Log.i("VisbotMotor", "Broadcast head($headAct) -> " + VisbotMotorController.head(headAct))
            }
            if (!btConnectAddr.isNullOrEmpty() && context != null) {
                RobonovaBluetoothController.connect(context, if (btConnectAddr == "auto") null else btConnectAddr) { ok, msg ->
                    android.util.Log.i("RobonovaBT", "Broadcast btConnect($btConnectAddr) -> ok=$ok, $msg")
                }
            }
            if (btByte in 40..108 && context != null) {
                RobonovaBluetoothController.sendActionByte(context, btByte, "DEC-$btByte") { ok, msg ->
                    android.util.Log.i("RobonovaBT", "Broadcast btByte($btByte) -> ok=$ok, $msg")
                }
            }
        }
    }

    // Thu âm 16kHz Mono PCM 16-bit (chuẩn chung cho cả Sherpa-ONNX và XiaoZhi Opus)
    private val isRecording = AtomicBoolean(false)
    private var audioRecord: AudioRecord? = null
    private var recordThread: Thread? = null
    private var micEventSink: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    // Phát âm thanh PCM thời gian thực từ XiaoZhi (16kHz hoặc 24kHz Mono 16-bit)
    private var audioTrack: AudioTrack? = null
    private var currentPlaySampleRate = 0
    private val playQueue = LinkedBlockingQueue<ByteArray>()
    private val isPlayerRunning = AtomicBoolean(false)
    private var playerThread: Thread? = null

    // Phát radio / nhạc qua URL (HLS m3u8, mp3, aac)
    private var mediaPlayer: MediaPlayer? = null
    private var mediaPrepared = false
    private var mediaWantPlaying = false
    private var mediaTitle = ""
    private var mediaUrl = ""
    private var mediaVolume = 1.0f

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        acquireWakeLock()

        // Nạp sẵn thư viện native Sherpa-ONNX & Opus (ARMv7 / ARM64)
        try {
            System.loadLibrary("onnxruntime")
            System.loadLibrary("sherpa-onnx-c-api")
        } catch (_: Throwable) {
        }
        try {
            System.loadLibrary("opus")
        } catch (_: Throwable) {
        }

        // Khởi tạo bộ điều khiển động cơ bánh xe & servo cổ UBTECH Visbot
        VisbotMotorController.init(this)
        try {
            registerReceiver(robotCmdReceiver, IntentFilter("com.mtc.mina_visbot.ROBOT_CMD"))
        } catch (_: Throwable) {
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // 1. Luồng PCM 16kHz liên tục từ mic lên Flutter
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, MIC_STREAM_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    micEventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    micEventSink = null
                }
            })

        // 2. Thu âm & phát PCM độ trễ thấp + âm lượng loa
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, AUDIO_METHOD_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startMic" -> result.success(startMicCapture())
                    "stopMic" -> {
                        stopMicCapture()
                        result.success(true)
                    }
                    "initPlayer" -> {
                        initPcmPlayer(call.argument<Int>("sampleRate") ?: 24000)
                        result.success(true)
                    }
                    "writePcm" -> {
                        val pcm = call.argument<ByteArray>("pcm")
                        if (pcm != null && pcm.isNotEmpty()) playQueue.offer(pcm)
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
                    "getVolume" -> result.success(getSystemVolume())
                    else -> result.notImplemented()
                }
            }

        // 3. Media, trình duyệt, camera, cài đặt hệ thống
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PLATFORM_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "mediaPlay" -> result.success(
                        mediaPlay(call.argument<String>("url") ?: "", call.argument<String>("title") ?: "")
                    )
                    "mediaPause" -> {
                        mediaWantPlaying = false
                        try {
                            if (mediaPrepared && mediaPlayer?.isPlaying == true) mediaPlayer?.pause()
                        } catch (_: Throwable) {
                        }
                        result.success(true)
                    }
                    "mediaResume" -> {
                        if (mediaPlayer != null) {
                            mediaWantPlaying = true
                            try {
                                if (mediaPrepared) mediaPlayer?.start()
                            } catch (_: Throwable) {
                            }
                        }
                        result.success(true)
                    }
                    "mediaStop" -> {
                        mediaStop()
                        result.success(true)
                    }
                    "mediaSetVolume" -> {
                        mediaVolume = ((call.argument<Double>("volume") ?: 1.0).toFloat()).coerceIn(0f, 1f)
                        try {
                            mediaPlayer?.setVolume(mediaVolume, mediaVolume)
                        } catch (_: Throwable) {
                        }
                        result.success(true)
                    }
                    "mediaState" -> result.success(
                        mapOf(
                            // "playing" = đang phát HOẶC đang tải để phát
                            "playing" to (mediaPlayer != null && mediaWantPlaying),
                            "title" to mediaTitle,
                            "url" to mediaUrl,
                        )
                    )
                    "openBrowser" -> {
                        val url = call.argument<String>("url") ?: "https://www.google.com"
                        startActivity(
                            Intent(this, BrowserActivity::class.java)
                                .putExtra(BrowserActivity.EXTRA_URL, url)
                                .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
                        )
                        result.success(true)
                    }
                    "closeBrowser" -> {
                        BrowserActivity.current?.get()?.finish()
                        result.success(true)
                    }
                    "takePhoto" -> takePhoto(result)
                    "openWifiSettings" -> {
                        safeStart(Intent(Settings.ACTION_WIFI_SETTINGS))
                        result.success(true)
                    }
                    "openSystemSettings" -> {
                        safeStart(Intent(Settings.ACTION_SETTINGS))
                        result.success(true)
                    }
                    "openHomeSettings" -> {
                        if (!safeStart(Intent(Settings.ACTION_HOME_SETTINGS))) {
                            safeStart(Intent(Settings.ACTION_SETTINGS))
                        }
                        result.success(true)
                    }
                    "isDefaultLauncher" -> {
                        val home = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME)
                        val info = packageManager.resolveActivity(home, PackageManager.MATCH_DEFAULT_ONLY)
                        result.success(info?.activityInfo?.packageName == packageName)
                    }
                    "robotStatus" -> {
                        if (!VisbotMotorController.isInitialized) {
                            VisbotMotorController.init(this)
                        }
                        result.success(
                            mapOf(
                                "ready" to VisbotMotorController.isInitialized,
                                "message" to VisbotMotorController.lastStatusMessage,
                            )
                        )
                    }
                    "robotMove" -> {
                        if (!VisbotMotorController.isInitialized) {
                            VisbotMotorController.init(this)
                        }
                        val dir = call.argument<String>("direction") ?: "forward"
                        val durationMs = (call.argument<Number>("durationMs")?.toLong()) ?: 1500L
                        val speed = call.argument<Number>("speed")?.toFloat()
                        result.success(VisbotMotorController.move(dir, durationMs, speed))
                    }
                    "robotHead" -> {
                        if (!VisbotMotorController.isInitialized) {
                            VisbotMotorController.init(this)
                        }
                        val action = call.argument<String>("action") ?: "center"
                        val angle = call.argument<Number>("angle")?.toFloat()
                        val speed = call.argument<Number>("speed")?.toFloat()
                        result.success(VisbotMotorController.head(action, angle, speed))
                    }
                    "robotStop" -> {
                        result.success(VisbotMotorController.stop())
                    }
                    "robotDance" -> {
                        if (!VisbotMotorController.isInitialized) {
                            VisbotMotorController.init(this)
                        }
                        result.success(VisbotMotorController.dance())
                    }
                    "openBluetoothSettings" -> {
                        if (!safeStart(Intent(Settings.ACTION_BLUETOOTH_SETTINGS))) {
                            safeStart(Intent(Settings.ACTION_SETTINGS))
                        }
                        result.success(true)
                    }
                    "btStatus" -> {
                        result.success(RobonovaBluetoothController.getStatus(this))
                    }
                    "btScan" -> {
                        val dur = (call.argument<Number>("durationMs")?.toLong()) ?: 4500L
                        RobonovaBluetoothController.scanDevices(this, dur) { st ->
                            result.success(st)
                        }
                    }
                    "btConnect" -> {
                        val addr = call.argument<String>("address")
                        RobonovaBluetoothController.connect(this, addr) { ok, msg ->
                            result.success(mapOf("ok" to ok, "message" to msg))
                        }
                    }
                    "btDisconnect" -> {
                        RobonovaBluetoothController.disconnect()
                        result.success(true)
                    }
                    "btSendAction" -> {
                        val asciiByte = call.argument<Int>("asciiByte") ?: 40
                        val label = call.argument<String>("label") ?: "K1"
                        RobonovaBluetoothController.sendActionByte(this, asciiByte, label) { ok, msg ->
                            result.success(mapOf("ok" to ok, "message" to msg))
                        }
                    }
                    "btSendSequence" -> {
                        val bytesList = call.argument<List<Int>>("bytes") ?: listOf(40)
                        val delaysList = call.argument<List<Number>>("delaysMs") ?: listOf(3000)
                        val label = call.argument<String>("label") ?: "Combo"
                        val bArr = bytesList.toIntArray()
                        val dArr = LongArray(delaysList.size) { idx -> delaysList[idx].toLong() }
                        RobonovaBluetoothController.sendActionSequence(this, bArr, dArr, label) { ok, msg ->
                            result.success(mapOf("ok" to ok, "message" to msg))
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun safeStart(intent: Intent): Boolean {
        return try {
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(intent)
            true
        } catch (_: Throwable) {
            false
        }
    }

    // ------------------------------------------------------------------ Media

    private fun mediaPlay(url: String, title: String): Boolean {
        if (url.isEmpty()) return false
        mediaStop()
        return try {
            val mp = MediaPlayer()
            mp.setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                    .build()
            )
            mp.setDataSource(url)
            mp.setVolume(mediaVolume, mediaVolume)
            mp.setOnPreparedListener {
                mediaPrepared = true
                if (mediaWantPlaying) it.start()
            }
            mp.setOnErrorListener { _, _, _ ->
                mediaStop()
                true
            }
            mp.setOnCompletionListener {
                mediaWantPlaying = false
            }
            mediaPlayer = mp
            mediaPrepared = false
            mediaWantPlaying = true
            mediaTitle = title
            mediaUrl = url
            mp.prepareAsync()
            true
        } catch (_: Throwable) {
            mediaStop()
            false
        }
    }

    private fun mediaStop() {
        mediaWantPlaying = false
        mediaPrepared = false
        val mp = mediaPlayer
        mediaPlayer = null
        mediaTitle = ""
        mediaUrl = ""
        try {
            mp?.stop()
        } catch (_: Throwable) {
        }
        try {
            mp?.release()
        } catch (_: Throwable) {
        }
    }

    // ------------------------------------------------------------------ Camera

    /** Chụp 1 ảnh từ camera trước (hoặc camera bất kỳ), thu nhỏ còn cạnh dài 1024px, JPEG 80%. */
    @Suppress("DEPRECATION")
    private fun takePhoto(result: MethodChannel.Result) {
        val replied = AtomicBoolean(false)
        fun reply(bytes: ByteArray?, error: String?) {
            if (!replied.compareAndSet(false, true)) return
            mainHandler.post {
                if (bytes != null) result.success(bytes) else result.error("CAMERA", error, null)
            }
        }

        var cameraId = 0
        val info = Camera.CameraInfo()
        for (i in 0 until Camera.getNumberOfCameras()) {
            Camera.getCameraInfo(i, info)
            if (info.facing == Camera.CameraInfo.CAMERA_FACING_FRONT) {
                cameraId = i
                break
            }
        }

        val camera = try {
            Camera.open(cameraId)
        } catch (e: Throwable) {
            reply(null, "Không mở được camera: ${e.message}")
            return
        }

        val texture = SurfaceTexture(10)
        fun release() {
            try {
                camera.stopPreview()
            } catch (_: Throwable) {
            }
            try {
                camera.release()
            } catch (_: Throwable) {
            }
            try {
                texture.release()
            } catch (_: Throwable) {
            }
        }

        try {
            val params = camera.parameters
            val best = params.supportedPictureSizes
                .filter { it.width <= 2048 }
                .maxByOrNull { it.width * it.height }
            if (best != null) params.setPictureSize(best.width, best.height)
            params.pictureFormat = android.graphics.ImageFormat.JPEG
            camera.parameters = params
            camera.setPreviewTexture(texture)
            camera.startPreview()
        } catch (e: Throwable) {
            release()
            reply(null, "Lỗi khởi động camera: ${e.message}")
            return
        }

        // Chờ camera cân bằng sáng rồi chụp
        mainHandler.postDelayed({
            try {
                camera.takePicture(null, null) { data, _ ->
                    release()
                    Thread {
                        try {
                            reply(shrinkJpeg(data), null)
                        } catch (e: Throwable) {
                            reply(null, "Lỗi xử lý ảnh: ${e.message}")
                        }
                    }.start()
                }
            } catch (e: Throwable) {
                release()
                reply(null, "Lỗi chụp ảnh: ${e.message}")
            }
        }, 900)

        // Hết thời gian chờ
        mainHandler.postDelayed({
            if (!replied.get()) {
                release()
                reply(null, "Camera không phản hồi")
            }
        }, 8000)
    }

    private fun shrinkJpeg(data: ByteArray): ByteArray {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(data, 0, data.size, bounds)
        var sample = 1
        while (maxOf(bounds.outWidth, bounds.outHeight) / (sample * 2) >= 1024) sample *= 2
        val bmp = BitmapFactory.decodeByteArray(data, 0, data.size, BitmapFactory.Options().apply {
            inSampleSize = sample
        }) ?: return data
        val out = ByteArrayOutputStream()
        bmp.compress(Bitmap.CompressFormat.JPEG, 80, out)
        bmp.recycle()
        return out.toByteArray()
    }

    // ------------------------------------------------------------------ Mic / PCM

    private fun startMicCapture(): Boolean {
        if (isRecording.get()) return true
        val sampleRate = 16000
        val channelConfig = AudioFormat.CHANNEL_IN_MONO
        val audioFormat = AudioFormat.ENCODING_PCM_16BIT
        val minBuf = AudioRecord.getMinBufferSize(sampleRate, channelConfig, audioFormat)
        if (minBuf <= 0) return false

        // 1920 bytes = 960 mẫu = 1 khung 60ms ở 16kHz (chuẩn Opus XiaoZhi)
        val frameBytes = 1920
        val bufferSize = maxOf(minBuf * 4, frameBytes * 12)

        val record = try {
            AudioRecord(MediaRecorder.AudioSource.MIC, sampleRate, channelConfig, audioFormat, bufferSize)
        } catch (_: Throwable) {
            AudioRecord(MediaRecorder.AudioSource.VOICE_RECOGNITION, sampleRate, channelConfig, audioFormat, bufferSize)
        }

        if (record.state != AudioRecord.STATE_INITIALIZED) {
            record.release()
            return false
        }

        try {
            record.startRecording()
        } catch (_: Throwable) {
            record.release()
            return false
        }
        if (record.recordingState != AudioRecord.RECORDSTATE_RECORDING) {
            // Mic đang bị ứng dụng khác giữ
            record.release()
            return false
        }

        audioRecord = record
        isRecording.set(true)
        val pendingMicPosts = AtomicBoolean(false)

        recordThread = Thread({
            val buf = ByteArray(frameBytes)
            while (isRecording.get()) {
                var offset = 0
                while (offset < frameBytes && isRecording.get()) {
                    val read = record.read(buf, offset, frameBytes - offset)
                    if (read > 0) offset += read else break
                }
                if (offset == frameBytes && isRecording.get()) {
                    // Chống dồn ứ hàng đợi Main Looper nếu UI thread đang bận
                    if (pendingMicPosts.compareAndSet(false, true)) {
                        val copy = buf.copyOf()
                        mainHandler.post {
                            pendingMicPosts.set(false)
                            micEventSink?.success(copy)
                        }
                    }
                }
            }
        }, "MinaMicThread").apply {
            priority = Thread.NORM_PRIORITY + 1
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
        if (audioTrack != null && currentPlaySampleRate == sampleRate && isPlayerRunning.get()) return
        stopPcmPlayerInternal()
        currentPlaySampleRate = sampleRate

        val minBuf = AudioTrack.getMinBufferSize(sampleRate, AudioFormat.CHANNEL_OUT_MONO, AudioFormat.ENCODING_PCM_16BIT)
        val bufferSize = maxOf(minBuf * 2, sampleRate / 2)

        val track = AudioTrack(
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

        audioTrack = track
        track.play()
        isPlayerRunning.set(true)

        playerThread = Thread({
            while (isPlayerRunning.get()) {
                try {
                    val chunk = playQueue.poll(50, java.util.concurrent.TimeUnit.MILLISECONDS)
                    if (chunk != null && chunk.isNotEmpty()) track.write(chunk, 0, chunk.size)
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
            wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "MinaVisbot::VoiceWakeLock").apply {
                acquire()
            }
        } catch (_: Throwable) {
        }
    }

    override fun onDestroy() {
        try {
            unregisterReceiver(robotCmdReceiver)
        } catch (_: Throwable) {
        }
        stopMicCapture()
        stopPcmPlayerInternal()
        mediaStop()
        try {
            if (wakeLock?.isHeld == true) wakeLock?.release()
        } catch (_: Throwable) {
        }
        super.onDestroy()
    }
}
