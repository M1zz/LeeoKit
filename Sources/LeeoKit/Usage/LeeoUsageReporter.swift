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

    /// 이 설치를 가리키는 익명 UUID. 기기·계정과 무관하고, 재설치하면 새로 생긴다.
    /// 앱이 직접 이벤트 레코드를 만들 때(예: 소급 백필) 같은 설치로 묶으려면 이 값이 필요하다.
    public var installID: String {
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
    ///
    /// - Parameter occurredAt: **행동이 실제로 일어난 시각.** 생략하면 지금이다.
    ///   레코드의 `creationDate`는 서버가 "쓴 시각"으로 찍기 때문에, 오프라인이나
    ///   익스텐션에서 벌어진 일을 나중에 몰아 보내면 전부 보낸 날짜로 뭉쳐 버린다.
    ///   그래서 시각을 별도 필드로 함께 남기고, 집계는 이 값을 우선 본다.
    /// - Returns: 허브에 실제로 저장됐는지. 소급 백필처럼 **보낸 뒤 원본을 지우는** 쪽은
    ///   이 값을 봐야 한다. iCloud 미로그인이나 네트워크 실패로 못 보낸 기록을
    ///   보냈다고 치고 지워 버리면 그 사용자의 활동은 영영 복구되지 않는다.
    @discardableResult
    public func logEvent(_ name: String, occurredAt: Date? = nil) async -> Bool {
        guard await iCloudReady() else { return false }
        let record = CKRecord(recordType: Self.eventType)
        if let appId = config.appIdentifier { record["appId"] = appId }
        record["appName"] = appName
        record["event"] = name
        record["appVersion"] = Self.appVersion
        record["platform"] = Self.platform
        record["installID"] = installID
        record["occurredAt"] = occurredAt ?? Date()
        do {
            _ = try await database.save(record)
            return true
        } catch {
            print("⚠️ [LeeoUsageReporter.logEvent] '\(name)' 저장 실패: \(error)")
            return false
        }
    }

    public func logEventInBackground(_ name: String, occurredAt: Date? = nil) {
        Task { await logEvent(name, occurredAt: occurredAt) }
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

        /// 디스크에 적어 둔 것에서 되살릴 때 쓴다(앱이 증분 캐시를 들고 있는 경우).
        /// CKRecord 없이 만들 길이 없으면 캐시를 화면에 그릴 수 없다.
        public init(id: String, appId: String?, appVersion: String, platform: String,
                    osVersion: String, locale: String, launchCount: Int, eventCount: Int,
                    daysSinceInstall: Int, installDate: Date?, lastActiveAt: Date?,
                    metrics: [String: Double]) {
            self.id = id
            self.appId = appId
            self.appVersion = appVersion
            self.platform = platform
            self.osVersion = osVersion
            self.locale = locale
            self.launchCount = launchCount
            self.eventCount = eventCount
            self.daysSinceInstall = daysSinceInstall
            self.installDate = installDate
            self.lastActiveAt = lastActiveAt
            self.metrics = metrics
        }

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
    ///
    /// 한 번에 다 받지 않는다 — `LeeoCloudPage.size`건씩 커서로 이어 받는다. 서버는
    /// 한 요청에 400개까지만 돌려주고, 그보다 큰 `resultsLimit`은 조회 자체를 거부하기
    /// 때문이다(설치 900건에서 통계 화면 전체가 죽었던 이유). 페이지가 올 때마다
    /// `onPage`로 "지금까지"를 넘기므로 화면은 200건씩 채워지며 자란다.
    ///
    /// - Parameters:
    ///   - limit: 전체 상한(안전장치). 서버로 나가는 요청 크기와는 무관하다.
    ///   - onProgress: 페이지가 도착할 때마다 그때까지의 스냅샷을 정렬·필터까지 마친 상태로,
    ///     마지막엔 **멈춘 이유까지** 붙여서 넘긴다. 화면이 "다 받았는지"를 말할 수 있게.
    /// ⚠️ 남의 레코드를 읽으므로 컨테이너 read 권한이 필요하다(피드백 인박스와 동일).
    /// - Parameter changedSince: 이 시각 뒤에 **바뀐** 스냅샷만 받는다(증분).
    ///   nil 이면 전부 받는다.
    ///   ⚠️ 스냅샷은 설치마다 한 줄이고 사람이 돌아올 때마다 **덮어써진다.** 그래서
    ///      기준은 만든 시각이 아니라 고친 시각(`modificationDate`)이다. 만든 시각으로
    ///      거르면 오래전에 깔고 오늘 다시 온 사람이 통째로 빠진다.
    ///   ⚠️ 이 걸러내기는 CloudKit 스키마에서 `modificationDate` 가 **Queryable** 일 때만
    ///      된다. 인덱스가 없으면 조회가 거부되므로, 부르는 쪽에서 실패하면 전체 조회로
    ///      돌아갈 수 있게 에러를 그대로 던진다.
    public func fetchSnapshots(limit: Int = 5000,
                               changedSince: Date? = nil,
                               onProgress: (@MainActor (LeeoCloudProgress<UsageSnapshot>) -> Void)? = nil) async throws -> [UsageSnapshot] {
        let predicate = changedSince.map { NSPredicate(format: "modificationDate > %@", $0 as NSDate) }
            ?? NSPredicate(value: true)
        let query = CKQuery(recordType: Self.snapshotType, predicate: predicate)
        let appId = config.appIdentifier

        // 부분 결과도 완성본과 똑같이 보이도록, 페이지마다 같은 손질을 거쳐 넘긴다.
        let arrange: ([UsageSnapshot]) -> [UsageSnapshot] = { snaps in
            var out = appId == nil ? snaps : snaps.filter { $0.appId == appId }
            out.sort { ($0.lastActiveAt ?? .distantPast) > ($1.lastActiveAt ?? .distantPast) }
            return out
        }

        let all = try await LeeoCloudPage.collect(
            query, in: database, limit: limit,
            transform: { UsageSnapshot($0) },
            onProgress: onProgress.map { report in { progress in report(progress.mapItems(arrange)) } }
        )
        return arrange(all)
    }
}
