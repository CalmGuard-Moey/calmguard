package com.example.calmguardwear

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat

import androidx.health.services.client.ExerciseUpdateCallback
import androidx.health.services.client.HealthServices
import androidx.health.services.client.data.Availability
import androidx.health.services.client.data.BatchingMode
import androidx.health.services.client.data.DataPointContainer
import androidx.health.services.client.data.DataType
import androidx.health.services.client.data.ExerciseConfig
import androidx.health.services.client.data.ExerciseLapSummary
import androidx.health.services.client.data.ExerciseType
import androidx.health.services.client.data.ExerciseUpdate

import com.google.android.gms.wearable.PutDataMapRequest
import com.google.android.gms.wearable.Wearable

import kotlin.math.abs

class HeartRateForegroundService : Service() {

    private val exerciseClient by lazy {
        HealthServices.getClient(this).exerciseClient
    }

    private var lastSentHeartRate = 0
    private var lastSentTime = 0L
    private var exerciseStarted = false

    companion object {
        const val CHANNEL_ID = "calmguard_hr_channel"
        const val NOTIFICATION_ID = 1001
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        startForeground(NOTIFICATION_ID, buildNotification())
        startExerciseHeartRate()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startForeground(NOTIFICATION_ID, buildNotification())
        startExerciseHeartRate()
        return START_STICKY
    }

    private fun startExerciseHeartRate() {
        if (exerciseStarted) return

        try {
            exerciseClient.setUpdateCallback(exerciseCallback)

            val config = ExerciseConfig(
                exerciseType = ExerciseType.WORKOUT,
                dataTypes = setOf(DataType.HEART_RATE_BPM),
                isAutoPauseAndResumeEnabled = false,
                isGpsEnabled = false,
                batchingModeOverrides = setOf(BatchingMode.HEART_RATE_5_SECONDS)
            )

            exerciseClient.startExerciseAsync(config)

            exerciseStarted = true
            Log.d("CalmGuardHR", "Exercise HR started")

        } catch (e: Exception) {
            Log.e("CalmGuardHR", "Exercise HR start failed", e)
        }
    }

    private val exerciseCallback = object : ExerciseUpdateCallback {
        override fun onRegistered() { Log.d("CalmGuardHR",
            "Exercise callback registered")
        }
        override fun onRegistrationFailed(throwable: Throwable) {
            Log.e("CalmGuardHR", "Exercise callback registration failed", throwable)
        }
        override fun onExerciseUpdateReceived(update: ExerciseUpdate) {
            handleMetrics(update.latestMetrics)
        }
        override fun onLapSummaryReceived(lapSummary: ExerciseLapSummary) {
            // Not needed for CalmGuard
        }

        override fun onAvailabilityChanged(
            dataType: DataType<*, *>,
            availability: Availability
        ) {
            Log.d("CalmGuardHR", "Availability changed: $dataType $availability")
        }
    }

    private fun handleMetrics(metrics: DataPointContainer) {
        val points = metrics.getData(DataType.HEART_RATE_BPM)

        for (dp in points) {
            val hr = dp.value.toString().toFloatOrNull()?.toInt() ?: continue
            val now = System.currentTimeMillis()

            if (hr > 0 &&
                (lastSentHeartRate == 0 || abs(hr - lastSentHeartRate) >= 1) &&
                now - lastSentTime >= 2000
            ) {
                lastSentHeartRate = hr
                lastSentTime = now

                sendHeartRateToPhone(hr)
                Log.d("CalmGuardHR", "Exercise HR SENT: $hr")
            }
        }
    }

    private fun sendHeartRateToPhone(heartRate: Int) {
        Thread {
            try {
                val heartRateReq = PutDataMapRequest.create("/heart_rate")
                heartRateReq.dataMap.putInt("hr", heartRate)
                heartRateReq.dataMap.putLong("time", System.currentTimeMillis())

                val heartRateRequest = heartRateReq.asPutDataRequest()
                heartRateRequest.setUrgent()
                Wearable.getDataClient(this).putDataItem(heartRateRequest)

                Log.d(
                    "CalmGuardHR",
                    "DataLayer sent HR only: $heartRate")

            } catch (e: Exception) {
                Log.e("CalmGuardHR", "DataLayer send failed", e)
            }
        }.start()
    }

    override fun onDestroy() {
        try {
            exerciseClient.clearUpdateCallbackAsync(exerciseCallback)
            exerciseClient.endExerciseAsync()
        } catch (e: Exception) {
            Log.e("CalmGuardHR", "Exercise cleanup failed", e)
        }

        exerciseStarted = false
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun buildNotification(): Notification {
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("CalmGuard")
            .setContentText("Live heart-rate monitoring active")
            .setSmallIcon(android.R.drawable.ic_menu_info_details)
            .setOngoing(true)
            .build()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "CalmGuard Live HR",
                NotificationManager.IMPORTANCE_LOW
            )

            val manager =
                getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(channel)
        }
    }
}