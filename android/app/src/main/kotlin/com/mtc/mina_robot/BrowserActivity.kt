package com.mtc.mina_robot

import android.annotation.SuppressLint
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
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
import android.widget.LinearLayout
import android.widget.TextView
import java.io.ByteArrayInputStream
import java.lang.ref.WeakReference

/**
 * Trình duyệt chặn quảng cáo & hỗ trợ phát nhạc nền khi tắt màn hình cho Mina.
 * - Chặn tên miền quảng cáo/theo dõi trong assets/adblock_hosts.txt.
 * - Tự động tua/bỏ qua quảng cáo video YouTube và chặn sự kiện tạm dừng khi tắt màn hình.
 * - Tích hợp nút "🌙" tắt tối đen màn hình (nhạc vẫn phát bình thường, chạm để sáng lại).
 */
class BrowserActivity : Activity() {
    companion object {
        const val EXTRA_URL = "url"
        var current: WeakReference<BrowserActivity>? = null

        @Volatile
        private var blockedHosts: Set<String>? = null

        private const val YT_ADBLOCK_AND_BG_SCRIPT = """
            (function() {
              if (window.__minaBgHooked) return;
              window.__minaBgHooked = true;
              try {
                Object.defineProperty(document, 'hidden', { get: function() { return false; }, configurable: true });
                Object.defineProperty(document, 'webkitHidden', { get: function() { return false; }, configurable: true });
                Object.defineProperty(document, 'visibilityState', { get: function() { return 'visible'; }, configurable: true });
                window.addEventListener('visibilitychange', function(e) { e.stopImmediatePropagation(); }, true);
                window.addEventListener('webkitvisibilitychange', function(e) { e.stopImmediatePropagation(); }, true);
              } catch (e) {}

              var style = document.createElement('style');
              style.innerHTML = 'ytm-promoted-sparkles-web-renderer, ytm-companion-ad-renderer, .ad-interrupting, .video-ads, .ytp-ad-module, .ytp-ad-overlay-container { display: none !important; }';
              if (document.head) document.head.appendChild(style);

              setInterval(function() {
                try {
                  var skipBtns = document.querySelectorAll('.ytp-ad-skip-button, .ytp-ad-skip-button-modern, .ytp-skip-ad-button');
                  for (var i = 0; i < skipBtns.length; i++) { skipBtns[i].click(); }
                  var player = document.querySelector('.html5-video-player.ad-showing video');
                  if (player && !isNaN(player.duration) && player.duration > 0) {
                    player.muted = true;
                    player.currentTime = player.duration;
                  }
                } catch (e) {}
              }, 600);
            })();
        """
    }

    /** WebView giữ trạng thái hiển thị ảo để không bị Android ngắt tiếng khi tắt màn hình hoặc ẩn xuống nền. */
    private class BackgroundAudioWebView(context: Context) : WebView(context) {
        var keepAudioAliveInBackground: Boolean = true

        override fun onWindowVisibilityChanged(visibility: Int) {
            if (keepAudioAliveInBackground && visibility != View.VISIBLE) {
                super.onWindowVisibilityChanged(View.VISIBLE)
            } else {
                super.onWindowVisibilityChanged(visibility)
            }
        }
    }

    private lateinit var webView: BackgroundAudioWebView
    private lateinit var root: FrameLayout
    private var blackoutOverlay: View? = null
    private var customView: View? = null
    private var customViewCallback: WebChromeClient.CustomViewCallback? = null

    @SuppressLint("SetJavaScriptEnabled")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        current = WeakReference(this)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        loadBlocklist()

        root = FrameLayout(this).apply { setBackgroundColor(Color.BLACK) }
        webView = BackgroundAudioWebView(this)
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
                return true
            }

            override fun onPageFinished(view: WebView, url: String?) {
                super.onPageFinished(view, url)
                try {
                    view.evaluateJavascript(YT_ADBLOCK_AND_BG_SCRIPT, null)
                } catch (_: Throwable) {
                }
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

        // Cụm nút điều khiển góc phải trên: [🌙 Tắt màn] [✕ Đóng]
        val density = resources.displayMetrics.density
        val bar = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            background = GradientDrawable().apply {
                setColor(0xAA0F172A.toInt())
                cornerRadius = 14f * density
            }
            val padH = (4 * density).toInt()
            setPadding(padH, 0, padH, 0)
        }
        val btnHeight = (28 * density).toInt()
        val btnWidth = (30 * density).toInt()

        val dimBtn = TextView(this).apply {
            text = "🌙"
            textSize = 13f
            gravity = Gravity.CENTER
            setOnClickListener { enterBlackoutMode() }
        }
        val closeBtn = TextView(this).apply {
            text = "✕"
            textSize = 14f
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
            setOnClickListener { finish() }
        }
        bar.addView(dimBtn, LinearLayout.LayoutParams(btnWidth, btnHeight))
        bar.addView(closeBtn, LinearLayout.LayoutParams(btnWidth, btnHeight))

        val barParams = FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.WRAP_CONTENT,
            ViewGroup.LayoutParams.WRAP_CONTENT,
            Gravity.TOP or Gravity.END
        ).apply {
            topMargin = (4 * density).toInt()
            rightMargin = (4 * density).toInt()
        }
        root.addView(bar, barParams)

        setContentView(root)
        webView.loadUrl(intent.getStringExtra(EXTRA_URL) ?: "https://www.google.com")
    }

    private fun enterBlackoutMode() {
        if (blackoutOverlay != null) return
        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        val lp = window.attributes
        lp.screenBrightness = 0.0f
        window.attributes = lp

        val hint = TextView(this).apply {
            text = "🌙 Đang phát nhạc tắt màn hình\nChạm bất kỳ đâu để bật lại"
            textSize = 12f
            setTextColor(0x99FFFFFF.toInt())
            gravity = Gravity.CENTER
        }
        val cover = FrameLayout(this).apply {
            setBackgroundColor(Color.BLACK)
            isClickable = true
            isFocusable = true
            addView(hint, FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
                Gravity.CENTER
            ))
            setOnClickListener { exitBlackoutMode() }
        }
        hint.postDelayed({ hint.animate().alpha(0f).setDuration(600).start() }, 1600)
        blackoutOverlay = cover
        root.addView(cover, FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.MATCH_PARENT
        ))
    }

    private fun exitBlackoutMode() {
        val cover = blackoutOverlay ?: return
        blackoutOverlay = null
        root.removeView(cover)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        val lp = window.attributes
        lp.screenBrightness = WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE
        window.attributes = lp
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        exitBlackoutMode()
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
            blackoutOverlay != null -> exitBlackoutMode()
            customView != null -> exitFullscreen()
            webView.canGoBack() -> webView.goBack()
            else -> super.onBackPressed()
        }
    }

    override fun onDestroy() {
        if (current?.get() === this) current = null
        try {
            webView.keepAudioAliveInBackground = false
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
