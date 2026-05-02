package com.example.calmguard

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
    private lateinit var methodChannel: MethodChannel

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        methodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            watchChannel
        )

        Wearable.getMessageClient(this).addListener(this)
        Wearable.getDataClient(this).addListener(this)
    }

    override fun onDestroy() {
        Wearable.getMessageClient(this).removeListener(this)
        Wearable.getDataClient(this).removeListener(this)
        super.onDestroy()
    }

    override fun onMessageReceived(messageEvent: MessageEvent) {
        val path = messageEvent.path.removePrefix("/")
        val data = String(messageEvent.data)

        Log.d("CalmGuardPhone", "Received path:$path data: $data")

        runOnUiThread {
            when (path) {
                "watch_warning",
                "watch_trigger",
                "watch_reset" -> {
                    methodChannel.invokeMethod(path, null)
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
                            Log.d("CalmGuardPhone", "DataClient HR: $hr")
                            methodChannel.invokeMethod("onWatchHeartRate", hr)
                        }

                        "/stress" -> {
                            val stress = dataMap.getInt("stress")
                            Log.d("CalmGuardPhone", "DataClient Stress: $stress")
                            methodChannel.invokeMethod("onWatchStressLevel", stress)
                        }
                    }
                }
            }
        }
    }
}