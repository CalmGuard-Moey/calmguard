package com.example.calmguardwear

import android.app.Activity
import android.content.Intent
import android.graphics.Color
import android.os.Build
import android.os.Bundle
import android.view.Gravity
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView

class MainActivity : Activity() {

    private var statusText: TextView? = null
    private var monitoringText: TextView? = null
    private var infoText: TextView? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val scrollView = ScrollView(this).apply {
            setBackgroundColor(Color.BLACK)
        }

        val layout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(24, 24, 24, 24)
            gravity = Gravity.CENTER_HORIZONTAL
            setBackgroundColor(Color.BLACK)
        }

        val title = TextView(this).apply {
            text = "CalmGuard"
            textSize = 20f
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
            setPadding(0, 0, 0, 24)
        }

        statusText = TextView(this).apply {
            text = "🧠 Status: Ready"
            textSize = 16f
            setTextColor(Color.GREEN)
            setPadding(0, 8, 0, 8)
        }

        monitoringText = TextView(this).apply {
            text = "📊 Background HR: Active"
            textSize = 16f
            setTextColor(Color.GREEN)
            setPadding(0, 8, 0, 8)
        }

        infoText = TextView(this).apply {
            text = "HR is sent by the background service using DataClient."
            textSize = 13f
            setTextColor(Color.LTGRAY)
            gravity = Gravity.CENTER
            setPadding(0, 8, 0, 24)
        }

        val startButton = Button(this).apply {
            text = "START BACKGROUND HR"
            textSize = 16f
            setBackgroundColor(Color.DKGRAY)
            setTextColor(Color.WHITE)
            setOnClickListener {
                startHeartRateService()
            }
        }

        val stopButton = Button(this).apply {
            text = "STOP BACKGROUND HR"
            textSize = 16f
            setBackgroundColor(Color.DKGRAY)
            setTextColor(Color.WHITE)
            setOnClickListener {
                stopHeartRateService()
            }
        }

        layout.addView(title)
        layout.addView(statusText)
        layout.addView(monitoringText)
        layout.addView(infoText)
        layout.addView(startButton)
        layout.addView(stopButton)

        scrollView.addView(layout)
        setContentView(scrollView)

        startHeartRateService()
    }

    private fun startHeartRateService() {
        val serviceIntent = Intent(this, HeartRateForegroundService::class.java)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(serviceIntent)
        } else {
            startService(serviceIntent)
        }

        statusText?.text = "🧠 Status: Monitoring"
        statusText?.setTextColor(Color.GREEN)
        monitoringText?.text = "📊 Background HR: Active"
        monitoringText?.setTextColor(Color.GREEN)
    }

    private fun stopHeartRateService() {
        val serviceIntent = Intent(this, HeartRateForegroundService::class.java)
        stopService(serviceIntent)

        statusText?.text = "🧠 Status: Stopped"
        statusText?.setTextColor(Color.RED)
        monitoringText?.text = "📊 Background HR: Stopped"
        monitoringText?.setTextColor(Color.RED)
    }
}