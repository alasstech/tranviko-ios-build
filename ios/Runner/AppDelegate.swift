import Flutter
import PushKit
import UIKit
import flutter_callkit_incoming

@main
@objc class AppDelegate: FlutterAppDelegate, PKPushRegistryDelegate {
  private var voipRegistry: PKPushRegistry?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    let registry = PKPushRegistry(queue: .main)
    registry.delegate = self
    registry.desiredPushTypes = [.voIP]
    voipRegistry = registry

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func pushRegistry(
    _ registry: PKPushRegistry,
    didUpdate pushCredentials: PKPushCredentials,
    for type: PKPushType
  ) {
    guard type == .voIP else { return }
    let token = pushCredentials.token.map { String(format: "%02x", $0) }.joined()
    SwiftFlutterCallkitIncomingPlugin.sharedInstance?.setDevicePushTokenVoIP(token)
  }

  func pushRegistry(
    _ registry: PKPushRegistry,
    didInvalidatePushTokenFor type: PKPushType
  ) {
    guard type == .voIP else { return }
    SwiftFlutterCallkitIncomingPlugin.sharedInstance?.setDevicePushTokenVoIP("")
  }

  func pushRegistry(
    _ registry: PKPushRegistry,
    didReceiveIncomingPushWith payload: PKPushPayload,
    for type: PKPushType,
    completion: @escaping () -> Void
  ) {
    guard type == .voIP else {
      completion()
      return
    }

    var values = payload.dictionaryPayload.reduce(into: [String: Any]()) {
      result, item in
      if let key = item.key as? String {
        result[key] = item.value
      }
    }
    let signallingCallId = (values["callId"] as? String)
      ?? (values["id"] as? String)
      ?? UUID().uuidString
    let callId = UUID(uuidString: signallingCallId)?.uuidString
      ?? UUID().uuidString
    values["callId"] = signallingCallId
    values["nativeCallId"] = callId
    let callerName = (values["callerName"] as? String)
      ?? (values["nameCaller"] as? String)
      ?? (values["title"] as? String)
      ?? "Appel Tranviko"
    let handle = (values["callerId"] as? String)
      ?? (values["fromId"] as? String)
      ?? (values["handle"] as? String)
      ?? callerName
    let media = (values["media"] as? String)?.lowercased()
    let isVideo = (values["isVideo"] as? Bool) == true || media == "video"

    let call = flutter_callkit_incoming.Data(
      id: callId,
      nameCaller: callerName,
      handle: handle,
      type: isVideo ? 1 : 0
    )
    call.appName = "Tranviko"
    call.iconName = "AppIcon"
    call.extra = values as NSDictionary

    guard let plugin = SwiftFlutterCallkitIncomingPlugin.sharedInstance else {
      completion()
      return
    }
    plugin.showCallkitIncoming(call, fromPushKit: true) {
      completion()
    }
  }
}
