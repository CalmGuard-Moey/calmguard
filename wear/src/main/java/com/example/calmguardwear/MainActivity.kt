package com.example.calmguard

import android.app.Activity
import android.content.Context
import android.graphics.Color
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.Gravity
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import com.google.android.gms.tasks.Tasks
import com.google.android.gms.wearable.Wearable

class MainActivity : Activity(), SensorEventListener {

    private var isMonitoring = false
    private var handler: Handler? = null
    private var monitoringStatusView: TextView? = null
    private var heartRateView: TextView? = null
    private var stressStatusView: TextView? = null
    private var sensorManager: SensorManager? = null
    private var heartRateSensor: Sensor? = null

    // Thresholds for stress detection
    private val WARNING_THRESHOLD = 90
    private val TRIGGER_THRESHOLD = 110
    private val NORMAL_THRESHOLD = 75

    // State tracking
    private var currentHeartRate = 0f
    private var currentState = "normal" // normal, warning, triggered
    private var warningMessageSent = false
    private var triggerMessageSent = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        handler = Handler(Looper.getMainLooper())
        sensorManager = getSystemService(Context.SENSOR_SERVICE) as SensorManager
        heartRateSensor = sensorManager?.getDefaultSensor(Sensor.TYPE_HEART_RATE)

        if (heartRateSensor == null) {
            Log.e("CalmGuardWatch", "Heart rate sensor not available on this device")
        }

        val scrollView = ScrollView(this).apply {
            setBackgroundColor(Color.BLACK)
        }

