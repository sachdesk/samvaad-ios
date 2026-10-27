import XCTest
@testable import Samvaad

final class WidgetOriginTests: XCTestCase {
    func testBareHostBecomesHttps() {
        let origin = WidgetOrigin.parse("yobruh.samvaads.com", allowLocal: false)
        XCTAssertEqual(origin, WidgetOrigin(scheme: "https", host: "yobruh.samvaads.com", port: nil))
    }

    func testHttpsHostIsLowerCasedAndTrailingSlashDropped() {
        let origin = WidgetOrigin.parse("  https://Yobruh.Samvaads.com/ ", allowLocal: false)
        XCTAssertEqual(origin, WidgetOrigin(scheme: "https", host: "yobruh.samvaads.com", port: nil))
    }

    func testHttpsWithPort() {
        let origin = WidgetOrigin.parse("https://chat.yobruh.in:8443", allowLocal: false)
        XCTAssertEqual(origin, WidgetOrigin(scheme: "https", host: "chat.yobruh.in", port: 8443))
    }

    func testPlainHttpIsRejectedForPublicHosts() {
        XCTAssertNil(WidgetOrigin.parse("http://yobruh.samvaads.com", allowLocal: false))
        XCTAssertNil(WidgetOrigin.parse("http://yobruh.samvaads.com", allowLocal: true))
    }

    func testLocalHttpOnlyWhenAllowed() {
        XCTAssertNil(WidgetOrigin.parse("http://localhost:5173", allowLocal: false))
        XCTAssertEqual(
            WidgetOrigin.parse("http://localhost:5173", allowLocal: true),
            WidgetOrigin(scheme: "http", host: "localhost", port: 5173)
        )
        XCTAssertEqual(
            WidgetOrigin.parse("http://10.0.2.2:5173", allowLocal: true),
            WidgetOrigin(scheme: "http", host: "10.0.2.2", port: 5173)
        )
        XCTAssertEqual(
            WidgetOrigin.parse("http://127.0.0.1:5173", allowLocal: true),
            WidgetOrigin(scheme: "http", host: "127.0.0.1", port: 5173)
        )
    }

    func testRejectsJunk() {
        XCTAssertNil(WidgetOrigin.parse("", allowLocal: true))
        XCTAssertNil(WidgetOrigin.parse("   ", allowLocal: true))
        XCTAssertNil(WidgetOrigin.parse("ftp://yobruh.samvaads.com", allowLocal: true))
        XCTAssertNil(WidgetOrigin.parse("yobruh.samvaads.com/embed/widget", allowLocal: true))
        XCTAssertNil(WidgetOrigin.parse("https://yobruh.samvaads.com?x=1", allowLocal: true))
        XCTAssertNil(WidgetOrigin.parse("https://user:pw@yobruh.samvaads.com", allowLocal: true))
    }

    func testDefaultHost() {
        XCTAssertEqual(WidgetOrigin.defaultHost(forTenant: "Yobruh"), "yobruh.samvaads.com")
    }

    func testMatchesSameOriginOnly() {
        let origin = WidgetOrigin(scheme: "https", host: "yobruh.samvaads.com", port: nil)
        XCTAssertTrue(origin.matches(URL(string: "https://yobruh.samvaads.com/embed/widget?x=1")!))
        XCTAssertTrue(origin.matches(URL(string: "https://YOBRUH.samvaads.com:443/")!))
        XCTAssertFalse(origin.matches(URL(string: "http://yobruh.samvaads.com/")!))
        XCTAssertFalse(origin.matches(URL(string: "https://yobruh.samvaads.com:8443/")!))
        XCTAssertFalse(origin.matches(URL(string: "https://evil.yobruh.samvaads.com/")!))
        XCTAssertFalse(origin.matches(URL(string: "https://yobruh.samvaads.com.evil.in/")!))
    }

    func testMatchesSecurityOriginWithZeroPort() {
        let origin = WidgetOrigin(scheme: "https", host: "yobruh.samvaads.com", port: nil)
        XCTAssertTrue(origin.matches(scheme: "https", host: "yobruh.samvaads.com", port: 0))
        XCTAssertTrue(origin.matches(scheme: "https", host: "yobruh.samvaads.com", port: 443))
        XCTAssertFalse(origin.matches(scheme: "https", host: "yobruh.samvaads.com", port: 8443))

        let local = WidgetOrigin(scheme: "http", host: "localhost", port: 5173)
        XCTAssertTrue(local.matches(scheme: "http", host: "localhost", port: 5173))
        XCTAssertFalse(local.matches(scheme: "http", host: "localhost", port: 0))
    }
}

