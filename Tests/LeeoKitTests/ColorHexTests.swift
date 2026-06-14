import XCTest
import SwiftUI
@testable import LeeoKit

final class ColorHexTests: XCTestCase {

    func testHexInitWithHash() {
        XCTAssertNotNil(Color(hex: "#4FACFE"))
    }

    func testHexInitWithoutHash() {
        XCTAssertNotNil(Color(hex: "4FACFE"))
    }

    func testHexInitTrimsWhitespace() {
        XCTAssertNotNil(Color(hex: "  4FACFE \n"))
    }

    func testHexInitRejectsGarbage() {
        XCTAssertNil(Color(hex: "ZZZZZZ"))
    }

    func testHexRoundTrip() {
        // 변환 후 다시 읽어도 같은 hex가 나와야 함 (대문자 6자리)
        let original = "4FACFE"
        guard let color = Color(hex: original), let back = color.toHex() else {
            return XCTFail("round-trip failed")
        }
        XCTAssertEqual(back.uppercased(), original)
    }

    func testFromNameKnown() {
        XCTAssertEqual(Color.fromName("blue"), Color.blue)
    }

    func testFromNameUnknownFallsBackToGray() {
        XCTAssertEqual(Color.fromName("not-a-color"), Color.gray)
    }
}
