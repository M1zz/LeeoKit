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
//  `app_open` 은 앱이 보내지 않아도 된다 (v3.12). `report()` 를 부르거나
//  `LeeoKit.bootstrap` 을 쓰면 하루 한 번 알아서 나간다. 앱이 직접 보내도 같은 관문을
//  지나므로 하루 두 번 세지 않는다. 자세한 것은 아래 "하루 한 번 app_open" 절.
//

import Foundation
import CloudKit
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

public final class LeeoUsageReporter: @unchecked Sendable {
    public let config: LeeoFeedbackConfig
    private let appName: String

    /// `report()` 와 앱 활성화 감시가 `app_open` 을 하루 한 번 알아서 보낼지.
    /// 꺼도 앱이 직접 보내는 `app_open` 은 여전히 하루 한 번 관문을 지난다.
    public let sendsDailyAppOpen: Bool

    /// 설치 ID·쓰로틀 도장이 사는 곳. 기본은 `.standard`.
    /// 테스트가 표준 저장소를 더럽히지 않게 바꿔 끼울 수 있게만 열어 둔다.
    private let defaults: UserDefaults

    /// CloudKit 레코드 타입 이름.
    public static let snapshotType = "UsageSnapshot"
    public static let eventType = "UsageEvent"

    /// 허브가 "그날 앱을 열었다"로 읽는 이벤트 이름. 모든 앱이 같은 말을 써야 허브가 알아본다.
    public static let appOpenEvent = "app_open"

    /// - Parameter sendsDailyAppOpen: `app_open` 자동 전송 여부. 기본 켬.
    public init(config: LeeoFeedbackConfig, appName: String,
                sendsDailyAppOpen: Bool = true,
                defaults: UserDefaults = .standard) {
        self.config = config
        self.appName = appName
        self.sendsDailyAppOpen = sendsDailyAppOpen
        self.defaults = defaults
    }

    /// Spec 기반 편의 생성자 — 앱에서는 이걸 쓰면 된다(피드백과 같은 컨테이너·appId 재사용).
    /// `app_open` 자동 전송은 `Spec.sendsDailyAppOpen` 을 따른다.
    public convenience init<Spec: LeeoAppSpec>(spec: Spec.Type) {
        self.init(config: Spec.feedback, appName: Spec.appName,
                  sendsDailyAppOpen: Spec.sendsDailyAppOpen)
    }

    // MARK: - 익명 설치 ID (PII 아님, 재설치 전까지 고정)

    private static let installIDKey = "leeo.usage.installID"

    /// 이 설치를 가리키는 익명 UUID. 기기·계정과 무관하고, 재설치하면 새로 생긴다.
    /// 앱이 직접 이벤트 레코드를 만들 때(예: 소급 백필) 같은 설치로 묶으려면 이 값이 필요하다.
    public var installID: String {
        let d = defaults
        if let s = d.string(forKey: Self.installIDKey) { return s }
        let s = UUID().uuidString
        d.set(s, forKey: Self.installIDKey)
        return s
    }

    private var lastSnapshotKey: String {
        "leeo.usage.lastSnapshotAt.\(config.containerIdentifier).\(config.appIdentifier ?? "-")"
    }

