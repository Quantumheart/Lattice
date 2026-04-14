import Flutter
import UIKit
import flutter_callkit_incoming
import AVFAudio
import CallKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, CallkitIncomingAppDelegate {
  private var apnsChannel: FlutterMethodChannel?
  private var pendingPushPayloads: [[AnyHashable: Any]] = []
  private var channelReady = false
  private static let maxPendingPayloads = 20

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = self
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    let userInfo = response.notification.request.content.userInfo
    if let notification = userInfo["notification"] as? [String: Any],
       let roomId = notification["room_id"] as? String {
      apnsChannel?.invokeMethod("onNotificationTap", arguments: roomId)
    }
    completionHandler()
  }

  // ── APNs token callbacks ────────────────────────────────────

  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Foundation.Data
  ) {
    let token = deviceToken.map { String(format: "%02x", $0) }.joined()
    apnsChannel?.invokeMethod("onToken", arguments: token)
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }

  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    apnsChannel?.invokeMethod("onRegistrationError", arguments: error.localizedDescription)
  }

  // ── Background push receipt ─────────────────────────────────

  override func application(
    _ application: UIApplication,
    didReceiveRemoteNotification userInfo: [AnyHashable: Any],
    fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
  ) {
    if channelReady {
      var completed = false
      apnsChannel?.invokeMethod("onRemoteMessage", arguments: userInfo) { _ in
        guard !completed else { return }
        completed = true
        completionHandler(.newData)
      }
      DispatchQueue.main.asyncAfter(deadline: .now() + 25) {
        guard !completed else { return }
        completed = true
        completionHandler(.newData)
      }
    } else {
      if pendingPushPayloads.count < AppDelegate.maxPendingPayloads {
        pendingPushPayloads.append(userInfo)
      }
      completionHandler(.newData)
    }
  }

  private func flushPendingPayloads() {
    for payload in pendingPushPayloads {
      apnsChannel?.invokeMethod("onRemoteMessage", arguments: payload)
    }
    pendingPushPayloads.removeAll()
  }

  // ── Flutter engine ──────────────────────────────────────────

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "LatticeApnsPlugin") else { return }
    let messenger = registrar.messenger()

    apnsChannel = FlutterMethodChannel(name: "lattice/apns", binaryMessenger: messenger)
    apnsChannel?.setMethodCallHandler { [weak self] (call, result) in
      switch call.method {
      case "requestToken":
        self?.channelReady = true
        self?.flushPendingPayloads()
        UNUserNotificationCenter.current().requestAuthorization(
          options: [.alert, .badge, .sound]
        ) { granted, error in
          DispatchQueue.main.async {
            if granted {
              UIApplication.shared.registerForRemoteNotifications()
              result(nil)
            } else {
              result(FlutterError(
                code: "PERMISSION_DENIED",
                message: error?.localizedDescription ?? "Notification permission denied",
                details: nil
              ))
            }
          }
        }
      case "unregister":
        UIApplication.shared.unregisterForRemoteNotifications()
        result(nil)
      case "getAppGroupPath":
        let path = FileManager.default.containerURL(
          forSecurityApplicationGroupIdentifier: "group.io.github.quantumheart.lattice"
        )?.path
        result(path)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  // ── CallKit ─────────────────────────────────────────────────

  func onAccept(_ call: flutter_callkit_incoming.Call, _ action: CXAnswerCallAction) {
    action.fulfill()
  }

  func onDecline(_ call: flutter_callkit_incoming.Call, _ action: CXEndCallAction) {
    action.fulfill()
  }

  func onEnd(_ call: flutter_callkit_incoming.Call, _ action: CXEndCallAction) {
    action.fulfill()
  }

  func onTimeOut(_ call: flutter_callkit_incoming.Call) {}

  func didActivateAudioSession(_ audioSession: AVAudioSession) {}

  func didDeactivateAudioSession(_ audioSession: AVAudioSession) {}
}
