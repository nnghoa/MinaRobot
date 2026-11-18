package com.mtc.minalilybridge

import android.annotation.SuppressLint
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.MediaRecorder
import android.media.ToneGenerator
import android.media.audiofx.AcousticEchoCanceler
import android.media.audiofx.NoiseSuppressor
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.os.Process
import android.util.Log
import java.io.File
import java.io.FileOutputStream
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.atomic.AtomicBoolean

class MinaBridgeService : Service() {

    companion object {
        private const val TAG = "MinaBridgeSvc"
        private const val NOTIF_CHANNEL_ID = "mina_lily_bridge_channel"
        private const val NOTIF_ID = 1808
        private const val CURRENT_KW_SCHEMA_VERSION = 3

        const val PREFS_NAME = "mina_lily_bridge_prefs"
        const val KEY_ENABLED = "listening_enabled"
        const val KEY_THRESHOLD = "kws_threshold"
        const val KEY_SCORE = "kws_score"
        const val KEY_AUTO_BOOT = "auto_boot"
        const val KEY_PLAY_BEEP = "play_beep"
        const val KEY_NOD_ON_WAKE = "nod_on_wake"
        const val KEY_KW_SCHEMA_VER = "kw_schema_ver"

        const val ACTION_START_LISTENING = "com.mtc.mina_lily_bridge.START_LISTENING"
        const val ACTION_PAUSE_LISTENING = "com.mtc.mina_lily_bridge.PAUSE_LISTENING"
        const val ACTION_RELOAD_CONFIG = "com.mtc.mina_lily_bridge.RELOAD_CONFIG"
        const val ACTION_WAKE_LILY_NOW = "com.mtc.mina_lily_bridge.WAKE_LILY_NOW"
        const val ACTION_YIELD_30S = "com.mtc.mina_lily_bridge.YIELD_30S"
        const val ACTION_MOTOR_CMD = "com.mtc.mina_lily_bridge.MOTOR_CMD"
        const val ACTION_UI_UPDATE = "com.mtc.mina_lily_bridge.UI_UPDATE"

        const val LILY_PKG = "com.sensornotes.xiaozhi"
        const val LILY_WAKE_ACTION = "com.hy.honeybot.launch.action"

        const val STATE_PAUSED = "PAUSED"
        const val STATE_LISTENING = "LISTENING"
        const val STATE_YIELDED = "YIELDED"
        const val STATE_ERROR = "ERROR"

        // Bộ từ khóa mở rộng v3: Gọi Lily VIP + Khẩu lệnh chuyển động Offline (Tiến, Lùi, Quay trái/phải, Gật đầu, Nhảy, Dừng)
        val DEFAULT_KEYWORDS_V2 = """
HH AH0 L OW1 M IY1 N AA0 @Hello_Mina
HH EH0 L OW1 M IY1 N AA0 @Hello_Mina
HH AH0 L OW1 M IY1 N AH0 @Hello_Mina
HH EH0 L OW1 M IY1 N AH0 @Hello_Mina
HH EY1 L OW1 M IY1 N AA0 @Hello_Mina
HH EY1 L OW1 M IY1 N AH0 @Hello_Mina
HH EH1 L OW0 M IY1 N AA0 @Hello_Mina
HH EH1 L OW0 M IY1 N AH0 @Hello_Mina
h ā l ōu m ī n ā @Hello_Mina
h ēi l ōu m ī n ā @Hello_Mina
h é l ōu m ī n ā @Hello_Mina
h è l ōu m ī n ā @Hello_Mina
HH AY1 M IY1 N AA0 @Hi_Mina
HH AY1 M IY1 N AH0 @Hi_Mina
h āi m ī n ā @Hi_Mina
x īn ch áo m ī n ā @Xin_chào_Mina
x īn ch ào m ī n ā @Xin_chào_Mina
S IH1 N CH AW1 M IY1 N AA0 @Xin_chào_Mina
ch áo m ī n ā @Chào_Mina
ch áo m í n a @Chào_Mina
ch ào m ī n ā @Chào_Mina
q iáo m ī n ā @Chào_Mina
x iǎo m ī n ā @Chào_Mina
CH AW1 M IY1 N AA0 @Chào_Mina
CH AW1 M IY1 N AH0 @Chào_Mina
HH EY1 M IY1 N AA0 @Hey_Mina
HH EY1 M IY1 N AH0 @Hey_Mina
h ēi m ī n ā @Hey_Mina
m ī n ā ēi @Mina_ơi
m í n a āi @Mina_ơi
M IY1 N AA0 ER1 @Mina_ơi
M IY1 N AH0 OY1 @Mina_ơi
m ī n ā @Mina
m í n á @Mina
m ì n à @Mina
m ī n a @Mina
m í n a @Mina
m i n a @Mina
m ǐ n ǎ @Mina
M IY1 N AA0 @Mina
M IY1 N AH0 @Mina
M IY0 N AA0 @Mina
M IH1 N AH0 @Mina
M IH0 N AH0 @Mina
m ī n ā t iàn l ēn @Motor_Forward
m ī n ā d iàn l ēn @Motor_Forward
m ī n ā ch ài d èi @Motor_Forward
M IY1 N AA0 T IY1 N L EH1 N @Motor_Forward
M IY1 N AA0 CH AY1 T ER1 Y @Motor_Forward
m ī n ā l uì l ài @Motor_Backward
m ī n ā ch ài l uí @Motor_Backward
M IY1 N AA0 L UW1 Y L AY1 @Motor_Backward
M IY1 N AA0 CH AY1 L UW1 Y @Motor_Backward
m ī n ā g uāi zh ái @Motor_Left
m ī n ā k uāi ch ái @Motor_Left
M IY1 N AA0 K W AY1 CH AY1 @Motor_Left
m ī n ā g uāi f ǎi @Motor_Right
m ī n ā k uāi f ái @Motor_Right
M IY1 N AA0 K W AY1 F AY1 @Motor_Right
m ī n ā g è d òu @Motor_Nod
M IY1 N AA0 G AH1 T D AW1 @Motor_Nod
m ī n ā n iǎ d ī @Motor_Dance
m ī n ā n iá m uá @Motor_Dance
M IY1 N AA0 N AY1 D IY1 @Motor_Dance
M IY1 N AA0 D AE1 N S @Motor_Dance
m ī n ā y íng l ài @Mina_dừng_lại
m ī n ā r éng l ài @Mina_dừng_lại
M IY1 N AA0 Z IH1 NG L AY1 @Mina_dừng_lại
M IY1 N AA0 Y IH1 NG L AY1 @Mina_dừng_lại
""".trimIndent() + "\n"

        @Volatile
        var currentState: String = STATE_PAUSED
            private set

        @Volatile
        var statusDetail: String = "Chưa khởi động"
            private set

        @Volatile
        var lastTriggerInfo: String = "Chưa có lượt gọi nào"
            private set

        @Volatile
        var lastPeakLevel: Int = 0
            private set

        fun getKeywordsFile(context: Context): File {
            val dir = File(context.filesDir, "mina_kws")
            if (!dir.exists()) dir.mkdirs()
            return File(dir, "keywords.txt")
        }
    }

