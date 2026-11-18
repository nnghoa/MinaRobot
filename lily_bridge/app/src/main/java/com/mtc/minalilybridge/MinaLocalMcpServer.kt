package com.mtc.minalilybridge

import android.annotation.SuppressLint
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.MediaPlayer
import android.media.MediaRecorder
import android.net.wifi.WifiManager
import android.os.BatteryManager
import android.os.Build
import android.provider.Settings
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.io.BufferedReader
import java.io.ByteArrayOutputStream
import java.io.InputStreamReader
import java.io.OutputStream
import java.net.InetAddress
import java.net.ServerSocket
import java.net.Socket
import java.net.URLDecoder
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.charset.StandardCharsets
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.abs
import kotlin.math.sqrt

/**
 * Máy chủ MCP nội bộ siêu nhẹ (JSON-RPC 2.0 HTTP trên 127.0.0.1:8765/mcp)
 * Cung cấp các tiện ích Mina (Radio VOV, trạng thái pin/mạng, mở nhanh ứng dụng) cho Lily VIP.
 */
class MinaLocalMcpServer(private val appContext: Context) {
    companion object {
        private const val TAG = "MinaLocalMcp"
        const val PORT = 8765

        private val VOV_STREAMS = mapOf(
            "vov1" to Pair("Đài VOV1 Thời sự", "https://str.vov.gov.vn/vovlive/vov1vov5Vietnamese.sdp_aac/playlist.m3u8"),
            "vov2" to Pair("Đài VOV2 Văn hóa & Đời sống", "https://str.vov.gov.vn/vovlive/vov2.sdp_aac/playlist.m3u8"),
            "vov3" to Pair("Đài VOV3 Âm nhạc", "https://str.vov.gov.vn/vovlive/vov3.sdp_aac/playlist.m3u8"),
            "vovgt_hcm" to Pair("VOV Giao thông TP.HCM", "https://str.vov.gov.vn/vovlive/vovGTHCM.sdp_aac/playlist.m3u8"),
            "vovgt_hn" to Pair("VOV Giao thông Hà Nội", "https://str.vov.gov.vn/vovlive/vovGTHN.sdp_aac/playlist.m3u8")
        )
    }

    private val running = AtomicBoolean(false)
    private var serverSocket: ServerSocket? = null
    private val pool = Executors.newCachedThreadPool()
    private var radioPlayer: MediaPlayer? = null
    @Volatile
    var currentRadioTitle: String = ""
        private set

    fun start() {
        if (running.getAndSet(true)) return
        Thread({
            try {
                val srv = ServerSocket(PORT, 16, InetAddress.getByName("127.0.0.1"))
                serverSocket = srv
                Log.i(TAG, "MinaLocalMcpServer started at http://127.0.0.1:$PORT/mcp")
                while (running.get()) {
                    val client = srv.accept()
                    pool.execute { handleClient(client) }
                }
            } catch (e: Throwable) {
                if (running.get()) {
                    Log.e(TAG, "Server loop error: ${e.message}")
                }
            }
        }, "MinaMcpAccept").start()
    }

    fun stop() {
        running.set(false)
        stopRadio()
        try {
            serverSocket?.close()
        } catch (_: Throwable) {
        }
        serverSocket = null
    }

    @Synchronized
    fun playRadio(channelKey: String): String {
        stopRadio()
        val key = channelKey.trim().lowercase()
        val entry = VOV_STREAMS[key] ?: VOV_STREAMS["vov3"]!!
        return try {
            val mp = MediaPlayer()
            mp.setAudioAttributes(
                AudioAttributes.Builder()
                    .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .build()
            )
            mp.setDataSource(entry.second)
            mp.setOnPreparedListener { it.start() }
            mp.prepareAsync()
            radioPlayer = mp
            currentRadioTitle = entry.first
            "Đang mở trực tuyến ${entry.first}."
        } catch (e: Throwable) {
            currentRadioTitle = ""
            "Không mở được đài ${entry.first}: ${e.message}"
        }
    }

    @Synchronized
    fun stopRadio(): String {
        val prev = currentRadioTitle
        try {
            radioPlayer?.stop()
        } catch (_: Throwable) {
        }
        try {
            radioPlayer?.release()
        } catch (_: Throwable) {
        }
        radioPlayer = null
        currentRadioTitle = ""
        return if (prev.isNotEmpty()) "Đã tắt $prev." else "Radio đang tắt."
    }

