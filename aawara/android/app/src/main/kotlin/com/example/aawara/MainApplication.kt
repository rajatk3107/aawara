package com.example.aawara

import android.app.Application
import android.app.NotificationChannel
import android.app.NotificationManager

class MainApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        createNotificationChannels()
    }

    private fun createNotificationChannels() {
        val nm = getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(
            NotificationChannel(
                "aawara_steps",
                "Step Counter",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Shows step count while tracking is active"
                setShowBadge(false)
            }
        )
        nm.createNotificationChannel(
            NotificationChannel(
                "aawara_steps_goal",
                "Step Goal Alerts",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Notifies when daily step goal is reached"
            }
        )
    }
}
