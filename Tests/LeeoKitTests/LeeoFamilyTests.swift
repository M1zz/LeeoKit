//
//  LeeoFamilyTests.swift
//  LeeoKitTests
//
//  앱 소개 카탈로그는 사람이 손으로 적는 표라, 틀려도 컴파일은 통과한다.
//  여기서 잡는 것: 죽은 앱 참조 · 중복 id · 어디에도 안 나오는 앱 · 스토어 주소 오타 ·
//  자기 자신을 자기가 광고하는 사고.
//

import XCTest
@testable import LeeoKit

private let privacy = URL(string: "https://ysoup.io/privacy")!
private let support = URL(string: "https://ysoup.io/support")!

/// 카탈로그에 실재하는 앱(클립키보드) 행세를 하는 스펙.
private enum ClipSpec: LeeoAppSpec {
    static let appName = "ClipKeyboard"
    static let developerEmail = "leeo@kakao.com"
    static let feedback = LeeoFeedbackConfig(containerIdentifier: "iCloud.com.Ysoup.Clip")
    static let legal = LeeoLegalConfig(privacyURL: privacy, supportURL: support)
    static let monetization = LeeoMonetization.free
    static let appStoreID: String? = "1543660502"
}

/// 카탈로그에 없는 앱. 아무것도 빠지지 않아야 한다.
private enum StrangerSpec: LeeoAppSpec {
    static let appName = "Stranger"
    static let developerEmail = "leeo@kakao.com"
    static let feedback = LeeoFeedbackConfig(containerIdentifier: "iCloud.com.Ysoup.Stranger")
    static let legal = LeeoLegalConfig(privacyURL: privacy, supportURL: support)
    static let monetization = LeeoMonetization.free
    static let appStoreID: String? = "9999999999"
}

/// `familyID` 를 직접 못박은 앱. 스토어 ID 대조보다 이쪽이 우선한다.
private enum PinnedSpec: LeeoAppSpec {
    static let appName = "Pinned"
    static let developerEmail = "leeo@kakao.com"
    static let feedback = LeeoFeedbackConfig(containerIdentifier: "iCloud.com.Ysoup.Pinned")
    static let legal = LeeoLegalConfig(privacyURL: privacy, supportURL: support)
    static let monetization = LeeoMonetization.free
    static let appStoreID: String? = "1543660502"
    static let familyID: String? = "rereminder"
}

final class LeeoFamilyTests: XCTestCase {

    // MARK: - 카탈로그 무결성

