//
//  LeeoFeedbackServiceTests.swift
//  LeeoKitTests
//
//  피드백 CloudKit 연동의 리그레션 테스트 (네트워크 없이 로컬 CKRecord로 검증).
//  클립키보드의 FeedbackServiceTests에서 이식 — 앱별 상수 검증은 각 앱 테스트에 남긴다.
//
//  잠그는 계약:
//  1. 기본 설정값 — recordType/subscriptionID 기본값이 바뀌면 기존 앱들의
//     Dashboard 스키마·기기 구독과 어긋나는 조용한 장애가 재발한다.
//  2. 쓰기(makeRecord)와 읽기(FeedbackRecord) 필드 키가 항상 1:1로 유지된다.
//  3. LeeoFeedbackType rawValue는 서버에 저장된 값이므로 절대 변경 불가.
//

import XCTest
import CloudKit
@testable import LeeoKit

final class LeeoFeedbackServiceTests: XCTestCase {

    /// 테스트용 설정 — 단일 앱 스키마 (appIdentifier 없음)
    private let config = LeeoFeedbackConfig(containerIdentifier: "iCloud.test.Container")

    // MARK: - 기본값 (기존 앱들과의 계약)

    func testDefaultRecordTypeIsStable() {
        // 기존 앱들의 Dashboard Record Type — 기본값이 바뀌면 기존 피드백이 조회에서 빠진다
        XCTAssertEqual(config.recordType, "Feedback")
    }

    func testDefaultSubscriptionIDIsStable() {
        // 서버에 저장된 구독 ID — 바뀌면 기존 기기의 구독을 해제할 수 없게 된다
        XCTAssertEqual(config.subscriptionID, "feedback-new-v1")
    }

    func testDefaultAppIdentifierIsNil() {
        // 단일 앱 스키마 호환 — appId 필드를 쓰지 않는 것이 기본
        XCTAssertNil(config.appIdentifier)
    }

    // MARK: - 인박스 조회 쿼리

    func testFetchQueryTargetsRecordTypeWithTruePredicate() {
        let query = LeeoFeedbackService.makeFetchQuery(config: config)

        XCTAssertEqual(query.recordType, "Feedback")
        // TRUEPREDICATE — Production에 recordName Queryable 인덱스가 필요한 형태
        XCTAssertEqual(query.predicate, NSPredicate(value: true))
    }

    func testFetchQuerySortsByCreationDateDescending() {
        let query = LeeoFeedbackService.makeFetchQuery(config: config)

        XCTAssertEqual(query.sortDescriptors?.count, 1)
        XCTAssertEqual(query.sortDescriptors?.first?.key, "creationDate")
        XCTAssertEqual(query.sortDescriptors?.first?.ascending, false)
    }

    // MARK: - 제출 레코드 구성 (쓰기 모델)

    func testMakeRecordPopulatesAllSchemaFields() {
        let record = LeeoFeedbackService.makeRecord(
            config: config,
            type: "bug",
            message: "새 메모 생성이 안돼요",
            deviceInfo: "App 4.3.7 | iPhone | iOS 26.5.2"
        )

        XCTAssertEqual(record.recordType, "Feedback")
        XCTAssertEqual(record["type"] as? String, "bug")
        XCTAssertEqual(record["message"] as? String, "새 메모 생성이 안돼요")
        XCTAssertEqual(record["deviceInfo"] as? String, "App 4.3.7 | iPhone | iOS 26.5.2")
        XCTAssertEqual(record["locale"] as? String, Locale.current.identifier)

        // appVersion은 번들에 따라 값이 다르므로 존재만 보장
        XCTAssertNotNil(record["appVersion"] as? String)

        #if targetEnvironment(macCatalyst)
        XCTAssertEqual(record["platform"] as? String, "macCatalyst")
        #else
        XCTAssertEqual(record["platform"] as? String, "iOS")
        #endif

        // status는 제출 시점에는 없어야 한다 (개발자가 인박스에서 완료 표시할 때만 기록)
        XCTAssertNil(record["status"])

        // appIdentifier가 nil이면 appId 필드도 없어야 한다 (기존 스키마 호환)
        XCTAssertNil(record["appId"])
    }

    func testMakeRecordWritesAppIdOnlyForHubConfig() {
        // 공용 허브 설정 — appId 필드가 앱 구분값으로 기록된다
        let hubConfig = LeeoFeedbackConfig(
            containerIdentifier: "iCloud.test.Hub", appIdentifier: "com.test.MyApp")
        let record = LeeoFeedbackService.makeRecord(
            config: hubConfig, type: "bug", message: "m", deviceInfo: "d")

        XCTAssertEqual(record["appId"] as? String, "com.test.MyApp")
    }

    // MARK: - 인박스 읽기 모델 (FeedbackRecord)

