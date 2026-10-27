import XCTest
@testable import Samvaad

final class OutgoingMessageTests: XCTestCase {
    func testIdentifyJSON() {
        let identity = Identity(email: "asha@yobruh.in", name: "Asha", userHash: "abc123")
        XCTAssertEqual(
            BridgeScript.json(for: .identify(identity)),
            #"{"identity":{"email":"asha@yobruh.in","name":"Asha","user_hash":"abc123"},"type":"identify"}"#
        )
    }

    func testIdentifyWithoutNameLeavesItOut() {
        let identity = Identity(email: "asha@yobruh.in", name: nil, userHash: "abc123")
        XCTAssertEqual(
            BridgeScript.json(for: .identify(identity)),
            #"{"identity":{"email":"asha@yobruh.in","user_hash":"abc123"},"type":"identify"}"#
        )
    }

    func testResetJSON() {
        XCTAssertEqual(BridgeScript.json(for: .reset), #"{"type":"reset"}"#)
    }

    func testMessageEscapesQuotesAndBackslashes() {
        let json = BridgeScript.json(for: .message(text: #"Order "YB-1042" \ late"#))
        XCTAssertEqual(json, #"{"text":"Order \"YB-1042\" \\ late","type":"message"}"#)
    }

    func testPushTokenFieldsAreTopLevel() {
        let push = PushToken(token: "00ab", route: .apns)
        XCTAssertEqual(
            BridgeScript.json(for: .pushToken(push, appId: "in.yobruh.shop")),
            #"{"app_id":"in.yobruh.shop","platform":"ios","route":"apns","token":"00ab","type":"pushToken"}"#
        )
    }

    func testPushTokenWithoutAppId() {
        let push = PushToken(token: "fcm-token", route: .fcm)
        XCTAssertEqual(
            BridgeScript.json(for: .pushToken(push, appId: nil)),
            #"{"platform":"ios","route":"fcm","token":"fcm-token","type":"pushToken"}"#
        )
        XCTAssertEqual(
            BridgeScript.json(for: .pushToken(push, appId: "")),
            #"{"platform":"ios","route":"fcm","token":"fcm-token","type":"pushToken"}"#
        )
    }

    func testLineAndParagraphSeparatorsAreEscaped() {
        let script = BridgeScript.script(for: .message(text: "one\u{2028}two\u{2029}three"))
        XCTAssertNotNil(script)
        XCTAssertFalse(script!.contains("\u{2028}"))
        XCTAssertFalse(script!.contains("\u{2029}"))
        XCTAssertTrue(script!.contains(#"one two three"#))
    }

    func testNewlinesAndNonASCIIStayValid() {
        let json = BridgeScript.json(for: .message(text: "नमस्ते\nline"))
        XCTAssertEqual(json, #"{"text":"नमस्ते\nline","type":"message"}"#)
    }

    func testScriptCallsTheBridge() {
        XCTAssertEqual(
            BridgeScript.script(for: .reset),
            #"window.SamvaadBridge && window.SamvaadBridge.receive({"type":"reset"});"#
        )
    }
}

final class IncomingMessageTests: XCTestCase {
    func testReady() {
        let body: [String: Any] = ["v": 1, "type": "ready", "enabled": true]
        XCTAssertEqual(IncomingMessage.parse(body), .ready(enabled: true))
        let off: [String: Any] = ["v": 1, "type": "ready", "enabled": false]
        XCTAssertEqual(IncomingMessage.parse(off), .ready(enabled: false))
        let missing: [String: Any] = ["v": 1, "type": "ready"]
        XCTAssertEqual(IncomingMessage.parse(missing), .ready(enabled: true))
    }

    func testReadyFromNSNumbers() {
        // What WebKit hands over for `{ v: 1, type: 'ready', enabled: false }`.
        let body: NSDictionary = ["v": NSNumber(value: 1), "type": "ready", "enabled": NSNumber(value: false)]
        XCTAssertEqual(IncomingMessage.parse(body), .ready(enabled: false))
    }

    func testClose() {
        let body: [String: Any] = ["v": 1, "type": "close"]
        XCTAssertEqual(IncomingMessage.parse(body), .close)
    }

    func testUnread() {
        let body: [String: Any] = ["v": 1, "type": "unread", "count": 3]
        XCTAssertEqual(IncomingMessage.parse(body), .unread(count: 3))
        let number: [String: Any] = ["v": NSNumber(value: 1), "type": "unread", "count": NSNumber(value: 7)]
        XCTAssertEqual(IncomingMessage.parse(number), .unread(count: 7))
        let double: [String: Any] = ["v": 1, "type": "unread", "count": 2.0]
        XCTAssertEqual(IncomingMessage.parse(double), .unread(count: 2))
        let negative: [String: Any] = ["v": 1, "type": "unread", "count": -4]
        XCTAssertEqual(IncomingMessage.parse(negative), .unread(count: 0))
    }

    func testUnreadRejectsBadCounts() {
        let fraction: [String: Any] = ["v": 1, "type": "unread", "count": 2.5]
        XCTAssertNil(IncomingMessage.parse(fraction))
        let text: [String: Any] = ["v": 1, "type": "unread", "count": "3"]
        XCTAssertNil(IncomingMessage.parse(text))
        let missing: [String: Any] = ["v": 1, "type": "unread"]
        XCTAssertNil(IncomingMessage.parse(missing))
    }

    func testNavigate() {
        let body: [String: Any] = ["v": 1, "type": "navigate", "url": "https://yobruh.in/orders/YB-1042"]
        XCTAssertEqual(IncomingMessage.parse(body), .navigate(URL(string: "https://yobruh.in/orders/YB-1042")!))
        let bad: [String: Any] = ["v": 1, "type": "navigate", "url": "not a url"]
        XCTAssertNil(IncomingMessage.parse(bad))
        let missing: [String: Any] = ["v": 1, "type": "navigate"]
        XCTAssertNil(IncomingMessage.parse(missing))
    }

    func testVisibilityIsParsed() {
        let body: [String: Any] = ["v": 1, "type": "visibility", "visible": false]
        XCTAssertEqual(IncomingMessage.parse(body), .visibility(visible: false))
    }

    func testRequiresVersionOne() {
        let missing: [String: Any] = ["type": "close"]
        XCTAssertNil(IncomingMessage.parse(missing))
        let future: [String: Any] = ["v": 2, "type": "close"]
        XCTAssertNil(IncomingMessage.parse(future))
    }

    func testUnknownOrMalformed() {
        let unknown: [String: Any] = ["v": 1, "type": "explode"]
        XCTAssertNil(IncomingMessage.parse(unknown))
        XCTAssertNil(IncomingMessage.parse(42))
        XCTAssertNil(IncomingMessage.parse("not json"))
        XCTAssertNil(IncomingMessage.parse([1, 2, 3]))
    }

    func testJSONStringBody() {
        XCTAssertEqual(IncomingMessage.parse(#"{"v":1,"type":"unread","count":5}"#), .unread(count: 5))
    }
}
