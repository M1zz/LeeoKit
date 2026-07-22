//
//  LeeoEngagement.swift
//  LeeoKit
//
//  앱 사용 신호(실행 횟수·설치 후 경과일·의미 있는 행동 수)를 기록해
//  리뷰 요청/만족도 프롬프트의 타이밍을 판단한다. UserDefaults 기반이라 의존성 0.
//  앱 그룹 공유가 필요하면 suiteName 을 지정한다.
//
//  사용 예:
//      // 앱 시작 시 1회
//      LeeoEngagement.shared.registerLaunch()
//      // 저장/완료/공유 등 긍정적 행동 후
//      LeeoEngagement.shared.registerSignificantEvent()
//

import Foundation

public final class LeeoEngagement: @unchecked Sendable {
    /// 표준 UserDefaults 를 쓰는 공용 인스턴스.
    public static let shared = LeeoEngagement()

    private let defaults: UserDefaults
    private let prefix = "leeo.engagement."

    /// - Parameter suiteName: 앱 그룹 등 공유 저장소를 쓰려면 지정 (없으면 .standard)
    public init(suiteName: String? = nil) {
        self.defaults = suiteName.flatMap { UserDefaults(suiteName: $0) } ?? .standard
    }

    private func key(_ k: String) -> String { prefix + k }

    // MARK: - 읽기

    /// 설치(최초 실행) 시각 — 처음 접근할 때 고정된다.
    public var installDate: Date {
        if let t = defaults.object(forKey: key("installDate")) as? Date { return t }
        let now = Date()
        defaults.set(now, forKey: key("installDate"))
        return now
    }

    public var daysSinceInstall: Int {
        Calendar.current.dateComponents([.day], from: installDate, to: Date()).day ?? 0
    }

    /// 앱을 실행한 누적 횟수.
    public var launchCount: Int { defaults.integer(forKey: key("launchCount")) }

    /// 의미 있는 긍정 행동(저장/완료/공유 등)의 누적 횟수.
    public var significantEventCount: Int { defaults.integer(forKey: key("eventCount")) }

    // MARK: - 기록

    /// 앱 시작 시 1회 호출. 갱신된 실행 횟수를 반환한다.
    @discardableResult
    public func registerLaunch() -> Int {
        _ = installDate   // 설치 시각 고정 보장
        let n = launchCount + 1
        defaults.set(n, forKey: key("launchCount"))
        return n
    }

    /// 사용자가 만족했을 법한 긍정 행동 뒤에 호출. 갱신된 이벤트 수를 반환한다.
    @discardableResult
    public func registerSignificantEvent() -> Int {
        let n = significantEventCount + 1
        defaults.set(n, forKey: key("eventCount"))
        return n
    }

    // MARK: - 프롬프트 쿨다운/버전 기록 (LeeoReviewRequest 가 사용)

    func lastPromptDate(_ id: String) -> Date? { defaults.object(forKey: key("lastPrompt.\(id)")) as? Date }
    func markPrompted(_ id: String) { defaults.set(Date(), forKey: key("lastPrompt.\(id)")) }
    func lastPromptedVersion(_ id: String) -> String? { defaults.string(forKey: key("lastVersion.\(id)")) }
    func markPromptedVersion(_ id: String, _ version: String) { defaults.set(version, forKey: key("lastVersion.\(id)")) }

    /// 테스트/디버그용 — 모든 기록 초기화.
    public func reset() {
        for k in defaults.dictionaryRepresentation().keys where k.hasPrefix(prefix) {
            defaults.removeObject(forKey: k)
        }
    }
}
