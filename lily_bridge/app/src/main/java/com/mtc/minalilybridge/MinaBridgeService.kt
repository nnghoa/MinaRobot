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

        const val PREFS_NAME = "mina_lily_bridge_prefs"
        const val KEY_ENABLED = "listening_enabled"
        const val KEY_THRESHOLD = "kws_threshold"
        const val KEY_SCORE = "kws_score"
        const val KEY_AUTO_BOOT = "auto_boot"
        const val KEY_PLAY_BEEP = "play_beep"

        const val ACTION_START_LISTENING = "com.mtc.mina_lily_bridge.START_LISTENING"
        const val ACTION_PAUSE_LISTENING = "com.mtc.mina_lily_bridge.PAUSE_LISTENING"
        const val ACTION_RELOAD_CONFIG = "com.mtc.mina_lily_bridge.RELOAD_CONFIG"
        const val ACTION_WAKE_LILY_NOW = "com.mtc.mina_lily_bridge.WAKE_LILY_NOW"
        const val ACTION_YIELD_30S = "com.mtc.mina_lily_bridge.YIELD_30S"
        const val ACTION_UI_UPDATE = "com.mtc.mina_lily_bridge.UI_UPDATE"

        const val LILY_PKG = "com.sensornotes.xiaozhi"
        const val LILY_WAKE_ACTION = "com.hy.honeybot.launch.action"

        const val STATE_PAUSED = "PAUSED"
        const val STATE_LISTENING = "LISTENING"
        const val STATE_YIELDED = "YIELDED"
        const val STATE_ERROR = "ERROR"

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

    private var workerThread: Thread? = null
    private var mcpServer: MinaLocalMcpServer? = null
    private lateinit var audioManager: AudioManager
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onCreate() {
        super.onCreate()
        audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        createNotificationChannel()
        startForeground(NOTIF_ID, buildNotification("Đang khởi tạo cầu nối Mina -> Lily VIP..."))

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
                updateState(STATE_PAUSED, "Đã tạm dừng nghe \"Mina ơi\" (Mic nhường hoàn toàn)")
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
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun startWorkerIfNeeded() {
        if (workerRunning.getAndSet(true)) return
        val t = Thread({ runAudioLoop() }, "MinaKwsAudioLoop")
        workerThread = t
        t.start()
    }

    private fun stopWorker() {
        workerRunning.set(false)
        workerThread?.interrupt()
        try {
            workerThread?.join(1200)
        } catch (_: Throwable) {
        }
        workerThread = null
    }

    private fun ensureModelsExtracted(): File {
        val modelDir = File(filesDir, "mina_kws")
        if (!modelDir.exists()) modelDir.mkdirs()

        val assetNames = listOf(
            "encoder.int8.onnx",
            "decoder.onnx",
            "joiner.int8.onnx",
            "tokens.txt",
            "keywords.txt"
        )
        for (name in assetNames) {
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
        return modelDir
    }

    private fun createSpotterFromPrefs(modelDir: File): Long {
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val score = prefs.getFloat(KEY_SCORE, 1.5f)
        val threshold = prefs.getFloat(KEY_THRESHOLD, 0.20f)
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
        val bufSize = (minBuf * 2).coerceAtLeast(16000 * 2) // >= 1s ring buffer

        return try {
            val rec = AudioRecord(
                MediaRecorder.AudioSource.VOICE_RECOGNITION,
                sampleRate,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT,
                bufSize
            )
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

    private fun runAudioLoop() {
        Process.setThreadPriority(Process.THREAD_PRIORITY_AUDIO)

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

        var audioRecord: AudioRecord? = null
        var aec: AcousticEchoCanceler? = null
        var ns: NoiseSuppressor? = null

        var yielded = false
        var yieldGraceUntilMs = 0L
        var seenExternalRecorderDuringYield = false
        var externalSilentSinceMs = 0L

        var silentFrames = 0
        var exactZeroFrames = 0
        var frameCounter = 0
        val pcmBuf = ShortArray(960) // 60ms @ 16kHz

        try {
            while (workerRunning.get()) {
                val now = System.currentTimeMillis()

                // 1. Nạp lại cấu hình độ nhạy / từ khóa nếu người dùng vừa chỉnh trong UI
                if (reloadRequested.getAndSet(false)) {
                    MinaKwsNative.nativeDestroy(kwsHandle)
                    kwsHandle = createSpotterFromPrefs(modelDir)
                    if (kwsHandle == 0L) {
                        updateState(STATE_ERROR, "Lỗi cú pháp trong file keywords.txt")
                        break
                    }
                }

                // 2. Xử lý yêu cầu gọi Lily thủ công (từ nút test hoặc phím cứng)
                if (manualWakeRequested.getAndSet(false)) {
                    closeMic(audioRecord, aec, ns)
                    audioRecord = null; aec = null; ns = null
                    lastPeakLevel = 0
                    yielded = true
                    seenExternalRecorderDuringYield = false
                    externalSilentSinceMs = 0L
                    yieldGraceUntilMs = System.currentTimeMillis() + 7500L
                    triggerLilyConversation("Gọi nhanh")
                    updateState(STATE_YIELDED, "Đang nhường Mic cho Lily VIP đàm thoại...")
                    continue
                }

                // 3. Kiểm tra nhường Mic 30s thủ công từ thanh thông báo
                if (now < forceYieldUntilMs) {
                    if (audioRecord != null) {
                        closeMic(audioRecord, aec, ns)
                        audioRecord = null; aec = null; ns = null
                        lastPeakLevel = 0
                    }
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
                            // Đang trong 7.5s đầu chờ Lily mở kết nối mạng và lấy Mic
                            Thread.sleep(350)
                            continue
                        }
                        if (externalSilentSinceMs == 0L) {
                            externalSilentSinceMs = now
                        } else if (now - externalSilentSinceMs >= 2600L) {
                            // Lily đã ngắt phiên thoại và trả Mic >= 2.6 giây -> Mina nhận lại Mic!
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

                // 5. Trước khi mở Mic hoặc định kỳ kiểm tra xem Lily có đang tự thu âm không
                if (audioRecord == null) {
                    if (hasExternalRecorder(-1)) {
                        yielded = true
                        seenExternalRecorderDuringYield = true
                        externalSilentSinceMs = 0L
                        updateState(STATE_YIELDED, "Lily VIP đang sử dụng Mic...")
                        Thread.sleep(500)
                        continue
                    }
                    val opened = openMic()
                    audioRecord = opened.first
                    aec = opened.second
                    ns = opened.third
                    if (audioRecord == null) {
                        updateState(STATE_YIELDED, "Mic đang bận bởi ứng dụng khác, chờ 2s...")
                        Thread.sleep(1800)
                        continue
                    }
                    silentFrames = 0
                    exactZeroFrames = 0
                    MinaKwsNative.nativeReset(kwsHandle)
                    updateState(STATE_LISTENING, "Đang nghe Offline: \"Mina\", \"Chào Mina\", \"Mina ơi\"")
                }

                // Kiểm tra nhanh mỗi ~0.5s xem có app khác vừa mở AudioRecord song song không
                frameCounter++
                if (frameCounter % 8 == 0 && hasExternalRecorder(audioRecord.audioSessionId)) {
                    closeMic(audioRecord, aec, ns)
                    audioRecord = null; aec = null; ns = null
                    lastPeakLevel = 0
                    yielded = true
                    seenExternalRecorderDuringYield = true
                    externalSilentSinceMs = 0L
                    updateState(STATE_YIELDED, "Tự động nhường Mic cho Lily VIP...")
                    continue
                }

                val readCount = audioRecord.read(pcmBuf, 0, pcmBuf.size)
                if (readCount <= 0) {
                    closeMic(audioRecord, aec, ns)
                    audioRecord = null; aec = null; ns = null
                    Thread.sleep(500)
                    continue
                }

                // Đo biên độ đỉnh để chạy Silence Gate (0% CPU khi phòng yên tĩnh) & phát hiện bị tắt tiếng
                var maxAbs = 0
                var i = 0
                while (i < readCount) {
                    val v = kotlin.math.abs(pcmBuf[i].toInt())
                    if (v > maxAbs) maxAbs = v
                    i += 4
                }
                lastPeakLevel = maxAbs

                if (maxAbs == 0) {
                    exactZeroFrames++
                    if (exactZeroFrames > 20) {
                        // Android AudioFlinger trả về toàn 0 khi một app tiền cảnh khác lấy quyền Mic
                        closeMic(audioRecord, aec, ns)
                        audioRecord = null; aec = null; ns = null
                        yielded = true
                        seenExternalRecorderDuringYield = false
                        externalSilentSinceMs = 0L
                        yieldGraceUntilMs = System.currentTimeMillis() + 5000L
                        updateState(STATE_YIELDED, "Phát hiện ứng dụng khác yêu cầu Mic, đang nhường...")
                        continue
                    }
                } else {
                    exactZeroFrames = 0
                }

                if (maxAbs < 130) {
                    silentFrames++
                    if (silentFrames > 25) {
                        // Phòng yên lặng > 1.5s -> bỏ qua suy luận ONNX để CPU = 0%
                        continue
                    }
                } else {
                    silentFrames = 0
                }

                val kw = MinaKwsNative.nativeAcceptAndDecode(kwsHandle, pcmBuf, readCount).trim()
                if (kw.isNotEmpty()) {
                    Log.i(TAG, "WAKE KEYWORD SPOTTED: $kw")
                    if (kw.contains("dừng_lại", ignoreCase = true)) {
                        mcpServer?.stopRadio()
                        val ts = SimpleDateFormat("HH:mm:ss", Locale.getDefault()).format(Date())
                        lastTriggerInfo = "$kw ($ts) -> Đã dừng phát media"
                        broadcastUiUpdate()
                        continue
                    }

                    // NHẢ MIC TỨC THÌ (< 5ms) TRƯỚC KHI GỌI LILY VIP!
                    closeMic(audioRecord, aec, ns)
                    audioRecord = null; aec = null; ns = null
                    lastPeakLevel = 0
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
            Log.e(TAG, "Audio loop crashed: ${t.message}", t)
            updateState(STATE_ERROR, "Lỗi luồng âm thanh: ${t.message}")
        } finally {
            closeMic(audioRecord, aec, ns)
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

        // 1. Đánh thức màn hình nếu đang tắt
        try {
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            val wl = pm.newWakeLock(
                PowerManager.SCREEN_BRIGHT_WAKE_LOCK or PowerManager.ACQUIRE_CAUSES_WAKEUP,
                "mina_lily_bridge:wakeup"
            )
            wl.acquire(8000L)
        } catch (_: Throwable) {
        }

        // 2. Phát tiếng "ting" ngắn (70ms) báo hiệu đã nghe thấy "Mina ơi"
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        if (prefs.getBoolean(KEY_PLAY_BEEP, true)) {
            try {
                val tg = ToneGenerator(AudioManager.STREAM_NOTIFICATION, 75)
                tg.startTone(ToneGenerator.TONE_PROP_ACK, 75)
                mainHandler.postDelayed({
                    try { tg.release() } catch (_: Throwable) {}
                }, 200L)
            } catch (_: Throwable) {
            }
        }

        // 3. Kích hoạt thẳng phiên nghe trực tuyến của Lily VIP bằng Intent chuẩn đã xác minh
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
                description = "Lắng nghe từ khóa Mina ơi Offline và đánh thức Lily VIP"
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
