package com.edusys.mobile

import android.Manifest
import android.bluetooth.BluetoothAdapter
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.bluetooth.le.BluetoothLeAdvertiser
import android.content.pm.PackageManager
import android.os.Bundle
import android.os.ParcelUuid
import android.telephony.SubscriptionManager
import android.util.Base64
import android.util.Log
import androidx.core.app.ActivityCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileWriter
import java.util.UUID

class MainActivity : FlutterActivity() {
    private val channelName = "edusys/device"
    private val bleChannelName = "edusys/ble_advertise"
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
            .addServiceUuid(ParcelUuid(UUID.fromString(serviceUuid)))
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
                val reason = when (errorCode) {
                    ADVERTISE_FAILED_DATA_TOO_LARGE -> "Payload too large for BLE advertisement"
                    ADVERTISE_FAILED_TOO_MANY_ADVERTISERS -> "Too many concurrent advertisers"
                    ADVERTISE_FAILED_ALREADY_STARTED -> "Already advertising"
                    ADVERTISE_FAILED_INTERNAL_ERROR -> "Internal BLE error"
                    ADVERTISE_FAILED_FEATURE_UNSUPPORTED -> "BLE advertising not supported on this device"
                    else -> "Unknown error: $errorCode"
                }
                runOnUiThread {
                    pendingAdvertiseResult?.error("BLE_ADVERTISE_FAILED", reason, errorCode)
                    pendingAdvertiseResult = null
                }
            }
        }

        bleAdvertiser.startAdvertising(settings, data, advertiseCallback)
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
