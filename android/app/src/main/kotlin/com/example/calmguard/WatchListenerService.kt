package com.example.calmguard

import android.content.Intent
import android.util.Log
import com.google.android.gms.wearable.MessageEvent
import com.google.android.gms.wearable.WearableListenerService

class WatchListenerService : WearableListenerService() {

    override fun onMessageReceived(messageEvent: MessageEvent) {
        super.onMessageReceived(messageEvent)

        when (messageEvent.path) {
            "/heart_rate" -> {
                val heartRate = String(messageEvent.data).toIntOrNull()
                Log.d("WatchListenerService", "Received heart rate: $heartRate")

                if (heartRate != null) {
                    val intent = Intent("WATCH_HEART_RATE_UPDATE")
                    intent.putExtra("heart_rate", heartRate)
                    sendBroadcast(intent)
                }
            }

            "/watch_warning" -> {
                Log.d("WatchListenerService", "Received watch warning")
            }

            "/watch_trigger" -> {
                Log.d("WatchListenerService", "Received watch trigger")
            }

            "/watch_reset" -> {
                Log.d("WatchListenerService", "Received watch reset")
            }
        }
    }
}