    func testFeedbackRecordMapsAllFieldsFromCKRecord() {
        let ckRecord = CKRecord(recordType: config.recordType)
        ckRecord["type"] = "feature"
        ckRecord["message"] = "카테고리 페이지가 바로 생기면 좋겠어요"
        ckRecord["deviceInfo"] = "App 4.3.7 | iPhone | iOS 26.5.2"
        ckRecord["appVersion"] = "4.3.7"
        ckRecord["locale"] = "ko_KR"
        ckRecord["platform"] = "iOS"
        ckRecord["status"] = "done"

        let record = LeeoFeedbackService.FeedbackRecord(ckRecord)

        XCTAssertEqual(record.id, ckRecord.recordID.recordName)
        XCTAssertEqual(record.type, "feature")
        XCTAssertEqual(record.message, "카테고리 페이지가 바로 생기면 좋겠어요")
        XCTAssertEqual(record.deviceInfo, "App 4.3.7 | iPhone | iOS 26.5.2")
        XCTAssertEqual(record.appVersion, "4.3.7")
        XCTAssertEqual(record.locale, "ko_KR")
        XCTAssertEqual(record.platform, "iOS")
        XCTAssertEqual(record.status, "done")
    }

    func testFeedbackRecordDefaultsWhenFieldsMissing() {
        // Dashboard에서 수동 생성했거나 구버전이 만든 레코드 — 필드가 비어도 크래시 없이 표시
        let record = LeeoFeedbackService.FeedbackRecord(CKRecord(recordType: config.recordType))

        XCTAssertEqual(record.type, "-")
        XCTAssertEqual(record.message, "")
        XCTAssertEqual(record.deviceInfo, "")
        XCTAssertEqual(record.appVersion, "")
        XCTAssertEqual(record.locale, "")
        XCTAssertEqual(record.platform, "")
        XCTAssertNil(record.appId)
        XCTAssertNil(record.status)
        XCTAssertFalse(record.isDone)
    }

    func testIsDoneOnlyWhenStatusIsExactlyDone() {
        let ckRecord = CKRecord(recordType: config.recordType)
        var record = LeeoFeedbackService.FeedbackRecord(ckRecord)

        record.status = "done"
        XCTAssertTrue(record.isDone)

        for notDone in [nil, "", "DONE", "open", "in-progress"] {
            record.status = notDone
            XCTAssertFalse(record.isDone, "status=\(notDone ?? "nil")은 완료로 표시되면 안 된다")
        }
    }

    func testSubmitAndInboxFieldKeysStayInSync() {
        // 핵심 회귀 가드: 쓰기(makeRecord)와 읽기(FeedbackRecord)의 필드 키가 어긋나면
        // 제출은 성공하는데 인박스에는 기본값("-", "")만 보이는 조용한 장애가 된다
        let submitted = LeeoFeedbackService.makeRecord(
            config: config,
            type: "question",
            message: "템플릿은 어떻게 쓰나요?",
            deviceInfo: "App 4.3.9 | iPhone | iOS 26.5.2"
        )

        let read = LeeoFeedbackService.FeedbackRecord(submitted)

        XCTAssertEqual(read.type, "question")
        XCTAssertEqual(read.message, "템플릿은 어떻게 쓰나요?")
        XCTAssertEqual(read.deviceInfo, "App 4.3.9 | iPhone | iOS 26.5.2")
        XCTAssertEqual(read.locale, Locale.current.identifier)
        XCTAssertFalse(read.appVersion.isEmpty)
        XCTAssertFalse(read.platform.isEmpty)
    }

    // MARK: - LeeoFeedbackType (서버에 저장되는 rawValue)

    func testFeedbackTypeRawValuesAreStable() {
        // rawValue는 CloudKit 레코드의 type 필드에 그대로 저장된다 — 변경 금지
        XCTAssertEqual(LeeoFeedbackType.bug.rawValue, "bug")
        XCTAssertEqual(LeeoFeedbackType.feature.rawValue, "feature")
        XCTAssertEqual(LeeoFeedbackType.question.rawValue, "question")
        XCTAssertEqual(LeeoFeedbackType.other.rawValue, "other")
        XCTAssertEqual(LeeoFeedbackType.allCases.count, 4)
    }

    func testFeedbackTypeRoundTripsThroughStoredRawValue() {
        // 인박스는 LeeoFeedbackType(rawValue: record.type)으로 아이콘/이름을 복원한다
        for type in LeeoFeedbackType.allCases {
            let record = LeeoFeedbackService.makeRecord(
                config: config, type: type.rawValue, message: "m", deviceInfo: "d")
            let restored = LeeoFeedbackType(rawValue: LeeoFeedbackService.FeedbackRecord(record).type)
            XCTAssertEqual(restored, type)
        }
    }

    func testUnknownFeedbackTypeFallsBackToNil() {
        // 미래 버전이 새 타입을 추가해도 구버전 인박스는 raw 문자열로 표시 (크래시 없음)
        XCTAssertNil(LeeoFeedbackType(rawValue: "praise"))
    }

    func testFeedbackTypeHasIconAndLocalizedName() {
        for type in LeeoFeedbackType.allCases {
            XCTAssertFalse(type.icon.isEmpty)
            XCTAssertFalse(type.localizedName.isEmpty)
        }
    }
}
