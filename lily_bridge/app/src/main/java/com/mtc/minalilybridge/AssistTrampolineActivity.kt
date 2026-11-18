package com.mtc.minalilybridge

import android.app.Activity
import android.content.Intent
import android.os.Build
import android.os.Bundle

class AssistTrampolineActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val svc = Intent(this, MinaBridgeService::class.java).apply {
            action = MinaBridgeService.ACTION_WAKE_LILY_NOW
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(svc)
        } else {
            startService(svc)
        }
        finish()
    }
}
