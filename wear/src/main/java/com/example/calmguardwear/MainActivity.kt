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
import android.Manifest
import android.content.pm.PackageManager
import android.speech.RecognizerIntent
import android.speech.RecognitionListener
import android.speech.SpeechRecognizer
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import android.util.Log
import android.widget.Toast
import com.google.android.gms.wearable.Wearable

class MainActivity : Activity() {

    private var statusText: TextView? = null
    private var monitoringText: TextView? = null
    private var infoText: TextView? = null
    private var speechRecognizer: SpeechRecognizer? = null
    private val REQUEST_RECORD_AUDIO = 101

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

        val startVoiceButton = Button(this).apply {
            text = "Start Voice Check"
            textSize = 16f
            setBackgroundColor(Color.DKGRAY)
            setTextColor(Color.WHITE)
            setOnClickListener {
                startVoiceCheck()
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
        layout.addView(startVoiceButton)
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

    private fun startVoiceCheck() {
        // Check permission
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            Log.d("CalmGuardWear", "RECORD_AUDIO permission not granted, requesting")
            Toast.makeText(this, "Requesting microphone permission", Toast.LENGTH_SHORT).show()
            ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.RECORD_AUDIO), REQUEST_RECORD_AUDIO)
            return
        }

        if (!SpeechRecognizer.isRecognitionAvailable(this)) {
            infoText?.text = "Speech recognition not available"
            Log.d("CalmGuardWear", "Speech recognition not available on this device")
            Toast.makeText(this, "Speech recognition is not available", Toast.LENGTH_SHORT).show()
            return
        }

        if (speechRecognizer == null) {
            speechRecognizer = SpeechRecognizer.createSpeechRecognizer(this)
            speechRecognizer?.setRecognitionListener(object : RecognitionListener {
                override fun onReadyForSpeech(params: Bundle?) {}
                override fun onBeginningOfSpeech() {}
                override fun onRmsChanged(rmsdB: Float) {}
                override fun onBufferReceived(buffer: ByteArray?) {}
                override fun onEndOfSpeech() {}
                override fun onEvent(eventType: Int, params: Bundle?) {}
                override fun onPartialResults(partialResults: Bundle?) {
                    // No-op for manual test
                }
                override fun onError(error: Int) {
                    infoText?.text = "Voice check error: $error"
                    Log.d("CalmGuardWear", "SpeechRecognizer error: $error")
                    Toast.makeText(this@MainActivity, "Voice check error: $error", Toast.LENGTH_SHORT).show()
                    speechRecognizer?.cancel()
                    speechRecognizer?.destroy()
                    speechRecognizer = null
                }
                override fun onResults(results: Bundle?) {
                    val matches = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                    val text = if (!matches.isNullOrEmpty()) matches[0] else ""
                    if (text.isNotEmpty()) {
                        infoText?.text = "Heard: $text"
                        sendVoiceToPhone(text)
                    } else {
                        infoText?.text = "No speech recognized"
                    }

                    speechRecognizer?.stopListening()
                    speechRecognizer?.destroy()
                    speechRecognizer = null
                }
            })
        }

        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, false)
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 3)
        }

        try {
            speechRecognizer?.startListening(intent)
            infoText?.text = "Listening (manual test)..."
        } catch (e: Exception) {
            infoText?.text = "Voice error"
            Log.d("CalmGuardWear", "startListening failed: ${e.message}")
            Toast.makeText(this, "Voice start failed: ${e.message}", Toast.LENGTH_SHORT).show()
        }
    }

    private fun sendVoiceToPhone(text: String) {
        val payload = text.toByteArray(Charsets.UTF_8)
        Wearable.getNodeClient(this).connectedNodes
            .addOnSuccessListener { nodes ->
                for (node in nodes) {
                    Wearable.getMessageClient(this).sendMessage(node.id, "/watch_voice_result", payload)
                }
            }
            .addOnFailureListener {
                Log.d("CalmGuardWear", "Failed to get nodes: ${it.message}")
            }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQUEST_RECORD_AUDIO) {
            if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                Log.d("CalmGuardWear", "RECORD_AUDIO permission granted by user")
                startVoiceCheck()
            } else {
                infoText?.text = "Microphone permission required"
                Log.d("CalmGuardWear", "RECORD_AUDIO permission denied by user")
                Toast.makeText(this, "Microphone permission is required for voice check", Toast.LENGTH_SHORT).show()
            }
        }
    }

    override fun onDestroy() {
        speechRecognizer?.destroy()
        speechRecognizer = null
        super.onDestroy()
    }
}