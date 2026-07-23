//
//  LeeoUsageReporter.swift
//  LeeoKit
//
//  익명 사용 통계 수집 — 피드백과 같은 CloudKit 컨테이너(config.containerIdentifier)로
//  ① 설치당 스냅샷 1개(UsageSnapshot, upsert)  ② 주요 이벤트 스트림(UsageEvent)을 보낸다.
//
//  ⚠️ 개인 식별 정보(PII)는 수집하지 않는다. 설치 식별은 기기/계정과 무관한 무작위 UUID.
//  ⚠️ CloudKit Dashboard: UsageSnapshot/UsageEvent 레코드 타입을 Production에 배포하고,
//     통계 뷰어(LeeoUsageStatsView)로 전체를 읽으려면 read 권한이 필요하다(피드백과 동일).
//
//  사용 예:
//      // 앱 시작 시 1회
//      LeeoEngagement.shared.registerLaunch()
//      LeeoUsageReporter(spec: MyAppSpec.self).reportInBackground()
//      // 주요 행동 뒤
//      LeeoUsageReporter(spec: MyAppSpec.self).logEventInBackground("merge")
//

import Foundation
import CloudKit

public final class LeeoUsageReporter: @unchecked Sendable {
    public let config: LeeoFeedbackConfig
    private let appName: String

    /// CloudKit 레코드 타입 이름.
    public static let snapshotType = "UsageSnapshot"
    public static let eventType = "UsageEvent"

    public init(config: LeeoFeedbackConfig, appName: String) {
        self.config = config
        self.appName = appName
    }

    /// Spec 기반 편의 생성자 — 앱에서는 이걸 쓰면 된다(피드백과 같은 컨테이너·appId 재사용).
    public convenience init<Spec: LeeoAppSpec>(spec: Spec.Type) {
        self.init(config: Spec.feedback, appName: Spec.appName)
    }

    // MARK: - 익명 설치 ID (PII 아님, 재설치 전까지 고정)

    private static let installIDKey = "leeo.usage.installID"
    private var installID: String {
        let d = UserDefaults.standard
        if let s = d.string(forKey: Self.installIDKey) { return s }
        let s = UUID().uuidString
        d.set(s, forKey: Self.installIDKey)
        return s
    }

    private var lastSnapshotKey: String {
        "leeo.usage.lastSnapshotAt.\(config.containerIdentifier).\(config.appIdentifier ?? "-")"
    }

    // MARK: - 환경값

