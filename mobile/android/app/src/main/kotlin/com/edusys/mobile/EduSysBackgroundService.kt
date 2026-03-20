package com.edusys.mobile

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.pm.ServiceInfo
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import id.flutter.flutter_background_service.BackgroundService

/**
 * Subclass of flutter_background_service's BackgroundService.
 *
 * On Android 14+ (API 34+) with targetSdk 34+, calling startForeground()
 * without an explicit foregroundServiceType causes a fatal
 * CannotPostForegroundServiceNotificationException.
 *
 * This class overrides onStartCommand to call the typed variant of
 * startForeground() before the plugin's own logic runs, ensuring the
 * system accepts the notification.
 */
class EduSysBackgroundService : BackgroundService() {

    private val channelId = "edusys_attendance"
    private val notificationId = 1001
    private val tag = "EduSysBGS"

    override fun onCreate() {
        super.onCreate()
        ensureChannel()
        Log.i(tag, "EduSysBackgroundService.onCreate")
    }

    override fun onStartCommand(intent: android.content.Intent?, flags: Int, startId: Int): Int {
        ensureChannel()
        val notification = buildNotification()
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                // Android 14+ — must pass foregroundServiceType
                startForeground(
                    notificationId,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
                )
            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(
                    notificationId,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
                )
            } else {
                startForeground(notificationId, notification)
            }
            Log.i(tag, "startForeground succeeded")
        } catch (e: Exception) {
            Log.e(tag, "startForeground failed: ${e.message}", e)
        }
        return super.onStartCommand(intent, flags, startId)
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java) ?: return
        if (manager.getNotificationChannel(channelId) != null) return
        val channel = NotificationChannel(
            channelId,
            "EduSys Attendance",
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "Attendance tracking active"
            setShowBadge(false)
        }
        manager.createNotificationChannel(channel)
        Log.i(tag, "Notification channel created")
    }

    private fun buildNotification(): Notification {
        return NotificationCompat.Builder(this, channelId)
            .setContentTitle("EduSys Attendance")
            .setContentText("Attendance tracking active")
            .setSmallIcon(android.R.drawable.ic_menu_mylocation)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
            .setAutoCancel(false)
            .build()
    }
}
