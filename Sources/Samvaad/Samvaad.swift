import UIKit

/// Samvaad chat for iOS apps.
///
/// The chat itself is Samvaad's website-widget page, shown full screen in a web view.
/// Call everything on the main thread.
@MainActor
public enum Samvaad {
    /// SDK version.
    public static let version = "0.1.0"

    /// Light or dark chat. `.auto` (the default) follows the screen the chat opens from.
    public static var theme: SamvaadTheme = .auto

    /// Called on the main thread whenever the unread count changes.
    public static var onUnreadChange: ((Int) -> Void)?

    /// The last unread count the chat reported.
    public private(set) static var unreadCount: Int = 0

    // MARK: - Setup

    /// Sets the workspace. Call once, early (for example in `application(_:didFinishLaunchingWithOptions:)`).
    ///
    /// - Parameters:
    ///   - tenantId: Your Samvaad tenant ID.
    ///   - host: The host serving your chat, e.g. `yobruh.samvaads.com`. Defaults to
    ///     `<tenantId>.samvaads.com`. Must be https; debug builds also accept
    ///     `http://localhost:<port>` for local testing.
    public static func configure(tenantId: String, host: String? = nil) {
        loadStateIfNeeded()
        let id = tenantId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else {
            SamvaadLog.logger.error("configure: tenantId is empty")
            return
        }
        let givenHost = host?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let rawHost = givenHost.isEmpty ? WidgetOrigin.defaultHost(forTenant: id) : givenHost
        guard let origin = WidgetOrigin.parse(rawHost, allowLocal: WidgetOrigin.isDebugBuild) else {
            SamvaadLog.logger.error("configure: host is not a valid https host: \(rawHost, privacy: .public)")
            return
        }
        configuration = Configuration(tenantId: id, origin: origin)
    }

    // MARK: - Identity

    /// Tells the chat who the signed-in customer is.
    ///
    /// `userHash` is HMAC-SHA256 of the lower-cased email, keyed with your identity secret,
    /// and must be computed on your backend. Never put the identity secret in the app.
    /// The identity is kept in memory: call this on each launch once your user is signed in.
    public static func identify(email: String, name: String? = nil, userHash: String) {
        loadStateIfNeeded()
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanHash = userHash.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanEmail.isEmpty, !cleanHash.isEmpty else {
            SamvaadLog.logger.error("identify: email and userHash are required")
            return
        }
        let cleanName = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let identity = Identity(
            email: cleanEmail,
            name: (cleanName?.isEmpty ?? true) ? nil : cleanName,
            userHash: cleanHash
        )
        guard identity != state.identity else { return }
        state.identity = identity
        // A page that is not ready yet gets it with the other page-load messages.
        activeChat?.sendIfReady(.identify(identity))
    }

    /// Signs the customer out of the chat. The open chat (or the next one) starts over.
    /// The device push token is kept.
    public static func logout() {
        loadStateIfNeeded()
        let chat = activeChat
        let sendNow = state.logout(pageReady: chat?.isPageReady ?? false)
        saveState()
        if sendNow { chat?.sendIfReady(.reset) }
        updateUnread(0)
    }

    // MARK: - Chat screen

    /// Opens the chat full screen.
    ///
    /// - Parameters:
    ///   - presenter: The view controller to present from. Defaults to the top-most view
    ///     controller of the key window.
    ///   - message: Optional text to prefill in the message box (not sent).
    public static func present(from presenter: UIViewController? = nil, message: String? = nil) {
        loadStateIfNeeded()
        guard let configuration = configuration else {
            SamvaadLog.logger.error("present: call Samvaad.configure(tenantId:host:) first")
            return
        }
        let trimmed = message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let prefill: OutgoingMessage? = trimmed.isEmpty ? nil : .message(text: trimmed)

        if let chat = activeChat, chat.viewIfLoaded?.window != nil {
            if let prefill = prefill { chat.send(prefill) }
            return
        }

        let candidate: UIViewController? = presenter.map { topMost(from: $0) } ?? topViewController()
        guard let base = candidate else {
            SamvaadLog.logger.error("present: no view controller to present from")
            return
        }

        let appIsDark: Bool?
        switch base.traitCollection.userInterfaceStyle {
        case .dark: appIsDark = true
        case .light: appIsDark = false
        default: appIsDark = nil
        }
        let themeValue = WidgetURLBuilder.themeParameter(theme, appIsDark: appIsDark)
        guard let url = WidgetURLBuilder.url(
            origin: configuration.origin,
            tenantId: configuration.tenantId,
            theme: themeValue
        ) else {
            SamvaadLog.logger.error("present: could not build the chat URL")
            return
        }

        let chat = SamvaadChatViewController(url: url, origin: configuration.origin, theme: theme)
        if let prefill = prefill { chat.send(prefill) }
        activeChat = chat
        base.present(chat, animated: true)
    }

