import UIKit
import Flutter
import CoreBluetooth

@main
@objc class AppDelegate: FlutterAppDelegate, CBPeripheralManagerDelegate {
    private var peripheralManager: CBPeripheralManager?
    private var bleChannel: FlutterMethodChannel?
    private var pendingServiceUUID: CBUUID?
    private var pendingResult: FlutterResult?

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        GeneratedPluginRegistrant.register(with: self)

        let controller = window?.rootViewController as! FlutterViewController
        bleChannel = FlutterMethodChannel(
            name: "edusys/ble_advertise",
            binaryMessenger: controller.binaryMessenger
        )

        bleChannel?.setMethodCallHandler { [weak self] call, result in
            switch call.method {
            case "startAdvertising":
                guard
                    let args = call.arguments as? [String: Any],
                    let serviceUuidString = args["serviceUuid"] as? String
                else {
                    result(FlutterError(
                        code: "INVALID_ARGS",
                        message: "serviceUuid is required",
                        details: nil
                    ))
                    return
                }
                self?.startAdvertising(
                    serviceUuidString: serviceUuidString,
                    result: result
                )
            case "stopAdvertising":
                self?.stopAdvertising()
                result(true)
            default:
                result(FlutterMethodNotImplemented)
            }
        }

        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    private func startAdvertising(
        serviceUuidString: String,
        result: @escaping FlutterResult
    ) {
        pendingServiceUUID = CBUUID(string: serviceUuidString)
        pendingResult = result
        peripheralManager = CBPeripheralManager(delegate: self, queue: nil)
    }

    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        guard peripheral.state == .poweredOn,
              let uuid = pendingServiceUUID else {
            pendingResult?(FlutterError(
                code: "BLE_OFF",
                message: "Bluetooth is not available or powered off",
                details: nil
            ))
            pendingResult = nil
            return
        }

        let advertisementData: [String: Any] = [
            CBAdvertisementDataServiceUUIDsKey: [uuid],
            CBAdvertisementDataLocalNameKey: "EduSys"
        ]
        peripheral.startAdvertising(advertisementData)
        pendingResult?(true)
        pendingResult = nil
    }

    func peripheralManager(
        _ peripheral: CBPeripheralManager,
        didStartAdvertising error: Error?
    ) {
        if let error = error {
            pendingResult?(FlutterError(
                code: "ADVERTISE_FAILED",
                message: error.localizedDescription,
                details: nil
            ))
            pendingResult = nil
        }
    }

    private func stopAdvertising() {
        peripheralManager?.stopAdvertising()
        peripheralManager = nil
        pendingServiceUUID = nil
    }
}
