import XCTest
@testable import LeeoKit

/// 기기 언어가 패키지에 없는 언어(헝가리어 등)면 영어로, 한국어면 한국어로 떨어져야 한다.
/// ⚠️ 예시 언어는 **패키지에 없는 것**이어야 한다 — 독일어로, 다음엔 네덜란드어로 쓰다가 그 번역이 들어오며 깨졌다.
///
/// 원문이 ko 인 카탈로그에서 defaultLocalization 을 en 으로 두면, ko 값을 명시하지 않는 한
/// ko.lproj 가 안 생겨 한국어 사용자가 영어를 본다 (→ scripts/fill-source-ko.py).
/// 두 쪽이 다 지켜지는지 여기서 본다.
final class LocalizationFallbackTests: XCTestCase {

    private var bundle: Bundle { .module }

    func testDevelopmentRegionIsEnglish() {
        XCTAssertEqual(bundle.developmentLocalization, "en")
    }

    func testUnsupportedLanguageFallsBackToEnglish() {
        XCTAssertFalse(bundle.localizations.contains("hu"), "hu 가 들어왔으면 없는 언어로 예시를 바꿀 것")
        let picked = Bundle.preferredLocalizations(from: bundle.localizations, forPreferences: ["hu"])
        XCTAssertEqual(picked.first, "en")
    }

    func testAddedEuropeanLanguagesArePicked() {
        for lang in ["de", "fr", "es", "pt-BR", "it",
                     "cs", "da", "el", "fi", "nb", "nl", "pl", "sv", "tr"] {
            let picked = Bundle.preferredLocalizations(from: bundle.localizations, forPreferences: [lang])
            XCTAssertEqual(picked.first, lang, "\(lang).lproj 가 패키지에 없다")
        }
    }

    func testKoreanStaysKorean() {
        XCTAssertTrue(bundle.localizations.contains("ko"), "ko.lproj가 없다 — fill-source-ko.py를 돌릴 것")
        let picked = Bundle.preferredLocalizations(from: bundle.localizations, forPreferences: ["ko"])
        XCTAssertEqual(picked.first, "ko")
    }

    func testKoreanTableReturnsKoreanText() throws {
        let path = try XCTUnwrap(bundle.path(forResource: "ko", ofType: "lproj"))
        let ko = try XCTUnwrap(Bundle(path: path))
        let enPath = try XCTUnwrap(bundle.path(forResource: "en", ofType: "lproj"))
        let en = try XCTUnwrap(Bundle(path: enPath))

        let key = "리뷰 남기기"
        let missing = "__missing__"
        let koValue = ko.localizedString(forKey: key, value: missing, table: nil)
        let enValue = en.localizedString(forKey: key, value: missing, table: nil)
        XCTAssertEqual(koValue, key)
        XCTAssertNotEqual(enValue, missing)
        XCTAssertNotEqual(enValue, key)
    }

    /// 체코어·폴란드어는 숫자에 따라 낱말 꼴이 셋 이상이다 — 카탈로그의 복수형이 실제로 고른다.
    func testCzechPluralFormsFollowCount() throws {
        let path = try XCTUnwrap(bundle.path(forResource: "cs", ofType: "lproj"))
        let cs = try XCTUnwrap(Bundle(path: path))
        let format = cs.localizedString(forKey: "%d일", value: nil, table: nil)
        XCTAssertEqual(String(format: format, locale: Locale(identifier: "cs"), 2), "2 dny")
        XCTAssertEqual(String(format: format, locale: Locale(identifier: "cs"), 5), "5 dní")
    }

    /// 앱 이름만 든 키가 어느 언어에서도 한국어로 남지 않는다 (교차 홍보 카드).
    func testAppNameKeysAreLocalized() throws {
        for lang in ["en", "ja", "ru", "zh-Hans", "nl"] {
            let path = try XCTUnwrap(bundle.path(forResource: lang, ofType: "lproj"))
            let b = try XCTUnwrap(Bundle(path: path))
            for key in ["두번알림", "욕망의 무지개", "무지개 공방", "클립키보드: 빠른 붙여넣기"] {
                let value = b.localizedString(forKey: key, value: nil, table: nil)
                XCTAssertNil(value.range(of: "\\p{Script=Hangul}", options: .regularExpression),
                             "\(lang): \(key) → \(value)")
            }
        }
    }
}
