package com.mtc.minalilybridge

import android.Manifest
import android.app.Activity
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.text.InputType
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.Button
import android.widget.CheckBox
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast

/**
 * Giao diện điều khiển gọn nhẹ tối ưu riêng cho màn hình 308x240 px của UBTECH Visbot.
 */
class MainActivity : Activity() {

    private lateinit var tvStateBadge: TextView
    private lateinit var tvDetail: TextView
    private lateinit var tvLastTrigger: TextView
    private lateinit var pbMicLevel: ProgressBar
    private lateinit var btnToggle: Button
    private lateinit var etKeywords: EditText
    private lateinit var sensitivityButtons: List<Pair<Float, Button>>

    private val uiHandler = Handler(Looper.getMainLooper())
    private val meterRunnable = object : Runnable {
        override fun run() {
            refreshStatusViews()
            uiHandler.postDelayed(this, 350L)
        }
    }

    private val uiReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            refreshStatusViews()
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        buildCompactVisbotUi()
        ensureRecordAudioPermissionAndStart()
    }

    override fun onResume() {
        super.onResume()
        val filter = IntentFilter(MinaBridgeService.ACTION_UI_UPDATE)
        if (Build.VERSION.SDK_INT >= 33) {
            registerReceiver(uiReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(uiReceiver, filter)
        }
        loadKeywordsEditor()
        refreshStatusViews()
        uiHandler.post(meterRunnable)
    }

    override fun onPause() {
        uiHandler.removeCallbacks(meterRunnable)
        try {
            unregisterReceiver(uiReceiver)
        } catch (_: Throwable) {
        }
        super.onPause()
    }

    private fun ensureRecordAudioPermissionAndStart() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
            checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), 101)
            return
        }
        val prefs = getSharedPreferences(MinaBridgeService.PREFS_NAME, Context.MODE_PRIVATE)
        if (prefs.getBoolean(MinaBridgeService.KEY_ENABLED, true)) {
            sendServiceAction(MinaBridgeService.ACTION_START_LISTENING)
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 101 && grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
            sendServiceAction(MinaBridgeService.ACTION_START_LISTENING)
        }
    }

    private fun sendServiceAction(action: String) {
        val svc = Intent(this, MinaBridgeService::class.java).setAction(action)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(svc)
        } else {
            startService(svc)
        }
    }

    private fun dp(v: Int): Int = (v * resources.displayMetrics.density).toInt().coerceAtLeast(1)

    private fun roundedBg(fillColor: Int, strokeColor: Int = Color.TRANSPARENT, radiusDp: Int = 8): GradientDrawable {
        return GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            cornerRadius = dp(radiusDp).toFloat()
            setColor(fillColor)
            if (strokeColor != Color.TRANSPARENT) {
                setStroke(dp(1), strokeColor)
            }
        }
    }

    private fun buildCompactVisbotUi() {
        val scroll = ScrollView(this).apply {
            setBackgroundColor(Color.parseColor("#F5F7FA"))
            isFillViewport = true
        }

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            isFocusable = true
            isFocusableInTouchMode = true
            setPadding(dp(8), dp(6), dp(8), dp(10))
        }

        // 1. Tiêu đề + Huy hiệu trạng thái trực tiếp
        tvStateBadge = TextView(this).apply {
            text = "MINA BRIDGE -> LILY VIP"
            textSize = 12f
            typeface = Typeface.DEFAULT_BOLD
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
            setPadding(dp(8), dp(6), dp(8), dp(6))
            background = roundedBg(Color.parseColor("#16A34A"))
        }
        root.addView(tvStateBadge, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))

        // 2. Hộp trạng thái chi tiết + Thanh âm lượng Mic
        val cardStatus = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(8), dp(6), dp(8), dp(6))
            background = roundedBg(Color.WHITE, Color.parseColor("#CBD5E1"))
        }

        tvDetail = TextView(this).apply {
            text = "Đang khởi tạo..."
            textSize = 11f
            setTextColor(Color.parseColor("#0F172A"))
        }
        cardStatus.addView(tvDetail)

        pbMicLevel = ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal).apply {
            max = 8000
            progress = 0
        }
        cardStatus.addView(
            pbMicLevel,
            LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(8)).apply {
                topMargin = dp(4)
                bottomMargin = dp(4)
            }
        )

        tvLastTrigger = TextView(this).apply {
            text = "Lượt gọi gần nhất: Chưa có"
            textSize = 10f
            setTextColor(Color.parseColor("#475569"))
        }
        cardStatus.addView(tvLastTrigger)

        root.addView(
            cardStatus,
            LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply {
                topMargin = dp(6)
            }
        )

        // 3. Hàng nút chính: Bật/Tắt nghe & Gọi thử Lily ngay
        val rowActions = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
        }

        btnToggle = Button(this).apply {
            text = "TẠM DỪNG"
            textSize = 10.5f
            isAllCaps = false
            setTextColor(Color.WHITE)
            background = roundedBg(Color.parseColor("#2563EB"), radiusDp = 6)
            setOnClickListener {
                val prefs = getSharedPreferences(MinaBridgeService.PREFS_NAME, Context.MODE_PRIVATE)
                val currentlyOn = prefs.getBoolean(MinaBridgeService.KEY_ENABLED, true) &&
                    MinaBridgeService.currentState != MinaBridgeService.STATE_PAUSED
                if (currentlyOn) {
                    sendServiceAction(MinaBridgeService.ACTION_PAUSE_LISTENING)
                } else {
                    sendServiceAction(MinaBridgeService.ACTION_START_LISTENING)
                }
            }
        }
        rowActions.addView(
            btnToggle,
            LinearLayout.LayoutParams(0, dp(36), 1f).apply { rightMargin = dp(4) }
        )

        val btnWakeNow = Button(this).apply {
            text = "GỌI LILY VIP NGAY"
            textSize = 10.5f
            isAllCaps = false
            setTextColor(Color.WHITE)
            background = roundedBg(Color.parseColor("#0D9488"), radiusDp = 6)
            setOnClickListener {
                sendServiceAction(MinaBridgeService.ACTION_WAKE_LILY_NOW)
            }
        }
        rowActions.addView(
            btnWakeNow,
            LinearLayout.LayoutParams(0, dp(36), 1.15f)
        )

        root.addView(
            rowActions,
            LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply {
                topMargin = dp(6)
            }
        )

        // 4. Chọn độ nhạy nhận diện từ khóa
        val tvSensLabel = TextView(this).apply {
            text = "Độ nhạy câu gọi \"Mina ơi\":"
            textSize = 10.5f
            typeface = Typeface.DEFAULT_BOLD
            setTextColor(Color.parseColor("#1E293B"))
        }
        root.addView(
            tvSensLabel,
            LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply {
                topMargin = dp(8)
            }
        )

        val rowSens = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        val presets = listOf(
            Triple(0.11f, "Rất nhạy", "0.11"),
            Triple(0.15f, "Chuẩn", "0.15"),
            Triple(0.24f, "Chống ồn", "0.24")
        )
        val btnList = mutableListOf<Pair<Float, Button>>()
        for ((idx, item) in presets.withIndex()) {
            val b = Button(this).apply {
                text = "${item.second} (${item.third})"
                textSize = 9.5f
                isAllCaps = false
                setOnClickListener {
                    getSharedPreferences(MinaBridgeService.PREFS_NAME, Context.MODE_PRIVATE)
                        .edit()
                        .putFloat(MinaBridgeService.KEY_THRESHOLD, item.first)
                        .apply()
                    sendServiceAction(MinaBridgeService.ACTION_RELOAD_CONFIG)
                    updateSensitivityButtonStyles()
                    Toast.makeText(this@MainActivity, "Đã đặt ngưỡng: ${item.second}", Toast.LENGTH_SHORT).show()
                }
            }
            btnList.add(Pair(item.first, b))
            rowSens.addView(
                b,
                LinearLayout.LayoutParams(0, dp(32), 1f).apply {
                    if (idx < presets.size - 1) rightMargin = dp(4)
                }
            )
        }
        sensitivityButtons = btnList
        updateSensitivityButtonStyles()
        root.addView(
            rowSens,
            LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply {
                topMargin = dp(3)
            }
        )

        // 5. Tùy chọn khởi động cùng Robot & Tiếng báo "Ting"
        val prefs = getSharedPreferences(MinaBridgeService.PREFS_NAME, Context.MODE_PRIVATE)
        val cbAutoBoot = CheckBox(this).apply {
            text = "Tự chạy ngầm khi bật nguồn Robot"
            textSize = 10.5f
            isChecked = prefs.getBoolean(MinaBridgeService.KEY_AUTO_BOOT, true)
            setOnCheckedChangeListener { _, checked ->
                prefs.edit().putBoolean(MinaBridgeService.KEY_AUTO_BOOT, checked).apply()
            }
        }
        root.addView(cbAutoBoot)

        val cbBeep = CheckBox(this).apply {
            text = "Phát tiếng 'Ting' nhẹ khi nghe \"Mina ơi\""
            textSize = 10.5f
            isChecked = prefs.getBoolean(MinaBridgeService.KEY_PLAY_BEEP, true)
            setOnCheckedChangeListener { _, checked ->
                prefs.edit().putBoolean(MinaBridgeService.KEY_PLAY_BEEP, checked).apply()
            }
        }
        root.addView(cbBeep)

        // 6. Trình sửa nhanh file keywords.txt (Open-Vocabulary Phonemes)
        val tvKwLabel = TextView(this).apply {
            text = "Từ khóa đánh thức (keywords.txt):"
            textSize = 10.5f
            typeface = Typeface.DEFAULT_BOLD
            setTextColor(Color.parseColor("#1E293B"))
        }
        root.addView(
            tvKwLabel,
            LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply {
                topMargin = dp(6)
            }
        )

        etKeywords = EditText(this).apply {
            textSize = 9.5f
            typeface = Typeface.MONOSPACE
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_MULTI_LINE or InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS
            minLines = 4
            maxLines = 7
            gravity = Gravity.TOP or Gravity.START
            setPadding(dp(6), dp(6), dp(6), dp(6))
            background = roundedBg(Color.WHITE, Color.parseColor("#94A3B8"), radiusDp = 6)
        }
        root.addView(
            etKeywords,
            LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply {
                topMargin = dp(3)
            }
        )

        val btnSaveKw = Button(this).apply {
            text = "Lưu từ khóa & Nạp lại Sherpa-ONNX"
            textSize = 10f
            isAllCaps = false
            setTextColor(Color.WHITE)
            background = roundedBg(Color.parseColor("#4F46E5"), radiusDp = 6)
            setOnClickListener {
                val content = etKeywords.text.toString().trim()
                if (content.isNotEmpty()) {
                    MinaBridgeService.getKeywordsFile(this@MainActivity).writeText(content + "\n", Charsets.UTF_8)
                    sendServiceAction(MinaBridgeService.ACTION_RELOAD_CONFIG)
                    Toast.makeText(this@MainActivity, "Đã cập nhật keywords.txt!", Toast.LENGTH_SHORT).show()
                }
            }
        }
        root.addView(
            btnSaveKw,
            LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(34)).apply {
                topMargin = dp(4)
            }
        )

        // 7. Chân trang hiển thị cổng MCP nội bộ
        val tvMcpInfo = TextView(this).apply {
            text = "Cổng MCP nội bộ: http://127.0.0.1:${MinaLocalMcpServer.PORT}/mcp\n(Sherpa-ONNX 32-bit armeabi-v7a | 1 Thread | Auto Mic Hand-off)"
            textSize = 9.5f
            setTextColor(Color.parseColor("#64748B"))
            setPadding(dp(2), dp(8), dp(2), dp(4))
        }
        root.addView(tvMcpInfo)

        scroll.addView(root)
        setContentView(scroll)
    }

    private fun updateSensitivityButtonStyles() {
        val cur = getSharedPreferences(MinaBridgeService.PREFS_NAME, Context.MODE_PRIVATE)
            .getFloat(MinaBridgeService.KEY_THRESHOLD, 0.15f)
        for ((thr, btn) in sensitivityButtons) {
            val active = kotlin.math.abs(cur - thr) < 0.01f
            btn.setTextColor(if (active) Color.WHITE else Color.parseColor("#1E293B"))
            btn.background = roundedBg(
                if (active) Color.parseColor("#2563EB") else Color.parseColor("#E2E8F0"),
                radiusDp = 6
            )
        }
    }

    private fun loadKeywordsEditor() {
        try {
            val kwFile = MinaBridgeService.getKeywordsFile(this)
            if (kwFile.exists()) {
                etKeywords.setText(kwFile.readText(Charsets.UTF_8))
            } else {
                val txt = assets.open("models/kws/keywords.txt").bufferedReader(Charsets.UTF_8).use { it.readText() }
                etKeywords.setText(txt)
            }
        } catch (_: Throwable) {
        }
    }

    private fun refreshStatusViews() {
        val st = MinaBridgeService.currentState
        tvDetail.text = MinaBridgeService.statusDetail
        tvLastTrigger.text = "Gần nhất: ${MinaBridgeService.lastTriggerInfo}"
        pbMicLevel.progress = MinaBridgeService.lastPeakLevel.coerceIn(0, 8000)

        when (st) {
            MinaBridgeService.STATE_LISTENING -> {
                tvStateBadge.text = "● ĐANG NGHE \"MINA ƠI\" (OFFLINE)"
                tvStateBadge.background = roundedBg(Color.parseColor("#16A34A"))
                btnToggle.text = "TẠM DỪNG NGHE"
                btnToggle.background = roundedBg(Color.parseColor("#DC2626"), radiusDp = 6)
            }
            MinaBridgeService.STATE_YIELDED -> {
                tvStateBadge.text = "⇄ ĐANG NHƯỜNG MIC CHO LILY VIP"
                tvStateBadge.background = roundedBg(Color.parseColor("#0284C7"))
                btnToggle.text = "TẠM DỪNG NGHE"
                btnToggle.background = roundedBg(Color.parseColor("#DC2626"), radiusDp = 6)
            }
            MinaBridgeService.STATE_ERROR -> {
                tvStateBadge.text = "⚠ LỖI CẦU NỐI"
                tvStateBadge.background = roundedBg(Color.parseColor("#DC2626"))
                btnToggle.text = "THỬ BẬT LẠI"
                btnToggle.background = roundedBg(Color.parseColor("#16A34A"), radiusDp = 6)
            }
            else -> {
                tvStateBadge.text = "⏸ ĐANG TẠM DỪNG"
                tvStateBadge.background = roundedBg(Color.parseColor("#64748B"))
                btnToggle.text = "BẬT NGHE \"MINA ƠI\""
                btnToggle.background = roundedBg(Color.parseColor("#16A34A"), radiusDp = 6)
            }
        }
    }
}
