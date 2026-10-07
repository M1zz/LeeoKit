//
//  LeeoDiagnostics.swift
//  LeeoKit
//
//  크래시·행(hang) 가시성 — MetricKit 진단을 피드백/통계와 **같은 CloudKit 컨테이너**에 쌓는다.
//
//  왜 Sentry/Crashlytics 가 아닌가
//   · 외부 SDK 0개 원칙 유지 — SDK 자체의 수집이 없고, App Privacy 신고 항목이 늘지 않는다.
//   · 허브가 이미 있으므로 새 인프라 비용이 사실상 0이다.
//   · **키보드·위젯 익스텐션의 메모리 종료(jetsam)까지 잡힌다.** 익스텐션은 메모리 예산이
//     빡빡해 서드파티 SDK를 넣기 어려운데, MetricKit 은 OS가 수집해 주므로 코드가 안 들어간다.
//
//  한계 (알고 쓸 것)
//   · 페이로드는 iOS가 **하루 한 번꼴로 묶어서** 준다 → 실시간 알림용이 아니다.
//     "어제 이 버전에서 크래시가 늘었나"를 보는 용도.
//   · 시뮬레이터에서는 거의 오지 않는다. 실기기 + 사용자 규모가 필요하다.
//   · macOS/Catalyst 는 MetricKit 진단 페이로드를 주지 않아 자동으로 비활성이다.
//
//  ⚠️ 개인정보: 콜스택·앱 버전·OS·기기 종류만 보낸다. 설치 식별자조차 붙이지 않는다
//     (크래시 집계에 필요 없다). App Privacy 는 `CrashData`(미연결·비추적)로 신고한다.
//
//  사용 예:
//      // 앱 시작 시 1회 — 구독만 하고 즉시 반환한다(런치 비용 없음)
//      LeeoDiagnostics.shared.start(spec: MyAppSpec.self)
//
//  CloudKit Dashboard 준비 (1회)
//      레코드 타입 `CrashReport` — 필드: appId·kind·detail·appVersion·osVersion·deviceType·stack
//      (3.17 부터) occurredAt·buildNumber·exceptionType·exceptionCode·signal — 클립키보드가 먼저 써서
//      허브 스키마에는 이미 있다. 새 컨테이너라면 Production 배포 전에 한 번 확인할 것.
//      (앱을 한 번 크래시시키면 자동 생성된다) → Production 배포
//

import Foundation
import CloudKit

/// 허브에 올라간 진단 한 건 (조회용).
public struct LeeoCrashReport: Identifiable, Sendable {
    public let id: String
    /// "crash" | "hang" | "disk_write"
    public let kind: String
    public let detail: String
    public let appVersion: String
    public let osVersion: String
    public let deviceType: String
    public let stack: String
    public let createdAt: Date?
    /// 아래는 3.17 에서 늘린 것 — 옛 레코드에는 없다.
    /// 크래시가 **난** 시각 (createdAt 은 MetricKit 이 배달한 때라 하루까지 늦다)
    public var occurredAt: Date? = nil
    /// 죽은 빌드 (`MXMetaData.applicationBuildVersion`). appVersion 은 **전송 시점에 깔린** 버전이다.
    public var buildNumber: String? = nil
    public var exceptionType: String? = nil
    public var exceptionCode: String? = nil
    public var signal: String? = nil
}

#if canImport(MetricKit) && os(iOS) && !targetEnvironment(macCatalyst)
import MetricKit

public final class LeeoDiagnostics: NSObject, MXMetricManagerSubscriber {

    public static let shared = LeeoDiagnostics()

    public static let recordType = "CrashReport"
    /// 한 페이로드에서 올리는 최대 건수 — 공개 DB 쓰기 폭주 방지.
    private static let maxReportsPerPayload = 5
    /// 콜스택 문자열 상한 — CloudKit 레코드 비대화 방지. 한 줄짜리 프레임이라 200프레임쯤 들어간다.
    /// (3.16 까지는 들여쓴 JSON 을 4000자에서 잘라 13프레임만 남았다 — `LeeoCrashStack` 머리말)
    private static let maxStackLength = LeeoCrashStack.defaultMaxLength

