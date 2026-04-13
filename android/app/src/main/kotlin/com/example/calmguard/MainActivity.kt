package com.example.calmguard

import android.os.Bundle
import android.util.Log
import com.google.android.gms.wearable.MessageClient
import com.google.android.gms.wearable.MessageEvent
import com.google.android.gms.wearable.Wearable
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity(), MessageClient.OnMessageReceivedListener {

    private val CHANNEL = "calmguard/watch"
    private var methodChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
    }

    override fun onResume() {
        super.onResume()
        Wearable.getMessageClient(this).addListener(this)
        Log.e("CalmGuardPhone", "Listener added")
    }

    override fun onPause() {
        Wearable.getMessageClient(this).removeListener(this)
        Log.e("CalmGuardPhone", "Listener removed")
        super.onPause()
    }

    override fun onMessageReceived(messageEvent: MessageEvent) {
        val message = String(messageEvent.data)

        Log.e("CalmGuardPhone", "Watch message: $message")

        if (message == "triggered_from_watch") {
            methodChannel?.invokeMethod("watch_trigger", null)
        }
    }
}
