package com.mtc.mina_robot

import android.annotation.SuppressLint
import android.app.Activity
import android.content.Intent
import android.graphics.Color
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.FrameLayout
import android.widget.TextView
import java.io.ByteArrayInputStream
import java.lang.ref.WeakReference

/**
 * Trình duyệt chặn quảng cáo cho Mina.
 * Chặn theo danh sách tên miền quảng cáo/theo dõi trong assets/adblock_hosts.txt
 * (khớp cả tên miền con). Lưu ý: quảng cáo phát chung luồng với video YouTube
 * thì chặn theo tên miền không loại bỏ hết được.
 */
class BrowserActivity : Activity() {
    companion object {
        const val EXTRA_URL = "url"
        var current: WeakReference<BrowserActivity>? = null

        @Volatile
        private var blockedHosts: Set<String>? = null
    }

    private lateinit var webView: WebView
    private lateinit var root: FrameLayout
    private var customView: View? = null
    private var customViewCallback: WebChromeClient.CustomViewCallback? = null

    @SuppressLint("SetJavaScriptEnabled")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        current = WeakReference(this)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        loadBlocklist()

        root = FrameLayout(this).apply { setBackgroundColor(Color.BLACK) }
        webView = WebView(this)
        webView.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true
            mediaPlaybackRequiresUserGesture = false
            loadWithOverviewMode = true
            useWideViewPort = true
            builtInZoomControls = true
            displayZoomControls = false
            mixedContentMode = WebSettings.MIXED_CONTENT_COMPATIBILITY_MODE
        }
        webView.webViewClient = object : WebViewClient() {
            override fun shouldInterceptRequest(view: WebView, request: WebResourceRequest): WebResourceResponse? {
                val host = request.url.host ?: return null
                if (isBlocked(host)) {
                    return WebResourceResponse("text/plain", "utf-8", ByteArrayInputStream(ByteArray(0)))
                }
                return null
            }

            override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                val scheme = request.url.scheme ?: return false
                if (scheme == "http" || scheme == "https") return false
                // intent://, market:// ... -> bỏ qua để không thoát khỏi trình duyệt
                return true
            }
        }
        webView.webChromeClient = object : WebChromeClient() {
            override fun onShowCustomView(view: View, callback: CustomViewCallback) {
                customView = view
                customViewCallback = callback
                root.addView(view, FrameLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
                webView.visibility = View.GONE
            }

            override fun onHideCustomView() {
                exitFullscreen()
            }
        }
        root.addView(webView, FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))

        // Nút đóng nhỏ ở góc phải
        val close = TextView(this).apply {
            text = "✕"
            textSize = 16f
            setTextColor(Color.WHITE)
            setBackgroundColor(0x99000000.toInt())
            gravity = Gravity.CENTER
            setOnClickListener { finish() }
        }
        val size = (32 * resources.displayMetrics.density).toInt()
        root.addView(close, FrameLayout.LayoutParams(size, size, Gravity.TOP or Gravity.END))

        setContentView(root)
        webView.loadUrl(intent.getStringExtra(EXTRA_URL) ?: "https://www.google.com")
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        intent.getStringExtra(EXTRA_URL)?.let { webView.loadUrl(it) }
    }

    private fun exitFullscreen() {
        customView?.let { root.removeView(it) }
        customView = null
        customViewCallback?.onCustomViewHidden()
        customViewCallback = null
        webView.visibility = View.VISIBLE
    }

    @Deprecated("Deprecated in Java")
    override fun onBackPressed() {
        when {
            customView != null -> exitFullscreen()
            webView.canGoBack() -> webView.goBack()
            else -> super.onBackPressed()
        }
    }

    override fun onPause() {
        super.onPause()
        webView.onPause()
    }

    override fun onResume() {
        super.onResume()
        webView.onResume()
    }

    override fun onDestroy() {
        if (current?.get() === this) current = null
        try {
            webView.loadUrl("about:blank")
            webView.destroy()
        } catch (_: Throwable) {
        }
        super.onDestroy()
    }

    private fun loadBlocklist() {
        if (blockedHosts != null) return
        blockedHosts = try {
            assets.open("adblock_hosts.txt").bufferedReader().useLines { lines ->
                lines.map { it.substringBefore('#').trim().lowercase() }
                    .filter { it.isNotEmpty() }
                    .toHashSet()
            }
        } catch (_: Throwable) {
            emptySet()
        }
    }

    /** Khớp tên miền và mọi tên miền cha (ads.example.com chặn khi danh sách có example.com). */
    private fun isBlocked(host: String): Boolean {
        val set = blockedHosts ?: return false
        var h = host.lowercase()
        while (true) {
            if (set.contains(h)) return true
            val dot = h.indexOf('.')
            if (dot < 0 || dot == h.length - 1) return false
            h = h.substring(dot + 1)
            if (!h.contains('.')) return false
        }
    }
}
