import Foundation

/// What the SDK knows across chat screens: who is signed in, the device push token and
/// whether the next page load must start with `reset`. No UIKit here.
struct BridgeState: Equatable {
    var identity: Identity?
    var pushToken: PushToken?
    /// Set by `logout()` when no ready chat page was there to receive `reset`.
    var pendingReset: Bool = false
    /// The app's bundle identifier, sent as `app_id` with the push token.
    var appId: String?

    /// The messages a freshly loaded page gets right after `ready`, in order:
    /// `reset` first (if a logout is pending), then `identify`, then `pushToken`.
    /// Clears the pending reset, since it is now on its way.
    mutating func takePageLoadMessages() -> [OutgoingMessage] {
        var out: [OutgoingMessage] = []
        if pendingReset {
            out.append(.reset)
            pendingReset = false
        }
        if let identity = identity { out.append(.identify(identity)) }
        if let pushToken = pushToken { out.append(.pushToken(pushToken, appId: appId)) }
        return out
    }

    /// Forgets the identity. Returns true when `reset` should be sent now (a chat page is
    /// open and ready); otherwise remembers to send it after the next page's `ready`.
    /// The push token is kept: it belongs to the device.
    mutating func logout(pageReady: Bool) -> Bool {
        identity = nil
        if pageReady {
            pendingReset = false
            return true
        }
        pendingReset = true
        return false
    }
}

/// Queue of app → page messages for one chat screen: held until the page says `ready`,
/// then sent in order. A new page load (reload, `reset`) waits for `ready` again.
struct BridgeQueue {
    private(set) var isReady = false
    private(set) var pending: [OutgoingMessage] = []

    /// A new document is loading: hold messages until it is ready.
    mutating func pageWillLoad() {
        isReady = false
    }

    /// Returns the messages to send now: `[message]` when ready, else none (queued).
    mutating func send(_ message: OutgoingMessage) -> [OutgoingMessage] {
        if isReady { return [message] }
        pending.append(message)
        return []
    }

    /// The page is listening. Returns everything to send, in order: the page-load
    /// messages first, then whatever was queued.
    mutating func ready(pageLoadMessages: [OutgoingMessage]) -> [OutgoingMessage] {
        isReady = true
        let out = pageLoadMessages + pending
        pending.removeAll()
        return out
    }
}

/// Small key-value storage, so the state can be tested without `UserDefaults`.
protocol KeyValueStore: AnyObject {
    func string(forKey key: String) -> String?
    func bool(forKey key: String) -> Bool
    func set(_ value: Any?, forKey key: String)
    func removeObject(forKey key: String)
}

extension UserDefaults: KeyValueStore {}

/// Saves the parts of `BridgeState` that must outlive the app process: the push token and
/// the pending-reset flag. The identity is kept in memory only; apps call `identify` on
/// each launch once their user is signed in.
struct BridgeStateStore {
    static let tokenKey = "samvaad.sdk.pushToken"
    static let routeKey = "samvaad.sdk.pushRoute"
    static let pendingResetKey = "samvaad.sdk.pendingReset"

    let store: KeyValueStore

    func load(into state: inout BridgeState) {
        if let token = store.string(forKey: Self.tokenKey),
           let routeRaw = store.string(forKey: Self.routeKey),
           let route = PushRoute(rawValue: routeRaw),
           !token.isEmpty {
            state.pushToken = PushToken(token: token, route: route)
        }
        state.pendingReset = store.bool(forKey: Self.pendingResetKey)
    }

    func save(_ state: BridgeState) {
        if let push = state.pushToken {
            store.set(push.token, forKey: Self.tokenKey)
            store.set(push.route.rawValue, forKey: Self.routeKey)
        } else {
            store.removeObject(forKey: Self.tokenKey)
            store.removeObject(forKey: Self.routeKey)
        }
        if state.pendingReset {
            store.set(true, forKey: Self.pendingResetKey)
        } else {
            store.removeObject(forKey: Self.pendingResetKey)
        }
    }
}
