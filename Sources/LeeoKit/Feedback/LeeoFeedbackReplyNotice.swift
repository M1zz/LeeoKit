//
//  LeeoFeedbackReplyNotice.swift
//  LeeoKit
//
//  답장이 왔다는 것을 **사용자가 알게** 하는 길. 답장은 설정 > 보낸 의견에만 있어서, 설정에
//  들어가지 않는 사람은 답장이 와도 몰랐다. 두 가지를 더한다.
//
//   1. 앱 안 알림 — 앱이 앞으로 올 때마다(10분에 한 번까지) 답장을 읽고, 안 읽은 답장이 있으면
//      보낸 의견 화면을 시트로 띄운다. 알림 권한이 필요 없다.
//
//          WindowGroup {
//              ContentView()
//                  .leeoFeedbackReplyNotice(MyAppSpec.self)
//          }
//
//   2. 로컬 알림 — 앱이 뒤로 갈 때 백그라운드 새로고침을 예약하고, iOS 가 앱을 깨우면 답장을
//      읽어 새 답장이 있으면 알림을 띄운다. **이미 알림을 허락한 앱에서만** 보낸다. 답장 때문에
//      권한을 새로 묻지 않는다. iOS 만.
//
//          WindowGroup { … }
//              .leeoFeedbackReplyRefresh(MyAppSpec.self)
//
//      호스트 앱 Info.plist (앱별 1회):
//       - BGTaskSchedulerPermittedIdentifiers 에 `com.leeokit.feedback.replies`
//       - UIBackgroundModes 에 `fetch`
//      빠뜨려도 앱은 그대로다 — 예약이 실패할 뿐이고, 1번은 계속 동작한다.
//
//  ⚠️ 보낸 의견이 없는 기기는 네트워크를 쓰지 않는다(`refreshReplies` 가 장부부터 본다).
//  ⚠️ 같은 답장으로 두 번 알리지 않는다. 답장 글이 바뀌면(개발자가 고치면) 다시 한 번.
//

// watchOS 에는 없다 — 답장 시트는 iPhone 에서.
#if !os(watchOS)
import SwiftUI
#if canImport(UserNotifications)
import UserNotifications
#endif
#if os(iOS)
import BackgroundTasks
#endif

// MARK: - 알림 규칙 (순수 함수 — 시험이 여기를 본다)

public enum LeeoReplyNoticePolicy {

    /// 앞으로 올 때마다 서버를 읽지 않게 — 이만큼 지나야 다시 읽는다.
    public static let foregroundInterval: TimeInterval = 10 * 60

    /// 백그라운드 새로고침을 이보다 이르게 청하지 않는다. 실제 시각은 iOS 가 정한다.
    public static let backgroundInterval: TimeInterval = 4 * 3600

    /// 앱 안 시트를 띄울 답장 — 설정의 배지와 같은 기준(안 읽음). 로컬 알림을 보냈는지는 보지 않는다.
    public static func presentable(_ list: [LeeoSentFeedback]) -> [LeeoSentFeedback] {
        list.filter(\.hasUnreadReply)
    }

    /// 로컬 알림을 보낼 답장 — 아직 알리지 않은 안 읽은 답장. `notified` 는 피드백 id → 알린 답장 글.
    public static func unnotified(_ list: [LeeoSentFeedback],
                                  notified: [String: String]) -> [LeeoSentFeedback] {
        list.filter { item in
            guard item.hasUnreadReply, let reply = item.reply else { return false }
            return notified[item.id] != reply
        }
    }

    /// 다시 읽을 때가 됐나.
    public static func isDue(lastCheck: Date?, now: Date = Date(),
                             interval: TimeInterval = foregroundInterval) -> Bool {
        guard let lastCheck else { return true }
        return now.timeIntervalSince(lastCheck) >= interval
    }
}

// MARK: - 서비스

extension LeeoFeedbackService {

    /// 답장 확인용 백그라운드 새로고침 식별자 — 호스트 앱 Info.plist 의
    /// BGTaskSchedulerPermittedIdentifiers 에 이 값을 넣는다.
    public static let replyRefreshTaskIdentifier = "com.leeokit.feedback.replies"

    private var notifiedRepliesKey: String {
        "leeo.feedback.replies.notified.\(config.containerIdentifier).\(config.recordType).\(config.appIdentifier ?? "-")"
    }

