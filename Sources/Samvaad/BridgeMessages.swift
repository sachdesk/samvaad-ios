import Foundation

/// The signed-in customer, as given to `Samvaad.identify`.
struct Identity: Equatable {
    let email: String
    let name: String?
    let userHash: String
}

/// How the server delivers a push to this device.
enum PushRoute: String, Equatable {
    case fcm
    case apns
}

struct PushToken: Equatable {
    let token: String
    let route: PushRoute
}

/// Messages the app sends to the page (`window.SamvaadBridge.receive`).
enum OutgoingMessage: Equatable {
    case identify(Identity)
    case reset
    case message(text: String)
    case pushToken(PushToken, appId: String?)

    var type: String {
        switch self {
        case .identify: return "identify"
        case .reset: return "reset"
        case .message: return "message"
        case .pushToken: return "pushToken"
        }
    }

    /// The JSON object the page expects for this message.
    var jsonObject: [String: Any] {
        switch self {
        case .identify(let identity):
            var fields: [String: Any] = [
                "email": identity.email,
                "user_hash": identity.userHash,
            ]
            if let name = identity.name { fields["name"] = name }
            return ["type": type, "identity": fields]
        case .reset:
            return ["type": type]
        case .message(let text):
            return ["type": type, "text": text]
        case .pushToken(let push, let appId):
            // Top-level fields, not nested (see the page's readHostMessage).
            var object: [String: Any] = [
                "type": type,
                "token": push.token,
                "route": push.route.rawValue,
                "platform": "ios",
            ]
            if let appId = appId, !appId.isEmpty { object["app_id"] = appId }
            return object
        }
    }
}

enum BridgeScript {
    /// JSON for one message, safe to paste into a JavaScript source string.
    /// U+2028 / U+2029 are valid in JSON strings but were line terminators in older
    /// JavaScript, so they are escaped too.
    static func json(for message: OutgoingMessage) -> String? {
        let object = message.jsonObject
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8)
        else { return nil }
        return escapeLineSeparators(text)
    }

    static func escapeLineSeparators(_ text: String) -> String {
        return text
            .replacingOccurrences(of: "\u{2028}", with: "\\u2028")
            .replacingOccurrences(of: "\u{2029}", with: "\\u2029")
    }

    /// The script that hands one message to the page.
    static func script(for message: OutgoingMessage) -> String? {
        guard let body = json(for: message) else { return nil }
        return "window.SamvaadBridge && window.SamvaadBridge.receive(\(body));"
    }
}

/// Messages the page sends to the app (`window.webkit.messageHandlers.samvaad`).
enum IncomingMessage: Equatable {
    case ready(enabled: Bool)
    case close
    case unread(count: Int)
    case navigate(URL)
    case visibility(visible: Bool)

    static let bridgeVersion = 1

    /// Reads `message.body`: a dictionary (or a JSON string) with `v: 1` and a known `type`.
    /// Anything else returns nil.
    static func parse(_ body: Any) -> IncomingMessage? {
        var raw: Any = body
        if let text = raw as? String {
            guard let data = text.data(using: .utf8),
                  let decoded = try? JSONSerialization.jsonObject(with: data)
            else { return nil }
            raw = decoded
        }
        guard let dict = raw as? [String: Any],
              let version = integer(dict["v"]), version == bridgeVersion,
              let type = dict["type"] as? String
        else { return nil }

        switch type {
        case "ready":
            let enabled = (dict["enabled"] as? Bool) ?? true
            return .ready(enabled: enabled)
        case "close":
            return .close
        case "unread":
            guard let count = integer(dict["count"]) else { return nil }
            return .unread(count: max(0, count))
        case "navigate":
            guard let text = dict["url"] as? String,
                  let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
                  url.scheme != nil
            else { return nil }
            return .navigate(url)
        case "visibility":
            return .visibility(visible: (dict["visible"] as? Bool) ?? true)
        default:
            return nil
        }
    }

    /// A whole number from a JS number (NSNumber / Int / Double).
    static func integer(_ value: Any?) -> Int? {
        // No `is Bool` check here: on Apple platforms a JS number 0 or 1 arrives as an
        // NSNumber that also casts to Bool, so such a check would drop `v: 1`.
        guard let value = value else { return nil }
        if let int = value as? Int { return int }
        if let double = value as? Double, double.isFinite, double.rounded() == double,
           abs(double) < 1e15 {
            return Int(double)
        }
        return nil
    }
}
