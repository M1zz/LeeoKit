//
//  LeeoFeedbackService.swift
//  LeeoKit
//
//  앱 내 피드백/기능 요청을 CloudKit Public Database로 직접 제출한다.
//  메일 앱 없이도 동작하며, 개발자는 앱 내 인박스(LeeoFeedbackInboxView) 또는
//  CloudKit Dashboard에서 접수 내역을 확인한다.
//
//  ⚠️ CloudKit Dashboard 설정 필요 (앱별 1회):
//  - Public DB에 config.recordType 레코드 타입 (개발 환경에서 첫 저장 시 자동 생성)
//  - Security Roles: World에 create만 허용, read 권한 제거
//  - 인박스를 쓰려면 admin 역할에 read(+write) 권한과 개발자 userRecordName 등록
//  - 스키마를 Production으로 배포
//

import Foundation
import CloudKit
#if canImport(UIKit)
import UIKit
import UserNotifications
#endif
#if os(iOS)
import BackgroundTasks
#endif

public final class LeeoFeedbackService {
    public let config: LeeoFeedbackConfig
    private let appName: String

    public init(config: LeeoFeedbackConfig, appName: String) {
        self.config = config
        self.appName = appName
    }

    /// Spec 기반 편의 생성자 — 앱에서는 이걸 쓰면 된다.
    public convenience init<Spec: LeeoAppSpec>(spec: Spec.Type) {
        self.init(config: Spec.feedback, appName: Spec.appName)
    }

    public enum FeedbackError: LocalizedError {
        case iCloudUnavailable
        case saveFailed(Error)

        public var errorDescription: String? {
            switch self {
            case .iCloudUnavailable:
                return L("iCloud에 로그인되어 있지 않아요", comment: "Feedback error: iCloud unavailable")
            case .saveFailed:
                return L("전송에 실패했어요", comment: "Feedback error: save failed")
            }
        }
    }

    // MARK: - 개발자 인박스 (마스터 모드 전용)

    /// 접수된 피드백 한 건 (조회용 read model)
    public struct FeedbackRecord: Identifiable, Sendable {
        public let id: String
        public let type: String
        public let message: String
        public let deviceInfo: String
        public let appVersion: String
        public let locale: String
        public let platform: String
        /// 회신용 이름/이메일 (사용자가 남긴 경우에만 값 존재)
        public let contactName: String
        public let contactEmail: String
        /// 공용 허브 컨테이너에서 앱 구분값 (단일 앱 스키마에서는 nil)
        public let appId: String?
        /// 공용 허브에서 사람이 읽는 앱 이름 (단일 앱 스키마에서는 빈 문자열)
        public let appName: String
        public let createdAt: Date?
        /// 처리 상태 — "done"이면 완료 (개발자가 인박스에서 표시)
        public var status: String?

        public var isDone: Bool { status == "done" }

        public init(_ record: CKRecord) {
            self.id = record.recordID.recordName
            self.type = record["type"] as? String ?? "-"
            self.message = record["message"] as? String ?? ""
            self.deviceInfo = record["deviceInfo"] as? String ?? ""
            self.appVersion = record["appVersion"] as? String ?? ""
            self.locale = record["locale"] as? String ?? ""
            self.platform = record["platform"] as? String ?? ""
            self.contactName = record["contactName"] as? String ?? ""
            self.contactEmail = record["contactEmail"] as? String ?? ""
            self.appId = record["appId"] as? String
            self.appName = record["appName"] as? String ?? ""
            self.createdAt = record.creationDate
            self.status = record["status"] as? String
        }
    }

