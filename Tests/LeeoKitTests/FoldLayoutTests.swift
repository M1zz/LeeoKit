//
//  FoldLayoutTests.swift
//  LeeoKitTests
//
//  아이폰 듀오 자리 셈. 바깥 466 x 678, 안쪽 669 x 951.
//

#if os(iOS)
import XCTest
@testable import LeeoKit

final class FoldLayoutTests: XCTestCase {
    func testOuterScreenStaysSingle() {
        let fold = FoldLayout.resolve(windowSize: CGSize(width: 466, height: 678), isPhone: true)
        XCTAssertEqual(fold.posture, .single)
        XCTAssertFalse(fold.isUnfolded)
    }

    func testIPadIsNeverFolded() {
        let fold = FoldLayout.resolve(windowSize: CGSize(width: 1032, height: 1376), isPhone: false)
        XCTAssertEqual(fold.posture, .single)
    }

    func testInnerLandscapeSplitsAtWidthCenter() {
        let fold = FoldLayout.resolve(windowSize: CGSize(width: 951, height: 669), isPhone: true)
        XCTAssertEqual(fold.posture, .innerLandscape)
        XCTAssertEqual(fold.hingeCenter, 475.5)
        let sizes = fold.split(of: CGRect(x: 0, y: 0, width: 951, height: 669))
        XCTAssertEqual(sizes.lead, 463.5)
        XCTAssertEqual(sizes.trail, 463.5)
        XCTAssertEqual(fold.choosePaneSize.width, 463.5)
    }

    func testInnerPortraitSplitsAtHeightCenter() {
        let fold = FoldLayout.resolve(windowSize: CGSize(width: 669, height: 951), isPhone: true)
        XCTAssertEqual(fold.posture, .innerPortrait)
        XCTAssertEqual(fold.choosePaneSize.height, 951 - 487.5)
    }

    /// 판이 창 전체가 아니어도(안전 영역 아래) 경계는 진짜 선 위에 온다.
    func testSplitIsMeasuredFromTheWindowNotThePane() {
        let fold = FoldLayout.resolve(windowSize: CGSize(width: 669, height: 951), isPhone: true)
        let sizes = fold.split(of: CGRect(x: 0, y: 60, width: 669, height: 857))
        XCTAssertEqual(sizes.lead, 463.5 - 60)
        XCTAssertEqual(sizes.lead + fold.band + sizes.trail, 857)
    }

    /// 시스템이 알려 준 띠가 있으면 그쪽이 정답이다.
    func testReportedDivisionWins() {
        let fold = FoldLayout.resolve(windowSize: CGSize(width: 951, height: 669), isPhone: true,
                                      division: CGRect(x: 460, y: 0, width: 30, height: 669))
        XCTAssertEqual(fold.posture, .innerLandscape)
        XCTAssertEqual(fold.hingeCenter, 475)
        XCTAssertEqual(fold.band, 30)
    }
}
#endif
