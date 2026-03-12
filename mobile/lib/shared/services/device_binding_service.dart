import "package:device_info_plus/device_info_plus.dart";
import "package:flutter/services.dart";

class DeviceBindingService {
  final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();
  static const MethodChannel _channel = MethodChannel("edusys/device");

  Future<String> getDeviceId() async {
    final info = await _deviceInfo.androidInfo;
    final androidId = info.id;
    if (androidId.isNotEmpty) {
      return androidId;
    }
    return "UNKNOWN_DEVICE";
  }

  Future<String> getSimSerial() async {
    try {
      final serial = await _channel.invokeMethod<String>("getSimSerial");
      if (serial != null && serial.isNotEmpty) {
        return serial;
      }
    } catch (_) {}
    return "SIM_UNAVAILABLE";
  }
}
