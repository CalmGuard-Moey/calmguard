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

        val calmButton = Button(this).apply {
            text = "CALM ME"
            textSize = 16f
            setBackgroundColor(Color.DKGRAY)
            setTextColor(Color.WHITE)

            setOnClickListener {
                stressStatus.text = "🧠 Status: Rising"
                stressStatus.setTextColor(Color.YELLOW)

                voiceStatus.text = "🎤 Voice Trigger: Active"
                voiceStatus.setTextColor(Color.CYAN)

                heartRate.text = "❤️ Heart Rate: 96 BPM"

                sendMessageToPhone()
            }
        }

        layout.addView(title)
        layout.addView(heartRate)
        layout.addView(stressStatus)
        layout.addView(voiceStatus)
        layout.addView(calmButton)

        scrollView.addView(layout)
        setContentView(scrollView)
    }

    private fun sendMessageToPhone() {
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
                    Log.e("CalmGuardWatch", "Sending to node: ${node.id}")

                    Tasks.await(
                        messageClient.sendMessage(
                            node.id,
                            "/calmguard_data",
                            "triggered_from_watch".toByteArray()
                        )
                    )

                    Log.e("CalmGuardWatch", "Sent message to phone: triggered_from_watch")
                }
            } catch (e: Exception) {
                Log.e("CalmGuardWatch", "Failed to send message", e)
            }
        }.start()
    }
}