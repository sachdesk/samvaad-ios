import SafariServices
import UIKit
import WebKit

/// Forwards script messages to a handler it does not retain, so the content controller
/// (owned by the web view, owned by the chat screen) does not keep the chat screen alive.
final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?

    init(target: WKScriptMessageHandler) {
        self.target = target
        super.init()
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}

/// The full-screen chat: Samvaad's widget page in a web view, plus the bridge.
final class SamvaadChatViewController: UIViewController {
    static let handlerName = "samvaad"

    private let pageURL: URL
    private let origin: WidgetOrigin
    private var queue = BridgeQueue()
    private var webView: WKWebView?

    private let statusView = UIView()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let statusLabel = UILabel()
    private let retryButton = UIButton(type: .system)
    private let closeButton: UIButton = {
        var config = UIButton.Configuration.gray()
        config.title = "Close"
        config.cornerStyle = .capsule
        return UIButton(configuration: config, primaryAction: nil)
    }()

    /// True once the current page has said `ready` (and until it reloads).
    var isPageReady: Bool { queue.isReady }

    init(url: URL, origin: WidgetOrigin, theme: SamvaadTheme) {
        self.pageURL = url
        self.origin = origin
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
        switch theme {
        case .light: overrideUserInterfaceStyle = .light
        case .dark: overrideUserInterfaceStyle = .dark
        case .auto: overrideUserInterfaceStyle = .unspecified
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        let configuration = WKWebViewConfiguration()
        // Persistent store: the chat session token lives in the page's localStorage.
        configuration.websiteDataStore = WKWebsiteDataStore.default()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.allowsInlineMediaPlayback = true
        let contentController = WKUserContentController()
        contentController.add(WeakScriptMessageHandler(target: self), name: Self.handlerName)
        configuration.userContentController = contentController

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = false
        webView.backgroundColor = .systemBackground
        webView.scrollView.backgroundColor = .systemBackground
        if #available(iOS 16.4, *) {
            webView.isInspectable = WidgetOrigin.isDebugBuild
        }
        view.addSubview(webView)

        // The page has no notch handling: keep it inside the safe area.
        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: guide.topAnchor),
            webView.bottomAnchor.constraint(equalTo: guide.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: guide.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: guide.trailingAnchor),
        ])
        self.webView = webView

        setUpStatusView()
        load()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed {
            Samvaad.chatDidClose(self)
        }
    }

    private func load() {
        showStatus(.loading)
        queue.pageWillLoad()
        webView?.load(URLRequest(url: pageURL))
    }

    // MARK: - App → page

    /// Sends now if the page is ready, else queues until `ready`.
    func send(_ message: OutgoingMessage) {
        deliver(queue.send(message))
    }

    /// Sends only if the page is ready. Used for state (identify, pushToken, reset) that a
    /// page which is still loading gets anyway with its page-load messages.
    func sendIfReady(_ message: OutgoingMessage) {
        guard queue.isReady else { return }
        deliver([message])
    }

    private func deliver(_ messages: [OutgoingMessage]) {
        guard let webView = webView else { return }
        for message in messages {
            guard let script = BridgeScript.script(for: message) else {
                SamvaadLog.logger.error("bridge: could not encode \(message.type, privacy: .public)")
                continue
            }
            webView.evaluateJavaScript(script, completionHandler: nil)
        }
    }

    // MARK: - Page → app

    private func handle(_ message: WKScriptMessage) {
        guard message.name == Self.handlerName, message.frameInfo.isMainFrame else { return }
        let security = message.frameInfo.securityOrigin
        guard origin.matches(scheme: security.`protocol`, host: security.host, port: security.port) else { return }
        guard let incoming = IncomingMessage.parse(message.body) else { return }

        switch incoming {
        case .ready:
            // `enabled: false` means the tenant's widget is off; the page says so itself.
            showStatus(.ready)
            let pageLoadMessages = Samvaad.takePageLoadMessages()
            deliver(queue.ready(pageLoadMessages: pageLoadMessages))
        case .close:
            close()
        case .unread(let count):
            Samvaad.updateUnread(count)
        case .navigate(let url):
            openOutside(ExternalTarget.classify(url))
        case .visibility:
            break
        }
    }

    private func close() {
        Samvaad.chatDidClose(self)
        if let presenting = presentingViewController {
            presenting.dismiss(animated: true)
        } else {
            dismiss(animated: true)
        }
    }

    // MARK: - Links outside the chat

    private func openOutside(_ target: ExternalTarget) {
        switch target {
        case .browser(let url):
            let safari = SFSafariViewController(url: url)
            let host = Samvaad.topMost(from: self)
            host.present(safari, animated: true)
        case .system(let url):
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        case .ignored:
            break
        }
    }

    // MARK: - Loading and error states

    private enum Status {
        /// Spinner and a native Close button.
        case loading
        /// Error message, Try again and Close.
        case failed
        /// The document loaded but has not said `ready` yet: show it, keep Close.
        case pageShown
        /// The page is running and has its own close control.
        case ready
    }

    private func setUpStatusView() {
        statusView.translatesAutoresizingMaskIntoConstraints = false
        statusView.backgroundColor = .systemBackground
        view.addSubview(statusView)

        spinner.hidesWhenStopped = true

        statusLabel.text = "Couldn't load the chat. Check your connection and try again."
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.font = UIFont.preferredFont(forTextStyle: .body)
        statusLabel.adjustsFontForContentSizeCategory = true
        statusLabel.textColor = .secondaryLabel

        retryButton.setTitle("Try again", for: .normal)
        retryButton.addTarget(self, action: #selector(retryTapped), for: .touchUpInside)

        closeButton.setTitle("Close", for: .normal)
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        closeButton.translatesAutoresizingMaskIntoConstraints = false

        let stack = UIStackView(arrangedSubviews: [spinner, statusLabel, retryButton])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        statusView.addSubview(stack)
        // On the root view, above the web view, so it stays usable on a page that never
        // says `ready` (a server error page has no close control of its own).
        view.addSubview(closeButton)

        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            statusView.topAnchor.constraint(equalTo: view.topAnchor),
            statusView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            statusView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            statusView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            closeButton.topAnchor.constraint(equalTo: guide.topAnchor, constant: 8),
            closeButton.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -16),

            stack.centerYAnchor.constraint(equalTo: guide.centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -32),
        ])
    }

    private func showStatus(_ status: Status) {
        switch status {
        case .loading:
            statusView.isHidden = false
            spinner.startAnimating()
            statusLabel.isHidden = true
            retryButton.isHidden = true
            closeButton.isHidden = false
        case .failed:
            statusView.isHidden = false
            spinner.stopAnimating()
            statusLabel.isHidden = false
            retryButton.isHidden = false
            closeButton.isHidden = false
        case .pageShown:
            spinner.stopAnimating()
            statusView.isHidden = true
            closeButton.isHidden = false
        case .ready:
            spinner.stopAnimating()
            statusView.isHidden = true
            closeButton.isHidden = true
        }
    }

    @objc private func retryTapped() {
        load()
    }

    @objc private func closeTapped() {
        close()
    }

    private static func isCancellation(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled { return true }
        // WebKitErrorFrameLoadInterruptedByPolicyChange: a link we opened outside instead.
        if nsError.domain == "WebKitErrorDomain" && nsError.code == 102 { return true }
        return false
    }
}

