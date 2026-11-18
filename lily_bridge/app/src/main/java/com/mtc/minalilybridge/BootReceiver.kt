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
            if (prefs.getBoolean(MinaBridgeService.KEY_AUTO_BOOT, true)) {
                val svc = Intent(context, MinaBridgeService::class.java).apply {
                    action = MinaBridgeService.ACTION_START_LISTENING
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
