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
  private var pendingNotificationActions: [(action: String, roomId: String, eventId: String?, replyText: String?)] = []
  private var channelReady = false
  private static let maxPendingPayloads = 20

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let replyAction = UNTextInputNotificationAction(
      identifier: "reply",
      title: "Reply",
      textInputButtonTitle: "Send",
      textInputPlaceholder: "Message..."
    )
    let markReadAction = UNNotificationAction(
      identifier: "mark_read",
      title: "Mark as Read"
    )
    let category = UNNotificationCategory(
      identifier: "MESSAGE",
      actions: [replyAction, markReadAction],
      intentIdentifiers: []
    )
    UNUserNotificationCenter.current().setNotificationCategories([category])
    UNUserNotificationCenter.current().delegate = self
    application.applicationIconBadgeNumber = 0
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func applicationDidBecomeActive(_ application: UIApplication) {
    application.applicationIconBadgeNumber = 0
  }

  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    let userInfo = response.notification.request.content.userInfo
    guard let notification = userInfo["notification"] as? [String: Any],
          let roomId = notification["room_id"] as? String else {
      completionHandler()
      return
    }

    let eventId = notification["event_id"] as? String

    switch response.actionIdentifier {
    case "reply":
      let replyText = (response as? UNTextInputNotificationResponse)?.userText
      dispatchOrQueue(action: "reply", roomId: roomId, eventId: eventId, replyText: replyText)
    case "mark_read":
      dispatchOrQueue(action: "mark_read", roomId: roomId, eventId: eventId, replyText: nil)
    default:
      dispatchOrQueue(action: "tap", roomId: roomId, eventId: eventId, replyText: nil)
    }

    UIApplication.shared.applicationIconBadgeNumber = 0
    completionHandler()
  }

  private func dispatchOrQueue(action: String, roomId: String, eventId: String?, replyText: String?) {
    if channelReady {
      dispatchAction(action: action, roomId: roomId, eventId: eventId, replyText: replyText)
    } else {
      pendingNotificationActions.append((action: action, roomId: roomId, eventId: eventId, replyText: replyText))
    }
  }

  private func dispatchAction(action: String, roomId: String, eventId: String?, replyText: String?) {
    switch action {
    case "reply":
      apnsChannel?.invokeMethod("onNotificationReply", arguments: ["roomId": roomId, "text": replyText ?? ""])
    case "mark_read":
      apnsChannel?.invokeMethod("onNotificationMarkAsRead", arguments: ["roomId": roomId, "eventId": eventId ?? ""])
    default:
      apnsChannel?.invokeMethod("onNotificationTap", arguments: roomId)
    }
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

    for pending in pendingNotificationActions {
      dispatchAction(action: pending.action, roomId: pending.roomId, eventId: pending.eventId, replyText: pending.replyText)
    }
    pendingNotificationActions.removeAll()
  }

  // ── Flutter engine ──────────────────────────────────────────

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "KoheraApnsPlugin") else { return }
    let messenger = registrar.messenger()

    apnsChannel = FlutterMethodChannel(name: "kohera/apns", binaryMessenger: messenger)
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
      case "clearBadge":
        UIApplication.shared.applicationIconBadgeNumber = 0
        result(nil)
      case "getAppGroupPath":
        let path = FileManager.default.containerURL(
          forSecurityApplicationGroupIdentifier: "group.io.github.quantumheart.kohera"
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
