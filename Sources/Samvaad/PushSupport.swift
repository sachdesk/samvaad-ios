import Foundation

enum PushTokenEncoding {
    /// APNs device token bytes as lower-case hex, the form the server expects.
    static func hex(_ data: Data) -> String {
        let digits: [Character] = Array("0123456789abcdef")
        var out = ""
        out.reserveCapacity(data.count * 2)
        for byte in data {
            out.append(digits[Int(byte >> 4)])
            out.append(digits[Int(byte & 0x0F)])
        }
        return out
    }
}

enum PushPayload {
    /// True when a notification came from Samvaad: `samvaad: "1"` at the top level of
    /// `userInfo` (next to `aps` for APNs, or in the FCM data map).
    static func isSamvaad(_ userInfo: [AnyHashable: Any]) -> Bool {
        guard let value = userInfo["samvaad"] else { return false }
        if let text = value as? String {
            return text.trimmingCharacters(in: .whitespaces) == "1"
        }
        if let number = value as? NSNumber {
            return number.intValue == 1 && number.doubleValue == 1
        }
        return false
    }

    /// The `tenant_id` of a Samvaad push, when present.
    static func tenantId(_ userInfo: [AnyHashable: Any]) -> String? {
        return userInfo["tenant_id"] as? String
    }
}
