//
//  LeeoCrashLoopGuard.swift
//  LeeoKit
//
//  켤 때마다 같은 자리에서 죽는 일(크래시 루프)을 알아채고, 다음 실행을 가볍게 연다.
//  **앱 익스텐션(키보드·공유·위젯)에서 쓸 수 있게** 만든 것이 핵심이다.
//
//  왜 필요한가: ClipKeyboard 키보드 익스텐션이 뜰 때마다 죽는 사고가 있었다. 본 앱에는
//  런치 가드(ClipKeyboard/Service/LaunchGuard.swift)가 있었지만 익스텐션에는 아무것도 없어서,
//  사용자는 앱을 지우고 다시 깔 때까지 키보드를 한 번도 못 썼다. 익스텐션은 사용자가 직접
//  "다시 시도"할 방법도 없고, 죽으면 시스템 키보드로 조용히 넘어가 버려 무슨 일인지도 모른다.
//
//  Swift 트랩(강제 언래핑·인덱스 초과)은 do/catch 로 못 막는다. 그래서 **막는 대신 기억한다.**
//    ① 시작할 때 "지금 켜는 중" 표식을 디스크에 남긴다.
//    ② 잘 떴으면 지운다. 죽으면 표식이 그대로 남는다.
//    ③ 다음 시작에 표식이 남아 있으면 직전 실행이 끝나지 못한 것이다. 연속 횟수가
//       문턱(기본 2)에 닿으면 세이프 모드로 연다: 부가 기능을 쉬고 최소 화면만 띄운다.
//    ④ 세이프 모드에서 무사히 뜨면 횟수가 0 으로 돌아가고, 그다음 실행은 평소대로 연다.
//       (새 빌드나 바뀐 데이터가 원인을 없앴을 수 있고, 확인할 방법은 한 번 더 켜 보는 것뿐이다)
//
//  익스텐션 안전: Foundation 만 쓴다. `UIApplication.shared` 같은 익스텐션 금지 API 가 없다.
//
//  사용 예 (키보드 익스텐션):
//
//      final class KeyboardViewController: UIInputViewController {
//          // App Group 에 두면 본 앱이 같은 기록을 읽어 허브로 보낼 수 있다.
//          private let crashGuard = LeeoCrashLoopGuard(
//              name: "keyboard",
//              defaults: UserDefaults(suiteName: "group.com.example.app") ?? .standard)
//
//          override func viewDidLoad() {
//              super.viewDidLoad()
//              if crashGuard.beginLaunch() {
//                  showMinimalKeyboard()      // 부가 기능 없이 글자만 치는 화면
//                  return
//              }
//              showFullKeyboard()
//          }
//
//          override func viewDidAppear(_ animated: Bool) {
//              super.viewDidAppear(animated)
//              crashGuard.markLaunchSucceededAfterSurvivalDelay()   // 기본 3초 살아 있으면 성공
//          }
//
//          override func viewWillDisappear(_ animated: Bool) {
//              super.viewWillDisappear(animated)
//              crashGuard.markLaunchSucceeded()   // 사용자가 스스로 닫았다 = 죽은 것이 아니다
//          }
//      }
//
//  본 앱 (익스텐션이 몇 번 못 떴는지 허브로 보낸다):
//
//      let keyboardGuard = LeeoCrashLoopGuard(name: "keyboard", defaults: appGroupDefaults)
//      Task { await keyboardGuard.reportIncompleteLaunches(to: LeeoUsageReporter(spec: MySpec.self)) }
//

import Foundation

// MARK: - 순수 판정

/// 크래시 루프 판정에 필요한 값 전부. 저장소와 떨어져 있어 테스트에서 그대로 굴릴 수 있다.
public struct LeeoCrashLoopState: Equatable, Sendable {
    /// 지금 켜는 중인 실행의 세션 표식. 성공하면 nil 로 돌아간다.
    /// 다음 시작에 **다른 세션**의 표식이 남아 있으면 그 실행은 끝나지 못한 것이다.
    public var inFlightSession: String?
    /// 연속으로 끝나지 못한 실행 수. 한 번이라도 끝까지 가면 0.
    public var consecutiveIncomplete: Int
    /// 아직 허브로 보내지 않은 "끝나지 못한 실행" 수. 성공해도 줄지 않는다(보낼 때만 준다).
    public var unreportedIncomplete: Int

