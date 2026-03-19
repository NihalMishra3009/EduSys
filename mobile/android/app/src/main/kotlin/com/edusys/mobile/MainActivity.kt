package com.edusys.mobile

import android.Manifest
import android.bluetooth.BluetoothAdapter
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.bluetooth.le.BluetoothLeAdvertiser
import android.content.pm.PackageManager
import android.os.ParcelUuid
import android.telephony.SubscriptionManager
import android.util.Base64
import androidx.core.app.ActivityCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.UUID

class MainActivity : FlutterActivity() {
    private val channelName = "edusys/device"
    private val bleChannelName = "edusys/ble_advertise"
    private var advertiser: BluetoothLeAdvertiser? = null
    private var advertiseCallback: AdvertiseCallback? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            if (call.method == "getSimSerial") {
                result.success(getSimSerial())
            } else {
                result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, bleChannelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "startAdvertising" -> {
                    val serviceUuid = call.argument<String>("serviceUuid")
                    val manufacturerId = call.argument<Int>("manufacturerId") ?: 0x0001
                    val payloadBase64 = call.argument<String>("payloadBase64") ?: ""
                    val payload = Base64.decode(payloadBase64, Base64.NO_WRAP)
                    val ok = startAdvertising(serviceUuid, manufacturerId, payload)
                    if (ok) {
                        result.success(true)
                    } else {
                        result.error("BLE_ADVERTISE_FAILED", "Unable to start BLE advertising", null)
                    }
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
        if (ActivityCompat.checkSelfPermission(this, Manifest.permission.READ_PHONE_STATE) != PackageManager.PERMISSION_GRANTED) {
            return ""
        }

        val manager = getSystemService(SubscriptionManager::class.java) ?: return ""
        val subscriptions = manager.activeSubscriptionInfoList ?: return ""
        if (subscriptions.isEmpty()) {
            return ""
        }
        return subscriptions[0].iccId ?: ""
    }

    private fun startAdvertising(serviceUuid: String?, manufacturerId: Int, payload: ByteArray): Boolean {
        if (serviceUuid.isNullOrBlank()) return false
        val adapter = BluetoothAdapter.getDefaultAdapter() ?: return false
        if (!adapter.isEnabled) return false
        val bleAdvertiser = adapter.bluetoothLeAdvertiser ?: return false
        advertiser = bleAdvertiser

        val settings = AdvertiseSettings.Builder()
            .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
            .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_HIGH)
            .setConnectable(false)
            .build()

        val data = AdvertiseData.Builder()
            .setIncludeDeviceName(false)
            .addServiceUuid(ParcelUuid(UUID.fromString(serviceUuid)))
            .addManufacturerData(manufacturerId, payload)
            .build()

        advertiseCallback = object : AdvertiseCallback() {}
        bleAdvertiser.startAdvertising(settings, data, advertiseCallback)
        return true
    }

    private fun stopAdvertising() {
        val bleAdvertiser = advertiser ?: return
        val callback = advertiseCallback ?: return
        bleAdvertiser.stopAdvertising(callback)
        advertiser = null
        advertiseCallback = null
    }
}
