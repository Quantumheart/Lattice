import AVFoundation
import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    let channel = FlutterMethodChannel(
      name: "com.kohera.app/tcc",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    channel.setMethodCallHandler { (call, result) in
      switch call.method {
      case "checkScreenCapturePermission":
        result(CGPreflightScreenCaptureAccess())
      case "requestScreenCapturePermission":
        result(CGRequestScreenCaptureAccess())
      case "checkMediaPermission":
        guard let mediaType = self.parseMediaType(call) else {
          result(FlutterError(code: "INVALID_ARG", message: "Expected 'camera' or 'microphone'", details: nil))
          return
        }
        let status = AVCaptureDevice.authorizationStatus(for: mediaType)
        result(status == .authorized)
      case "requestMediaPermission":
        guard let mediaType = self.parseMediaType(call) else {
          result(FlutterError(code: "INVALID_ARG", message: "Expected 'camera' or 'microphone'", details: nil))
          return
        }
        AVCaptureDevice.requestAccess(for: mediaType) { granted in
          DispatchQueue.main.async { result(granted) }
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    super.awakeFromNib()
  }

  private func parseMediaType(_ call: FlutterMethodCall) -> AVMediaType? {
    guard let args = call.arguments as? [String: Any],
          let type = args["type"] as? String else { return nil }
    switch type {
    case "camera": return .video
    case "microphone": return .audio
    default: return nil
    }
  }
}