    func testAppIDsAreUnique() {
        let ids = LeeoFamilyCatalog.apps.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "앱 id 가 겹친다: \(ids)")
    }

    func testAppStoreIDsAreUniqueAndNumeric() {
        let storeIDs = LeeoFamilyCatalog.apps.map(\.appStoreID)
        XCTAssertEqual(storeIDs.count, Set(storeIDs).count, "스토어 ID 가 겹친다: \(storeIDs)")
        for id in storeIDs {
            XCTAssertFalse(id.isEmpty)
            XCTAssertTrue(id.allSatisfy(\.isNumber), "스토어 ID 는 숫자여야 한다: \(id)")
        }
    }

    func testStoreURLsAreHTTPS() {
        for app in LeeoFamilyCatalog.apps {
            let url = app.storeURL
            XCTAssertNotNil(url, "\(app.id): 스토어 주소를 만들 수 없다")
            XCTAssertEqual(url?.scheme, "https", "\(app.id): https 가 아니다")
        }
    }

    func testEveryAppHasCopy() {
        for app in LeeoFamilyCatalog.apps {
            XCTAssertFalse(app.name.isEmpty, "\(app.id): 이름이 비었다")
            XCTAssertFalse(app.tagline.isEmpty, "\(app.id): 한 줄 소개가 비었다")
            XCTAssertFalse(app.purpose.isEmpty, "\(app.id): 목적이 비었다")
            XCTAssertFalse(app.forWhom.isEmpty, "\(app.id): 대상이 비었다")
            XCTAssertFalse(app.moments.isEmpty, "\(app.id): 상황이 비었다")
            XCTAssertFalse(app.platforms.isEmpty, "\(app.id): 플랫폼이 비었다")
        }
    }

    /// 아이콘이 빠지면 카드가 SF Symbol 자리표시로 조용히 물러난다. 틀려도 화면은 멀쩡해 보이니 여기서 잡는다.
    func testEveryAppShipsItsAppIcon() {
        let pngSignature: [UInt8] = [0x89, 0x50, 0x4E, 0x47]
        for app in LeeoFamilyCatalog.apps {
            guard let data = app.iconPNGData else {
                XCTFail("\(app.id): 아이콘이 없다. scripts/embed_family_icons.py 의 SOURCES 에 더하고 다시 돌린다")
                continue
            }
            XCTAssertTrue(data.starts(with: pngSignature), "\(app.id): PNG 가 아니다")
        }
    }

    // MARK: - 이야기

    func testSynergyIDsAreUnique() {
        let ids = LeeoFamilyCatalog.synergies.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "이야기 id 가 겹친다: \(ids)")
    }

    func testSynergiesReferenceRealApps() {
        let known = Set(LeeoFamilyCatalog.apps.map(\.id))
        for story in LeeoFamilyCatalog.synergies {
            for appID in story.appIDs {
                XCTAssertTrue(known.contains(appID), "\(story.id): 없는 앱 '\(appID)' 을 가리킨다")
            }
            XCTAssertEqual(story.appIDs.count, Set(story.appIDs).count,
                           "\(story.id): 같은 앱이 두 번 나온다")
            // 넷부터는 이야기가 아니라 카탈로그가 된다 (LeeoFamilySynergy 머리주석).
            XCTAssertTrue((2...3).contains(story.appIDs.count),
                          "\(story.id): 한 이야기의 앱은 둘 또는 셋이다")
            XCTAssertFalse(story.beats.isEmpty, "\(story.id): 박자가 없다")
            XCTAssertFalse(story.payoff.isEmpty, "\(story.id): 마무리 한 줄이 없다")
        }
    }

    /// 소개만 되고 아무 장면에도 안 나오는 앱이 있으면, 그 앱은 "받아 주세요" 광고로만 남는다.
    func testEveryAppAppearsInSomeStory() {
        let cast = Set(LeeoFamilyCatalog.synergies.flatMap(\.appIDs))
        for app in LeeoFamilyCatalog.apps {
            XCTAssertTrue(cast.contains(app.id), "\(app.id): 어떤 이야기에도 안 나온다")
        }
    }

    // MARK: - 자기 자신 빼기

    func testCurrentAppResolvesByStoreID() {
        XCTAssertEqual(LeeoFamilyCatalog.currentAppID(ClipSpec.self), "clipkeyboard")
    }

    func testFamilyIDBeatsStoreID() {
        XCTAssertEqual(LeeoFamilyCatalog.currentAppID(PinnedSpec.self), "rereminder")
    }

    func testOthersExcludeSelf() {
        let others = LeeoFamilyCatalog.others(for: ClipSpec.self)
        XCTAssertFalse(others.contains { $0.id == "clipkeyboard" }, "자기 자신을 자기가 광고한다")
        XCTAssertEqual(others.count, LeeoFamilyCatalog.apps.count - 1)
    }

    func testUnknownSpecKeepsEveryone() {
        XCTAssertNil(LeeoFamilyCatalog.currentAppID(StrangerSpec.self))
        XCTAssertEqual(LeeoFamilyCatalog.others(for: StrangerSpec.self).count,
                       LeeoFamilyCatalog.apps.count)
    }

    func testStoriesSplitAroundCurrentApp() {
        let mine = LeeoFamilyCatalog.synergies(involving: ClipSpec.self)
        let rest = LeeoFamilyCatalog.synergies(excluding: ClipSpec.self)
        XCTAssertFalse(mine.isEmpty, "지금 앱이 나오는 장면이 하나도 없다")
        XCTAssertEqual(mine.count + rest.count, LeeoFamilyCatalog.synergies.count)
        XCTAssertTrue(mine.allSatisfy { $0.involves("clipkeyboard") })
        XCTAssertTrue(rest.allSatisfy { !$0.involves("clipkeyboard") })
    }

    /// 지금 기기에서 받을 수 있는 앱이 앞에 서야 한다.
    func testOthersPutInstallableFirst() {
        let others = LeeoFamilyCatalog.others(for: ClipSpec.self)
        let flags = others.map(\.runsOnThisDevice)
        XCTAssertEqual(flags, flags.sorted(by: { $0 && !$1 }), "설치 가능한 앱이 뒤로 밀렸다")
    }
}
