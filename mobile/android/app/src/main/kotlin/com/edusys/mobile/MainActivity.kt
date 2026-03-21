package com.edusys.mobile

import android.Manifest
import android.bluetooth.BluetoothAdapter
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.bluetooth.le.BluetoothLeAdvertiser
import android.content.Intent
import android.net.Uri
import android.os.PowerManager
import android.content.ComponentName
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.pm.PackageManager
import android.location.LocationManager
import android.os.Build
import android.os.Bundle
import android.telephony.SubscriptionManager
import android.util.Base64
import android.util.Log
import androidx.core.app.ActivityCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileWriter

class MainActivity : FlutterActivity() {
    private val channelName = "edusys/device"
    private val bleChannelName = "edusys/ble_advertise"
    private val attendanceNativeChannel = "edusys/attendance_native"
    private val attendanceChannelId = "edusys_attendance"
    private var advertiser: BluetoothLeAdvertiser? = null
    private var advertiseCallback: AdvertiseCallback? = null
    private var pendingAdvertiseResult: MethodChannel.Result? = null
    private val tag = "EduSysNative"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        logNative("MainActivity.onCreate")
        Thread.setDefaultUncaughtExceptionHandler { t, e ->
            logNative("Uncaught exception on ${t.name}: ${e.message}", e)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                if (call.method == "getSimSerial") {
                    result.success(getSimSerial())
                } else {
                    result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, bleChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startAdvertising" -> {
                        val serviceUuid = call.argument<String>("serviceUuid")
                        val manufacturerId = call.argument<Int>("manufacturerId") ?: 0x0001
                        val payloadBase64 = call.argument<String>("payloadBase64") ?: ""
                        val payload = Base64.decode(payloadBase64, Base64.NO_WRAP)
                        pendingAdvertiseResult = result
                        startAdvertising(serviceUuid, manufacturerId, payload)
                    }
                    "stopAdvertising" -> {
                        stopAdvertising()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, attendanceNativeChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "ensureChannel" -> {
                        createAttendanceChannel()
                        result.success(true)
                    }
                    "setBackgroundReceivers" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: false
                        setBackgroundReceiversEnabled(enabled)
                        result.success(true)
                    }
                    "openAppSettings" -> {
                        openAppSettings()
                        result.success(true)
                    }
                    "requestIgnoreBatteryOptimizations" -> {
                        requestIgnoreBatteryOptimizations()
                        result.success(true)
                    }
                    "openBatteryOptimizationSettings" -> {
                        openBatteryOptimizationSettings()
                        result.success(true)
                    }
                    "openBluetoothSettings" -> {
                        openBluetoothSettings()
                        result.success(true)
                    }
                    "openLocationSettings" -> {
                        openLocationSettings()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun getSimSerial(): String {
        if (ActivityCompat.checkSelfPermission(
                this,
                Manifest.permission.READ_PHONE_STATE
            ) != PackageManager.PERMISSION_GRANTED
        ) return ""
        val manager = getSystemService(SubscriptionManager::class.java) ?: return ""
        val subscriptions = manager.activeSubscriptionInfoList ?: return ""
        if (subscriptions.isEmpty()) return ""
        return subscriptions[0].iccId ?: ""
    }

    private fun startAdvertising(
        serviceUuid: String?,
        manufacturerId: Int,
        payload: ByteArray
    ) {
        if (serviceUuid.isNullOrBlank()) {
            pendingAdvertiseResult?.error("INVALID_UUID", "serviceUuid is null or blank", null)
            pendingAdvertiseResult = null
            return
        }
        val adapter = BluetoothAdapter.getDefaultAdapter()
        if (adapter == null || !adapter.isEnabled) {
            pendingAdvertiseResult?.error("BT_OFF", "Bluetooth adapter unavailable or off", null)
            pendingAdvertiseResult = null
            return
        }
        val bleAdvertiser = adapter.bluetoothLeAdvertiser
        if (bleAdvertiser == null) {
            pendingAdvertiseResult?.error(
                "BLE_ADVERTISE_UNSUPPORTED",
                "Device does not support BLE advertising",
                null
            )
            pendingAdvertiseResult = null
            return
        }

        stopAdvertising()
        advertiser = bleAdvertiser

        val settings = AdvertiseSettings.Builder()
            .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
            .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_HIGH)
            .setConnectable(false)
            .build()

        val safePayload = if (payload.size > 11) payload.copyOf(11) else payload

        val data = AdvertiseData.Builder()
            .setIncludeDeviceName(false)
            .addManufacturerData(manufacturerId, safePayload)
            .build()

        advertiseCallback = object : AdvertiseCallback() {
            override fun onStartSuccess(settingsInEffect: AdvertiseSettings?) {
                runOnUiThread {
                    pendingAdvertiseResult?.success(true)
                    pendingAdvertiseResult = null
                }
            }

            override fun onStartFailure(errorCode: Int) {
                runOnUiThread {
                    if (errorCode == ADVERTISE_FAILED_ALREADY_STARTED) {
                        // Already advertising — treat as success, not failure
                        pendingAdvertiseResult?.success(true)
                        pendingAdvertiseResult = null
                        return@runOnUiThread
                    }
                    val reason = when (errorCode) {
                        ADVERTISE_FAILED_DATA_TOO_LARGE -> "Payload too large for BLE advertisement"
                        ADVERTISE_FAILED_TOO_MANY_ADVERTISERS -> "Too many concurrent advertisers"
                        ADVERTISE_FAILED_INTERNAL_ERROR -> "Internal BLE error"
                        ADVERTISE_FAILED_FEATURE_UNSUPPORTED -> "BLE advertising not supported on this device"
                        else -> "Unknown error: $errorCode"
                    }
                    pendingAdvertiseResult?.error("BLE_ADVERTISE_FAILED", reason, errorCode)
                    pendingAdvertiseResult = null
                }
            }
        }

        bleAdvertiser.startAdvertising(settings, data, advertiseCallback)
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

    private fun setBackgroundReceiversEnabled(enabled: Boolean) {
        val pm = packageManager ?: return
        val watchdog = ComponentName(
            this,
            "id.flutter.flutter_background_service.WatchdogReceiver"
        )
        val boot = ComponentName(
            this,
            "id.flutter.flutter_background_service.BootReceiver"
        )
        val state = if (enabled) {
            PackageManager.COMPONENT_ENABLED_STATE_ENABLED
        } else {
            PackageManager.COMPONENT_ENABLED_STATE_DISABLED
        }
        pm.setComponentEnabledSetting(watchdog, state, PackageManager.DONT_KILL_APP)
        pm.setComponentEnabledSetting(boot, state, PackageManager.DONT_KILL_APP)
    }

    private fun openAppSettings() {
        try {
            val intent = Intent(android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                data = Uri.fromParts("package", packageName, null)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
        } catch (_: Exception) {
            // Ignore
        }
    }

    private fun requestIgnoreBatteryOptimizations() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
        try {
            val power = getSystemService(PowerManager::class.java) ?: return
            if (power.isIgnoringBatteryOptimizations(packageName)) return
            val intent = Intent(android.provider.Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                data = Uri.parse("package:$packageName")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
        } catch (_: Exception) {
            // Ignore
        }
    }

    private fun openBatteryOptimizationSettings() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
        try {
            val intent = Intent(android.provider.Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
        } catch (_: Exception) {
            // Ignore
        }
    }

    private fun openBluetoothSettings() {
        try {
            val intent = Intent(android.provider.Settings.ACTION_BLUETOOTH_SETTINGS).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
        } catch (_: Exception) {
            // Ignore
        }
    }

    private fun openLocationSettings() {
        try {
            val intent = Intent(android.provider.Settings.ACTION_LOCATION_SOURCE_SETTINGS).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
        } catch (_: Exception) {
            // Ignore
        }
    }

    private fun stopAdvertising() {
        val bleAdvertiser = advertiser ?: return
        val callback = advertiseCallback ?: return
        try {
            bleAdvertiser.stopAdvertising(callback)
        } catch (_: Exception) {
            // Ignore — adapter may have been turned off
        }
        advertiser = null
        advertiseCallback = null
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
