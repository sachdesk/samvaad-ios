import Foundation

/// Light or dark look for the chat screen.
public enum SamvaadTheme: String, Sendable, CaseIterable {
    /// Follow the app: the chat uses the light/dark style of the screen it opens from.
    case auto
    case light
    case dark
}