    private var config: LeeoFeedbackConfig?
    /// 수집을 원격으로 끌 수 있게 하는 훅. nil 이면 항상 수집.
    private var isEnabled: (() -> Bool)?

    private override init() { super.init() }

    /// 앱 시작 시 1회. 구독만 하고 즉시 반환한다.
    /// - Parameter isEnabled: 원격 킬스위치를 연결하고 싶을 때 전달 (예: `{ LeeoRemoteFlags.isEnabled(MyFlag.diagnostics) }`)
    public func start<Spec: LeeoAppSpec>(spec: Spec.Type, isEnabled: (() -> Bool)? = nil) {
        self.config = Spec.feedback
        self.isEnabled = isEnabled
        MXMetricManager.shared.add(self)
    }

    // MARK: - MXMetricManagerSubscriber

    public func didReceive(_ payloads: [MXDiagnosticPayload]) {
        guard let config, isEnabled?() ?? true else { return }

        var reports: [Pending] = []
        for payload in payloads {
            // 크래시가 **난** 시각. 레코드 생성 시각은 배달 시각이라 하루까지 늦다.
            let occurredAt = payload.timeStampEnd

            reports += payload.crashDiagnostics?.prefix(Self.maxReportsPerPayload).map {
                Pending(kind: "crash", detail: $0.terminationReason ?? "-",
                        stack: Self.stackString($0.callStackTree),
                        osVersion: $0.metaData.osVersion,
                        deviceType: $0.metaData.deviceType,
                        buildNumber: $0.metaData.applicationBuildVersion,
                        occurredAt: occurredAt,
                        // 종료 사유 한 줄로는 SIGSEGV 와 워치독이 안 갈린다
                        exceptionType: $0.exceptionType?.stringValue,
                        exceptionCode: $0.exceptionCode?.stringValue,
                        signal: $0.signal?.stringValue)
            } ?? []

            reports += payload.hangDiagnostics?.prefix(Self.maxReportsPerPayload).map {
                Pending(kind: "hang", detail: "\($0.hangDuration.value)\($0.hangDuration.unit.symbol)",
                        stack: Self.stackString($0.callStackTree),
                        osVersion: $0.metaData.osVersion,
                        deviceType: $0.metaData.deviceType,
                        buildNumber: $0.metaData.applicationBuildVersion,
                        occurredAt: occurredAt)
            } ?? []

            reports += payload.diskWriteExceptionDiagnostics?.prefix(Self.maxReportsPerPayload).map {
                Pending(kind: "disk_write", detail: "\($0.totalWritesCaused.value)\($0.totalWritesCaused.unit.symbol)",
                        stack: Self.stackString($0.callStackTree),
                        osVersion: $0.metaData.osVersion,
                        deviceType: $0.metaData.deviceType,
                        buildNumber: $0.metaData.applicationBuildVersion,
                        occurredAt: occurredAt)
            } ?? []
        }

        guard !reports.isEmpty else { return }
        let snapshot = reports
        Task(priority: .utility) { await Self.upload(snapshot, config: config) }
    }

    /// 성능 지표는 지금은 받기만 한다(적재는 크래시 가시성이 자리잡은 뒤).
    public func didReceive(_ payloads: [MXMetricPayload]) { }

    // MARK: - 내부

    /// ⚠️ `MXMetaData` 를 그대로 들고 있으면 Sendable 이 깨진다(Swift 6에서 에러).
    ///    Task 로 넘기기 전에 필요한 문자열만 즉시 뽑아 값 타입으로 만든다.
    private struct Pending: Sendable {
        let kind: String
        let detail: String
        let stack: String
        let osVersion: String
        let deviceType: String
        let buildNumber: String
        let occurredAt: Date
        /// 크래시에만 있다. 멈춤·디스크쓰기는 nil.
        var exceptionType: String? = nil
        var exceptionCode: String? = nil
        var signal: String? = nil
    }

