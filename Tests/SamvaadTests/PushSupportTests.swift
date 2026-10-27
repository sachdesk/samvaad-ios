import XCTest
@testable import Samvaad

final class PushSupportTests: XCTestCase {
    func testHexIsLowerCaseAndZeroPadded() {
        XCTAssertEqual(PushTokenEncoding.hex(Data([0x00, 0xAB, 0x0F, 0xFF, 0x10])), "00ab0fff10")
        XCTAssertEqual(PushTokenEncoding.hex(Data()), "")
    }

    func testHexOfA32ByteToken() {
        let bytes = Data((0..<32).map { UInt8($0) })
        let hex = PushTokenEncoding.hex(bytes)
        XCTAssertEqual(hex.count, 64)
        XCTAssertTrue(hex.hasPrefix("000102030405"))
        XCTAssertTrue(hex.hasSuffix("1d1e1f"))
    }

    func testSamvaadPayloadIsRecognised() {
        let apns: [AnyHashable: Any] = [
            "aps": ["alert": ["title": "Yobruh Retail", "body": "New reply"]],
            "samvaad": "1",
            "tenant_id": "yobruh",
            "session_id": "s1",
        ]
        XCTAssertTrue(PushPayload.isSamvaad(apns))
        XCTAssertEqual(PushPayload.tenantId(apns), "yobruh")

        let fcm: [AnyHashable: Any] = ["samvaad": "1", "tenant_id": "yobruh", "session_id": "s1"]
        XCTAssertTrue(PushPayload.isSamvaad(fcm))

        let number: [AnyHashable: Any] = ["samvaad": NSNumber(value: 1)]
        XCTAssertTrue(PushPayload.isSamvaad(number))
    }

    func testOtherPayloadsAreNotOurs() {
        XCTAssertFalse(PushPayload.isSamvaad([:]))
        XCTAssertFalse(PushPayload.isSamvaad(["samvaad": "0"]))
        XCTAssertFalse(PushPayload.isSamvaad(["samvaad": "yes"]))
        XCTAssertFalse(PushPayload.isSamvaad(["samvaad": NSNumber(value: 2)]))
        XCTAssertFalse(PushPayload.isSamvaad(["aps": ["alert": "Order YB-1042 shipped"], "order_id": "YB-1042"]))
    }
}
