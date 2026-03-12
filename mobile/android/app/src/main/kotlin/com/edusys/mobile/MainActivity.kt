package com.edusys.mobile

import android.Manifest
import android.content.pm.PackageManager
import android.telephony.SubscriptionManager
import androidx.core.app.ActivityCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "edusys/device"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            if (call.method == "getSimSerial") {
                result.success(getSimSerial())
            } else {
                result.notImplemented()
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
}
