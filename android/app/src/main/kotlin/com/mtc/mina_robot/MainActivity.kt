package com.mtc.mina_robot

import android.annotation.SuppressLint
import android.app.SearchManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.SurfaceTexture
import android.graphics.drawable.GradientDrawable
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
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.MediaStore
import android.provider.Settings
import android.view.Gravity
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
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
    private var platformChannel: MethodChannel? = null

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
            val sayText = intent.getStringExtra("say")
            val assistantId = intent.getStringExtra("assistant")
            val resetTopic = intent.getBooleanExtra("resetTopic", false)
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
            if (!sayText.isNullOrEmpty() || !assistantId.isNullOrEmpty() || resetTopic) {
                mainHandler.post {
                    platformChannel?.invokeMethod(
                        "onBroadcastCommand",
                        mapOf("say" to sayText, "assistant" to assistantId, "resetTopic" to resetTopic)
                    )
                }
            }
        }
    }

    // Thu âm 16kHz Mono PCM 16-bit (chuẩn chung cho cả Sherpa-ONNX và XiaoZhi Opus)
    private val isRecording = AtomicBoolean(false)
    private var audioRecord: AudioRecord? = null
    private var echoCanceler: AcousticEchoCanceler? = null
    private var noiseSuppressor: NoiseSuppressor? = null
    private var recordThread: Thread? = null
    private var micEventSink: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private var lastFrontButtonMs: Long = 0L

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

    // Nút nổi điều hướng nhanh [🏠 Mina | 🌙 Tắt màn] khi mở Zing MP3 / NewPipe & lớp phủ tắt màn hình nghe nhạc
    private var floatingPillView: View? = null
    private var systemBlackoutView: View? = null
    private var localBlackoutView: View? = null
    private val transientAudioFocusListener = AudioManager.OnAudioFocusChangeListener { }

    override fun onResume() {
        super.onResume()
        hideFloatingNavOverlay()
    }

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

        // Khởi tạo bộ điều khiển động cơ bánh xe, servo cổ & nút cảm biến UBTECH Visbot
        VisbotMotorController.onFrontSensorPressed = { sensorId ->
            emitFrontButtonEvent("sensor:$sensorId", isBackKey = false)
        }
        VisbotMotorController.init(this)
        try {
            registerReceiver(robotCmdReceiver, IntentFilter("com.mtc.mina_visbot.ROBOT_CMD"))
        } catch (_: Throwable) {
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val act = intent.action ?: ""
        if (act == Intent.ACTION_VOICE_COMMAND || act == Intent.ACTION_ASSIST) {
            emitFrontButtonEvent("intent:$act", isBackKey = false)
        }
    }

    /**
     * Bắt nút cứng phía trước trên thân robot UBTECH Visbot:
     * - mtk-irqkey (scanCode = 182 -> KEYCODE_BACK)
     * - mtk-pmic-keys (scanCode = 582 -> KEYCODE_VOICE_ASSIST / ASSIST)
     */
    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        val kc = event.keyCode
        val sc = event.scanCode
        if (kc == KeyEvent.KEYCODE_VOLUME_UP ||
            kc == KeyEvent.KEYCODE_VOLUME_DOWN ||
            kc == KeyEvent.KEYCODE_POWER
        ) {
            return super.dispatchKeyEvent(event)
        }

        val isFrontPhysicalKey =
            sc == 182 ||
                sc == 582 ||
                kc == KeyEvent.KEYCODE_BACK ||
                kc == KeyEvent.KEYCODE_VOICE_ASSIST ||
                kc == KeyEvent.KEYCODE_ASSIST ||
                kc == KeyEvent.KEYCODE_SEARCH ||
                kc == KeyEvent.KEYCODE_HEADSETHOOK

        if (isFrontPhysicalKey) {
            if (event.action == KeyEvent.ACTION_DOWN) {
                return true
            }
            if (event.action == KeyEvent.ACTION_UP && !event.isCanceled) {
                val src = when {
                    sc == 182 -> "front_irqkey_182"
                    sc == 582 -> "front_voice_582"
                    else -> "key_$kc"
                }
                emitFrontButtonEvent(src, isBackKey = (kc == KeyEvent.KEYCODE_BACK && sc != 582))
                return true
            }
            return true
        }
        return super.dispatchKeyEvent(event)
    }

    private fun emitFrontButtonEvent(source: String, isBackKey: Boolean) {
        val now = System.currentTimeMillis()
        if (now - lastFrontButtonMs < 350L) return
        lastFrontButtonMs = now
        mainHandler.post {
            if (localBlackoutView != null || systemBlackoutView != null) {
                exitScreenBlackout()
                return@post
            }
            android.util.Log.i("MinaButton", "Hardware front button: source=$source, isBackKey=$isBackKey")
            platformChannel?.invokeMethod(
                "onHardwareFrontButton",
                mapOf("source" to source, "isBackKey" to isBackKey)
            )
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
        val pCh = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PLATFORM_CHANNEL)
        platformChannel = pCh
        pCh.setMethodCallHandler { call, result ->
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
                    "openYoutube" -> {
                        val query = call.argument<String>("query")
                        val url = call.argument<String>("url")
                        result.success(openAdFreeYoutube(query, url))
                    }
                    "openZingMp3" -> {
                        val query = call.argument<String>("query")
                        result.success(openZingMp3App(query))
                    }
                    "screenBlackout" -> {
                        val enable = call.argument<Boolean>("enable") ?: true
                        if (enable) enterScreenBlackout() else exitScreenBlackout()
                        result.success(true)
                    }
                    "holdAudioFocus" -> {
                        holdTransientAudioFocus()
                        result.success(true)
                    }
                    "releaseAudioFocus" -> {
                        releaseTransientAudioFocus()
                        result.success(true)
                    }
                    "externalMediaControl" -> {
                        val action = call.argument<String>("action") ?: "pause"
                        dispatchExternalMediaKey(action)
                        result.success(true)
                    }
                    "takePhoto" -> takePhoto(result)
                    "openWifiSettings" -> {
                        if (safeStart(Intent(Settings.ACTION_WIFI_SETTINGS))) showFloatingNavOverlay()
                        result.success(true)
                    }
                    "openSystemSettings" -> {
                        if (safeStart(Intent(Settings.ACTION_SETTINGS))) showFloatingNavOverlay()
                        result.success(true)
                    }
                    "openHomeSettings" -> {
                        if (!safeStart(Intent(Settings.ACTION_HOME_SETTINGS))) {
                            safeStart(Intent(Settings.ACTION_SETTINGS))
                        }
                        showFloatingNavOverlay()
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
                        showFloatingNavOverlay()
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

    // ------------------------------------------------------------------ YouTube Không Quảng Cáo & Zing MP3 + Tắt Màn Hình

    private fun isPackageInstalled(pkg: String): Boolean {
        return try {
            packageManager.getPackageInfo(pkg, 0)
            true
        } catch (_: Throwable) {
            false
        }
    }

    /**
     * Ưu tiên mở ứng dụng YouTube không quảng cáo & phát nền (NewPipe / Tubular).
     * Nếu chưa cài đặt thì tự động mở trình duyệt tích hợp đã chặn quảng cáo & cho phép phát nền.
     */
    private fun openAdFreeYoutube(query: String?, directUrl: String?): Map<String, Any> {
        val candidates = listOf("org.schabi.newpipe", "org.polymorphicshade.tubular")
        val installedPkg = candidates.firstOrNull { isPackageInstalled(it) }

        if (installedPkg != null) {
            val targetUri = when {
                !directUrl.isNullOrBlank() -> Uri.parse(directUrl)
                !query.isNullOrBlank() -> Uri.parse("https://www.youtube.com/results?search_query=${Uri.encode(query)}")
                else -> null
            }
            var launched = false
            if (targetUri != null) {
                launched = safeStart(Intent(Intent.ACTION_VIEW, targetUri).setPackage(installedPkg))
            }
            if (!launched) {
                val launchIntent = packageManager.getLaunchIntentForPackage(installedPkg)
                if (launchIntent != null) launched = safeStart(launchIntent)
            }
            if (launched) {
                showFloatingNavOverlay()
                return mapOf("ok" to true, "mode" to "newpipe", "package" to installedPkg)
            }
        }

        val fallbackUrl = when {
            !directUrl.isNullOrBlank() -> directUrl
            !query.isNullOrBlank() -> "https://m.youtube.com/results?search_query=${Uri.encode(query)}"
            else -> "https://m.youtube.com"
        }
        startActivity(
            Intent(this, BrowserActivity::class.java)
                .putExtra(BrowserActivity.EXTRA_URL, fallbackUrl)
                .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
        )
        return mapOf("ok" to true, "mode" to "webview", "url" to fallbackUrl)
    }

    /**
     * Mở ứng dụng Zing MP3 (com.zing.mp3) hỗ trợ phát nhạc nền khi tắt màn hình.
     * Nếu chưa cài APK Zing MP3 thì mở m.zingmp3.vn trong trình duyệt phát nền.
     */
    private fun openZingMp3App(query: String?): Map<String, Any> {
        val pkg = "com.zing.mp3"
        if (isPackageInstalled(pkg)) {
            var launched = false
            if (!query.isNullOrBlank()) {
                val playSearch = Intent(MediaStore.INTENT_ACTION_MEDIA_PLAY_FROM_SEARCH).apply {
                    setPackage(pkg)
                    putExtra(SearchManager.QUERY, query)
                }
                launched = safeStart(playSearch)
                if (!launched) {
                    val searchIntent = Intent(Intent.ACTION_SEARCH).apply {
                        setPackage(pkg)
                        putExtra(SearchManager.QUERY, query)
                    }
                    launched = safeStart(searchIntent)
                }
            }
            if (!launched) {
                val launchIntent = packageManager.getLaunchIntentForPackage(pkg)
                if (launchIntent != null) launched = safeStart(launchIntent)
            }
            if (launched) {
                showFloatingNavOverlay()
                return mapOf("ok" to true, "mode" to "zing_app")
            }
        }

        val fallbackUrl = if (!query.isNullOrBlank()) {
            "https://m.zingmp3.vn/tim-kiem/tat-ca?q=${Uri.encode(query)}"
        } else {
            "https://m.zingmp3.vn"
        }
        startActivity(
            Intent(this, BrowserActivity::class.java)
                .putExtra(BrowserActivity.EXTRA_URL, fallbackUrl)
                .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
        )
        return mapOf("ok" to true, "mode" to "webview", "url" to fallbackUrl)
    }

    private fun canDrawSystemOverlay(): Boolean {
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.M || Settings.canDrawOverlays(this)
    }

    private fun overlayWindowType(): Int {
        @Suppress("DEPRECATION")
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            WindowManager.LayoutParams.TYPE_PHONE
        }
    }

    /**
     * Thanh nổi nhỏ [🏠 | 🌙] ở góc trên phải màn hình 308x240 khi đang mở Zing MP3 / NewPipe / Cài đặt:
     * - 🏠: Quay về khuôn mặt Mina (nhạc nền vẫn tiếp tục phát).
     * - 🌙: Tắt tối đen màn hình ngay để nghe nhạc tiết kiệm pin, chạm bất kỳ đâu để bật lại.
     */
    @SuppressLint("ClickableViewAccessibility")
    private fun showFloatingNavOverlay() {
        if (!canDrawSystemOverlay() || floatingPillView != null) return
        try {
            val wm = getSystemService(Context.WINDOW_SERVICE) as WindowManager
            val density = resources.displayMetrics.density
            val pill = LinearLayout(applicationContext).apply {
                orientation = LinearLayout.HORIZONTAL
                background = GradientDrawable().apply {
                    setColor(0xCC0F172A.toInt())
                    cornerRadius = 14f * density
                    setStroke((1 * density).toInt().coerceAtLeast(1), 0x6600E5FF)
                }
                val padH = (4 * density).toInt()
                setPadding(padH, 0, padH, 0)
            }

            val btnW = (30 * density).toInt()
            val btnH = (26 * density).toInt()

            val homeBtn = TextView(applicationContext).apply {
                text = "🏠"
                textSize = 12f
                gravity = Gravity.CENTER
                setOnClickListener {
                    hideFloatingNavOverlay()
                    val backHome = Intent(this@MainActivity, MainActivity::class.java).apply {
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
                    }
                    safeStart(backHome)
                }
            }

            val sleepBtn = TextView(applicationContext).apply {
                text = "🌙"
                textSize = 12f
                gravity = Gravity.CENTER
                setOnClickListener { enterScreenBlackout() }
            }

            pill.addView(homeBtn, LinearLayout.LayoutParams(btnW, btnH))
            pill.addView(sleepBtn, LinearLayout.LayoutParams(btnW, btnH))

            val params = WindowManager.LayoutParams(
                WindowManager.LayoutParams.WRAP_CONTENT,
                WindowManager.LayoutParams.WRAP_CONTENT,
                overlayWindowType(),
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
                PixelFormat.TRANSLUCENT
            ).apply {
                gravity = Gravity.TOP or Gravity.END
                x = (4 * density).toInt()
                y = (4 * density).toInt()
            }

            // Cho phép kéo thanh nổi nếu che nút của ứng dụng bên dưới
            var downRawX = 0f
            var downRawY = 0f
            var startX = 0
            var startY = 0
            pill.setOnTouchListener { _, ev ->
                when (ev.actionMasked) {
                    MotionEvent.ACTION_DOWN -> {
                        downRawX = ev.rawX
                        downRawY = ev.rawY
                        startX = params.x
                        startY = params.y
                        false
                    }
                    MotionEvent.ACTION_MOVE -> {
                        val dx = (ev.rawX - downRawX).toInt()
                        val dy = (ev.rawY - downRawY).toInt()
                        if (kotlin.math.abs(dx) > 6 || kotlin.math.abs(dy) > 6) {
                            params.x = (startX - dx).coerceAtLeast(0)
                            params.y = (startY + dy).coerceAtLeast(0)
                            try {
                                wm.updateViewLayout(pill, params)
                            } catch (_: Throwable) {
                            }
                            true
                        } else {
                            false
                        }
                    }
                    else -> false
                }
            }

            wm.addView(pill, params)
            floatingPillView = pill
        } catch (_: Throwable) {
        }
    }

    private fun hideFloatingNavOverlay() {
        val v = floatingPillView ?: return
        floatingPillView = null
        try {
            val wm = getSystemService(Context.WINDOW_SERVICE) as WindowManager
            wm.removeView(v)
        } catch (_: Throwable) {
        }
    }

    /** Tắt tối đen màn hình (hạ độ sáng đèn nền về 0 + phủ đen toàn màn) nhưng giữ nhạc nền phát liên tục. */
    private fun enterScreenBlackout() {
        if (canDrawSystemOverlay()) {
            if (systemBlackoutView != null) return
            try {
                val wm = getSystemService(Context.WINDOW_SERVICE) as WindowManager
                val hint = TextView(applicationContext).apply {
                    text = "🌙 Đang phát nhạc tắt màn hình\nChạm bất kỳ đâu để sáng lại"
                    textSize = 12f
                    setTextColor(0x99FFFFFF.toInt())
                    gravity = Gravity.CENTER
                }
                val cover = FrameLayout(applicationContext).apply {
                    setBackgroundColor(Color.BLACK)
                    isClickable = true
                    isFocusable = true
                    addView(hint, FrameLayout.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT,
                        ViewGroup.LayoutParams.MATCH_PARENT,
                        Gravity.CENTER
                    ))
                    setOnClickListener { exitScreenBlackout() }
                }
                hint.postDelayed({ hint.animate().alpha(0f).setDuration(600).start() }, 1600)

                val params = WindowManager.LayoutParams(
                    WindowManager.LayoutParams.MATCH_PARENT,
                    WindowManager.LayoutParams.MATCH_PARENT,
                    overlayWindowType(),
                    WindowManager.LayoutParams.FLAG_FULLSCREEN or
                        WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                        WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
                    PixelFormat.OPAQUE
                ).apply {
                    screenBrightness = 0.0f
                }
                wm.addView(cover, params)
                systemBlackoutView = cover
                return
            } catch (_: Throwable) {
            }
        }

        // Dự phòng nội bộ trên cửa sổ MainActivity nếu chưa cấp quyền SYSTEM_ALERT_WINDOW
        if (localBlackoutView != null) return
        val content = findViewById<ViewGroup>(android.R.id.content) ?: return
        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        val lp = window.attributes
        lp.screenBrightness = 0.0f
        window.attributes = lp

        val cover = FrameLayout(this).apply {
            setBackgroundColor(Color.BLACK)
            isClickable = true
            setOnClickListener { exitScreenBlackout() }
        }
        localBlackoutView = cover
        content.addView(cover, FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.MATCH_PARENT
        ))
    }

    private fun exitScreenBlackout() {
        systemBlackoutView?.let { v ->
            systemBlackoutView = null
            try {
                val wm = getSystemService(Context.WINDOW_SERVICE) as WindowManager
                wm.removeView(v)
            } catch (_: Throwable) {
            }
        }
        localBlackoutView?.let { v ->
            localBlackoutView = null
            try {
                findViewById<ViewGroup>(android.R.id.content)?.removeView(v)
            } catch (_: Throwable) {
            }
            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            val lp = window.attributes
            lp.screenBrightness = WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE
            window.attributes = lp
        }
    }

    @Suppress("DEPRECATION")
    private fun holdTransientAudioFocus() {
        try {
            val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
            am.requestAudioFocus(
                transientAudioFocusListener,
                AudioManager.STREAM_MUSIC,
                AudioManager.AUDIOFOCUS_GAIN_TRANSIENT
            )
        } catch (_: Throwable) {
        }
    }

    @Suppress("DEPRECATION")
    private fun releaseTransientAudioFocus() {
        try {
            val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
            am.abandonAudioFocus(transientAudioFocusListener)
        } catch (_: Throwable) {
        }
    }

    private fun dispatchExternalMediaKey(action: String) {
        val keyCode = when (action) {
            "pause" -> KeyEvent.KEYCODE_MEDIA_PAUSE
            "resume", "play" -> KeyEvent.KEYCODE_MEDIA_PLAY
            "stop" -> KeyEvent.KEYCODE_MEDIA_STOP
            "next" -> KeyEvent.KEYCODE_MEDIA_NEXT
            "previous" -> KeyEvent.KEYCODE_MEDIA_PREVIOUS
            else -> KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE
        }
        try {
            val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
            am.dispatchMediaKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, keyCode))
            am.dispatchMediaKeyEvent(KeyEvent(KeyEvent.ACTION_UP, keyCode))
        } catch (_: Throwable) {
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

        // Bật khử tiếng vọng (AEC) & lọc ồn phần cứng để bắt khẩu lệnh ngắt lời ngay cả khi loa đang nói
        try {
            if (AcousticEchoCanceler.isAvailable()) {
                echoCanceler = AcousticEchoCanceler.create(record.audioSessionId)?.apply {
                    enabled = true
                }
            }
        } catch (_: Throwable) {
        }
        try {
            if (NoiseSuppressor.isAvailable()) {
                noiseSuppressor = NoiseSuppressor.create(record.audioSessionId)?.apply {
                    enabled = true
                }
            }
        } catch (_: Throwable) {
        }
        android.util.Log.i(
            "MinaAudio",
            "Mic started (session=${record.audioSessionId}, aec=${echoCanceler?.enabled == true}, ns=${noiseSuppressor?.enabled == true})"
        )

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
            echoCanceler?.release()
        } catch (_: Throwable) {
        }
        echoCanceler = null
        try {
            noiseSuppressor?.release()
        } catch (_: Throwable) {
        }
        noiseSuppressor = null
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
        hideFloatingNavOverlay()
        exitScreenBlackout()
        releaseTransientAudioFocus()
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