    private val workerRunning = AtomicBoolean(false)
    private val reloadRequested = AtomicBoolean(false)
    private val manualWakeRequested = AtomicBoolean(false)
    @Volatile
    private var forceYieldUntilMs: Long = 0L

    private var orchestratorThread: Thread? = null
    private var mcpServer: MinaLocalMcpServer? = null
    private var cpuWakeLock: PowerManager.WakeLock? = null
    private lateinit var audioManager: AudioManager
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onCreate() {
        super.onCreate()
        audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        createNotificationChannel()
        startForeground(NOTIF_ID, buildNotification("Đang khởi tạo cầu nối Mina -> Lily VIP..."))

        acquireCpuWakeLock()
        VisbotMotorController.onFrontSensorPressed = { sensorId ->
            Log.i(TAG, "Physical Visbot touch/button pressed ($sensorId) -> waking Lily VIP")
            if (workerRunning.get()) {
                manualWakeRequested.set(true)
            } else {
                triggerLilyConversation("Chạm nút thân máy ($sensorId)")
            }
        }
        VisbotMotorController.init(applicationContext)
        mcpServer = MinaLocalMcpServer(applicationContext).also { it.start() }

        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        if (prefs.getBoolean(KEY_ENABLED, true)) {
            startWorkerIfNeeded()
        } else {
            updateState(STATE_PAUSED, "Đang tạm dừng nghe từ khóa")
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        when (intent?.action) {
            ACTION_PAUSE_LISTENING -> {
                prefs.edit().putBoolean(KEY_ENABLED, false).apply()
                stopWorker()
                updateState(STATE_PAUSED, "Đã tạm dừng nghe (Mic nhường hoàn toàn)")
            }
            ACTION_START_LISTENING -> {
                prefs.edit().putBoolean(KEY_ENABLED, true).apply()
                forceYieldUntilMs = 0L
                startWorkerIfNeeded()
            }
            ACTION_RELOAD_CONFIG -> {
                reloadRequested.set(true)
                if (prefs.getBoolean(KEY_ENABLED, true)) {
                    startWorkerIfNeeded()
                }
            }
            ACTION_YIELD_30S -> {
                forceYieldUntilMs = System.currentTimeMillis() + 30_000L
                Log.i(TAG, "User requested 30s mic yield")
            }
            ACTION_WAKE_LILY_NOW -> {
                if (workerRunning.get()) {
                    manualWakeRequested.set(true)
                } else {
                    triggerLilyConversation("Nút gọi trực tiếp")
                }
            }
            ACTION_MOTOR_CMD -> {
                if (!VisbotMotorController.isInitialized) {
                    VisbotMotorController.init(applicationContext)
                }
                val mv = intent.getStringExtra("move")
                val hd = intent.getStringExtra("head")
                val dur = intent.getLongExtra("durationMs", 1100L)
                if (!mv.isNullOrEmpty()) {
                    val res = VisbotMotorController.move(mv, dur)
                    Log.i(TAG, "ACTION_MOTOR_CMD move($mv) -> $res")
                }
                if (!hd.isNullOrEmpty()) {
                    val res = VisbotMotorController.head(hd)
                    Log.i(TAG, "ACTION_MOTOR_CMD head($hd) -> $res")
                }
            }
            else -> {
                if (prefs.getBoolean(KEY_ENABLED, true)) {
                    startWorkerIfNeeded()
                }
            }
        }
        return START_STICKY
    }

    override fun onDestroy() {
        stopWorker()
        mcpServer?.stop()
        mcpServer = null
        releaseCpuWakeLock()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun acquireCpuWakeLock() {
        try {
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            cpuWakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "mina_lily_bridge:kws_cpu").apply {
                setReferenceCounted(false)
                acquire()
            }
        } catch (_: Throwable) {
        }
    }

    private fun releaseCpuWakeLock() {
        try {
            if (cpuWakeLock?.isHeld == true) cpuWakeLock?.release()
        } catch (_: Throwable) {
        }
        cpuWakeLock = null
    }

    private fun startWorkerIfNeeded() {
        if (workerRunning.getAndSet(true)) return
        val t = Thread({ runOrchestratorLoop() }, "MinaKwsOrchestrator")
        orchestratorThread = t
        t.start()
    }

    private fun stopWorker() {
        workerRunning.set(false)
        orchestratorThread?.interrupt()
        try {
            orchestratorThread?.join(1500)
        } catch (_: Throwable) {
        }
        orchestratorThread = null
    }

    private fun ensureModelsExtracted(): File {
        val modelDir = File(filesDir, "mina_kws")
        if (!modelDir.exists()) modelDir.mkdirs()

        val binaryAssets = listOf(
            "encoder.int8.onnx",
            "decoder.onnx",
            "joiner.int8.onnx",
            "tokens.txt"
        )
        for (name in binaryAssets) {
            val dst = File(modelDir, name)
            if (!dst.exists() || dst.length() == 0L) {
                assets.open("models/kws/$name").use { input ->
                    FileOutputStream(dst).use { out ->
                        input.copyTo(out)
                        out.flush()
                    }
                }
            }
        }

        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val savedVer = prefs.getInt(KEY_KW_SCHEMA_VER, 0)
        val kwFile = File(modelDir, "keywords.txt")
        if (!kwFile.exists() || kwFile.length() == 0L || savedVer < CURRENT_KW_SCHEMA_VERSION) {
            kwFile.writeText(DEFAULT_KEYWORDS_V2, Charsets.UTF_8)
            prefs.edit()
                .putInt(KEY_KW_SCHEMA_VER, CURRENT_KW_SCHEMA_VERSION)
                .putFloat(KEY_SCORE, 1.8f)
                .putFloat(KEY_THRESHOLD, 0.15f)
                .apply()
            Log.i(TAG, "Upgraded keywords.txt to v$CURRENT_KW_SCHEMA_VERSION (Hello Mina + 0.15 threshold)")
        }
        return modelDir
    }

    private fun createSpotterFromPrefs(modelDir: File): Long {
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val score = prefs.getFloat(KEY_SCORE, 1.8f)
        val threshold = prefs.getFloat(KEY_THRESHOLD, 0.15f)
        return MinaKwsNative.nativeCreate(
            File(modelDir, "encoder.int8.onnx").absolutePath,
            File(modelDir, "decoder.onnx").absolutePath,
            File(modelDir, "joiner.int8.onnx").absolutePath,
            File(modelDir, "tokens.txt").absolutePath,
            File(modelDir, "keywords.txt").absolutePath,
            score,
            threshold
        )
    }

    private fun hasExternalRecorder(mySessionId: Int): Boolean {
        return try {
            val cfgs = audioManager.activeRecordingConfigurations
            cfgs.any { cfg -> cfg.clientAudioSessionId != mySessionId }
        } catch (_: Throwable) {
            false
        }
    }

    @SuppressLint("MissingPermission")
    private fun openMic(): Triple<AudioRecord?, AcousticEchoCanceler?, NoiseSuppressor?> {
        val sampleRate = 16000
        val minBuf = AudioRecord.getMinBufferSize(
            sampleRate,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT
        )
        if (minBuf <= 0) return Triple(null, null, null)
        // Bộ đệm 64KB (~2 giây PCM16 @ 16kHz) đảm bảo AudioFlinger trên MT8167S không bao giờ tràn bộ đệm
        val bufSize = (minBuf * 8).coerceAtLeast(65536)

        return try {
            // Ưu tiên AudioSource.MIC (source=1) giống hệt Lily & Mina_Visbot để kích hoạt mạch khuếch đại Mic phần cứng
            val rec = try {
                AudioRecord(
                    MediaRecorder.AudioSource.MIC,
                    sampleRate,
                    AudioFormat.CHANNEL_IN_MONO,
                    AudioFormat.ENCODING_PCM_16BIT,
                    bufSize
                )
            } catch (_: Throwable) {
                AudioRecord(
                    MediaRecorder.AudioSource.VOICE_RECOGNITION,
                    sampleRate,
                    AudioFormat.CHANNEL_IN_MONO,
                    AudioFormat.ENCODING_PCM_16BIT,
                    bufSize
                )
            }

            if (rec.state != AudioRecord.STATE_INITIALIZED) {
                rec.release()
                return Triple(null, null, null)
            }
            var aec: AcousticEchoCanceler? = null
            var ns: NoiseSuppressor? = null
            try {
                if (AcousticEchoCanceler.isAvailable()) {
                    aec = AcousticEchoCanceler.create(rec.audioSessionId)?.apply { enabled = true }
                }
            } catch (_: Throwable) {
            }
            try {
                if (NoiseSuppressor.isAvailable()) {
                    ns = NoiseSuppressor.create(rec.audioSessionId)?.apply { enabled = true }
                }
            } catch (_: Throwable) {
            }
            rec.startRecording()
            if (rec.recordingState != AudioRecord.RECORDSTATE_RECORDING) {
                try { aec?.release() } catch (_: Throwable) {}
                try { ns?.release() } catch (_: Throwable) {}
                rec.release()
                return Triple(null, null, null)
            }
            Log.i(TAG, "Opened MIC (session=${rec.audioSessionId}, buf=$bufSize)")
            Triple(rec, aec, ns)
        } catch (e: Throwable) {
            Log.e(TAG, "openMic failed: ${e.message}")
            Triple(null, null, null)
        }
    }

    private fun closeMic(rec: AudioRecord?, aec: AcousticEchoCanceler?, ns: NoiseSuppressor?) {
        try { aec?.release() } catch (_: Throwable) {}
        try { ns?.release() } catch (_: Throwable) {}
        if (rec != null) {
            try {
                if (rec.recordingState == AudioRecord.RECORDSTATE_RECORDING) {
                    rec.stop()
                }
            } catch (_: Throwable) {
            }
            try {
                rec.release()
            } catch (_: Throwable) {
            }
        }
    }

    /**
     * Kiến trúc Tách Kép 2 Luồng (Zero Buffer-Overflow):
     * - Luồng 1 (MicReaderThread - URGENT_AUDIO): Chỉ đọc AudioRecord.read() liên tục mỗi 60ms và đẩy vào hàng đợi vòng,
     *   tuyệt đối không chờ ONNX nên không bao giờ bị mất âm tiết ("RecordThread: buffer overflow").
     * - Luồng 2 (Orchestrator / KWS Decode): Lấy lô mẫu từ hàng đợi, chạy Sherpa-ONNX và quản lý chuyển giao Mic với Lily VIP.
     */
    private fun runOrchestratorLoop() {
        if (!MinaKwsNative.isLoaded) {
            updateState(STATE_ERROR, "Lỗi nạp thư viện Sherpa-ONNX: ${MinaKwsNative.loadError}")
            workerRunning.set(false)
            return
        }

        val modelDir = try {
            ensureModelsExtracted()
        } catch (e: Throwable) {
            updateState(STATE_ERROR, "Lỗi giải nén model KWS: ${e.message}")
            workerRunning.set(false)
            return
        }

        var kwsHandle = createSpotterFromPrefs(modelDir)
        if (kwsHandle == 0L) {
            updateState(STATE_ERROR, "Không khởi tạo được Sherpa-ONNX KeywordSpotter")
            workerRunning.set(false)
            return
        }

        // Hàng đợi mẫu PCM giữa MicReaderThread và KwsDecodeThread (tối đa 6400 mẫu = 400ms)
        val queueLock = Object()
        val maxQueueSamples = 6400
        val sampleQueue = ShortArray(maxQueueSamples)
        var queueLen = 0
        val micThreadActive = AtomicBoolean(false)
        val micSilencedBySystem = AtomicBoolean(false)
        var micReaderThread: Thread? = null

        var audioRecord: AudioRecord? = null
        var aec: AcousticEchoCanceler? = null
        var ns: NoiseSuppressor? = null

        fun stopActiveCapture() {
            micThreadActive.set(false)
            synchronized(queueLock) {
                queueLen = 0
                queueLock.notifyAll()
            }
            closeMic(audioRecord, aec, ns)
            try {
                micReaderThread?.join(400)
            } catch (_: Throwable) {
            }
            micReaderThread = null
            audioRecord = null
            aec = null
            ns = null
            lastPeakLevel = 0
        }

        fun startActiveCapture(): Boolean {
            val opened = openMic()
            val rec = opened.first ?: return false
            audioRecord = rec
            aec = opened.second
            ns = opened.third
            micSilencedBySystem.set(false)
            synchronized(queueLock) {
                queueLen = 0
            }
            micThreadActive.set(true)

            val reader = Thread({
                Process.setThreadPriority(Process.THREAD_PRIORITY_URGENT_AUDIO)
                val frame = ShortArray(960) // 60ms @ 16kHz
                var silentFrames = 0
                var exactZeroFrames = 0

                while (micThreadActive.get() && workerRunning.get()) {
                    val n = try {
                        rec.read(frame, 0, frame.size)
                    } catch (_: Throwable) {
                        -1
                    }
                    if (n <= 0) {
                        if (!micThreadActive.get()) break
                        Thread.sleep(20)
                        continue
                    }

                    var rawMax = 0
                    for (i in 0 until n step 2) {
                        val v = kotlin.math.abs(frame[i].toInt())
                        if (v > rawMax) rawMax = v
                    }

                    if (rawMax == 0) {
                        exactZeroFrames++
                        if (exactZeroFrames > 25) {
                            micSilencedBySystem.set(true)
                            synchronized(queueLock) { queueLock.notifyAll() }
                            break
                        }
                    } else {
                        exactZeroFrames = 0
                    }

                    // Khuếch đại phần mềm ×2.2 (có kẹp bão hòa mềm) giúp bắt nhạy câu gọi từ khoảng cách 1–3m trên Visbot
                    var boostedMax = 0
                    for (i in 0 until n) {
                        val boosted = (frame[i].toInt() * 22) / 10
                        val clamped = boosted.coerceIn(-32768, 32767)
                        frame[i] = clamped.toShort()
                        val absV = kotlin.math.abs(clamped)
                        if (absV > boostedMax) boostedMax = absV
                    }
                    lastPeakLevel = boostedMax

                    if (boostedMax < 160) {
                        silentFrames++
                        if (silentFrames > 28) {
                            // Im lặng > 1.7s -> nghỉ đẩy vào ONNX để CPU = 0%
                            continue
                        }
                    } else {
                        silentFrames = 0
                    }

                    synchronized(queueLock) {
                        if (queueLen + n > maxQueueSamples) {
                            val drop = (queueLen + n) - maxQueueSamples
                            System.arraycopy(sampleQueue, drop, sampleQueue, 0, queueLen - drop)
                            queueLen -= drop
                        }
                        System.arraycopy(frame, 0, sampleQueue, queueLen, n)
                        queueLen += n
                        queueLock.notifyAll()
                    }
                }
            }, "MinaMicUrgentReader")
            micReaderThread = reader
            reader.start()
            return true
        }

        var yielded = false
        var yieldGraceUntilMs = 0L
        var seenExternalRecorderDuringYield = false
        var externalSilentSinceMs = 0L
        var checkExtCounter = 0

        try {
            while (workerRunning.get()) {
                val now = System.currentTimeMillis()

                // 1. Nạp lại cấu hình độ nhạy / từ khóa nếu vừa chỉnh
                if (reloadRequested.getAndSet(false)) {
                    MinaKwsNative.nativeDestroy(kwsHandle)
                    kwsHandle = createSpotterFromPrefs(modelDir)
                    if (kwsHandle == 0L) {
                        updateState(STATE_ERROR, "Lỗi cú pháp trong file keywords.txt")
                        break
                    }
                }

                // 2. Yêu cầu gọi Lily thủ công
                if (manualWakeRequested.getAndSet(false)) {
                    stopActiveCapture()
                    yielded = true
                    seenExternalRecorderDuringYield = false
                    externalSilentSinceMs = 0L
                    yieldGraceUntilMs = System.currentTimeMillis() + 7500L
                    triggerLilyConversation("Gọi nhanh")
                    updateState(STATE_YIELDED, "Đang nhường Mic cho Lily VIP đàm thoại...")
                    continue
                }

                // 3. Tạm nhường Mic 30s từ thông báo
                if (now < forceYieldUntilMs) {
                    if (audioRecord != null) stopActiveCapture()
                    val remSec = ((forceYieldUntilMs - now) / 1000L).coerceAtLeast(1L)
                    updateState(STATE_YIELDED, "Đang tạm nhường Mic (${remSec}s)...")
                    Thread.sleep(500)
                    continue
                }

                // 4. Trạng thái ĐANG NHƯỜNG MIC CHO LILY VIP
                if (yielded) {
                    val lilyRecording = hasExternalRecorder(-1)
                    if (lilyRecording) {
                        seenExternalRecorderDuringYield = true
                        externalSilentSinceMs = 0L
                        updateState(STATE_YIELDED, "Lily VIP đang giữ Mic đàm thoại...")
                    } else {
                        if (now < yieldGraceUntilMs && !seenExternalRecorderDuringYield) {
                            Thread.sleep(350)
                            continue
                        }
                        if (externalSilentSinceMs == 0L) {
                            externalSilentSinceMs = now
                        } else if (now - externalSilentSinceMs >= 2600L) {
                            yielded = false
                            seenExternalRecorderDuringYield = false
                            externalSilentSinceMs = 0L
                            MinaKwsNative.nativeReset(kwsHandle)
                            Log.i(TAG, "Lily finished session -> Re-acquiring mic for Mina KWS")
                            continue
                        }
                    }
                    Thread.sleep(450)
                    continue
                }

                // 5. Đảm bảo luồng đọc Mic đang chạy
                if (audioRecord == null) {
                    if (hasExternalRecorder(-1)) {
                        yielded = true
                        seenExternalRecorderDuringYield = true
                        externalSilentSinceMs = 0L
                        updateState(STATE_YIELDED, "Lily VIP đang sử dụng Mic...")
                        Thread.sleep(500)
                        continue
                    }
                    if (!startActiveCapture()) {
                        updateState(STATE_YIELDED, "Mic đang bận, chờ 2s...")
                        Thread.sleep(1800)
                        continue
                    }
                    MinaKwsNative.nativeReset(kwsHandle)
                    updateState(STATE_LISTENING, "Đang nghe: \"Hello Mina\", \"Chào Mina\", \"Mina ơi\"")
                }

                if (micSilencedBySystem.getAndSet(false)) {
                    stopActiveCapture()
                    yielded = true
                    seenExternalRecorderDuringYield = false
                    externalSilentSinceMs = 0L
                    yieldGraceUntilMs = System.currentTimeMillis() + 5000L
                    updateState(STATE_YIELDED, "Nhường Mic cho ứng dụng tiền cảnh...")
                    continue
                }

                checkExtCounter++
                val curRec = audioRecord
                if (curRec != null && checkExtCounter % 6 == 0 && hasExternalRecorder(curRec.audioSessionId)) {
                    stopActiveCapture()
                    yielded = true
                    seenExternalRecorderDuringYield = true
                    externalSilentSinceMs = 0L
                    updateState(STATE_YIELDED, "Tự động nhường Mic cho Lily VIP...")
                    continue
                }

                // 6. Chờ lấy lô mẫu âm thanh từ hàng đợi mà không giữ khóa khi giải mã ONNX
                var chunk: ShortArray? = null
                synchronized(queueLock) {
                    if (queueLen == 0 && workerRunning.get() && !manualWakeRequested.get() && !reloadRequested.get()) {
                        queueLock.wait(300)
                    }
                    if (queueLen > 0) {
                        chunk = sampleQueue.copyOfRange(0, queueLen)
                        queueLen = 0
                    }
                }

                val data = chunk ?: continue
                val kw = MinaKwsNative.nativeAcceptAndDecode(kwsHandle, data, data.size).trim()
                if (kw.isNotEmpty()) {
                    Log.i(TAG, "WAKE KEYWORD SPOTTED: $kw")
                    val ts = SimpleDateFormat("HH:mm:ss", Locale.getDefault()).format(Date())

                    if (kw.contains("dừng_lại", ignoreCase = true)) {
                        VisbotMotorController.stop()
                        mcpServer?.stopRadio()
                        lastTriggerInfo = "$kw ($ts) -> Đã dừng bánh xe & media"
                        broadcastUiUpdate()
                        continue
                    }

                    // Khẩu lệnh điều khiển chuyển động Offline tức thì (< 100ms, không cần mạng)
                    if (kw.startsWith("@Motor_", ignoreCase = true)) {
                        if (!VisbotMotorController.isInitialized) {
                            VisbotMotorController.init(applicationContext)
                        }
                        val actDesc = when (kw) {
                            "@Motor_Forward" -> VisbotMotorController.move("forward", 1300L)
                            "@Motor_Backward" -> VisbotMotorController.move("backward", 1300L)
                            "@Motor_Left" -> VisbotMotorController.move("turn_left", 950L)
                            "@Motor_Right" -> VisbotMotorController.move("turn_right", 950L)
                            "@Motor_Nod" -> VisbotMotorController.head("nod")
                            "@Motor_Dance" -> VisbotMotorController.dance()
                            else -> "Đã nhận $kw"
                        }
                        lastTriggerInfo = "$kw ($ts) -> $actDesc"
                        broadcastUiUpdate()
                        continue
                    }

                    // NHẢ MIC TỨC THÌ (< 5ms) TRƯỚC KHI GỌI LILY VIP!
                    stopActiveCapture()
                    mcpServer?.stopRadio()

                    yielded = true
                    seenExternalRecorderDuringYield = false
                    externalSilentSinceMs = 0L
                    yieldGraceUntilMs = System.currentTimeMillis() + 7500L

                    triggerLilyConversation(kw)
                    updateState(STATE_YIELDED, "Đã gọi Lily VIP (từ khóa: $kw)...")
                }
            }
        } catch (_: InterruptedException) {
        } catch (t: Throwable) {
            Log.e(TAG, "Orchestrator loop crashed: ${t.message}", t)
            updateState(STATE_ERROR, "Lỗi luồng âm thanh: ${t.message}")
        } finally {
            stopActiveCapture()
            if (kwsHandle != 0L) {
                MinaKwsNative.nativeDestroy(kwsHandle)
            }
            workerRunning.set(false)
        }
    }

    @Suppress("DEPRECATION")
    private fun triggerLilyConversation(reason: String) {
        val ts = SimpleDateFormat("HH:mm:ss", Locale.getDefault()).format(Date())
        lastTriggerInfo = "$reason lúc $ts"

        try {
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            val wl = pm.newWakeLock(
                PowerManager.SCREEN_BRIGHT_WAKE_LOCK or PowerManager.ACQUIRE_CAUSES_WAKEUP,
                "mina_lily_bridge:wakeup"
            )
            wl.acquire(8000L)
        } catch (_: Throwable) {
        }

        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        if (prefs.getBoolean(KEY_NOD_ON_WAKE, true)) {
            mainHandler.post {
                try {
                    if (!VisbotMotorController.isInitialized) {
                        VisbotMotorController.init(applicationContext)
                    }
                    VisbotMotorController.head("nod")
                } catch (_: Throwable) {
                }
            }
        }
        if (prefs.getBoolean(KEY_PLAY_BEEP, true)) {
            try {
                val tg = ToneGenerator(AudioManager.STREAM_NOTIFICATION, 80)
                tg.startTone(ToneGenerator.TONE_PROP_ACK, 80)
                mainHandler.postDelayed({
                    try { tg.release() } catch (_: Throwable) {}
                }, 220L)
            } catch (_: Throwable) {
            }
        }

        mainHandler.post {
            try {
                val wakeIntent = Intent(LILY_WAKE_ACTION).apply {
                    setPackage(LILY_PKG)
                    addFlags(
                        Intent.FLAG_ACTIVITY_NEW_TASK or
                            Intent.FLAG_ACTIVITY_SINGLE_TOP or
                            Intent.FLAG_ACTIVITY_CLEAR_TOP
                    )
                }
                if (wakeIntent.resolveActivity(packageManager) != null) {
                    startActivity(wakeIntent)
                    Log.i(TAG, "Triggered Lily via $LILY_WAKE_ACTION ($reason)")
                } else {
                    val fallback = packageManager.getLaunchIntentForPackage(LILY_PKG)
                    if (fallback != null) {
                        fallback.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(fallback)
                        Log.i(TAG, "Triggered Lily via launcher fallback ($reason)")
                    } else {
                        updateState(STATE_ERROR, "Không tìm thấy ứng dụng Lily ($LILY_PKG)")
                    }
                }
            } catch (e: Throwable) {
                Log.e(TAG, "Failed to launch Lily: ${e.message}")
            }
        }
    }

    private fun updateState(newState: String, detail: String) {
        val changed = (currentState != newState || statusDetail != detail)
        currentState = newState
        statusDetail = detail
        if (changed) {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.notify(NOTIF_ID, buildNotification(detail))
            broadcastUiUpdate()
        }
    }

    private fun broadcastUiUpdate() {
        sendBroadcast(Intent(ACTION_UI_UPDATE).setPackage(packageName))
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val ch = NotificationChannel(
                NOTIF_CHANNEL_ID,
                "Mina Bridge -> Lily VIP",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Lắng nghe từ khóa Mina Offline và đánh thức Lily VIP"
                setShowBadge(false)
            }
            nm.createNotificationChannel(ch)
        }
    }

    @Suppress("DEPRECATION")
    private fun buildNotification(text: String): Notification {
        val piFlags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        val openUiPi = PendingIntent.getActivity(
            this,
            1,
            Intent(this, MainActivity::class.java),
            piFlags
        )
        val yieldPi = PendingIntent.getService(
            this,
            2,
            Intent(this, MinaBridgeService::class.java).setAction(ACTION_YIELD_30S),
            piFlags
        )

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, NOTIF_CHANNEL_ID)
        } else {
            Notification.Builder(this)
        }

        return builder
            .setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setContentTitle("Mina Bridge -> Lily VIP")
            .setContentText(text)
            .setOngoing(true)
            .setContentIntent(openUiPi)
            .addAction(android.R.drawable.ic_media_pause, "Nhường Mic 30s", yieldPi)
            .build()
    }
}
