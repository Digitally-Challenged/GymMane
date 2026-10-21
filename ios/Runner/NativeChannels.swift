import Flutter
import HealthKit
import Photos
import UIKit

/// Baseline platform services and explicit capability discovery for optional UI.
final class NativeChannels {
  private var channels: [FlutterMethodChannel] = []
  private var originalBrightness: CGFloat?

  func register(with messenger: FlutterBinaryMessenger) {
    bind("gymmane/capabilities", messenger) { call, result in
      guard call.method == "get" else { result(FlutterMethodNotImplemented); return }
      result(["liveActivities": false, "homeWidgets": false,
              "deviceClass": UIDevice.current.userInterfaceIdiom == .pad ? "tablet" : "phone",
              "healthKit": HKHealthStore.isHealthDataAvailable()])
    }
    bind("gymmane/live_activity", messenger) { call, result in
      switch call.method {
      case "availability": result(false)
      // No ActivityKit extension is shipped. Baseline callers await void.
      case "update", "end": result(nil)
      default: result(FlutterMethodNotImplemented)
      }
    }
    bind("gymmane/screen", messenger) { [weak self] call, result in
      guard let on = (call.arguments as? [String: Any])?["on"] as? Bool else {
        result(FlutterError(code: "invalid_argument", message: "on must be a boolean.", details: nil))
        return
      }
      switch call.method {
      case "keepOn": UIApplication.shared.isIdleTimerDisabled = on; result(nil)
      case "dim":
        guard let self else { result(nil); return }
        if on {
          if self.originalBrightness == nil { self.originalBrightness = UIScreen.main.brightness }
          UIScreen.main.brightness = 0.1
        } else if let brightness = self.originalBrightness {
          UIScreen.main.brightness = brightness
          self.originalBrightness = nil
        }
        result(nil)
      default: result(FlutterMethodNotImplemented)
      }
    }
    bind("gymmane/haptics", messenger) { call, result in
      guard call.method == "buzz" else { result(FlutterMethodNotImplemented); return }
      UINotificationFeedbackGenerator().notificationOccurred(.success)
      result(nil)
    }
    bind("gymmane/gallery", messenger) { call, result in
      guard call.method == "savePng" else { result(FlutterMethodNotImplemented); return }
      guard let args = call.arguments as? [String: Any],
            let bytes = args["bytes"] as? FlutterStandardTypedData,
            UIImage(data: bytes.data) != nil else {
        result(FlutterError(code: "invalid_argument", message: "Valid image bytes required.", details: nil))
        return
      }
      PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
        guard status == .authorized || status == .limited else {
          DispatchQueue.main.async { result(false) }
          return
        }
        PHPhotoLibrary.shared().performChanges({
          PHAssetCreationRequest.forAsset().addResource(with: .photo, data: bytes.data, options: nil)
        }) { saved, _ in DispatchQueue.main.async { result(saved) } }
      }
    }
  }

  private func bind(_ name: String, _ messenger: FlutterBinaryMessenger,
                    _ handler: @escaping FlutterMethodCallHandler) {
    let channel = FlutterMethodChannel(name: name, binaryMessenger: messenger)
    channel.setMethodCallHandler(handler)
    channels.append(channel)
  }
}
