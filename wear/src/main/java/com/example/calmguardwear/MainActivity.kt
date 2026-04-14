package com.example.calmguard

import android.app.Activity
import android.graphics.Color
import android.os.Bundle
import android.util.Log
import android.view.Gravity
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import com.google.android.gms.tasks.Tasks
import com.google.android.gms.wearable.Wearable

class MainActivity : Activity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

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

        val heartRate = TextView(this).apply {
            text = "❤️ Heart Rate: 82 BPM"
            textSize = 14f
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
            setPadding(0, 16, 0, 8)
        }

        val stressStatus = TextView(this).apply {
            text = "🧠 Status: Calm"
            textSize = 14f
            setTextColor(Color.GREEN)
            gravity = Gravity.CENTER
            setPadding(0, 8, 0, 8)
        }

        val voiceStatus = TextView(this).apply {
            text = "🎤 Voice Trigger: Off"
            textSize = 14f
            setTextColor(Color.LTGRAY)
            gravity = Gravity.CENTER
            setPadding(0, 8, 0, 16)
        }

        val warningButton = Button(this).apply {
            text = "WARNING"
            textSize = 14f
            setBackgroundColor(Color.DKGRAY)
            setTextColor(Color.WHITE)
            setPadding(16, 12, 16, 12)

            setOnClickListener {
                stressStatus.text = "🧠 Status: Warning"
                stressStatus.setTextColor(Color.YELLOW)

                heartRate.text = "❤️ Heart Rate: 92 BPM"

                sendWatchWarning()
            }
        }

        val triggerButton = Button(this).apply {
            text = "TRIGGER"
            textSize = 14f
            setBackgroundColor(Color.DKGRAY)
            setTextColor(Color.WHITE)
            setPadding(16, 12, 16, 12)

            setOnClickListener {
                stressStatus.text = "🧠 Status: Triggered"
                stressStatus.setTextColor(Color.RED)

                voiceStatus.text = "🎤 Voice Trigger: Active"
                voiceStatus.setTextColor(Color.CYAN)

                heartRate.text = "❤️ Heart Rate: 110 BPM"

                sendWatchTrigger()
            }
        }

        val resetButton = Button(this).apply {
            text = "RESET"
            textSize = 14f
            setBackgroundColor(Color.DKGRAY)
            setTextColor(Color.WHITE)
            setPadding(16, 12, 16, 12)

            setOnClickListener {
                stressStatus.text = "🧠 Status: Calm"
                stressStatus.setTextColor(Color.GREEN)

                voiceStatus.text = "🎤 Voice Trigger: Off"
                voiceStatus.setTextColor(Color.LTGRAY)

                heartRate.text = "❤️ Heart Rate: 82 BPM"

                sendWatchReset()
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

        buttonLayout.addView(warningButton, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.WRAP_CONTENT,
            LinearLayout.LayoutParams.WRAP_CONTENT
        ).apply {
            setMargins(0, 8, 0, 8)
        })

        buttonLayout.addView(triggerButton, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.WRAP_CONTENT,
            LinearLayout.LayoutParams.WRAP_CONTENT
        ).apply {
            setMargins(0, 8, 0, 8)
        })

        buttonLayout.addView(resetButton, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.WRAP_CONTENT,
            LinearLayout.LayoutParams.WRAP_CONTENT
        ).apply {
            setMargins(0, 8, 0, 8)
        })

        layout.addView(title)
        layout.addView(heartRate)
        layout.addView(stressStatus)
        layout.addView(voiceStatus)
        layout.addView(buttonLayout)

        scrollView.addView(layout)
        setContentView(scrollView)
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
}