        val layout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setBackgroundColor(Color.BLACK)
            setPadding(24, 24, 24, 24)
        }

        val title = TextView(this).apply {
            text = "CalmGuard"
            textSize = 20f
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
        }

        heartRateView = TextView(this).apply {
            text = "❤️ Heart Rate: -- BPM"
            textSize = 16f
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
            setPadding(0, 16, 0, 8)
        }

        stressStatusView = TextView(this).apply {
            text = "🧠 Status: Calm"
            textSize = 14f
            setTextColor(Color.GREEN)
            gravity = Gravity.CENTER
            setPadding(0, 8, 0, 8)
        }

        val sensorStatus = TextView(this).apply {
            text = "📡 Sensor: Waiting..."
            textSize = 14f
            setTextColor(Color.LTGRAY)
            gravity = Gravity.CENTER
            setPadding(0, 8, 0, 8)
        }

        monitoringStatusView = TextView(this).apply {
            text = "📊 Monitoring: Offline"
            textSize = 14f
            setTextColor(Color.RED)
            gravity = Gravity.CENTER
            setPadding(0, 8, 0, 16)
        }

        val startButton = Button(this).apply {
            text = "START MONITORING"
            textSize = 14f
            setBackgroundColor(Color.DKGRAY)
            setTextColor(Color.WHITE)
            setPadding(16, 12, 16, 12)

            setOnClickListener {
                if (!isMonitoring) {
                    startMonitoring()
                }
            }
        }

        val stopButton = Button(this).apply {
            text = "STOP MONITORING"
            textSize = 14f
            setBackgroundColor(Color.DKGRAY)
            setTextColor(Color.WHITE)
            setPadding(16, 12, 16, 12)

            setOnClickListener {
                if (isMonitoring) {
                    stopMonitoring()
                }
            }
        }

        val buttonLayout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply {
                setMargins(0, 16, 0, 0)
            }
        }

        buttonLayout.addView(startButton, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.WRAP_CONTENT,
            LinearLayout.LayoutParams.WRAP_CONTENT
        ).apply {
            setMargins(0, 8, 0, 8)
        })

        buttonLayout.addView(stopButton, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.WRAP_CONTENT,
            LinearLayout.LayoutParams.WRAP_CONTENT
        ).apply {
            setMargins(0, 8, 0, 8)
        })

        layout.addView(title)
        layout.addView(heartRateView)
        layout.addView(stressStatusView)
        layout.addView(sensorStatus)
        layout.addView(monitoringStatusView)
        layout.addView(buttonLayout)

        scrollView.addView(layout)
        setContentView(scrollView)
    }

    private fun startMonitoring() {
        isMonitoring = true
        currentState = "normal"
        warningMessageSent = false
        triggerMessageSent = false

        monitoringStatusView?.apply {
            text = "📊 Monitoring: Active"
            setTextColor(Color.GREEN)
        }

        Log.e("CalmGuardWatch", "Monitoring started - listening to heart rate sensor")

        // Register for heart rate sensor events
        if (heartRateSensor != null) {
            sensorManager?.registerListener(this, heartRateSensor, SensorManager.SENSOR_DELAY_UI)
        } else {
            Log.e("CalmGuardWatch", "Heart rate sensor is null, cannot register listener")
        }
    }

    private fun stopMonitoring() {
        isMonitoring = false
        currentState = "normal"

        monitoringStatusView?.apply {
            text = "📊 Monitoring: Offline"
            setTextColor(Color.RED)
        }

        // Unregister from sensor events
        sensorManager?.unregisterListener(this)

        Log.e("CalmGuardWatch", "Monitoring stopped")
    }

    override fun onSensorChanged(event: SensorEvent?) {
        if (event == null || !isMonitoring) {
            return
        }

        if (event.sensor.type == Sensor.TYPE_HEART_RATE) {
            currentHeartRate = event.values[0]

            handler?.post {
                heartRateView?.text = "❤️ Heart Rate: ${currentHeartRate.toInt()} BPM"
            }

            Log.e("CalmGuardWatch", "Heart rate: ${currentHeartRate.toInt()} BPM")

            // Check stress state based on heart rate
            evaluateHeartRateState()
        }
    }

    private fun evaluateHeartRateState() {
        val newState = when {
            currentHeartRate >= TRIGGER_THRESHOLD -> "triggered"
            currentHeartRate >= WARNING_THRESHOLD -> "warning"
            else -> "normal"
        }

        // State machine: handle transitions
        if (newState != currentState) {
            Log.e("CalmGuardWatch", "State changed: $currentState -> $newState (HR: ${currentHeartRate.toInt()})")

            when (newState) {
                "warning" -> {
                    if (!warningMessageSent) {
                        handler?.post {
                            stressStatusView?.apply {
                                text = "🧠 Status: Warning"
                                setTextColor(Color.YELLOW)
                            }
                        }
                        sendWatchWarning()
                        warningMessageSent = true
                        triggerMessageSent = false
                    }
                }

                "triggered" -> {
                    if (!triggerMessageSent) {
                        handler?.post {
                            stressStatusView?.apply {
                                text = "🧠 Status: Triggered"
                                setTextColor(Color.RED)
                            }
                        }
                        sendWatchTrigger()
                        triggerMessageSent = true
                    }
                }

                "normal" -> {
                    if (warningMessageSent || triggerMessageSent) {
                        handler?.post {
                            stressStatusView?.apply {
                                text = "🧠 Status: Calm"
                                setTextColor(Color.GREEN)
                            }
                        }
                        sendWatchReset()
                        warningMessageSent = false
                        triggerMessageSent = false
                    }
                }
            }

            currentState = newState
        }
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {
        // No action needed
    }

    private fun sendWatchWarning() {
        Thread {
            try {
                val nodeClient = Wearable.getNodeClient(this@MainActivity)
                val messageClient = Wearable.getMessageClient(this@MainActivity)

                val nodes = Tasks.await(nodeClient.connectedNodes)

                Log.e("CalmGuardWatch", "Connected nodes count: ${nodes.size}")

                if (nodes.isEmpty()) {
                    Log.e("CalmGuardWatch", "No connected phone nodes found")
                }

                for (node in nodes) {
                    Log.e("CalmGuardWatch", "Sending warning to node: ${node.id}")

                    Tasks.await(
                        messageClient.sendMessage(
                            node.id,
                            "/watch_warning",
                            "watch_warning_triggered".toByteArray()
                        )
                    )

                    Log.e("CalmGuardWatch", "Sent message to phone: /watch_warning")
                }
            } catch (e: Exception) {
                Log.e("CalmGuardWatch", "Failed to send warning message", e)
            }
        }.start()
    }

    private fun sendWatchTrigger() {
        Thread {
            try {
                val nodeClient = Wearable.getNodeClient(this@MainActivity)
                val messageClient = Wearable.getMessageClient(this@MainActivity)

                val nodes = Tasks.await(nodeClient.connectedNodes)

                Log.e("CalmGuardWatch", "Connected nodes count: ${nodes.size}")

                if (nodes.isEmpty()) {
                    Log.e("CalmGuardWatch", "No connected phone nodes found")
                }

                for (node in nodes) {
                    Log.e("CalmGuardWatch", "Sending trigger to node: ${node.id}")

                    Tasks.await(
                        messageClient.sendMessage(
                            node.id,
                            "/watch_trigger",
                            "watch_trigger_activated".toByteArray()
                        )
                    )

                    Log.e("CalmGuardWatch", "Sent message to phone: /watch_trigger")
                }
            } catch (e: Exception) {
                Log.e("CalmGuardWatch", "Failed to send trigger message", e)
            }
        }.start()
    }

    private fun sendWatchReset() {
        Thread {
            try {
                val nodeClient = Wearable.getNodeClient(this@MainActivity)
                val messageClient = Wearable.getMessageClient(this@MainActivity)

                val nodes = Tasks.await(nodeClient.connectedNodes)

                Log.e("CalmGuardWatch", "Connected nodes count: ${nodes.size}")

                if (nodes.isEmpty()) {
                    Log.e("CalmGuardWatch", "No connected phone nodes found")
                }

                for (node in nodes) {
                    Log.e("CalmGuardWatch", "Sending reset to node: ${node.id}")

                    Tasks.await(
                        messageClient.sendMessage(
                            node.id,
                            "/watch_reset",
                            "watch_reset_requested".toByteArray()
                        )
                    )

                    Log.e("CalmGuardWatch", "Sent message to phone: /watch_reset")
                }
            } catch (e: Exception) {
                Log.e("CalmGuardWatch", "Failed to send reset message", e)
            }
        }.start()
    }

    override fun onDestroy() {
        super.onDestroy()
        if (isMonitoring) {
            sensorManager?.unregisterListener(this)
        }
        handler?.removeCallbacksAndMessages(null)
    }

    override fun onPause() {
        super.onPause()
        if (isMonitoring) {
            sensorManager?.unregisterListener(this)
        }
    }

    override fun onResume() {
        super.onResume()
        if (isMonitoring && heartRateSensor != null) {
            sensorManager?.registerListener(this, heartRateSensor, SensorManager.SENSOR_DELAY_UI)
        }
    }
}