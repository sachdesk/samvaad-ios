import XCTest
@testable import Samvaad

private final class MemoryStore: KeyValueStore {
    var values: [String: Any] = [:]

    func string(forKey key: String) -> String? { values[key] as? String }
    func bool(forKey key: String) -> Bool { (values[key] as? Bool) ?? false }
    func set(_ value: Any?, forKey key: String) { values[key] = value }
    func removeObject(forKey key: String) { values[key] = nil }
}

final class BridgeStateTests: XCTestCase {
    private let asha = Identity(email: "asha@yobruh.in", name: "Asha", userHash: "abc123")
    private let apns = PushToken(token: "00ab", route: .apns)

    func testNothingToSendForAFreshState() {
        var state = BridgeState()
        XCTAssertEqual(state.takePageLoadMessages(), [])
    }

    func testPageLoadSendsIdentifyThenPushTokenEveryTime() {
        var state = BridgeState(identity: asha, pushToken: apns, pendingReset: false, appId: "in.yobruh.shop")
        let expected: [OutgoingMessage] = [.identify(asha), .pushToken(apns, appId: "in.yobruh.shop")]
        XCTAssertEqual(state.takePageLoadMessages(), expected)
        // Sent again on the next page load.
        XCTAssertEqual(state.takePageLoadMessages(), expected)
    }

    func testLogoutWithAReadyPageSendsResetNow() {
        var state = BridgeState(identity: asha, pushToken: apns, pendingReset: false, appId: nil)
        XCTAssertTrue(state.logout(pageReady: true))
        XCTAssertNil(state.identity)
        XCTAssertFalse(state.pendingReset)
        XCTAssertEqual(state.pushToken, apns, "the device push token is kept")
        // The page reloads after reset: only the push token goes again.
        XCTAssertEqual(state.takePageLoadMessages(), [.pushToken(apns, appId: nil)])
    }

    func testLogoutWithoutAPageResetsOnTheNextLoadFirst() {
        var state = BridgeState(identity: asha, pushToken: apns, pendingReset: false, appId: nil)
        XCTAssertFalse(state.logout(pageReady: false))
        XCTAssertTrue(state.pendingReset)

        // A new customer signs in before the chat opens again.
        let ravi = Identity(email: "ravi@yobruh.in", name: nil, userHash: "def456")
        state.identity = ravi

        XCTAssertEqual(
            state.takePageLoadMessages(),
            [.reset, .identify(ravi), .pushToken(apns, appId: nil)]
        )
        XCTAssertFalse(state.pendingReset)
        // Reset is sent once only.
        XCTAssertEqual(state.takePageLoadMessages(), [.identify(ravi), .pushToken(apns, appId: nil)])
    }

    func testStoreKeepsPushTokenAndResetFlagButNotIdentity() {
        let memory = MemoryStore()
        let store = BridgeStateStore(store: memory)

        var state = BridgeState(identity: asha, pushToken: apns, pendingReset: true, appId: "in.yobruh.shop")
        store.save(state)

        var loaded = BridgeState()
        store.load(into: &loaded)
        XCTAssertEqual(loaded.pushToken, apns)
        XCTAssertTrue(loaded.pendingReset)
        XCTAssertNil(loaded.identity)

        _ = state.takePageLoadMessages()
        store.save(state)
        var again = BridgeState()
        store.load(into: &again)
        XCTAssertFalse(again.pendingReset)
        XCTAssertNil(memory.values[BridgeStateStore.pendingResetKey])
    }

    func testStoreIgnoresAnUnknownRoute() {
        let memory = MemoryStore()
        memory.values[BridgeStateStore.tokenKey] = "abc"
        memory.values[BridgeStateStore.routeKey] = "carrier-pigeon"
        var state = BridgeState()
        BridgeStateStore(store: memory).load(into: &state)
        XCTAssertNil(state.pushToken)
    }
}

final class BridgeQueueTests: XCTestCase {
    private let asha = Identity(email: "asha@yobruh.in", name: nil, userHash: "abc123")

    func testQueuesUntilReadyThenFlushesInOrder() {
        var queue = BridgeQueue()
        XCTAssertFalse(queue.isReady)
        XCTAssertEqual(queue.send(.message(text: "Where is YB-1042?")), [])
        XCTAssertEqual(queue.send(.message(text: "second")), [])

        let out = queue.ready(pageLoadMessages: [.reset, .identify(asha)])
        XCTAssertEqual(out, [
            .reset,
            .identify(asha),
            .message(text: "Where is YB-1042?"),
            .message(text: "second"),
        ])
        XCTAssertTrue(queue.isReady)
        XCTAssertEqual(queue.pending, [])
    }

    func testSendsImmediatelyOnceReady() {
        var queue = BridgeQueue()
        _ = queue.ready(pageLoadMessages: [])
        XCTAssertEqual(queue.send(.reset), [.reset])
        XCTAssertEqual(queue.pending, [])
    }

    func testANewPageLoadQueuesAgain() {
        var queue = BridgeQueue()
        _ = queue.ready(pageLoadMessages: [])
        queue.pageWillLoad()
        XCTAssertFalse(queue.isReady)
        XCTAssertEqual(queue.send(.message(text: "hi")), [])
        XCTAssertEqual(queue.ready(pageLoadMessages: [.identify(asha)]), [.identify(asha), .message(text: "hi")])
    }
}