    private static var platform: String {
        #if targetEnvironment(macCatalyst)
        return "macCatalyst"
        #elseif os(iOS)
        return "iOS"
        #elseif os(macOS)
        return "macOS"
        #else
        return "unknown"
        #endif
    }
    private static var osVersion: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }
    private static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"
    }

    private var database: CKDatabase {
        CKContainer(identifier: config.containerIdentifier).publicCloudDatabase
    }
    private func iCloudReady() async -> Bool {
        (try? await CKContainer(identifier: config.containerIdentifier).accountStatus()) == .available
    }

    // MARK: - 설치 스냅샷 upsert

    /// LeeoEngagement 수치를 읽어 설치당 스냅샷을 갱신한다.
    /// - 같은 설치는 recordName(익명 UUID)이 같아 항상 덮어써진다 → 고유 사용자 수 집계에 적합.
    /// - `minInterval` 이내에 이미 보냈으면 건너뛴다(과도한 쓰기 방지).
    /// - Parameter metrics: 앱별 대략 지표(예: ["presentations": 12, "slides": 84]).
    ///   JSON 한 필드(`metrics`)로 저장돼 스키마 필드를 늘리지 않는다. 통계 뷰어가 평균을 낸다.
    public func report(
        engagement: LeeoEngagement = .shared,
        metrics: [String: Double] = [:],
        minInterval: TimeInterval = 12 * 3600
    ) async {
        let now = Date()
        if let last = UserDefaults.standard.object(forKey: lastSnapshotKey) as? Date,
           now.timeIntervalSince(last) < minInterval { return }
        guard await iCloudReady() else { return }

        let id = CKRecord.ID(recordName: "usage-\(installID)")
        let record = (try? await database.record(for: id))
            ?? CKRecord(recordType: Self.snapshotType, recordID: id)

        if let appId = config.appIdentifier { record["appId"] = appId }
        record["appName"] = appName
        record["appVersion"] = Self.appVersion
        record["platform"] = Self.platform
        record["osVersion"] = Self.osVersion
        record["locale"] = Locale.current.identifier
        record["launchCount"] = engagement.launchCount
        record["eventCount"] = engagement.significantEventCount
        record["daysSinceInstall"] = engagement.daysSinceInstall
        record["installDate"] = engagement.installDate
        record["lastActiveAt"] = now
        if !metrics.isEmpty, let json = Self.encodeMetrics(metrics) {
            record["metrics"] = json
        }

        do {
            _ = try await database.save(record)
            UserDefaults.standard.set(now, forKey: lastSnapshotKey)
            print("📈 [LeeoUsageReporter] 스냅샷 갱신 완료")
        } catch {
            print("⚠️ [LeeoUsageReporter.report] 스냅샷 저장 실패: \(error)")
        }
    }

    /// 앱 시작 시 부담 없이 호출하는 fire-and-forget 래퍼.
    public func reportInBackground(engagement: LeeoEngagement = .shared, metrics: [String: Double] = [:]) {
        Task { await report(engagement: engagement, metrics: metrics) }
    }

    private static func encodeMetrics(_ metrics: [String: Double]) -> String? {
        guard let data = try? JSONEncoder().encode(metrics) else { return nil }
        return String(data: data, encoding: .utf8)
    }
    private static func decodeMetrics(_ json: String?) -> [String: Double] {
        guard let json, let data = json.data(using: .utf8),
              let m = try? JSONDecoder().decode([String: Double].self, from: data) else { return [:] }
        return m
    }

    // MARK: - 주요 이벤트 스트림

    /// 의미 있는 행동 1건을 이벤트로 남긴다(예: "merge", "export", "photo_import").
    /// 고빈도 행동은 이벤트로 남기지 말고 LeeoEngagement.registerSignificantEvent()로 카운트만 하자.
    public func logEvent(_ name: String) async {
        guard await iCloudReady() else { return }
        let record = CKRecord(recordType: Self.eventType)
        if let appId = config.appIdentifier { record["appId"] = appId }
        record["appName"] = appName
        record["event"] = name
        record["appVersion"] = Self.appVersion
        record["platform"] = Self.platform
        record["installID"] = installID
        do {
            _ = try await database.save(record)
        } catch {
            print("⚠️ [LeeoUsageReporter.logEvent] '\(name)' 저장 실패: \(error)")
        }
    }

    public func logEventInBackground(_ name: String) {
        Task { await logEvent(name) }
    }

    // MARK: - 조회 (개발자 통계 뷰어용)

    /// 설치 스냅샷 한 건 (읽기용).
    public struct UsageSnapshot: Identifiable, Sendable {
        public let id: String
        public let appId: String?
        public let appVersion: String
        public let platform: String
        public let osVersion: String
        public let locale: String
        public let launchCount: Int
        public let eventCount: Int
        public let daysSinceInstall: Int
        public let installDate: Date?
        public let lastActiveAt: Date?
        /// 앱별 대략 지표(발표 수·장표 수 등). 없으면 빈 딕셔너리.
        public let metrics: [String: Double]

        init(_ r: CKRecord) {
            id = r.recordID.recordName
            appId = r["appId"] as? String
            appVersion = r["appVersion"] as? String ?? "-"
            platform = r["platform"] as? String ?? "-"
            osVersion = r["osVersion"] as? String ?? "-"
            locale = r["locale"] as? String ?? "-"
            launchCount = (r["launchCount"] as? Int) ?? 0
            eventCount = (r["eventCount"] as? Int) ?? 0
            daysSinceInstall = (r["daysSinceInstall"] as? Int) ?? 0
            installDate = r["installDate"] as? Date
            lastActiveAt = r["lastActiveAt"] as? Date
            metrics = LeeoUsageReporter.decodeMetrics(r["metrics"] as? String)
        }
    }

    /// 전체 설치 스냅샷을 조회한다(허브 모드면 appId로 필터, 최신 활동순 정렬).
    /// ⚠️ 남의 레코드를 읽으므로 컨테이너 read 권한이 필요하다(피드백 인박스와 동일).
    public func fetchSnapshots(limit: Int = 1000) async throws -> [UsageSnapshot] {
        let query = CKQuery(recordType: Self.snapshotType, predicate: NSPredicate(value: true))
        let (results, _) = try await database.records(matching: query, resultsLimit: limit)
        var snaps = results.compactMap { _, result in
            (try? result.get()).map(UsageSnapshot.init)
        }
        if let appId = config.appIdentifier {
            snaps = snaps.filter { $0.appId == appId }
        }
        snaps.sort { ($0.lastActiveAt ?? .distantPast) > ($1.lastActiveAt ?? .distantPast) }
        return snaps
    }
}