    /// 죽은 자리부터 한 줄에 한 프레임 — `LeeoCrashStack` 머리말 참고.
    private static func stackString(_ tree: MXCallStackTree) -> String {
        LeeoCrashStack.text(fromJSON: tree.jsonRepresentation(), maxLength: maxStackLength)
    }

    private static func upload(_ reports: [Pending], config: LeeoFeedbackConfig) async {
        let database = CKContainer(identifier: config.containerIdentifier).publicCloudDatabase
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"

        for report in reports {
            let record = CKRecord(recordType: recordType)
            record["appId"] = config.appIdentifier
            record["kind"] = report.kind
            record["detail"] = report.detail
            record["appVersion"] = appVersion
            record["osVersion"] = report.osVersion
            record["deviceType"] = report.deviceType
            record["stack"] = report.stack
            // 3.17 에서 늘린 것 — 읽는 쪽은 옛 레코드에 없을 수 있다고 보고 다룬다
            record["occurredAt"] = report.occurredAt
            record["buildNumber"] = report.buildNumber
            if let exceptionType = report.exceptionType { record["exceptionType"] = exceptionType }
            if let exceptionCode = report.exceptionCode { record["exceptionCode"] = exceptionCode }
            if let signal = report.signal { record["signal"] = signal }
            // 진단 전송 실패로 앱이 시끄러워질 이유는 없다 — 조용히 넘어간다.
            _ = try? await database.save(record)
        }
    }
}

#else

/// MetricKit 이 없는 플랫폼(macOS·Catalyst)용 빈 구현 —
/// 호출부를 `#if` 로 감싸지 않아도 되게 한다.
public final class LeeoDiagnostics {
    public static let shared = LeeoDiagnostics()
    public static let recordType = "CrashReport"
    private init() {}
    public func start<Spec: LeeoAppSpec>(spec: Spec.Type, isEnabled: (() -> Bool)? = nil) { }
}

#endif

// MARK: - 조회 (모든 플랫폼)

/// 허브에서 진단을 읽는다.
/// ⚠️ 수집(`LeeoDiagnostics`, iOS 전용)과 분리해 둔다 — 조회는 맥 뷰어에서도 되어야 하고,
///    수집과 조회는 수명주기가 다르다.
public enum LeeoDiagnosticsReader {

    public static func fetch(config: LeeoFeedbackConfig, limit: Int = 200) async throws -> [LeeoCrashReport] {
        let database = CKContainer(identifier: config.containerIdentifier).publicCloudDatabase

        // appId 인덱스 없이 동작하도록 클라이언트에서 거른다(피드백·통계와 같은 방식).
        let query = CKQuery(recordType: LeeoDiagnostics.recordType, predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

        // 작게 나눠 커서로 이어 받는다 — 한 요청에 400개를 넘기면 서버가 거부한다.
        return try await LeeoCloudPage.collect(query, in: database, limit: limit, transform: { record -> LeeoCrashReport? in
            guard config.appIdentifier == nil || (record["appId"] as? String) == config.appIdentifier else {
                return nil
            }
            var report = LeeoCrashReport(
                id: record.recordID.recordName,
                kind: record["kind"] as? String ?? "-",
                detail: record["detail"] as? String ?? "-",
                appVersion: record["appVersion"] as? String ?? "-",
                osVersion: record["osVersion"] as? String ?? "-",
                deviceType: record["deviceType"] as? String ?? "-",
                stack: record["stack"] as? String ?? "",
                createdAt: record.creationDate
            )
            report.occurredAt = record["occurredAt"] as? Date
            report.buildNumber = record["buildNumber"] as? String
            report.exceptionType = record["exceptionType"] as? String
            report.exceptionCode = record["exceptionCode"] as? String
            report.signal = record["signal"] as? String
            return report
        })
    }

    public static func fetch<Spec: LeeoAppSpec>(spec: Spec.Type, limit: Int = 200) async throws -> [LeeoCrashReport] {
        try await fetch(config: Spec.feedback, limit: limit)
    }
}
