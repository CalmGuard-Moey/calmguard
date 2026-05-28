package com.example.calmguardwear

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
                Log.d("WatchMessageListener", "Background watch voice request received")
                sendStatusToPhone("/watch_voice_started", "background_request_received")
            }
        }
    }

    private fun sendStatusToPhone(path: String, payload: String = "") {
        val bytes = payload.toByteArray(Charsets.UTF_8)
        Wearable.getNodeClient(this).connectedNodes
            .addOnSuccessListener { nodes ->
                for (node in nodes) {
                    Wearable.getMessageClient(this).sendMessage(node.id, path, bytes)
                    Log.d("WatchMessageListener", "Sent status $path to phone: $payload")
                }
            }
            .addOnFailureListener {
                Log.d("WatchMessageListener", "Failed to send status $path: ${it.message}")
            }
    }
}