    /// 인박스 조회 쿼리 — TRUEPREDICATE라 Production에 recordName Queryable 인덱스가,
    /// 정렬에 createdTimestamp Sortable 인덱스가 배포되어 있어야 한다.
    /// 공용 허브에서도 서버 필터 대신 전체 조회 후 클라이언트에서 appId로 거른다
    /// (appId Queryable 인덱스 배포 없이 동작하게 하기 위함).
    public static func makeFetchQuery(config: LeeoFeedbackConfig) -> CKQuery {
        let query = CKQuery(recordType: config.recordType, predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        return query
    }

    /// 접수된 피드백 전체 조회 (최신순, 최대 limit개).
    /// ⚠️ 개발자 계정 전용 — CloudKit Dashboard에서 admin 역할에 read 권한과
    /// 본인 userRecordName을 등록해야 다른 사용자의 레코드를 읽을 수 있다.
    public func fetchAll(limit: Int = 100) async throws -> [FeedbackRecord] {
        let container = CKContainer(identifier: config.containerIdentifier)
        let query = Self.makeFetchQuery(config: config)

        let (results, _) = try await container.publicCloudDatabase.records(
            matching: query, resultsLimit: limit)
        var records = results.compactMap { _, result in
            (try? result.get()).map(FeedbackRecord.init)
        }
        if let appId = config.appIdentifier {
            records = records.filter { $0.appId == appId }
        }
        // 완료 상태는 로컬(이 기기)에서 관리한다 — 공개 DB에선 남이 만든 레코드를 수정할 수
        // 없어(WRITE not permitted) 서버 status 쓰기가 실패하기 때문. 서버에 남아있을 수 있는
        // 레거시 done(과거 쓰기 성공분)은 로컬로 한 번 흡수한 뒤, 이후엔 로컬을 단일 소스로 쓴다.
        var doneIDs = loadLocalDoneIDs()
        let legacyServerDone = records.filter { $0.status == "done" }.map(\.id)
        if !legacyServerDone.isEmpty {
            doneIDs.formUnion(legacyServerDone)
            saveLocalDoneIDs(doneIDs)
        }
        records = records.map { rec in
            var r = rec
            r.status = doneIDs.contains(r.id) ? "done" : nil
            return r
        }
        print("📬 [LeeoFeedbackService.fetchAll] 피드백 \(records.count)건 로드 (완료 \(doneIDs.count)건, 로컬)")
        return records
    }

    // MARK: - 완료 상태 로컬 저장

    /// 완료 표시를 저장할 UserDefaults 키 — 컨테이너·레코드타입·앱ID로 네임스페이스(허브 공유 대비).
    private var localDoneKey: String {
        "leeo.feedback.done.\(config.containerIdentifier).\(config.recordType).\(config.appIdentifier ?? "-")"
    }

    private func loadLocalDoneIDs() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: localDoneKey) ?? [])
    }

    private func saveLocalDoneIDs(_ ids: Set<String>) {
        UserDefaults.standard.set(Array(ids), forKey: localDoneKey)
    }

    /// 특정 피드백의 완료 여부(로컬 기준).
    public func isDoneLocally(recordName: String) -> Bool {
        loadLocalDoneIDs().contains(recordName)
    }

    /// 완료/미완료 표시를 이 기기 로컬에 저장한다(서버 쓰기 없음 → 권한 오류 없음).
    /// 개발자 한 명만 인박스를 쓰므로 로컬 저장으로 충분하다.
    public func setDoneLocal(recordName: String, done: Bool) {
        var ids = loadLocalDoneIDs()
        if done { ids.insert(recordName) } else { ids.remove(recordName) }
        saveLocalDoneIDs(ids)
        print("✅ [LeeoFeedbackService.setDoneLocal] \(recordName) → done=\(done) (로컬)")
    }

    /// 현재 iCloud 계정의 CloudKit userRecordName — Dashboard admin 역할 등록에 필요.
    public func currentUserRecordName() async -> String? {
        let container = CKContainer(identifier: config.containerIdentifier)
        return try? await container.userRecordID().recordName
    }

    /// 피드백 완료/미완료 표시 (서버 반영).
    /// ⚠️ 다른 사용자의 레코드 수정이라 admin 역할에 **Write** 권한이 필요하다.
    public func setDone(recordName: String, done: Bool) async throws {
        let db = CKContainer(identifier: config.containerIdentifier).publicCloudDatabase
        let record = try await db.record(for: CKRecord.ID(recordName: recordName))
        record["status"] = done ? "done" : nil
        _ = try await db.save(record)
        print("✅ [LeeoFeedbackService.setDone] \(recordName) → done=\(done)")
    }

    /// 피드백 삭제 (서버 반영). admin 역할 Write 권한 필요.
    public func delete(recordName: String) async throws {
        let db = CKContainer(identifier: config.containerIdentifier).publicCloudDatabase
        _ = try await db.deleteRecord(withID: CKRecord.ID(recordName: recordName))
        print("🗑️ [LeeoFeedbackService.delete] \(recordName) 삭제")
    }

    // MARK: - 새 피드백 알림: 오류 타입 (로컬/구독 공용)

    public enum NotificationError: LocalizedError {
        case permissionDenied(appName: String)

        public var errorDescription: String? {
            switch self {
            case .permissionDenied(let appName):
                return String(
                    format: L("알림 권한이 꺼져 있어요. iOS 설정 > %@ > 알림에서 허용해 주세요.",
                              comment: "Feedback notification permission denied"),
                    appName)
            }
        }
    }

    // MARK: - (레거시) CloudKit 구독 기반 실시간 푸시
    //
    // ⚠️ public DB의 CKQuerySubscription은 **Production 컨테이너에서 생성이 거부**된다
    //    ("attempting to create a subscription in a production container"). 그래서 아래
    //    구독 방식은 개발 환경에서만 동작하며, 배포 빌드에서는 쓸 수 없다. 배포 빌드에서는
    //    아래 "로컬 알림(백그라운드 새로고침)" 방식을 사용한다.

    /// 새 피드백 푸시 알림 구독 여부 (서버 기준 — 재설치해도 유지).
    @available(*, deprecated, message: "Production public DB는 구독 생성을 거부한다. isLocalNotifyEnabled를 사용하라.")
    public func isNewFeedbackNotificationEnabled() async -> Bool {
        let db = CKContainer(identifier: config.containerIdentifier).publicCloudDatabase
        let sub = try? await db.subscription(for: config.subscriptionID)
        return sub != nil
    }

    /// 새 피드백 푸시 알림 켜기 — 알림 권한 요청 + APNs 등록 + CKQuerySubscription 저장.
    /// ⚠️ 구독이 발화하려면 이 계정이 피드백 레코드를 읽을 수 있어야 한다 (admin 역할 read).
    @available(*, deprecated, message: "Production public DB는 구독 생성을 거부한다. enableLocalNewFeedbackNotifications()를 사용하라.")
    public func enableNewFeedbackNotifications() async throws {
        #if canImport(UIKit)
        let granted = try await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound])
        guard granted else { throw NotificationError.permissionDenied(appName: appName) }
        await MainActor.run {
            UIApplication.shared.registerForRemoteNotifications()
        }
        #endif

        let subscription = CKQuerySubscription(
            recordType: config.recordType,
            predicate: NSPredicate(value: true),
            subscriptionID: config.subscriptionID,
            options: .firesOnRecordCreation
        )
        let info = CKSubscription.NotificationInfo()
        info.title = L("새 피드백이 도착했어요 📬", comment: "New feedback push title")
        info.alertBody = L("사용자가 의견을 남겼어요. 인박스에서 확인해 보세요.", comment: "New feedback push body")
        info.soundName = "default"
        subscription.notificationInfo = info

        let db = CKContainer(identifier: config.containerIdentifier).publicCloudDatabase
        _ = try await db.save(subscription)
        print("🔔 [LeeoFeedbackService.enableNewFeedbackNotifications] 구독 등록 완료")
    }

    /// 새 피드백 푸시 알림 끄기 — 구독 삭제.
    @available(*, deprecated, message: "disableLocalNewFeedbackNotifications()를 사용하라.")
    public func disableNewFeedbackNotifications() async throws {
        let db = CKContainer(identifier: config.containerIdentifier).publicCloudDatabase
        _ = try await db.deleteSubscription(withID: config.subscriptionID)
        print("🔕 [LeeoFeedbackService.disableNewFeedbackNotifications] 구독 해제 완료")
    }

    // MARK: - 새 피드백 로컬 알림 (백그라운드 새로고침 기반)
    //
    // 구독(CKQuerySubscription)이 Production public DB에서 막히므로, 서버 푸시 대신
    // BGAppRefreshTask로 앱을 주기적으로 깨워 새 피드백을 조회하고, 마지막으로 본 시각
    // 이후 새로 들어온 게 있으면 UNUserNotification(로컬 알림)으로 알린다.
    //
    // 실시간은 아니다 — iOS가 사용 패턴에 따라 백그라운드 실행을 스케줄한다. 앱을 열 때
    // (포그라운드)도 checkForNewFeedbackAndNotify()를 호출해 보완할 수 있다.
    //
    // 호스트 앱 설정 (앱별 1회):
    //  - Info.plist BGTaskSchedulerPermittedIdentifiers 배열에 backgroundRefreshTaskIdentifier 추가
    //  - Background Modes 사용(Background fetch) — Info.plist UIBackgroundModes에 "fetch"
    //  - 앱 시작 시 .backgroundTask(.appRefresh(...)) 로 핸들러 등록 후 scheduleBackgroundRefresh() 호출

    /// 백그라운드 새로고침 작업 식별자 — 호스트 앱 Info.plist의
    /// BGTaskSchedulerPermittedIdentifiers 및 .backgroundTask(.appRefresh(...)) 등록에 이 값을 쓴다.
    public static let backgroundRefreshTaskIdentifier = "com.leeokit.feedback.refresh"

    /// 로컬 알림 켜짐 여부를 저장할 UserDefaults 키.
    private var notifyEnabledKey: String {
        "leeo.feedback.notify.enabled.\(config.containerIdentifier).\(config.recordType).\(config.appIdentifier ?? "-")"
    }

    /// 마지막으로 확인한(=이미 알림을 보냈거나 인박스에서 본) 최신 피드백 생성 시각 저장 키.
    private var lastSeenKey: String {
        "leeo.feedback.notify.lastSeen.\(config.containerIdentifier).\(config.recordType).\(config.appIdentifier ?? "-")"
    }

    private func loadLastSeenDate() -> Date {
        let t = UserDefaults.standard.double(forKey: lastSeenKey)
        return t > 0 ? Date(timeIntervalSince1970: t) : .distantPast
    }

    private func saveLastSeenDate(_ date: Date) {
        UserDefaults.standard.set(date.timeIntervalSince1970, forKey: lastSeenKey)
    }

    /// 새 피드백 로컬 알림 켜짐 여부 (이 기기 기준).
    public var isLocalNotifyEnabled: Bool {
        UserDefaults.standard.bool(forKey: notifyEnabledKey)
    }

    /// 새 피드백 로컬 알림 켜기 — 알림 권한 요청 + 기준 시각을 '지금'으로 저장 + 백그라운드 새로고침 예약.
    /// 켠 순간 이후에 접수되는 피드백만 알림 대상이 된다(기존 밀린 피드백으로 폭탄 알림 방지).
    public func enableLocalNewFeedbackNotifications() async throws {
        #if canImport(UIKit)
        let granted = try await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])
        guard granted else { throw NotificationError.permissionDenied(appName: appName) }
        #endif
        saveLastSeenDate(Date())
        UserDefaults.standard.set(true, forKey: notifyEnabledKey)
        scheduleBackgroundRefresh()
        print("🔔 [LeeoFeedbackService] 로컬 새 피드백 알림 켜짐")
    }

    /// 새 피드백 로컬 알림 끄기 — 플래그 해제 + 예약된 백그라운드 작업 취소.
    public func disableLocalNewFeedbackNotifications() {
        UserDefaults.standard.set(false, forKey: notifyEnabledKey)
        #if os(iOS)
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.backgroundRefreshTaskIdentifier)
        #endif
        print("🔕 [LeeoFeedbackService] 로컬 새 피드백 알림 꺼짐")
    }

    /// 새 피드백을 조회해 마지막 확인 시각 이후 접수된 게 있으면 로컬 알림을 발송한다.
    /// 백그라운드 작업 핸들러와 포그라운드 진입 모두에서 호출한다. 반환값은 새로 발견한 건수.
    /// 알림이 꺼져 있으면 아무 것도 하지 않고 0을 반환한다.
    @discardableResult
    public func checkForNewFeedbackAndNotify() async -> Int {
        guard isLocalNotifyEnabled else { return 0 }

        let records: [FeedbackRecord]
        do {
            records = try await fetchAll()
        } catch {
            print("⚠️ [LeeoFeedbackService.checkForNewFeedbackAndNotify] 조회 실패: \(error)")
            return 0
        }

        let lastSeen = loadLastSeenDate()
        let fresh = records.filter { rec in
            guard let created = rec.createdAt else { return false }
            return created > lastSeen && !rec.isDone
        }
        guard !fresh.isEmpty else { return 0 }

        // 기준 시각을 새로 발견한 것들 중 가장 최신으로 올려, 다음 확인 때 중복 알림을 막는다.
        if let newest = fresh.compactMap(\.createdAt).max() {
            saveLastSeenDate(newest)
        }
        #if canImport(UIKit)
        await postLocalNotification(count: fresh.count)
        #endif
        print("📬 [LeeoFeedbackService.checkForNewFeedbackAndNotify] 새 피드백 \(fresh.count)건 → 로컬 알림")
        return fresh.count
    }

    /// 현재 화면에 보이는 피드백을 모두 '확인함'으로 처리 — 인박스 진입 시 호출해
    /// 이미 본 피드백으로 다시 알림이 오지 않게 한다.
    public func markAllFeedbackSeen(_ records: [FeedbackRecord]) {
        guard isLocalNotifyEnabled else { return }
        if let newest = records.compactMap(\.createdAt).max() {
            let current = loadLastSeenDate()
            if newest > current { saveLastSeenDate(newest) }
        }
        #if canImport(UIKit)
        Task { @MainActor in
            UNUserNotificationCenter.current().setBadgeCount(0)
        }
        #endif
    }

    /// 다음 백그라운드 새로고침을 예약한다 (iOS/Catalyst). 알림이 꺼져 있으면 예약하지 않는다.
    public func scheduleBackgroundRefresh(earliestAfter seconds: TimeInterval = 3600) {
        guard isLocalNotifyEnabled else { return }
        #if os(iOS)
        let request = BGAppRefreshTaskRequest(identifier: Self.backgroundRefreshTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: seconds)
        do {
            try BGTaskScheduler.shared.submit(request)
            print("⏰ [LeeoFeedbackService] 백그라운드 새로고침 예약 (\(Int(seconds))s 후)")
        } catch {
            print("⚠️ [LeeoFeedbackService] 백그라운드 새로고침 예약 실패: \(error)")
        }
        #endif
    }

    #if canImport(UIKit)
    /// 새 피드백 로컬 알림 즉시 발송.
    private func postLocalNotification(count: Int) async {
        let content = UNMutableNotificationContent()
        content.title = L("새 피드백이 도착했어요 📬", comment: "New feedback push title")
        content.body = count <= 1
            ? L("사용자가 의견을 남겼어요. 인박스에서 확인해 보세요.", comment: "New feedback push body")
            : String(format: L("새 피드백 %d건이 접수됐어요. 인박스에서 확인해 보세요.",
                               comment: "New feedback push body plural"), count)
        content.sound = .default
        content.badge = NSNumber(value: count)
        let request = UNNotificationRequest(
            identifier: UUID().uuidString, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }
    #endif

    // MARK: - 제출

    /// 제출용 CKRecord 구성 — 필드 키는 Dashboard 스키마·FeedbackRecord 읽기 모델과 1:1 대응.
    /// contactName/contactEmail은 비어 있으면 필드 자체를 쓰지 않는다 —
    /// 해당 필드가 없는 기존 Production 스키마(클립키보드 등)와의 호환 유지.
    public static func makeRecord(
        config: LeeoFeedbackConfig, type: String, message: String, deviceInfo: String,
        contactName: String = "", contactEmail: String = "", appName: String = ""
    ) -> CKRecord {
        let record = CKRecord(recordType: config.recordType)
        record["type"] = type
        record["message"] = message
        record["deviceInfo"] = deviceInfo
        if !contactName.isEmpty { record["contactName"] = contactName }
        if !contactEmail.isEmpty { record["contactEmail"] = contactEmail }
        record["appVersion"] = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"
        record["locale"] = Locale.current.identifier
        record["platform"] = {
            #if targetEnvironment(macCatalyst)
            return "macCatalyst"
            #else
            return "iOS"
            #endif
        }()
        // 허브 모드(appIdentifier 지정)에서만 앱 구분값을 쓴다 — 기계용 appId와
        // 사람이 읽는 appName을 함께 남겨, 공용 허브 뷰어가 프로젝트별로 묶을 수 있게 한다.
        // 단일 앱 스키마(appIdentifier == nil)에는 두 필드 모두 쓰지 않아 100% 호환.
        if let appId = config.appIdentifier {
            record["appId"] = appId
            if !appName.isEmpty { record["appName"] = appName }
        }
        return record
    }

    /// 피드백을 Public DB에 제출한다. 실패 시 throw — 호출부에서 이메일 폴백 처리.
    public func submit(
        type: String, message: String, deviceInfo: String,
        contactName: String = "", contactEmail: String = ""
    ) async throws {
        let container = CKContainer(identifier: config.containerIdentifier)

        // Public DB 쓰기도 iCloud 로그인이 필요하다.
        let status = try await container.accountStatus()
        guard status == .available else {
            print("⚠️ [LeeoFeedbackService.submit] iCloud 계정 없음: \(status)")
            throw FeedbackError.iCloudUnavailable
        }

        let record = Self.makeRecord(
            config: config, type: type, message: message, deviceInfo: deviceInfo,
            contactName: contactName, contactEmail: contactEmail, appName: appName)

        do {
            _ = try await container.publicCloudDatabase.save(record)
            print("✅ [LeeoFeedbackService.submit] 피드백 제출 완료 (type=\(type))")
        } catch {
            print("❌ [LeeoFeedbackService.submit] 제출 실패: \(error)")
            throw FeedbackError.saveFailed(error)
        }
    }
}

// MARK: - 패키지 다국어 헬퍼

/// 패키지 리소스 번들에서 문자열을 찾는다 (LeeoKit 내부 공용).
func L(_ key: String, comment: String) -> String {
    NSLocalizedString(key, bundle: .module, comment: comment)
}
