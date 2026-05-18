package com.example.calmguard

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

class CalmGuardForegroundService : Service() {

    companion object {
        const val CHANNEL_ID = "calmguard_monitoring_channel"
        const val NOTIFICATION_ID = 3001

        var currentStage: String = "GREEN"
        var currentHr: Int = 72
        var currentRisk: Int = 20
        var currentVoice: Int = 0
        var currentReason: String = "Monitoring"
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        startForeground(NOTIFICATION_ID, buildNotification())
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        currentStage = intent?.getStringExtra("stage") ?: currentStage
        currentHr = intent?.getIntExtra("hr", currentHr) ?: currentHr
        currentRisk = intent?.getIntExtra("risk", currentRisk) ?: currentRisk
        currentVoice = intent?.getIntExtra("voice", currentVoice) ?: currentVoice
        currentReason = intent?.getStringExtra("reason") ?: currentReason

        updateNotification()

        return START_STICKY
    }

    override fun onDestroy() {
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "CalmGuard Monitoring",
                NotificationManager.IMPORTANCE_LOW
            )

            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }

    private fun updateNotification() {
        val manager = getSystemService(NotificationManager::class.java)
        manager.notify(NOTIFICATION_ID, buildNotification())
    }

    private fun buildNotification(): Notification {
        val title = when (currentStage) {
            "RED" -> "🔴 CalmGuard Triggered"
            "ORANGE" -> "🟠 CalmGuard Warning"
            else -> "🟢 CalmGuard Monitoring"
        }

        val text = "HR: $currentHr bpm • Risk: $currentRisk/100 • Voice: $currentVoice/100"

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(text)
            .setStyle(
                NotificationCompat.BigTextStyle()
                    .bigText("$text\nReason: $currentReason")
            )
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .build()
    }
}