    // MARK: - Push

    /// Registers the APNs device token (from `application(_:didRegisterForRemoteNotificationsWithDeviceToken:)`).
    public static func setPushToken(_ deviceToken: Data) {
        guard !deviceToken.isEmpty else { return }
        updatePushToken(PushToken(token: PushTokenEncoding.hex(deviceToken), route: .apns))
    }

    /// Registers a Firebase Cloud Messaging token, for apps that receive push through Firebase.
    public static func setPushToken(fcmToken: String) {
        let token = fcmToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return }
        updatePushToken(PushToken(token: token, route: .fcm))
    }

    /// Opens the chat for a Samvaad notification.
    ///
    /// - Returns: `false` when the notification is not from Samvaad (your app handles it);
    ///   `true` when it is, and the chat is being opened.
    @discardableResult
    public static func handlePush(_ userInfo: [AnyHashable: Any], from presenter: UIViewController? = nil) -> Bool {
        guard PushPayload.isSamvaad(userInfo) else { return false }
        if let chat = activeChat, chat.viewIfLoaded?.window != nil { return true }
        if presenter != nil || topViewController() != nil {
            present(from: presenter)
        } else {
            // Launched from the notification: the window may not be on screen yet.
            Task { @MainActor in
                present(from: nil)
            }
        }
        return true
    }

    // MARK: - Internal

    struct Configuration {
        let tenantId: String
        let origin: WidgetOrigin
    }

    private(set) static var configuration: Configuration?
    static var state = BridgeState()
    static var stateStore = BridgeStateStore(store: UserDefaults.standard)
    private static var didLoadState = false
    weak static var activeChat: SamvaadChatViewController?

    private static func loadStateIfNeeded() {
        guard !didLoadState else { return }
        didLoadState = true
        stateStore.load(into: &state)
        state.appId = Bundle.main.bundleIdentifier
    }

    private static func saveState() {
        stateStore.save(state)
    }

    private static func updatePushToken(_ push: PushToken) {
        loadStateIfNeeded()
        guard state.pushToken != push else { return }
        state.pushToken = push
        saveState()
        activeChat?.sendIfReady(.pushToken(push, appId: state.appId))
    }

    /// Called by the chat screen after `ready`: reset (if pending), identify, pushToken.
    static func takePageLoadMessages() -> [OutgoingMessage] {
        loadStateIfNeeded()
        let messages = state.takePageLoadMessages()
        saveState()
        return messages
    }

    static func updateUnread(_ count: Int) {
        let value = max(0, count)
        guard value != unreadCount else { return }
        unreadCount = value
        onUnreadChange?(value)
    }

    static func chatDidClose(_ chat: SamvaadChatViewController) {
        if activeChat === chat { activeChat = nil }
    }

    // MARK: - Finding a presenter

    static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let ordered = scenes.filter { $0.activationState == .foregroundActive }
            + scenes.filter { $0.activationState != .foregroundActive }
        let windows = ordered.flatMap { $0.windows }
        let window = windows.first(where: { $0.isKeyWindow })
            ?? windows.first(where: { !$0.isHidden && $0.rootViewController != nil })
        guard let root = window?.rootViewController else { return nil }
        return topMost(from: root)
    }

    static func topMost(from controller: UIViewController) -> UIViewController {
        var current = controller
        // Bounded walk, so an unusual container can never loop forever.
        for _ in 0..<32 {
            if let presented = current.presentedViewController, !presented.isBeingDismissed {
                current = presented
            } else if let nav = current as? UINavigationController, let top = nav.topViewController {
                current = top
            } else if let tabs = current as? UITabBarController, let selected = tabs.selectedViewController {
                current = selected
            } else {
                break
            }
        }
        return current
    }
}
