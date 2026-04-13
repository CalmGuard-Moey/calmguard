package com.example.calmguard

import android.os.Handler
import android.os.Looper
import android.util.Log
import android.widget.Toast
import com.google.android.gms.wearable.MessageEvent
import com.google.android.gms.wearable.WearableListenerService

class WatchListenerService : WearableListenerService() {

    override fun onMessageReceived(messageEvent: MessageEvent) {
        super.onMessageReceived(messageEvent)

        val path = messageEvent.path
        val message = String(messageEvent.data)

        Log.e("CalmGuardPhone", "Received path: $path")
        Log.e("CalmGuardPhone", "Message from watch: $message")

        if (path == "/calmguard_data") {
            Handler(Looper.getMainLooper()).post {
                Toast.makeText(
                    applicationContext,
                    "Watch sent: $message",
                    Toast.LENGTH_LONG
                ).show()
            }
        }
    }
}