    /// 마지막으로 `app_open` 을 보낸(보내려고 잡은) 시각. 컨테이너·앱마다 따로 둔다.
    var lastAppOpenKey: String {
        "leeo.usage.lastAppOpenAt.\(config.containerIdentifier).\(config.appIdentifier ?? "-")"
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
    ///
    /// `sendsDailyAppOpen` 이 켜져 있으면 스냅샷 쓰로틀과 **상관없이** 오늘 몫의 `app_open` 도
    /// 함께 보낸다(하루 한 번). `report()` 는 앱이 화면에 올라올 때 부르는 자리이므로
    /// "그날 앱을 열었다"의 가장 흔한 신호다. 앱이 아무 이벤트도 안 보내는 날에도 허브의
    /// DAU·잔존에 잡히게 하려는 것이다.
    /// 백그라운드 실행에서 불리면 `app_open` 은 보내지 않고, 앱이 앞으로 올 때로 미룬다.
    public func report(
        engagement: LeeoEngagement = .shared,
        metrics: [String: Double] = [:],
        minInterval: TimeInterval = 12 * 3600
    ) async {
        await report(engagement: engagement, metrics: metrics, minInterval: minInterval,
                     includeDailyAppOpen: sendsDailyAppOpen)
    }

    /// 부트스트랩은 앱 `init()` 에서 부르고, 그 시점은 백그라운드 실행일 수도 있다.
    /// 그래서 부트스트랩만은 `app_open` 을 여기서 빼고 활성화 알림(`observeAppActivation`)에 맡긴다.
    func report(
        engagement: LeeoEngagement,
        metrics: [String: Double],
        minInterval: TimeInterval,
        includeDailyAppOpen: Bool
    ) async {
        if includeDailyAppOpen {
            // ⚠️ 백그라운드 실행(백그라운드 새로고침 · 조용한 푸시)에서도 이 길을 부르는 앱이 있다
            //    (클립키보드는 프로세스가 뜰 때마다 부른다). 그때 보내면 연 적 없는 날이
            //    "연 날"로 찍힌다. 앞에 떠 있을 때만 지금 보내고, 아니면 다음에 앞으로 올 때
            //    (`observeAppActivation`) 보낸다.
            observeAppActivation()
            if await Self.isAppInForeground() {
                await logDailyAppOpenIfNeeded()
            }
        }
        let now = Date()
        if let last = defaults.object(forKey: lastSnapshotKey) as? Date,
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
            defaults.set(now, forKey: lastSnapshotKey)
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
    ///
    /// ⚠️ 이름이 `app_open` 이면 하루 한 번 관문을 지난다(자동 전송과 같은 도장).
    ///    오늘 이미 나갔으면 보내지 않고 true 를 돌려준다. 자세한 것은 `logDailyAppOpenIfNeeded`.
    @discardableResult
    public func logEvent(_ name: String, occurredAt: Date? = nil) async -> Bool {
        if name == Self.appOpenEvent {
            return await logDailyAppOpen(occurredAt: occurredAt, now: Date())
        }
        return await send(name, occurredAt: occurredAt)
    }

    /// 관문 없이 곧장 보낸다. 모든 이벤트가 결국 여기로 온다.
    private func send(_ name: String, occurredAt: Date?) async -> Bool {
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

    // MARK: - 하루 한 번 app_open

    /// `app_open` 도장을 찍고 푸는 일을 한 줄로 세운다. 리포터는 쓰고 버리는 값이라
    /// (앱마다 `LeeoUsageReporter(spec:)` 를 그때그때 만든다) 인스턴스 락으로는 못 막는다.
    private static let appOpenLock = NSLock()

    /// 오늘 `app_open` 을 보내야 하는가. **순수 함수** (시각·달력을 밖에서 넣는다).
    ///
    /// 24시간 간격이 아니라 **달력 날짜**로 자른다. 허브는 "그날 이벤트가 하나라도
    /// 있었는가"로 DAU·잔존을 세기 때문에, 밤 11시와 다음 날 아침 8시는 둘 다 보내야 하고
    /// 새벽 2시와 오후 2시는 한 번이면 된다.
    /// 마지막 도장이 미래 날짜(시계를 되돌린 기기)여도 "다른 날"이므로 보낸다. 하루
    /// 한 건 더 나가는 쪽이, 시계가 따라잡을 때까지 며칠을 통째로 잃는 쪽보다 낫다.
    public static func shouldSendDailyAppOpen(lastSent: Date?, now: Date,
                                              calendar: Calendar = .current) -> Bool {
        guard let lastSent else { return true }
        return !calendar.isDate(lastSent, inSameDayAs: now)
    }

    /// 오늘 몫을 잡는다. 잡았으면 도장을 먼저 찍고 true.
    ///
    /// 보내기 **전에** 찍는 이유: 콜드 런치에서는 `report()` 와 활성화 알림, 앱의 수동 호출이
    /// 거의 동시에 들어온다. 보낸 뒤에 찍으면 셋 다 관문을 통과해 같은 날 세 건이 된다.
    /// 대신 전송이 실패하면 `releaseDailyAppOpen` 으로 되돌려 다음 활성화에 다시 시도한다.
    func claimDailyAppOpen(now: Date, calendar: Calendar = .current) -> (claimed: Bool, previous: Date?) {
        Self.appOpenLock.lock(); defer { Self.appOpenLock.unlock() }
        let last = defaults.object(forKey: lastAppOpenKey) as? Date
        guard Self.shouldSendDailyAppOpen(lastSent: last, now: now, calendar: calendar) else {
            return (false, last)
        }
        defaults.set(now, forKey: lastAppOpenKey)
        return (true, last)
    }

    /// 잡아 둔 오늘 몫을 되돌린다. 그 사이 다른 호출이 새 도장을 찍었으면 건드리지 않는다.
    func releaseDailyAppOpen(claimedAt now: Date, previous: Date?) {
        Self.appOpenLock.lock(); defer { Self.appOpenLock.unlock() }
        guard (defaults.object(forKey: lastAppOpenKey) as? Date) == now else { return }
        if let previous {
            defaults.set(previous, forKey: lastAppOpenKey)
        } else {
            defaults.removeObject(forKey: lastAppOpenKey)
        }
    }

    /// 오늘 아직 안 보냈으면 `app_open` 을 보낸다. 앱이 직접 부를 일은 거의 없다
    /// (`report()` 와 `LeeoKit.bootstrap` 이 부른다). `sendsDailyAppOpen` 이 꺼져 있으면 아무것도 안 한다.
    ///
    /// 앱이 `logEvent("app_open")` 을 따로 불러도 **같은 도장**을 보므로 하루 두 건이 되지 않는다.
    /// 앱 쪽에 이미 있는 하루 한 번 쓰로틀(각자 다른 키)은 그대로 두어도 된다: 관문이 둘이면
    /// 더 적게 나갈 수는 있어도 더 많이 나가지는 않는다.
    /// - Returns: 오늘 몫이 허브에 있는지(이번에 보냈거나 이미 보냈으면 true).
    @discardableResult
    public func logDailyAppOpenIfNeeded() async -> Bool {
        guard sendsDailyAppOpen else { return false }
        return await logDailyAppOpen(occurredAt: nil, now: Date())
    }

    public func logDailyAppOpenIfNeededInBackground() {
        Task { await logDailyAppOpenIfNeeded() }
    }

    /// 관문은 언제나 **지금**의 날짜로 판정한다. 지난 날짜의 `occurredAt` 으로 `app_open` 을
    /// 보내는 소급은 그대로 기록되지만 오늘 몫으로 친다(그런 호출을 하는 앱은 아직 없다).
    private func logDailyAppOpen(occurredAt: Date?, now: Date) async -> Bool {
        let claim = claimDailyAppOpen(now: now)
        guard claim.claimed else { return true }
        let sent = await send(Self.appOpenEvent, occurredAt: occurredAt)
        if !sent {
            releaseDailyAppOpen(claimedAt: now, previous: claim.previous)
        }
        return sent
    }

    // MARK: - 앱 활성화 감시

    /// 앱이 지금 앞에 떠 있는가(활성 · 막 뜨는 중). 백그라운드 실행이면 false.
    ///
    /// 익스텐션에서는 `UIApplication.shared` 를 쓸 수 없어서 이름으로 찾는다. 익스텐션에는
    /// 공유 앱 객체가 없으므로 nil 이 오고, 그때는 false(익스텐션은 "앱을 연 날"이 아니다).
    static func isAppInForeground() async -> Bool {
        #if canImport(UIKit)
        return await MainActor.run {
            guard let app = UIApplication.value(forKey: "sharedApplication") as? UIApplication else {
                return false
            }
            return app.applicationState != .background
        }
        #else
        return true
        #endif
    }

    private static let observerLock = NSLock()
    nonisolated(unsafe) private static var observers: [String: NSObjectProtocol] = [:]

    /// 앱이 앞으로 올 때마다 오늘 몫의 `app_open` 을 확인한다. 같은 컨테이너·앱에는 한 번만 걸린다.
    ///
    /// 왜 필요한가: 사람들은 앱을 며칠씩 종료하지 않는다. 런치 때만 보내면 그 며칠이
    /// 허브에서 통째로 빈 날이 된다. 활성화 알림은 날이 바뀐 뒤 돌아온 순간을 잡는다.
    /// 콜드 런치의 첫 활성화도 이 알림으로 오므로, 앱 `init()` 에서 걸어 두면 런치도 함께 잡힌다.
    ///
    /// `LeeoKit.bootstrap` 이 사용 통계를 켤 때 대신 부른다. 직접 쓰는 앱은 사용자가 통계를
    /// 끌 수 있다면 켜져 있을 때만 부를 것(걸어 둔 감시는 이 프로세스가 끝날 때까지 산다).
    /// `sendsDailyAppOpen` 이 꺼져 있으면 걸지 않는다.
    ///
    /// 익스텐션에서 불러도 컴파일·실행에 문제는 없다(`UIApplication.shared` 를 쓰지 않는다).
    /// 다만 익스텐션에는 이 알림이 오지 않으므로 아무 일도 일어나지 않는다.
    public func observeAppActivation() {
        guard sendsDailyAppOpen else { return }
        #if canImport(UIKit)
        let name = UIApplication.didBecomeActiveNotification
        #elseif canImport(AppKit)
        let name = NSApplication.didBecomeActiveNotification
        #else
        return
        #endif
        #if canImport(UIKit) || canImport(AppKit)
        let key = lastAppOpenKey
        Self.observerLock.lock(); defer { Self.observerLock.unlock() }
        guard Self.observers[key] == nil else { return }
        Self.observers[key] = NotificationCenter.default.addObserver(
            forName: name, object: nil, queue: nil
        ) { [self] _ in
            self.logDailyAppOpenIfNeededInBackground()
        }
        #endif
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
