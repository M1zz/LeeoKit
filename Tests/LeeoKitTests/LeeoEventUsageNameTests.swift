import XCTest
@testable import LeeoKit

final class LeeoEventUsageNameTests: XCTestCase {
    func testPurchaseFailedCarriesReason() {
        XCTAssertEqual(LeeoEvent.purchaseFailed(productID: "p", reason: "cancelled").usageName, "purchase_failed:cancelled")
        XCTAssertEqual(LeeoEvent.purchaseFailed(productID: "p", reason: nil).usageName, "purchase_failed")
        XCTAssertEqual(LeeoEvent.purchaseFailed(productID: "p", reason: "").usageName, "purchase_failed")
    }

    func testOtherEventsKeepPlainName() {
        XCTAssertEqual(LeeoEvent.paywallShown(reason: "limit").usageName, "paywall_shown")
        XCTAssertEqual(LeeoEvent.purchaseStarted(productID: "p").usageName, "purchase_started")
    }
}
