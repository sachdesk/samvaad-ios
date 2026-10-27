import Foundation

/// Where the widget page is served from: scheme, host and optional port.
struct WidgetOrigin: Equatable {
    let scheme: String
    let host: String
    let port: Int?

    /// Plain-http hosts that are allowed in debug builds only, for local testing.
    static let localHosts: Set<String> = ["localhost", "127.0.0.1", "10.0.2.2"]

    /// True in debug builds of the SDK (local http hosts are allowed).
    static var isDebugBuild: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    /// Reads `yobruh.samvaads.com`, `https://yobruh.samvaads.com` or, when `allowLocal`
    /// is true, `http://localhost:5173`. Paths, queries and credentials are not allowed.
    static func parse(_ raw: String, allowLocal: Bool) -> WidgetOrigin? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while text.hasSuffix("/") { text.removeLast() }
        guard !text.isEmpty else { return nil }
        if !text.contains("://") { text = "https://" + text }
        guard let comps = URLComponents(string: text),
              let scheme = comps.scheme?.lowercased(),
              let host = comps.host?.lowercased(),
              !host.isEmpty,
              comps.user == nil,
              comps.password == nil,
              comps.path.isEmpty,
              comps.query == nil,
              comps.fragment == nil
        else { return nil }
        if let port = comps.port, !(1...65535).contains(port) { return nil }
        switch scheme {
        case "https":
            break
        case "http":
            guard allowLocal, localHosts.contains(host) else { return nil }
        default:
            return nil
        }
        return WidgetOrigin(scheme: scheme, host: host, port: comps.port)
    }

    /// True when `url` is on this exact origin (scheme, host and port).
    func matches(_ url: URL) -> Bool {
        guard let urlScheme = url.scheme, let urlHost = url.host else { return false }
        return matches(scheme: urlScheme, host: urlHost, port: url.port)
    }

    /// Same check for a web security origin (`port` 0 or nil means the scheme's default).
    func matches(scheme otherScheme: String, host otherHost: String, port otherPort: Int?) -> Bool {
        let s = otherScheme.lowercased()
        let normalizedPort: Int? = (otherPort == 0) ? nil : otherPort
        return s == scheme
            && otherHost.lowercased() == host
            && Self.effectivePort(normalizedPort, scheme: s) == Self.effectivePort(port, scheme: scheme)
    }

    private static func effectivePort(_ port: Int?, scheme: String) -> Int {
        if let port = port { return port }
        return scheme == "http" ? 80 : 443
    }
}

/// Builds `https://<host>/embed/widget?tenant_id=<id>&mode=app&theme=<theme>`.
enum WidgetURLBuilder {
    static let path = "/embed/widget"

    static func url(origin: WidgetOrigin, tenantId: String, theme: String) -> URL? {
        var comps = URLComponents()
        comps.scheme = origin.scheme
        comps.host = origin.host
        comps.port = origin.port
        comps.path = path
        comps.percentEncodedQuery = [
            "tenant_id=\(encode(tenantId))",
            "mode=app",
            "theme=\(encode(theme))",
        ].joined(separator: "&")
        return comps.url
    }

    /// The `theme` query value: the explicit setting, or the app's current style for `.auto`
    /// (`appIsDark` nil means the style is not known, and the page decides).
    static func themeParameter(_ theme: SamvaadTheme, appIsDark: Bool?) -> String {
        switch theme {
        case .light:
            return "light"
        case .dark:
            return "dark"
        case .auto:
            guard let appIsDark = appIsDark else { return "auto" }
            return appIsDark ? "dark" : "light"
        }
    }

    /// RFC 3986 unreserved characters (ASCII only); everything else is percent-encoded.
    private static let queryValueAllowed = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )

    private static func encode(_ value: String) -> String {
        return value.addingPercentEncoding(withAllowedCharacters: queryValueAllowed) ?? ""
    }
}

/// Where a link that is not part of the chat page should go.
enum ExternalTarget: Equatable {
    /// http(s): shown in `SFSafariViewController`.
    case browser(URL)
    /// mailto / tel / sms: handed to the system.
    case system(URL)
    /// Anything else (javascript:, file:, custom schemes): dropped.
    case ignored

    static let systemSchemes: Set<String> = ["mailto", "tel", "sms"]

    static func classify(_ url: URL) -> ExternalTarget {
        let scheme = url.scheme?.lowercased() ?? ""
        if scheme == "http" || scheme == "https" {
            return url.host?.isEmpty == false ? .browser(url) : .ignored
        }
        if systemSchemes.contains(scheme) { return .system(url) }
        return .ignored
    }
}

/// What the web view does with one navigation.
enum NavigationDecision: Equatable {
    case allow
    case openOutside(ExternalTarget)
    case cancel
}

enum NavigationPolicy {
    /// Only the configured origin loads in the chat's main frame; other links open
    /// outside the app's chat screen. Sub-frames (embeds inside the page) are left alone.
    static func decide(url: URL?, isMainFrame: Bool, origin: WidgetOrigin) -> NavigationDecision {
        guard let url = url else { return .cancel }
        let scheme = url.scheme?.lowercased() ?? ""
        if scheme == "about" { return .allow }
        if origin.matches(url) { return .allow }
        if !isMainFrame {
            if ["http", "https", "blob", "data"].contains(scheme) { return .allow }
            return .cancel
        }
        let target = ExternalTarget.classify(url)
        if target == .ignored { return .cancel }
        return .openOutside(target)
    }
}
