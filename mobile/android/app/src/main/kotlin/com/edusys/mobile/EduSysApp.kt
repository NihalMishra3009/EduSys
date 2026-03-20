package com.edusys.mobile

import android.app.Application
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.ComponentName
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import java.io.File
import java.io.FileWriter

class EduSysApp : Application() {
    private val tag = "EduSysApp"
    private val attendanceChannelId = "edusys_attendance"

    override fun onCreate() {
        super.onCreate()
        logNative("Application.onCreate")
        createAttendanceChannel()
        disableBackgroundReceiversByDefault()
        Thread.setDefaultUncaughtExceptionHandler { t, e ->
            logNative("Uncaught exception on ${t.name}: ${e.message}", e)
        }
    }

    private fun createAttendanceChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java) ?: return
        val existing = manager.getNotificationChannel(attendanceChannelId)
        if (existing != null) return
        val channel = NotificationChannel(
            attendanceChannelId,
            "EduSys Attendance",
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "Foreground service notifications for attendance tracking"
        }
        manager.createNotificationChannel(channel)
    }

    private fun disableBackgroundReceiversByDefault() {
        val pm = packageManager ?: return
        val watchdog = ComponentName(
            this,
            "id.flutter.flutter_background_service.WatchdogReceiver"
        )
        val boot = ComponentName(
            this,
            "id.flutter.flutter_background_service.BootReceiver"
        )
        pm.setComponentEnabledSetting(
            watchdog,
            PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
            PackageManager.DONT_KILL_APP
        )
        pm.setComponentEnabledSetting(
            boot,
            PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
            PackageManager.DONT_KILL_APP
        )
    }

    private fun logNative(message: String, error: Throwable? = null) {
        if (error != null) {
            Log.e(tag, message, error)
        } else {
            Log.i(tag, message)
        }
        try {
            val dir = getExternalFilesDir(null) ?: filesDir
            val file = File(dir, "native_crash_log.txt")
            FileWriter(file, true).use { writer ->
                writer.appendLine("[${System.currentTimeMillis()}] $message")
                if (error != null) {
                    writer.appendLine(Log.getStackTraceString(error))
                }
            }
        } catch (_: Exception) {
            // Ignore logging failures
        }
    }
}
