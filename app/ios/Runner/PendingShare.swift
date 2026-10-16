import Flutter
import Foundation

/// Hands the app any share the Share Extension left behind.
///
/// The extension always writes what was shared into the App Group and then
/// tries to open the app by walking its responder chain looking for a
/// UIApplication. An app extension has no UIApplication — the class is
/// unavailable to extensions by design — so on current iOS that open quietly
/// does nothing and the share sheet just closes.
///
/// The plugin only reads the App Group when the app is opened by its
/// `ShareMedia-<bundle id>` URL, so a share whose redirect did not land is
/// never read at all: the seller shares a screenshot and nothing happens,
/// then or ever.
///
/// This reads the same two keys the extension writes, and clears them, so the
/// app can pick a share up on its own the next time it is opened or resumed.
/// When the redirect does work the plugin gets there first and this finds
/// nothing, which is the intended outcome rather than a race: both paths end
/// at the same `reset()`.
enum PendingShare {
  /// Must match the plugin's constants.
  private static let payloadKey = "ShareKey"
  private static let messageKey = "ShareMessageKey"
  private static let appGroupIdKey = "AppGroupId"

  private static var appGroupId: String {
    let custom = Bundle.main.object(forInfoDictionaryKey: appGroupIdKey) as? String
    if let custom, !custom.isEmpty { return custom }
    return "group.\(Bundle.main.bundleIdentifier ?? "")"
  }

  /// The pending share as the JSON the extension stored, or nil. Clears it.
  static func take() -> [String: Any]? {
    guard let defaults = UserDefaults(suiteName: appGroupId) else { return nil }
    guard let data = defaults.object(forKey: payloadKey) as? Data else { return nil }

    let message = defaults.string(forKey: messageKey)
    defaults.removeObject(forKey: payloadKey)
    defaults.removeObject(forKey: messageKey)

    guard let json = String(data: data, encoding: .utf8) else { return nil }
    return ["payload": json, "message": message as Any]
  }

  static func register(with registry: FlutterPluginRegistry) {
    guard let messenger = registry.registrar(forPlugin: "SortedPendingShare")?.messenger()
    else { return }
    let channel = FlutterMethodChannel(name: "sorted/pending_share", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "take":
        result(take())
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
