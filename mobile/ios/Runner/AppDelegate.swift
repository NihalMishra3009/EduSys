import Flutter
import UIKit
import CoreBluetooth

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, CBPeripheralManagerDelegate {
  private let bleChannelName = "edusys/ble_advertise"
  private var peripheralManager: CBPeripheralManager?
  private var pendingAdvertiseData: [String: Any]?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(name: bleChannelName, binaryMessenger: controller.binaryMessenger)
      channel.setMethodCallHandler { [weak self] call, result in
        switch call.method {
        case "startAdvertising":
          guard let args = call.arguments as? [String: Any],
                let serviceUuid = args["serviceUuid"] as? String,
                let payloadBase64 = args["payloadBase64"] as? String,
                let payloadData = Data(base64Encoded: payloadBase64) else {
            result(FlutterError(code: "BAD_ARGS", message: "Invalid advertise args", details: nil))
            return
          }
          let service = CBMutableService(type: CBUUID(string: serviceUuid), primary: true)
          let adv: [String: Any] = [
            CBAdvertisementDataServiceUUIDsKey: [service.uuid],
            CBAdvertisementDataManufacturerDataKey: payloadData
          ]
          self?.pendingAdvertiseData = adv
          if self?.peripheralManager == nil {
            self?.peripheralManager = CBPeripheralManager(delegate: self, queue: nil)
          } else if self?.peripheralManager?.state == .poweredOn {
            self?.peripheralManager?.add(service)
            self?.peripheralManager?.startAdvertising(adv)
          }
          result(true)
        case "stopAdvertising":
          self?.peripheralManager?.stopAdvertising()
          self?.pendingAdvertiseData = nil
          result(true)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
    guard peripheral.state == .poweredOn else { return }
    if let adv = pendingAdvertiseData {
      peripheral.startAdvertising(adv)
    }
  }
}
