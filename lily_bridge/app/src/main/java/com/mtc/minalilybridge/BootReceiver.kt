package com.mtc.minalilybridge

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        val act = intent?.action ?: return
        if (act == Intent.ACTION_BOOT_COMPLETED || act == "android.intent.action.QUICKBOOT_POWERON") {
            val prefs = context.getSharedPreferences(MinaBridgeService.PREFS_NAME, Context.MODE_PRIVATE)
            val autoBoot = prefs.getBoolean(MinaBridgeService.KEY_AUTO_BOOT, true)
            val lockLandscape = prefs.getBoolean(MinaBridgeService.KEY_LOCK_LANDSCAPE, true)
            if (autoBoot || lockLandscape) {
                val svc = Intent(context, MinaBridgeService::class.java).apply {
                    action = if (autoBoot && prefs.getBoolean(MinaBridgeService.KEY_ENABLED, true)) {
                        MinaBridgeService.ACTION_START_LISTENING
                    } else {
                        MinaBridgeService.ACTION_APPLY_ROTATION_LOCK
                    }
                }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(svc)
                } else {
                    context.startService(svc)
                }
            }
        }
    }
}