    private var notifiedReplies: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: notifiedRepliesKey) as? [String: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: notifiedRepliesKey) }
    }

    /// 알린 것으로 적는다 — 앱 안 시트로 보였든 로컬 알림으로 보냈든.
    func markRepliesNotified(_ items: [LeeoSentFeedback]) {
        guard !items.isEmpty else { return }
        var next = notifiedReplies
        for item in items { next[item.id] = item.reply }
        notifiedReplies = next
    }

    /// 답장을 읽고, 아직 알리지 않은 새 답장을 돌려준다(알린 것으로 적지는 않는다).
    func freshReplies() async -> [LeeoSentFeedback] {
        await refreshReplies()
        return LeeoReplyNoticePolicy.unnotified(sentFeedback, notified: notifiedReplies)
    }

    #if canImport(UserNotifications) && !os(watchOS)
    /// 이미 허락한 알림인가. 답장 때문에 권한을 새로 묻지 않는다.
    static func allowsReplyNotifications(_ status: UNAuthorizationStatus) -> Bool {
        #if os(iOS)
        return status == .authorized || status == .provisional || status == .ephemeral
        #else
        return status == .authorized || status == .provisional
        #endif
    }
    #endif

    /// 백그라운드에서 — 답장을 읽어 새 답장이 있으면 로컬 알림. 알림을 이미 허락한 경우에만
    /// 보낸다. 반환값은 알린 답장 수.
    @discardableResult
    public func checkRepliesAndNotify() async -> Int {
        #if canImport(UserNotifications) && !os(watchOS)
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard Self.allowsReplyNotifications(settings.authorizationStatus) else { return 0 }

        let fresh = await freshReplies()
        guard !fresh.isEmpty else { return 0 }

        let content = UNMutableNotificationContent()
        content.title = L("개발자가 답장을 보냈어요", comment: "Feedback reply notification title")
        content.body = fresh.count == 1
            ? (fresh[0].reply ?? "")
            : String(format: L("보낸 의견에 답장 %d개가 왔어요. 앱을 열어 확인해 보세요.",
                               comment: "Feedback reply notification body plural"), fresh.count)
        content.sound = .default
        content.threadIdentifier = Self.replyRefreshTaskIdentifier
        let request = UNNotificationRequest(identifier: "leeo.reply.\(fresh[0].id)", content: content, trigger: nil)
        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            return 0
        }
        markRepliesNotified(fresh)
        return fresh.count
        #else
        return 0
        #endif
    }

    /// 답장 확인 백그라운드 새로고침을 예약한다. 답장을 기다리는 의견이 없거나 알림을 허락하지
    /// 않았으면 예약하지 않는다.
    public func scheduleReplyRefresh(earliestAfter seconds: TimeInterval = LeeoReplyNoticePolicy.backgroundInterval) async {
        #if os(iOS)
        guard !LeeoFeedbackLedger.lookupIDs(in: sentFeedback).isEmpty else { return }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard Self.allowsReplyNotifications(settings.authorizationStatus) else { return }
        let request = BGAppRefreshTaskRequest(identifier: Self.replyRefreshTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: seconds)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Info.plist 에 식별자가 없으면 여기로 온다. 앱 안 알림(1번)은 그대로 동작한다.
            print("⚠️ [LeeoFeedbackService.scheduleReplyRefresh] 예약 실패(Info.plist 확인): \(error)")
        }
        #endif
    }
}

// MARK: - 1. 앱 안 알림

private struct LeeoFeedbackReplyNoticeModifier<Spec: LeeoAppSpec>: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @State private var isPresented = false

    /// 창이 여럿이어도 한 번만 읽게 — 실행 동안 기억한다.
    @MainActor private static var lastCheck: Date? {
        get { LeeoReplyNoticeClock.lastCheck }
        set { LeeoReplyNoticeClock.lastCheck = newValue }
    }

    func body(content: Content) -> some View {
        content
            .task { await check() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await check() } }
                #if os(iOS)
                if phase == .background {
                    Task { await LeeoFeedbackService(spec: Spec.self).scheduleReplyRefresh() }
                }
                #endif
            }
            .sheet(isPresented: $isPresented) {
                NavigationStack {
                    LeeoFeedbackRepliesView<Spec>()
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button(L("닫기", comment: "Close")) { isPresented = false }
                            }
                        }
                }
            }
    }

    @MainActor
    private func check() async {
        guard !isPresented else { return }
        let service = LeeoFeedbackService(spec: Spec.self)
        guard !service.sentFeedback.isEmpty else { return }
        // 서버는 10분에 한 번만 읽는다. 장부에 이미 있는 안 읽은 답장은 그때마다 본다.
        if LeeoReplyNoticePolicy.isDue(lastCheck: Self.lastCheck) {
            Self.lastCheck = Date()
            await service.refreshReplies()
        }
        // 설정의 배지와 같은 기준 — 안 읽은 답장이 있으면 뜬다. 로컬 알림으로 이미 알렸어도
        // (알림을 안 누르고 앱을 열었으면) 뜬다. 시트 안에서 읽음으로 적히니 되풀이되지 않는다.
        let unread = LeeoReplyNoticePolicy.presentable(service.sentFeedback)
        guard !unread.isEmpty, !isPresented else { return }
        service.markRepliesNotified(unread)
        isPresented = true
    }
}

@MainActor
private enum LeeoReplyNoticeClock {
    static var lastCheck: Date?
}

public extension View {
    /// 보낸 의견에 새 답장이 오면, 앱이 앞으로 올 때 보낸 의견 화면을 시트로 띄운다.
    /// iOS 에서는 앱이 뒤로 갈 때 답장 확인 백그라운드 새로고침도 예약한다
    /// (`leeoFeedbackReplyRefresh` 를 Scene 에 함께 달아야 실제로 돈다).
    func leeoFeedbackReplyNotice<Spec: LeeoAppSpec>(_ spec: Spec.Type) -> some View {
        modifier(LeeoFeedbackReplyNoticeModifier<Spec>())
    }
}

// MARK: - 2. 백그라운드 새로고침 → 로컬 알림

public extension Scene {
    /// iOS 가 앱을 깨우면 답장을 읽어 새 답장을 로컬 알림으로 알린다. iOS 외에서는 아무 일도 하지 않는다.
    @available(iOSApplicationExtension, unavailable)
    func leeoFeedbackReplyRefresh<Spec: LeeoAppSpec>(_ spec: Spec.Type) -> some Scene {
        #if os(iOS)
        return backgroundTask(.appRefresh(LeeoFeedbackService.replyRefreshTaskIdentifier)) {
            let service = LeeoFeedbackService(spec: Spec.self)
            await service.checkRepliesAndNotify()
            await service.scheduleReplyRefresh()
        }
        #else
        return self
        #endif
    }
}
#endif
