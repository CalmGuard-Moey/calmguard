package com.example.calmguard

import android.content.Intent
import android.os.Build
import android.util.Log

import com.google.android.gms.wearable.DataClient
import com.google.android.gms.wearable.DataEvent
import com.google.android.gms.wearable.DataEventBuffer
import com.google.android.gms.wearable.DataMapItem
import com.google.android.gms.wearable.MessageClient
import com.google.android.gms.wearable.MessageEvent
import com.google.android.gms.wearable.Wearable

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity(),
    MessageClient.OnMessageReceivedListener,
    DataClient.OnDataChangedListener {

    private val watchChannel = "calmguard/watch"
    private val voiceChannel = "calmguard/voice"

    companion object {
        var flutterMethodChannel: MethodChannel? = null
        var latestVoiceResult: String? = null
        var latestVoiceTimestamp: Long = 0L
    }

    private lateinit var methodChannel: MethodChannel
    private lateinit var voiceMethodChannel: MethodChannel

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        methodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            watchChannel
        )

        voiceMethodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            voiceChannel
        )

        flutterMethodChannel = voiceMethodChannel

        voiceMethodChannel.setMethodCallHandler { call, result ->

            when (call.method) {

                "startVoiceService" -> {

                    val intent = Intent(this, CalmGuardVoiceService::class.java)

                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        startForegroundService(intent)
                    } else {
                        startService(intent)
                    }

                    result.success(true)
                }

                "stopVoiceService" -> {

                    stopService(Intent(this, CalmGuardVoiceService::class.java))
                    result.success(true)
                }

                "getPendingVoiceResult" -> {

                    val resultMap = mapOf(
                        "text" to (latestVoiceResult ?: ""),
                        "timestamp" to latestVoiceTimestamp
                    )

                    latestVoiceResult = null
                    latestVoiceTimestamp = 0L

                    result.success(resultMap)
                }

                "requestWatchVoiceCheck" -> {
                    sendMessageToWatch("/start_watch_voice_check", ByteArray(0))
                    result.success(true)
                }

                else -> result.notImplemented()
            }
        }

        Wearable.getMessageClient(this).addListener(this)
        Wearable.getDataClient(this).addListener(this)
    }

    private fun sendMessageToWatch(path: String, payload: ByteArray) {
        Wearable.getNodeClient(this).connectedNodes
            .addOnSuccessListener { nodes ->
                for (node in nodes) {
                    Wearable.getMessageClient(this).sendMessage(node.id, path, payload)
                    Log.d("CalmGuardPhone", "Sent $path to watch")
                }
            }
            .addOnFailureListener {
                Log.d("CalmGuardPhone", "Failed to send $path: ${it.message}")
            }
    }

    override fun onDestroy() {
        Wearable.getMessageClient(this).removeListener(this)
        Wearable.getDataClient(this).removeListener(this)
        super.onDestroy()
    }

    override fun onMessageReceived(messageEvent: MessageEvent) {

        val path = messageEvent.path.removePrefix("/")
        val data = String(messageEvent.data)

        Log.d("CalmGuardPhone", "Received path:$path data:$data")

        runOnUiThread {

            when (path) {

                "watch_warning",
                "watch_trigger",
                "watch_reset" -> {
                    methodChannel.invokeMethod(path, null)
                }
                "watch_voice_result" -> {
                    // Forward watch mic result to Flutter voice channel
                    try {
                        voiceMethodChannel.invokeMethod("onNativeVoiceResult", data)
                    } catch (e: Exception) {
                        Log.d("CalmGuardPhone", "Failed to forward voice result: ${e.message}")
                    }
                }
                "watch_voice_started" -> {
                    try {
                        voiceMethodChannel.invokeMethod("onWatchVoiceStarted", null)
                    } catch (e: Exception) {
                        Log.d("CalmGuardPhone", "Failed to forward watch voice started: ${e.message}")
                    }
                }
                "watch_voice_finished" -> {
                    try {
                        voiceMethodChannel.invokeMethod("onWatchVoiceFinished", null)
                    } catch (e: Exception) {
                        Log.d("CalmGuardPhone", "Failed to forward watch voice finished: ${e.message}")
                    }
                }
                "watch_voice_timeout" -> {
                    try {
                        voiceMethodChannel.invokeMethod("onWatchVoiceTimeout", null)
                    } catch (e: Exception) {
                        Log.d("CalmGuardPhone", "Failed to forward watch voice timeout: ${e.message}")
                    }
                }
                "watch_voice_error" -> {
                    try {
                        voiceMethodChannel.invokeMethod("onWatchVoiceError", data)
                    } catch (e: Exception) {
                        Log.d("CalmGuardPhone", "Failed to forward watch voice error: ${e.message}")
                    }
                }
            }
        }
    }

    override fun onDataChanged(dataEvents: DataEventBuffer) {

        for (event in dataEvents) {

            if (event.type == DataEvent.TYPE_CHANGED) {

                val item = event.dataItem
                val path = item.uri.path ?: continue
                val dataMap = DataMapItem.fromDataItem(item).dataMap

                runOnUiThread {

                    when (path) {

                        "/heart_rate" -> {

                            val hr = dataMap.getInt("hr")

                            Log.d("CalmGuardPhone", "DataClient HR:$hr")

                            methodChannel.invokeMethod(
                                "onWatchHeartRate",
                                hr
                            )
                        }

                        "/stress" -> {

                            val stress = dataMap.getInt("stress")

                            Log.d("CalmGuardPhone", "DataClient Stress:$stress")

                            methodChannel.invokeMethod(
                                "onWatchStressLevel",
                                stress
                            )
                        }
                    }
                }
            }
        }
    }
}