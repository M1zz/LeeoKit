//
//  LeeoEngagement.swift
//  LeeoKit
//
//  앱 사용 참여도(실행 횟수·최초 실행일·의미 있는 행동 수)를 추적해
//  "만족도 체크를 언제 띄울지"를 결정하는 경량 저장소.
//  UserDefaults만 사용하고 개인정보나 네트워크 전송이 전혀 없다.
//
//  사용 예 (앱 진입점):
//      @main struct MyApp: App {
//          init() { LeeoEngagement.shared.registerLaunch() }
//          var body: some Scene {
//              WindowGroup { ContentView().leeoSatisfactionCheck(MyAppSpec.self) }
//          }
//      }
//

import Foundation

/// 참여도 지표를 누적하고 만족도 프롬프트 노출 조건을 판정한다.
///
/// UserDefaults는 스레드 세이프하므로 이 클래스는 별도 동기화 없이 어디서든 호출 가능하다.
public final class LeeoEngagement {
    public static let shared = LeeoEngagement()

    private let defaults: UserDefaults

    private enum Key {
        static let launchCount        = "leeo.engagement.launchCount"
        static let firstLaunch        = "leeo.engagement.firstLaunchDate"
        static let significantEvents  = "leeo.engagement.significantEvents"
        static let promptLastDate     = "leeo.engagement.satisfaction.lastPromptDate"
        static let promptLastVersion  = "leeo.engagement.satisfaction.lastPromptVersion"
        static let respondedPositive  = "leeo.engagement.satisfaction.respondedPositively"
    }

    /// - Parameter defaults: 테스트에서 주입 가능. 기본은 표준 저장소.
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - 기록

    /// 앱 시작 시 1회 호출. 실행 횟수를 누적하고 최초 실행일을 최초 1회 기록한다.
    public func registerLaunch() {
        if defaults.object(forKey: Key.firstLaunch) == nil {
            defaults.set(Date(), forKey: Key.firstLaunch)
        }
        defaults.set(launchCount + 1, forKey: Key.launchCount)
    }

    /// 의미 있는 사용 행동(예: 기록 저장, 목표 달성)을 누적한다.
    /// 만족도 체크를 "실제로 앱을 쓴 사용자"에게만 띄우고 싶을 때 게이팅에 활용된다.
    public func registerSignificantEvent() {
        defaults.set(significantEventCount + 1, forKey: Key.significantEvents)
    }

    // MARK: - 조회

    public var launchCount: Int { defaults.integer(forKey: Key.launchCount) }
    public var significantEventCount: Int { defaults.integer(forKey: Key.significantEvents) }
    public var firstLaunchDate: Date? { defaults.object(forKey: Key.firstLaunch) as? Date }

    /// 최초 실행일로부터 지난 일수 (없으면 0).
    public var daysSinceFirstLaunch: Int {
        guard let first = firstLaunchDate else { return 0 }
        return Calendar.current.dateComponents([.day], from: first, to: Date()).day ?? 0
    }

    /// 사용자가 이미 "좋아요"로 응답했는지 (한 번 긍정하면 다시 묻지 않는다).
    public var didRespondPositively: Bool { defaults.bool(forKey: Key.respondedPositive) }

    // MARK: - 만족도 프롬프트 게이팅

    /// 지금 만족도 체크를 띄워도 되는지 판정한다.
    /// 충분히 써봤고(횟수·기간·행동), 같은 버전에서 아직 안 물었고, 쿨다운이 지났고,
    /// 이전에 긍정 응답으로 리뷰 경로로 보낸 적이 없을 때만 true.
    public func shouldPromptSatisfaction(config: LeeoSatisfactionConfig) -> Bool {
        if didRespondPositively { return false }
        guard launchCount >= config.minLaunches else { return false }
        guard daysSinceFirstLaunch >= config.minDays else { return false }
        guard significantEventCount >= config.minSignificantEvents else { return false }

        // 같은 앱 버전에서 이미 물어봤으면 이번 버전에서는 다시 묻지 않는다.
        if defaults.string(forKey: Key.promptLastVersion) == currentVersion { return false }

        // 마지막 프롬프트로부터 쿨다운이 지나야 한다.
        if let last = defaults.object(forKey: Key.promptLastDate) as? Date {
            let days = Calendar.current.dateComponents([.day], from: last, to: Date()).day ?? 0
            if days < config.cooldownDays { return false }
        }
        return true
    }

    /// 프롬프트를 실제로 노출했음을 기록 (날짜 + 버전).
    public func markSatisfactionPrompted() {
        defaults.set(Date(), forKey: Key.promptLastDate)
        defaults.set(currentVersion, forKey: Key.promptLastVersion)
    }

    /// 사용자가 "좋아요"로 응답 → 이후로는 만족도 체크를 다시 띄우지 않는다.
    public func markRespondedPositively() {
        defaults.set(true, forKey: Key.respondedPositive)
    }

    /// 테스트/디버그용 초기화.
    public func resetEngagement() {
        [Key.launchCount, Key.firstLaunch, Key.significantEvents,
         Key.promptLastDate, Key.promptLastVersion, Key.respondedPositive]
            .forEach { defaults.removeObject(forKey: $0) }
    }

    private var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-"
    }
}

/// 만족도 체크 노출 조건. 기본값은 "며칠 써보고, 몇 번 실행한 뒤, 버전당 1회"에 맞춘 보수적 설정.
public struct LeeoSatisfactionConfig: Sendable {
    /// 최소 실행 횟수
    public var minLaunches: Int
    /// 최초 실행 후 최소 경과 일수
    public var minDays: Int
    /// 최소 의미 있는 행동 수 (registerSignificantEvent 누적치). 0이면 조건 없음.
    public var minSignificantEvents: Int
    /// 프롬프트 사이 최소 간격(일). 같은 버전 중복은 별도로 이미 막는다.
    public var cooldownDays: Int

    public init(
        minLaunches: Int = 4,
        minDays: Int = 2,
        minSignificantEvents: Int = 0,
        cooldownDays: Int = 120
    ) {
        self.minLaunches = minLaunches
        self.minDays = minDays
        self.minSignificantEvents = minSignificantEvents
        self.cooldownDays = cooldownDays
    }
}
