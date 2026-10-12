import XCTest
@testable import LeeoKit

final class LeeoBugCategoryTests: XCTestCase {

    // MARK: - 계약

    /// 허브가 `category:` 줄의 이 글자로 거른다. 바꾸면 지난 신고와 새 신고가 갈린다.
    func testRawValuesAreStable() {
        XCTAssertEqual(LeeoBugCategory.allCases.map(\.rawValue),
                       ["crash", "slow", "purchase", "sync", "data_loss",
                        "notification", "widget", "display", "other"])
    }

    func testEveryCategoryAsksAtMostThreeAndAtLeastOneRequired() {
        for category in LeeoBugCategory.allCases {
            let prompts = category.prompts
            XCTAssertLessThanOrEqual(prompts.count, 3, "\(category) 칸이 셋을 넘는다")
            XCTAssertTrue(prompts.contains(where: \.isRequired), "\(category) 에 필수 칸이 없다")
            XCTAssertEqual(Set(prompts.map(\.id)).count, prompts.count, "\(category) 칸 열쇠가 겹친다")
        }
    }

    /// 사진을 부탁하는 분류는 **어디서 찍는지**까지 말해야 한다.
    func testAttachmentsSayWhereToFindThem() {
        for category in LeeoBugCategory.allCases {
            for item in category.attachments {
                XCTAssertFalse(item.title.isEmpty, "\(item.id)")
                XCTAssertFalse(item.howTo.isEmpty, "\(item.id)")
            }
        }
        XCTAssertEqual(LeeoBugCategory.purchase.attachments.map(\.id),
                       ["purchase.history", "purchase.restore"])
    }

    /// 결제 분류는 영수증과 권한을, 데이터 분류는 처음 받은 날을 꼭 붙인다.
    func testPurchaseAndDataLossCarryReceipt() {
        XCTAssertEqual(LeeoBugCategory.purchase.probes, [.purchases, .appReceipt, .storefront])
        XCTAssertTrue(LeeoBugCategory.dataLoss.probes.contains(.appReceipt))
        XCTAssertTrue(LeeoBugCategory.notification.probes.contains(.notifications))
    }

    /// 다시 깔면 잃는 분류에는 지우지 말라는 말이 먼저 나온다.
    func testReinstallCaution() {
        XCTAssertNotNil(LeeoBugCategory.crash.caution)
        XCTAssertNotNil(LeeoBugCategory.dataLoss.caution)
        XCTAssertNotNil(LeeoBugCategory.sync.caution)
        XCTAssertNil(LeeoBugCategory.display.caution)
    }

    func testOtherKeepsGenericBugPrompts() {
        XCTAssertEqual(LeeoBugCategory.other.prompts.map(\.id), LeeoFeedbackType.bug.prompts.map(\.id))
    }

    // MARK: - 어느 앱에 어느 분류를

    func testPurchaseOnlyWhenSelling() {
        let free = LeeoBugCategory.defaults(sellsSomething: false, capabilities: .undeclared)
        XCTAssertFalse(free.contains(.purchase))
        let paid = LeeoBugCategory.defaults(sellsSomething: true, capabilities: .undeclared)
        XCTAssertTrue(paid.contains(.purchase))
    }

    /// 선언하지 않은 것은 보여 주고, 해당 없다고 적은 것만 뺀다.
    func testHidesOnlyDeclaredNotApplicable() {
        let undeclared = LeeoBugCategory.defaults(sellsSomething: false, capabilities: .undeclared)
        XCTAssertTrue(undeclared.contains(.notification))
        XCTAssertTrue(undeclared.contains(.widget))
        XCTAssertTrue(undeclared.contains(.sync))

        let caps = LeeoCapabilities(notApplicable: [.pushNotifications: "알림 없음",
                                                    .widgets: "위젯 없음",
                                                    .cloudSync: "기기 하나"])
        let trimmed = LeeoBugCategory.defaults(sellsSomething: false, capabilities: caps)
        XCTAssertFalse(trimmed.contains(.notification))
        XCTAssertFalse(trimmed.contains(.widget))
        XCTAssertFalse(trimmed.contains(.sync))
        XCTAssertEqual(trimmed.last, .other)
    }

    // MARK: - 보내기와 조립

    func testBugNeedsCategoryWhenOffered() {
        let answers = ["when": "아침", "symptom": "꺼져요"]
        XCTAssertFalse(LeeoFeedbackComposer.canSend(type: .bug, category: nil, requiresCategory: true,
                                                    answers: answers, note: ""))
        // 분류를 안 묻는 앱은 예전 그대로.
        XCTAssertTrue(LeeoFeedbackComposer.canSend(type: .bug, answers: answers, note: ""))
    }

    func testCategoryDecidesRequiredFields() {
        XCTAssertFalse(LeeoFeedbackComposer.canSend(type: .bug, category: .purchase, requiresCategory: true,
                                                    answers: [:], note: ""))
        XCTAssertTrue(LeeoFeedbackComposer.canSend(type: .bug, category: .purchase, requiresCategory: true,
                                                   answers: ["purchase.what": "평생 이용권이 사라졌어요"], note: ""))
    }

    /// 버그가 아닌 유형으로 옮기면 분류는 끼어들지 않는다.
    func testCategoryIgnoredOutsideBug() {
        XCTAssertEqual(LeeoFeedbackComposer.prompts(type: .feature, category: .purchase).map(\.id),
                       LeeoFeedbackType.feature.prompts.map(\.id))
        let text = LeeoFeedbackComposer.compose(type: .question, category: .purchase,
                                                answers: [:], note: "궁금해요")
        XCTAssertEqual(text, "궁금해요")
    }

    func testComposeStartsWithCategory() {
        let text = LeeoFeedbackComposer.compose(type: .bug, category: .purchase,
                                                answers: ["purchase.what": "잠겼어요"], note: "")
        let blocks = text.components(separatedBy: "\n\n")
        XCTAssertEqual(blocks.count, 2)
        XCTAssertTrue(blocks[0].hasSuffix(LeeoBugCategory.purchase.localizedName))
        XCTAssertTrue(blocks[1].hasSuffix("잠겼어요"))
    }

    func testCategoryLineIsMachineReadable() {
        XCTAssertEqual(LeeoFeedbackComposer.categoryLine(.dataLoss), "category: data_loss")
    }

    // MARK: - 진단

    func testDeviceLineShape() {
        let line = LeeoBugProbe.deviceLine()
        XCTAssertTrue(line.hasPrefix("[device] "))
        XCTAssertTrue(line.contains("lowPower="))
        XCTAssertTrue(line.contains("thermal="))
    }

    /// 날짜는 UTC 로 고정한다. 시간대가 섞이면 "언제 샀는지" 가 하루씩 어긋난다.
    func testDayIsUTC() {
        XCTAssertEqual(LeeoBugProbe.day(Date(timeIntervalSince1970: 1_771_686_000)), "2026-02-21")
    }

    /// 늦는 진단을 기다리지 않는다.
    func testTimeoutGivesUp() async {
        let start = Date()
        let value: Int? = await LeeoBugProbe.withTimeout {
            try? await Task.sleep(for: .seconds(30))
            return 1
        }
        XCTAssertNil(value)
        XCTAssertLessThan(Date().timeIntervalSince(start), 10)
    }

    func testFastWorkPasses() async {
        let value: Int? = await LeeoBugProbe.withTimeout { 7 }
        XCTAssertEqual(value, 7)
    }
}