    private fun handleClient(socket: Socket) {
        socket.use { sock ->
            sock.soTimeout = 10000
            val reader = BufferedReader(InputStreamReader(sock.getInputStream(), StandardCharsets.UTF_8))
            val out = sock.getOutputStream()

            val requestLine = reader.readLine() ?: return
            val parts = requestLine.split(" ")
            val method = parts.getOrNull(0)?.uppercase() ?: "GET"
            val path = parts.getOrNull(1) ?: "/"

            var contentLength = 0
            while (true) {
                val hdr = reader.readLine() ?: break
                if (hdr.isEmpty()) break
                if (hdr.lowercase().startsWith("content-length:")) {
                    contentLength = hdr.substringAfter(":").trim().toIntOrNull() ?: 0
                }
            }

            if (method == "OPTIONS") {
                writeHttpResponse(out, 200, "application/json", "")
                return
            }

            if (method == "GET") {
                val route = path.substringBefore("?")
                val q = parseQuery(path.substringAfter("?", ""))
                when (route) {
                    "/audio_diag" -> {
                        val report = runAudioDiagnostics(q["keep_yield"] == "1")
                        writeHttpResponse(out, 200, "application/json; charset=utf-8", report.toString(2))
                        return
                    }
                    "/record_wav" -> {
                        val src = q["source"]?.toIntOrNull() ?: MediaRecorder.AudioSource.MIC
                        val stereo = (q["stereo"] ?: "1") == "1"
                        val rate = (q["rate"]?.toIntOrNull() ?: 16000).coerceIn(8000, 48000)
                        val ms = (q["ms"]?.toIntOrNull() ?: 3000).coerceIn(300, 8000)
                        val hal = q["hal"] ?: ""
                        val wavBytes = captureWavBytes(src, stereo, rate, ms, hal, q["keep_yield"] == "1")
                        writeBinaryResponse(out, 200, "audio/wav", wavBytes)
                        return
                    }
                    "/audio_param" -> {
                        val res = handleAudioParam(q)
                        writeHttpResponse(out, 200, "application/json; charset=utf-8", res.toString(2))
                        return
                    }
                    else -> {
                        val info = JSONObject()
                            .put("status", "ok")
                            .put("service", "MinaLilyBridge")
                            .put("version", "1.0.6")
                            .put("mcpEndpoint", "http://127.0.0.1:$PORT/mcp")
                            .put("state", MinaBridgeService.currentState)
                            .put("detail", MinaBridgeService.statusDetail)
                            .put("lastPeak", MinaBridgeService.lastPeakLevel)
                            .put("lastTrigger", MinaBridgeService.lastTriggerInfo)
                            .put("radioPlaying", currentRadioTitle)
                        writeHttpResponse(out, 200, "application/json; charset=utf-8", info.toString())
                        return
                    }
                }
            }

            val bodyChars = CharArray(contentLength.coerceIn(0, 262144))
            var totalRead = 0
            while (totalRead < bodyChars.size) {
                val n = reader.read(bodyChars, totalRead, bodyChars.size - totalRead)
                if (n <= 0) break
                totalRead += n
            }
            val bodyStr = String(bodyChars, 0, totalRead).trim()
            if (bodyStr.isEmpty() || !path.startsWith("/mcp")) {
                writeHttpResponse(out, 400, "application/json", """{"error":"Invalid MCP request"}""")
                return
            }

            val rpc = JSONObject(bodyStr)
            val reply = handleJsonRpc(rpc)
            if (reply == null) {
                writeHttpResponse(out, 202, "application/json", "")
            } else {
                writeHttpResponse(out, 200, "application/json; charset=utf-8", reply.toString())
            }
        }
    }