final class WidgetURLBuilderTests: XCTestCase {
    func testBuildsAppModeURL() {
        let origin = WidgetOrigin(scheme: "https", host: "yobruh.samvaads.com", port: nil)
        let url = WidgetURLBuilder.url(origin: origin, tenantId: "yobruh", theme: "auto")
        XCTAssertEqual(
            url?.absoluteString,
            "https://yobruh.samvaads.com/embed/widget?tenant_id=yobruh&mode=app&theme=auto"
        )
    }

    func testKeepsLocalPort() {
        let origin = WidgetOrigin(scheme: "http", host: "localhost", port: 5173)
        let url = WidgetURLBuilder.url(origin: origin, tenantId: "t1", theme: "dark")
        XCTAssertEqual(url?.absoluteString, "http://localhost:5173/embed/widget?tenant_id=t1&mode=app&theme=dark")
    }

    func testEncodesTenantId() {
        let origin = WidgetOrigin(scheme: "https", host: "yobruh.samvaads.com", port: nil)
        let url = WidgetURLBuilder.url(origin: origin, tenantId: "a b&c=d+e", theme: "light")
        XCTAssertEqual(
            url?.absoluteString,
            "https://yobruh.samvaads.com/embed/widget?tenant_id=a%20b%26c%3Dd%2Be&mode=app&theme=light"
        )
    }

    func testThemeParameter() {
        XCTAssertEqual(WidgetURLBuilder.themeParameter(.light, appIsDark: true), "light")
        XCTAssertEqual(WidgetURLBuilder.themeParameter(.dark, appIsDark: false), "dark")
        XCTAssertEqual(WidgetURLBuilder.themeParameter(.auto, appIsDark: true), "dark")
        XCTAssertEqual(WidgetURLBuilder.themeParameter(.auto, appIsDark: false), "light")
        XCTAssertEqual(WidgetURLBuilder.themeParameter(.auto, appIsDark: nil), "auto")
    }
}

final class NavigationPolicyTests: XCTestCase {
    private let origin = WidgetOrigin(scheme: "https", host: "yobruh.samvaads.com", port: nil)

    private func decide(_ text: String?, mainFrame: Bool = true) -> NavigationDecision {
        return NavigationPolicy.decide(url: text.flatMap { URL(string: $0) }, isMainFrame: mainFrame, origin: origin)
    }

    func testOwnPageLoadsInside() {
        XCTAssertEqual(decide("https://yobruh.samvaads.com/embed/widget?tenant_id=yobruh&mode=app"), .allow)
        XCTAssertEqual(decide("about:blank"), .allow)
    }

    func testOtherWebLinksOpenInBrowser() {
        let url = URL(string: "https://yobruh.in/orders/YB-1042")!
        XCTAssertEqual(decide(url.absoluteString), .openOutside(.browser(url)))
        let http = URL(string: "http://yobruh.samvaads.com/")!
        XCTAssertEqual(decide(http.absoluteString), .openOutside(.browser(http)))
    }

    func testMailAndPhoneGoToTheSystem() {
        let mail = URL(string: "mailto:help@yobruh.in")!
        XCTAssertEqual(decide(mail.absoluteString), .openOutside(.system(mail)))
        let tel = URL(string: "tel:+911234567890")!
        XCTAssertEqual(decide(tel.absoluteString), .openOutside(.system(tel)))
    }

    func testUnknownSchemesAreDropped() {
        XCTAssertEqual(decide("javascript:alert(1)"), .cancel)
        XCTAssertEqual(decide("file:///etc/hosts"), .cancel)
        XCTAssertEqual(decide("yobruhshop://orders"), .cancel)
        XCTAssertEqual(decide(nil), .cancel)
    }

    func testSubFramesAreLeftAlone() {
        XCTAssertEqual(decide("https://www.youtube.com/embed/x", mainFrame: false), .allow)
        XCTAssertEqual(decide("javascript:alert(1)", mainFrame: false), .cancel)
    }

    func testExternalTargetClassification() {
        let web = URL(string: "https://yobruh.in")!
        XCTAssertEqual(ExternalTarget.classify(web), .browser(web))
        let sms = URL(string: "sms:12345")!
        XCTAssertEqual(ExternalTarget.classify(sms), .system(sms))
        XCTAssertEqual(ExternalTarget.classify(URL(string: "data:text/html,hi")!), .ignored)
    }
}
