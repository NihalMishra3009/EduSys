package com.edusys.mobile

import android.app.Application
import android.util.Log
import java.io.File
import java.io.FileWriter

class EduSysApp : Application() {
    private val tag = "EduSysApp"

    override fun onCreate() {
        super.onCreate()
        logNative("Application.onCreate")
        Thread.setDefaultUncaughtExceptionHandler { t, e ->
            logNative("Uncaught exception on ${t.name}: ${e.message}", e)
        }
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
