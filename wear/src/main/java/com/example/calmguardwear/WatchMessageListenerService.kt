package com.example.calmguardwear

import android.content.Intent
import android.util.Log
import com.google.android.gms.wearable.MessageEvent
import com.google.android.gms.wearable.Wearable
import com.google.android.gms.wearable.WearableListenerService

class WatchMessageListenerService : WearableListenerService() {

    override fun onMessageReceived(messageEvent: MessageEvent) {
        super.onMessageReceived(messageEvent)

        val path = messageEvent.path.removePrefix("/")
        Log.d("WatchMessageListener", "Received message: $path")

        when (path) {
            "start_watch_voice_check" -> {
                Log.d("WatchMessageListener", "Background watch voice request received, launching MainActivity")
                val launchIntent = Intent(this, MainActivity::class.java).apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
                    putExtra("autoStartVoiceCheck", true)
                }
                startActivity(launchIntent)
            }
        }
    }

    // Background voice requests are handled by launching MainActivity, which uses the existing voice check flow.
    // No direct phone mic or service startup is performed from this background listener.
}