    public init(inFlightSession: String? = nil, consecutiveIncomplete: Int = 0, unreportedIncomplete: Int = 0) {
        self.inFlightSession = inFlightSession
        self.consecutiveIncomplete = consecutiveIncomplete
        self.unreportedIncomplete = unreportedIncomplete
    }
}

/// 상태 전이 규칙. 부수효과 없는 함수만 둔다.
public enum LeeoCrashLoopPolicy {

    /// 실행 시작. 새 상태와 이번 실행이 세이프 모드인지를 돌려준다.
    ///
    /// 같은 세션이 다시 부르면(키보드는 한 프로세스 안에서 뷰 컨트롤러를 여러 번 만든다)
    /// 직전 실행이 죽은 게 아니므로 세지 않는다. 그 경우도 문턱은 다시 판정한다.
    public static func begin(_ state: LeeoCrashLoopState, session: String,
                             threshold: Int) -> (state: LeeoCrashLoopState, safeMode: Bool) {
        var next = state
        if let prior = state.inFlightSession, prior != session {
            next.consecutiveIncomplete += 1
            next.unreportedIncomplete += 1
        }
        next.inFlightSession = session
        return (next, next.consecutiveIncomplete >= max(1, threshold))
    }

    /// 실행 성공. 연속 횟수를 지우고 표식을 내린다.
    ///
    /// 다른 세션의 표식이면 표식은 건드리지 않는다: 그 사이 새 프로세스가 켜는 중일 수 있다.
    /// 연속 횟수는 어느 쪽이든 지운다. 이 프로세스가 끝까지 왔다는 사실은 변하지 않는다.
    public static func succeed(_ state: LeeoCrashLoopState, session: String) -> LeeoCrashLoopState {
        var next = state
        if state.inFlightSession == nil || state.inFlightSession == session {
            next.inFlightSession = nil
        }
        next.consecutiveIncomplete = 0
        return next
    }
}

// MARK: - 저장소를 붙인 가드

/// 크래시 루프 가드. 이름마다 기록이 따로 있다(`"keyboard"`, `"share"` 처럼).
///
/// 기록은 넘겨받은 `UserDefaults` 에 쓴다. App Group suite 를 주면 본 앱이 익스텐션의
/// 기록을 읽을 수 있다(`unreportedIncompleteLaunches`, `reportIncompleteLaunches(to:)`).
public final class LeeoCrashLoopGuard: @unchecked Sendable {

    /// 허브가 안정성 신호로 읽는 이벤트 이름. 실제로는 `launch_incomplete:<name>` 으로 간다
    /// (`paywall_view:memo` 처럼 콜론 뒤에 조각을 붙이는 기존 규약).
    public static let incompleteLaunchEvent = "launch_incomplete"

    public let name: String
    /// 연속 몇 번 끝나지 못하면 세이프 모드로 여는가. 기본 2.
    /// 1 이면 한 번만 죽어도 다음은 세이프 모드다(본 앱의 LaunchGuard 가 그렇다).
    /// 2 가 기본인 이유: 익스텐션은 메모리 초과나 시스템 정리로도 끝나지 못한 채 사라진다.
    /// 한 번은 사고일 수 있지만, 두 번 연속이면 그 실행 경로 자체가 이 기기에서 못 도는 것이다.
    public let threshold: Int
    /// 이만큼 살아 있으면 "무사히 떴다"로 친다. 기본 3초.
    public let survivalDelay: TimeInterval

    private let defaults: UserDefaults
    private let session: String
    private let lock = NSLock()
    private var safeMode = false

