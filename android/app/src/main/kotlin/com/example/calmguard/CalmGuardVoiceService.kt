package com.example.calmguard

import android.app.*
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.IBinder
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.util.Log
import androidx.core.app.NotificationCompat

class CalmGuardVoiceService : Service(), RecognitionListener {

    private val channelId = "calmguard_voice_channel"
    private val notificationId = 2001

    private var speechRecognizer: SpeechRecognizer? = null
    private var isListening = false

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
      //  startForeground(notificationId, buildNotification())
        startNativeListening()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        MainActivity.flutterMethodChannel?.invokeMethod(
            "onNativeVoiceServiceStarted",
            "Native voice service started"
        )

        if (!isListening) {
            startNativeListening()
        }

        return START_NOT_STICKY
    }

    private fun startNativeListening() {
        if (!SpeechRecognizer.isRecognitionAvailable(this)) {
            MainActivity.flutterMethodChannel?.invokeMethod(
                "onNativeVoiceError",
                "Speech recognition is not available on this device"
            )
            stopSelf()
            return
        }

        speechRecognizer?.destroy()
        speechRecognizer = SpeechRecognizer.createSpeechRecognizer(this)
        speechRecognizer?.setRecognitionListener(this)

        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(
                RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                RecognizerIntent.LANGUAGE_MODEL_FREE_FORM
            )
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, "en-AU")
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 5)
            putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS, 2500L)
            putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_POSSIBLY_COMPLETE_SILENCE_LENGTH_MILLIS, 2500L)
            putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_MINIMUM_LENGTH_MILLIS, 20000L)
        }

        isListening = true
        speechRecognizer?.startListening(intent)

        MainActivity.flutterMethodChannel?.invokeMethod(
            "onNativeVoiceListening",
            "Native mic listening started"
        )
    }

    override fun onReadyForSpeech(params: Bundle?) {
        Log.d("CalmGuardVoice", "Ready for speech")
    }

    override fun onBeginningOfSpeech() {
        Log.d("CalmGuardVoice", "Speech started")
    }

    override fun onRmsChanged(rmsdB: Float) {
        MainActivity.flutterMethodChannel?.invokeMethod(
            "onNativeVoiceLevel",
            rmsdB.toDouble()
        )
    }

    override fun onBufferReceived(buffer: ByteArray?) {}

    override fun onEndOfSpeech() {
        isListening = false
        stopSelf()
    }

    override fun onError(error: Int) {
        isListening = false
        MainActivity.flutterMethodChannel?.invokeMethod(
            "onNativeVoiceError",
            "Native speech error: $error"
        )
        stopSelf()
    }

    override fun onResults(results: Bundle?) {
        isListening = false

        val matches = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
        val text = matches?.firstOrNull() ?: ""

        MainActivity.latestVoiceResult = text
        MainActivity.latestVoiceTimestamp = System.currentTimeMillis()

        MainActivity.flutterMethodChannel?.invokeMethod(
            "onNativeVoiceResult",
            text
        )

        stopSelf()
    }

    override fun onPartialResults(partialResults: Bundle?) {
        val matches = partialResults?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
        val text = matches?.firstOrNull() ?: ""

        if (text.isNotBlank()) {
            MainActivity.flutterMethodChannel?.invokeMethod(
                "onNativeVoicePartial",
                text
            )
        }
    }

    override fun onEvent(eventType: Int, params: Bundle?) {}

    override fun onDestroy() {
        isListening = false
        speechRecognizer?.stopListening()
        speechRecognizer?.destroy()
        speechRecognizer = null

        MainActivity.flutterMethodChannel?.invokeMethod(
            "onNativeVoiceServiceStopped",
            "Native voice service stopped"
        )

        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                channelId,
                "CalmGuard Voice Check",
                NotificationManager.IMPORTANCE_LOW
            )

            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(): Notification {
        return NotificationCompat.Builder(this, channelId)
            .setContentTitle("CalmGuard voice check")
            .setContentText("Short background voice check is active")
            .setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setOngoing(false)
            .build()
    }
}