    private fun handleJsonRpc(rpc: JSONObject): JSONObject? {
        val method = rpc.optString("method", "")
        val hasId = rpc.has("id") && !rpc.isNull("id")
        val idVal = rpc.opt("id")

        if (method == "notifications/initialized" || !hasId) {
            return null
        }

        return when (method) {
            "initialize" -> {
                JSONObject()
                    .put("jsonrpc", "2.0")
                    .put("id", idVal)
                    .put(
                        "result",
                        JSONObject()
                            .put("protocolVersion", "2024-11-05")
                            .put("capabilities", JSONObject().put("tools", JSONObject()))
                            .put(
                                "serverInfo",
                                JSONObject()
                                    .put("name", "MinaLilyBridge")
                                    .put("version", "1.0.0")
                            )
                    )
            }
            "tools/list" -> {
                JSONObject()
                    .put("jsonrpc", "2.0")
                    .put("id", idVal)
                    .put("result", JSONObject().put("tools", buildToolsArray()))
            }
            "tools/call" -> {
                val params = rpc.optJSONObject("params") ?: JSONObject()
                val name = params.optString("name", "")
                val args = params.optJSONObject("arguments") ?: JSONObject()
                var isErr = false
                val text = try {
                    executeTool(name, args)
                } catch (e: Throwable) {
                    isErr = true
                    "Lỗi thực thi $name: ${e.message}"
                }
                JSONObject()
                    .put("jsonrpc", "2.0")
                    .put("id", idVal)
                    .put(
                        "result",
                        JSONObject()
                            .put(
                                "content",
                                JSONArray().put(
                                    JSONObject()
                                        .put("type", "text")
                                        .put("text", text)
                                )
                            )
                            .put("isError", isErr)
                    )
            }
            else -> {
                JSONObject()
                    .put("jsonrpc", "2.0")
                    .put("id", idVal)
                    .put("error", JSONObject().put("code", -32601).put("message", "Method not found: $method"))
            }
        }
    }

    private fun buildToolsArray(): JSONArray {
        val arr = JSONArray()
        arr.put(
            JSONObject()
                .put("name", "mina_play_radio")
                .put("description", "Mở đài phát thanh Radio VOV trực tuyến trên robot (vov1, vov2, vov3, vovgt_hcm, vovgt_hn)")
                .put(
                    "inputSchema",
                    JSONObject()
                        .put("type", "object")
                        .put(
                            "properties",
                            JSONObject().put(
                                "channel",
                                JSONObject()
                                    .put("type", "string")
                                    .put("description", "Mã kênh: vov1, vov2, vov3, vovgt_hcm, vovgt_hn")
                            )
                        )
                )
        )
        arr.put(
            JSONObject()
                .put("name", "mina_stop_radio")
                .put("description", "Tắt đài Radio VOV đang phát")
                .put("inputSchema", JSONObject().put("type", "object").put("properties", JSONObject()))
        )
        arr.put(
            JSONObject()
                .put("name", "mina_robot_status")
                .put("description", "Kiểm tra phần trăm pin, điện áp, nhiệt độ và mạng Wi-Fi của robot Visbot")
                .put("inputSchema", JSONObject().put("type", "object").put("properties", JSONObject()))
        )
        arr.put(
            JSONObject()
                .put("name", "mina_open_app")
                .put("description", "Mở ứng dụng giải trí hoặc cài đặt trên robot (smarttube, youtube, zingmp3, mstore, wifi)")
                .put(
                    "inputSchema",
                    JSONObject()
                        .put("type", "object")
                        .put(
                            "properties",
                            JSONObject().put(
                                "app",
                                JSONObject()
                                    .put("type", "string")
                                    .put("description", "Tên app: smarttube, youtube, zingmp3, mstore, wifi")
                            )
                        )
                )
        )
        arr.put(
            JSONObject()
                .put("name", "mina_visbot_move")
                .put("description", "Điều khiển bánh xe robot Visbot di chuyển: forward (tiến), backward (lùi), turn_left (quay trái), turn_right (quay phải), stop (dừng)")
                .put(
                    "inputSchema",
                    JSONObject()
                        .put("type", "object")
                        .put(
                            "properties",
                            JSONObject()
                                .put("direction", JSONObject().put("type", "string").put("description", "forward, backward, turn_left, turn_right, stop"))
                                .put("durationMs", JSONObject().put("type", "integer").put("description", "Thời gian chạy mili-giây (200..5000, mặc định 1200)"))
                        )
                )
        )
        arr.put(
            JSONObject()
                .put("name", "mina_visbot_head")
                .put("description", "Điều khiển đầu/cổ robot Visbot: nod (gật đầu), up (ngẩng lên), down (cúi xuống), center (nhìn thẳng)")
                .put(
                    "inputSchema",
                    JSONObject()
                        .put("type", "object")
                        .put(
                            "properties",
                            JSONObject().put("action", JSONObject().put("type", "string").put("description", "nod, up, down, center"))
                        )
                )
        )
        arr.put(
            JSONObject()
                .put("name", "mina_visbot_dance")
                .put("description", "Cho robot Visbot nhảy múa vui nhộn kết hợp xoay bánh xe và gật đầu")
                .put("inputSchema", JSONObject().put("type", "object").put("properties", JSONObject()))
        )
        return arr
    }