    /// 프로세스마다 하나. 같은 프로세스 안의 재호출을 "직전 실행이 죽었다"로 세지 않기 위한 값.
    private static let processSession = UUID().uuidString

    public init(name: String, defaults: UserDefaults,
                threshold: Int = 2, survivalDelay: TimeInterval = 3) {
        self.name = name
        self.defaults = defaults
        self.threshold = threshold
        self.survivalDelay = survivalDelay
        self.session = Self.processSession
    }

    /// 테스트용. 서로 다른 프로세스를 세션 값으로 흉내 낸다.
    init(name: String, defaults: UserDefaults, threshold: Int, survivalDelay: TimeInterval, session: String) {
        self.name = name
        self.defaults = defaults
        self.threshold = threshold
        self.survivalDelay = survivalDelay
        self.session = session
    }

    // MARK: 공개 상태

    /// 이번 실행이 세이프 모드인가. `beginLaunch()` 가 정한다.
    /// 이번 실행 도중 성공 표시를 해도 **이 프로세스에서는** 계속 true 다(화면을 도중에
    /// 바꾸지 않는다). 다음 실행부터 평소대로 연다.
    public var isInSafeMode: Bool {
        lock.lock(); defer { lock.unlock() }
        return safeMode
    }

    /// 지금 기록된 연속 실패 수.
    public var consecutiveIncompleteLaunches: Int { load().consecutiveIncomplete }

    /// 아직 허브로 보내지 않은 실패 수. 앱이 직접 보고할 때 읽는다.
    public var unreportedIncompleteLaunches: Int { load().unreportedIncomplete }

    // MARK: 실행 경계

    /// 실행 맨 앞에서 부른다. **true 면 세이프 모드**, 최소 화면만 띄울 것.
    @discardableResult
    public func beginLaunch() -> Bool {
        lock.lock(); defer { lock.unlock() }
        let result = LeeoCrashLoopPolicy.begin(load(), session: session, threshold: threshold)
        store(result.state)
        safeMode = result.safeMode
        if result.state.consecutiveIncomplete > 0 {
            print("❌ [LeeoCrashLoopGuard.beginLaunch] '\(name)' 직전 실행이 끝나지 못했다 "
                  + "(연속 \(result.state.consecutiveIncomplete)회)\(result.safeMode ? ", 세이프 모드로 연다" : "")")
        }
        return result.safeMode
    }

    /// 무사히 떴다. 첫 화면을 그린 뒤, 또는 `survivalDelay` 만큼 살아 있은 뒤에 부른다.
    /// 여러 번 불러도 된다.
    public func markLaunchSucceeded() {
        lock.lock(); defer { lock.unlock() }
        store(LeeoCrashLoopPolicy.succeed(load(), session: session))
    }

    /// `survivalDelay` 뒤에 성공 표시를 한다. 그 전에 죽으면 표시는 남지 않는다.
    public func markLaunchSucceededAfterSurvivalDelay() {
        DispatchQueue.main.asyncAfter(deadline: .now() + survivalDelay) { [self] in
            self.markLaunchSucceeded()
        }
    }

    /// 기록을 전부 지운다(설정 화면의 "키보드 기록 초기화" 같은 곳, 또는 테스트).
    public func reset() {
        lock.lock(); defer { lock.unlock() }
        store(LeeoCrashLoopState())
        safeMode = false
    }

    // MARK: 보고

    /// 아직 안 보낸 실패 수를 읽고 0 으로 돌린다. 앱이 자기 통계 경로로 보낼 때 쓴다.
    ///
    /// ⚠️ 가져간 뒤 보내다 실패하면 그 몫은 사라진다. 잃고 싶지 않으면 `reportIncompleteLaunches(to:)`.
    public func takeUnreportedIncompleteLaunches() -> Int {
        lock.lock(); defer { lock.unlock() }
        var state = load()
        let count = state.unreportedIncomplete
        state.unreportedIncomplete = 0
        store(state)
        return count
    }