// MARK: - WKScriptMessageHandler

extension SamvaadChatViewController: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        handle(message)
    }
}

// MARK: - WKNavigationDelegate

extension SamvaadChatViewController: WKNavigationDelegate {
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        // No target frame means a new window (target=_blank): treat it like the main frame.
        let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? true
        switch NavigationPolicy.decide(url: navigationAction.request.url, isMainFrame: isMainFrame, origin: origin) {
        case .allow:
            decisionHandler(.allow)
        case .openOutside(let target):
            decisionHandler(.cancel)
            openOutside(target)
        case .cancel:
            decisionHandler(.cancel)
        }
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        // A new document: hold app → page messages until it says `ready`.
        queue.pageWillLoad()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // The page normally hides the spinner with `ready`. If it has not yet, show the
        // page anyway and keep the native Close button until it does.
        if !queue.isReady { showStatus(.pageShown) }
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
    ) {
        if navigationResponse.isForMainFrame,
           let http = navigationResponse.response as? HTTPURLResponse,
           http.statusCode >= 400 {
            decisionHandler(.cancel)
            showStatus(.failed)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        guard !Self.isCancellation(error) else { return }
        showStatus(.failed)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard !Self.isCancellation(error), !queue.isReady else { return }
        showStatus(.failed)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        load()
    }
}

// MARK: - WKUIDelegate

extension SamvaadChatViewController: WKUIDelegate {
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        // window.open / target=_blank: chat pages load in place, everything else outside.
        if let url = navigationAction.request.url {
            if origin.matches(url) {
                webView.load(navigationAction.request)
            } else {
                openOutside(ExternalTarget.classify(url))
            }
        }
        return nil
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping () -> Void
    ) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
        presentPanel(alert, orElse: completionHandler)
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (Bool) -> Void
    ) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(false) })
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(true) })
        presentPanel(alert, orElse: { completionHandler(false) })
    }

    /// Shows a JS panel; WebKit requires the completion handler to run, so call the
    /// fallback when the panel cannot be shown.
    private func presentPanel(_ alert: UIAlertController, orElse fallback: @escaping () -> Void) {
        guard viewIfLoaded?.window != nil else {
            fallback()
            return
        }
        Samvaad.topMost(from: self).present(alert, animated: true)
    }
}
