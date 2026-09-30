import XCTest
@testable import LeeoKit

/// 기기 언어가 패키지에 없는 언어(네덜란드어 등)면 영어로, 한국어면 한국어로 떨어져야 한다.
/// ⚠️ 예시 언어는 **패키지에 없는 것**이어야 한다 — 독일어로 쓰다가 독일어 번역이 들어오며 깨졌다.
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
        XCTAssertFalse(bundle.localizations.contains("nl"), "nl 이 들어왔으면 없는 언어로 예시를 바꿀 것")
        let picked = Bundle.preferredLocalizations(from: bundle.localizations, forPreferences: ["nl"])
        XCTAssertEqual(picked.first, "en")
    }

    func testAddedEuropeanLanguagesArePicked() {
        for lang in ["de", "fr", "es", "pt-BR", "it"] {
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
}