    private fun executeTool(name: String, args: JSONObject): String {
        return when (name) {
            "mina_play_radio" -> playRadio(args.optString("channel", "vov3"))
            "mina_stop_radio" -> stopRadio()
            "mina_robot_status" -> readRobotStatus()
            "mina_open_app" -> openRobotApp(args.optString("app", ""))
            "mina_visbot_move" -> {
                if (!VisbotMotorController.isInitialized) VisbotMotorController.init(appContext)
                VisbotMotorController.move(args.optString("direction", "forward"), args.optLong("durationMs", 1200L))
            }
            "mina_visbot_head" -> {
                if (!VisbotMotorController.isInitialized) VisbotMotorController.init(appContext)
                VisbotMotorController.head(args.optString("action", "nod"))
            }
            "mina_visbot_dance" -> {
                if (!VisbotMotorController.isInitialized) VisbotMotorController.init(appContext)
                VisbotMotorController.dance()
            }
            else -> "Không nhận diện được công cụ $name"
        }
    }

    private fun readRobotStatus(): String {
        val bm = appContext.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        val level = bm?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
        val voltMv = bm?.getIntExtra(BatteryManager.EXTRA_VOLTAGE, -1) ?: -1
        val tempTenth = bm?.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, -1) ?: -1
        val status = bm?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
        val charging = status == BatteryManager.BATTERY_STATUS_CHARGING || status == BatteryManager.BATTERY_STATUS_FULL
        val wm = appContext.applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
        val ssid = wm?.connectionInfo?.ssid?.replace("\"", "") ?: "Unknown"
        return "Pin: $level% (${voltMv}mV, ${tempTenth / 10.0}°C, đang sạc=$charging) | Wi-Fi: $ssid | Radio: ${currentRadioTitle.ifEmpty { "Tắt" }}"
    }

    private fun openRobotApp(appKey: String): String {
        val k = appKey.trim().lowercase()
        if (k == "wifi") {
            appContext.startActivity(Intent(Settings.ACTION_WIFI_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            return "Đã mở Cài đặt Wi-Fi."
        }
        val pkg = when {
            k.contains("smart") -> "org.smarttube.stable"
            k.contains("you") -> "com.google.android.youtube.tv"
            k.contains("zing") || k.contains("mp3") -> "vng.zing.mp3"
            k.contains("mstore") -> "tungbui.mstore"
            else -> return "Ứng dụng '$appKey' không nằm trong danh sách hỗ trợ."
        }
        val launch = appContext.packageManager.getLaunchIntentForPackage(pkg)
            ?: return "Ứng dụng $pkg chưa được cài trên robot."
        launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        appContext.startActivity(launch)
        return "Đã mở ứng dụng $pkg."
    }

    private fun parseQuery(qs: String): Map<String, String> {
        if (qs.isBlank()) return emptyMap()
        val map = LinkedHashMap<String, String>()
        for (pair in qs.split("&")) {
            if (pair.isBlank()) continue
            val k = URLDecoder.decode(pair.substringBefore("="), "UTF-8")
            val v = URLDecoder.decode(pair.substringAfter("=", ""), "UTF-8")
            map[k] = v
        }
        return map
    }

    private fun yieldBridgeMic() {
        val svc = Intent(appContext, MinaBridgeService::class.java).setAction(MinaBridgeService.ACTION_YIELD_30S)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            appContext.startForegroundService(svc)
        } else {
            appContext.startService(svc)
        }
        Thread.sleep(420)
    }

    private fun resumeBridgeMicIfEnabled() {
        val prefs = appContext.getSharedPreferences(MinaBridgeService.PREFS_NAME, Context.MODE_PRIVATE)
        if (prefs.getBoolean(MinaBridgeService.KEY_ENABLED, true)) {
            val svc = Intent(appContext, MinaBridgeService::class.java).setAction(MinaBridgeService.ACTION_START_LISTENING)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                appContext.startForegroundService(svc)
            } else {
                appContext.startService(svc)
            }
        }
    }

    private fun computeChannelStats(samples: ShortArray, count: Int): JSONObject {
        if (count <= 0) return JSONObject().put("samples", 0)
        var minV = Int.MAX_VALUE
        var maxV = Int.MIN_VALUE
        var sum = 0.0
        for (i in 0 until count) {
            val v = samples[i].toInt()
            if (v < minV) minV = v
            if (v > maxV) maxV = v
            sum += v
        }
        val mean = sum / count
        var sqAc = 0.0
        var acPeak = 0.0
        var hpfPeak = 0
        var hpfSq = 0.0
        var prevX = samples[0].toFloat()
        var prevY = 0f
        var zeroCrossings = 0
        var prevSign = 0
        for (i in 0 until count) {
            val v = samples[i].toInt()
            val ac = v - mean
            sqAc += ac * ac
            if (abs(ac) > acPeak) acPeak = abs(ac)

            val xf = v.toFloat()
            val yf = (xf - prevX) + 0.995f * prevY
            prevX = xf
            prevY = yf
            val yi = yf.toInt().coerceIn(-32768, 32767)
            if (abs(yi) > hpfPeak) hpfPeak = abs(yi)
            hpfSq += (yf * yf).toDouble()

            val sign = if (yi > 15) 1 else if (yi < -15) -1 else 0
            if (sign != 0 && prevSign != 0 && sign != prevSign) {
                zeroCrossings++
            }
            if (sign != 0) prevSign = sign
        }
        val acRms = sqrt(sqAc / count)
        val hpfRms = sqrt(hpfSq / count)
        return JSONObject()
            .put("samples", count)
            .put("min", minV)
            .put("max", maxV)
            .put("dcMean", Math.round(mean * 10.0) / 10.0)
            .put("acRms", Math.round(acRms * 10.0) / 10.0)
            .put("acPeak", Math.round(acPeak))
            .put("hpfRms", Math.round(hpfRms * 10.0) / 10.0)
            .put("hpfPeak", hpfPeak)
            .put("zeroCrossings", zeroCrossings)
    }

    @SuppressLint("MissingPermission")
    private fun probeSource(label: String, source: Int, stereo: Boolean, sampleRate: Int, durationMs: Int): JSONObject {
        val out = JSONObject().put("label", label).put("source", source).put("stereo", stereo).put("sampleRate", sampleRate)
        val chMask = if (stereo) AudioFormat.CHANNEL_IN_STEREO else AudioFormat.CHANNEL_IN_MONO
        val minBuf = AudioRecord.getMinBufferSize(sampleRate, chMask, AudioFormat.ENCODING_PCM_16BIT)
        if (minBuf <= 0) return out.put("ok", false).put("error", "minBuf=$minBuf")
        val bufBytes = (minBuf * 4).coerceAtLeast(32768)
        var rec: AudioRecord? = null
        return try {
            rec = AudioRecord(source, sampleRate, chMask, AudioFormat.ENCODING_PCM_16BIT, bufBytes)
            if (rec.state != AudioRecord.STATE_INITIALIZED) {
                out.put("ok", false).put("error", "STATE_UNINITIALIZED")
            } else {
                rec.startRecording()
                if (rec.recordingState != AudioRecord.RECORDSTATE_RECORDING) {
                    out.put("ok", false).put("error", "NOT_RECORDING")
                } else {
                    val chCount = if (stereo) 2 else 1
                    val targetShorts = (sampleRate * durationMs / 1000) * chCount
                    val all = ShortArray(targetShorts)
                    var pos = 0
                    val deadline = System.currentTimeMillis() + durationMs + 500L
                    while (pos < targetShorts && System.currentTimeMillis() < deadline) {
                        val n = rec.read(all, pos, (targetShorts - pos).coerceAtMost(1920))
                        if (n > 0) pos += n else Thread.sleep(10)
                    }
                    // Bỏ 80ms đầu để ổn định mạch analog preamp
                    val skipFrames = (sampleRate * 80 / 1000).coerceAtMost((pos / chCount) / 3)
                    out.put("ok", true)
                    if (stereo) {
                        val frames = (pos / 2) - skipFrames
                        if (frames > 0) {
                            val left = ShortArray(frames)
                            val right = ShortArray(frames)
                            for (f in 0 until frames) {
                                val idx = (f + skipFrames) * 2
                                left[f] = all[idx]
                                right[f] = all[idx + 1]
                            }
                            out.put("left_ADC1", computeChannelStats(left, frames))
                            out.put("right_ADC3", computeChannelStats(right, frames))
                        }
                    } else {
                        val frames = pos - skipFrames
                        if (frames > 0) {
                            val mono = all.copyOfRange(skipFrames, pos)
                            out.put("mono", computeChannelStats(mono, frames))
                        }
                    }
                    out
                }
            }
        } catch (t: Throwable) {
            out.put("ok", false).put("error", t.message ?: "exception")
        } finally {
            try { rec?.stop() } catch (_: Throwable) {}
            try { rec?.release() } catch (_: Throwable) {}
        }
    }

    private fun runAudioDiagnostics(keepYield: Boolean): JSONObject {
        yieldBridgeMic()
        val am = appContext.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val root = JSONObject()
        try {
            root.put("dualMicParam", am.getParameters("Get_Dual_Mic_Setting"))
            root.put("lrSwitchParam", am.getParameters("LRChannelSwitch"))
            val probes = JSONArray()
            probes.put(probeSource("MIC_STEREO_16K", MediaRecorder.AudioSource.MIC, true, 16000, 650))
            probes.put(probeSource("MIC_STEREO_48K", MediaRecorder.AudioSource.MIC, true, 48000, 500))
            probes.put(probeSource("MIC_MONO_16K", MediaRecorder.AudioSource.MIC, false, 16000, 500))
            probes.put(probeSource("CAMCORDER_MONO_16K", MediaRecorder.AudioSource.CAMCORDER, false, 16000, 500))
            probes.put(probeSource("VOICE_RECOG_MONO_16K", MediaRecorder.AudioSource.VOICE_RECOGNITION, false, 16000, 500))
            probes.put(probeSource("VOICE_COMM_MONO_16K", MediaRecorder.AudioSource.VOICE_COMMUNICATION, false, 16000, 500))
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                probes.put(probeSource("UNPROCESSED_STEREO_16K", MediaRecorder.AudioSource.UNPROCESSED, true, 16000, 500))
            }
            root.put("probes", probes)
        } finally {
            if (!keepYield) resumeBridgeMicIfEnabled()
        }
        return root
    }

    @SuppressLint("MissingPermission")
    private fun captureWavBytes(
        source: Int,
        stereo: Boolean,
        sampleRate: Int,
        durationMs: Int,
        halParam: String,
        keepYield: Boolean
    ): ByteArray {
        yieldBridgeMic()
        if (halParam.isNotBlank()) {
            try {
                val am = appContext.getSystemService(Context.AUDIO_SERVICE) as AudioManager
                am.setParameters(halParam)
            } catch (_: Throwable) {
            }
        }
        val chCount = if (stereo) 2 else 1
        val chMask = if (stereo) AudioFormat.CHANNEL_IN_STEREO else AudioFormat.CHANNEL_IN_MONO
        val minBuf = AudioRecord.getMinBufferSize(sampleRate, chMask, AudioFormat.ENCODING_PCM_16BIT).coerceAtLeast(4096)
        val pcmOut = ByteArrayOutputStream()
        var rec: AudioRecord? = null
        try {
            rec = AudioRecord(source, sampleRate, chMask, AudioFormat.ENCODING_PCM_16BIT, (minBuf * 4).coerceAtLeast(32768))
            if (rec.state == AudioRecord.STATE_INITIALIZED) {
                rec.startRecording()
                val targetBytes = sampleRate * chCount * 2 * durationMs / 1000
                val chunk = ByteArray(3840)
                val deadline = System.currentTimeMillis() + durationMs + 800L
                while (pcmOut.size() < targetBytes && System.currentTimeMillis() < deadline) {
                    val n = rec.read(chunk, 0, chunk.size)
                    if (n > 0) pcmOut.write(chunk, 0, n) else Thread.sleep(10)
                }
            }
        } catch (_: Throwable) {
        } finally {
            try { rec?.stop() } catch (_: Throwable) {}
            try { rec?.release() } catch (_: Throwable) {}
            if (!keepYield) resumeBridgeMicIfEnabled()
        }

        val pcm = pcmOut.toByteArray()
        val byteRate = sampleRate * chCount * 2
        val header = ByteBuffer.allocate(44).order(ByteOrder.LITTLE_ENDIAN).apply {
            put("RIFF".toByteArray(StandardCharsets.US_ASCII))
            putInt(36 + pcm.size)
            put("WAVE".toByteArray(StandardCharsets.US_ASCII))
            put("fmt ".toByteArray(StandardCharsets.US_ASCII))
            putInt(16)
            putShort(1) // PCM
            putShort(chCount.toShort())
            putInt(sampleRate)
            putInt(byteRate)
            putShort((chCount * 2).toShort())
            putShort(16)
            put("data".toByteArray(StandardCharsets.US_ASCII))
            putInt(pcm.size)
        }.array()
        return header + pcm
    }

    private fun handleAudioParam(q: Map<String, String>): JSONObject {
        val am = appContext.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val prefs = appContext.getSharedPreferences(MinaBridgeService.PREFS_NAME, Context.MODE_PRIVATE)
        val res = JSONObject()
        q["set"]?.takeIf { it.isNotBlank() }?.let { kv ->
            am.setParameters(kv)
            res.put("appliedSet", kv)
            if (q["persist"] == "1") {
                prefs.edit().putString(MinaBridgeService.KEY_HAL_AUDIO_PARAM, kv).apply()
                res.put("persistedHalParam", kv)
            }
        }
        if (q["clear_hal"] == "1") {
            prefs.edit().remove(MinaBridgeService.KEY_HAL_AUDIO_PARAM).apply()
            res.put("clearedHalParam", true)
        }
        q["route"]?.toIntOrNull()?.let { r ->
            prefs.edit().putInt(MinaBridgeService.KEY_MIC_ROUTE, r).apply()
            res.put("savedMicRoute", r)
        }
        q["gain_x10"]?.toIntOrNull()?.let { g ->
            val clamped = g.coerceIn(5, 120)
            prefs.edit().putInt(MinaBridgeService.KEY_SW_GAIN_X10, clamped).apply()
            res.put("savedSwGainX10", clamped)
        }
        q["get"]?.takeIf { it.isNotBlank() }?.let { gk ->
            res.put("getResult", am.getParameters(gk))
        }
        if (q["reload"] == "1") {
            val svc = Intent(appContext, MinaBridgeService::class.java).setAction(MinaBridgeService.ACTION_RELOAD_CONFIG)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                appContext.startForegroundService(svc)
            } else {
                appContext.startService(svc)
            }
            res.put("reloaded", true)
        }
        res.put("activeHalParam", prefs.getString(MinaBridgeService.KEY_HAL_AUDIO_PARAM, "") ?: "")
        res.put("activeMicRoute", prefs.getInt(MinaBridgeService.KEY_MIC_ROUTE, 0))
        res.put("activeSwGainX10", prefs.getInt(MinaBridgeService.KEY_SW_GAIN_X10, 22))
        return res
    }

    private fun writeBinaryResponse(out: OutputStream, code: Int, contentType: String, bytes: ByteArray) {
        val header = buildString {
            append("HTTP/1.1 $code OK\r\n")
            append("Content-Type: $contentType\r\n")
            append("Content-Length: ${bytes.size}\r\n")
            append("Access-Control-Allow-Origin: *\r\n")
            append("Connection: close\r\n\r\n")
        }
        out.write(header.toByteArray(StandardCharsets.UTF_8))
        if (bytes.isNotEmpty()) out.write(bytes)
        out.flush()
    }

    private fun writeHttpResponse(out: OutputStream, code: Int, contentType: String, body: String) {
        val bytes = body.toByteArray(StandardCharsets.UTF_8)
        val statusText = when (code) {
            200 -> "OK"
            202 -> "Accepted"
            else -> "Bad Request"
        }
        val header = buildString {
            append("HTTP/1.1 $code $statusText\r\n")
            append("Content-Type: $contentType\r\n")
            append("Content-Length: ${bytes.size}\r\n")
            append("Access-Control-Allow-Origin: *\r\n")
            append("Connection: close\r\n\r\n")
        }
        out.write(header.toByteArray(StandardCharsets.UTF_8))
        if (bytes.isNotEmpty()) {
            out.write(bytes)
        }
        out.flush()
    }
}
