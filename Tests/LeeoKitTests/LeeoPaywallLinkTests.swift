import XCTest
@testable import LeeoKit

final class LeeoPaywallLinkTests: XCTestCase {
    func testPaywallHostOpensPaywall() {
        XCTAssertTrue(LeeoPaywallLink.opensPaywall(URL(string: "com.leeo.lullabyrecipe://paywall")!))
        XCTAssertTrue(LeeoPaywallLink.opensPaywall(URL(string: "any-scheme://Paywall")!))
    }

    func testOtherLinksDoNotOpenPaywall() {
        XCTAssertFalse(LeeoPaywallLink.opensPaywall(URL(string: "com.leeo.app://widget/today")!))
        XCTAssertFalse(LeeoPaywallLink.opensPaywall(URL(string: "com.leeo.app:///paywall")!))
    }
}