    /// 보고 한 번에 보내는 이벤트 상한. 루프가 수십 번 돌았어도 허브에 수십 줄을 쓰지 않는다.
    public static let maxEventsPerReport = 3

    /// 끝나지 못한 실행을 `launch_incomplete:<name>` 이벤트로 보낸다. 한 번에 최대 3건.
    ///
    /// **보통 본 앱에서 부른다.** 익스텐션에서 CloudKit 을 쓰려면 키보드는 전체 접근 허용,
    /// 모든 익스텐션은 iCloud 권한(entitlement)이 따로 있어야 하고, 위젯·공유 익스텐션은 실행
    /// 시간도 짧다. 그래서 기록은 App Group 에 남기고, 사용자가 본 앱을 열 때 본 앱이 보낸다.
    /// 조건을 다 갖춘 익스텐션이라면 익스텐션에서 불러도 된다(리포터는 익스텐션 금지 API 를 쓰지 않는다).
    ///
    /// 보낸 만큼만 줄인다. 전송이 실패하면 남은 몫은 다음 보고로 넘어간다.
    /// 상한을 넘은 몫은 버린다(몇 번 죽었는지보다 "죽었다"가 신호다).
    /// 이벤트의 `appVersion` 은 **부르는 쪽 번들**의 버전이다. 익스텐션과 본 앱의 버전은 같이 오른다.
    /// - Returns: 실제로 보낸 건수.
    @discardableResult
    public func reportIncompleteLaunches(to reporter: LeeoUsageReporter) async -> Int {
        let pending = unreportedIncompleteLaunches
        guard pending > 0 else { return 0 }
        let event = "\(Self.incompleteLaunchEvent):\(name)"
        let batch = min(pending, Self.maxEventsPerReport)
        var sent = 0
        for _ in 0..<batch {
            guard await reporter.logEvent(String(event.prefix(60))) else { break }
            sent += 1
        }
        settleReported(pending: pending, sent: sent, batch: batch)
        if sent > 0 {
            print("📈 [LeeoCrashLoopGuard.report] '\(name)' 끝나지 못한 실행 \(pending)회 중 \(sent)건 전송")
        }
        return sent
    }

    /// 보고 결과를 기록에 반영한다. async 함수 안에서는 락을 못 잡으므로 따로 둔다.
    private func settleReported(pending: Int, sent: Int, batch: Int) {
        lock.lock(); defer { lock.unlock() }
        var state = load()
        // 보내는 동안 새로 쌓인 몫(state.unreportedIncomplete - pending)은 남긴다.
        let fresh = max(0, state.unreportedIncomplete - pending)
        let leftover = sent == batch ? 0 : pending - sent
        state.unreportedIncomplete = fresh + leftover
        store(state)
    }

    // MARK: 저장

    private var sessionKey: String { "leeo.crashloop.\(name).session" }
    private var consecutiveKey: String { "leeo.crashloop.\(name).consecutive" }
    private var unreportedKey: String { "leeo.crashloop.\(name).unreported" }

    private func load() -> LeeoCrashLoopState {
        LeeoCrashLoopState(
            inFlightSession: defaults.string(forKey: sessionKey),
            consecutiveIncomplete: defaults.integer(forKey: consecutiveKey),
            unreportedIncomplete: defaults.integer(forKey: unreportedKey))
    }

    private func store(_ state: LeeoCrashLoopState) {
        if let s = state.inFlightSession {
            defaults.set(s, forKey: sessionKey)
        } else {
            defaults.removeObject(forKey: sessionKey)
        }
        defaults.set(state.consecutiveIncomplete, forKey: consecutiveKey)
        defaults.set(state.unreportedIncomplete, forKey: unreportedKey)
        // ⚠️ 디스크까지 밀어 넣는다. 바로 다음 줄에서 죽을 수도 있는 값이라, 시스템이
        //    알아서 내보내기를 기다리면 정작 필요한 표식이 사라진다. 실행당 두어 번뿐이다.
        defaults.synchronize()
    }
}
