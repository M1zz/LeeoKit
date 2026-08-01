//
//  LeeoKitBootstrap.swift
//  LeeoKit
//
//  계약을 실제로 **켜는** 한 줄.
//
//  계약(LeeoAppSpec)이 아무리 잘 채워져 있어도, 앱이 `registerLaunch()` 를 안 부르면
//  리뷰 프롬프트는 영원히 안 뜨고, `LeeoDiagnostics.start()` 를 안 부르면 크래시는
//  아무도 못 본다. 매번 이 호출들을 기억하는 대신 한 줄로 묶는다.
//
//      @main struct MyApp: App {
//          init() { LeeoKit.bootstrap(MyAppSpec.self) }
//          ...
//      }
//
//  원격 킬스위치까지 쓴다면 플래그 타입을 함께 넘긴다:
//
//      init() { LeeoKit.bootstrap(MyAppSpec.self, flags: MyFlag.self) }
//
//  무엇이 켜지는가 (전부 실패해도 앱은 정상 동작 — 가용성 우선):
//    1. 사용량 기록      → 만족도/리뷰 프롬프트 타이밍의 근거
//    2. 분석 싱크 등록   → 페이월 노출·구매 전환 퍼널
//    3. 크래시 진단 구독 → MetricKit → 피드백 허브와 같은 컨테이너
//    4. 사용현황 스냅샷  → CloudKit (분석 싱크가 꽂혀 있을 때만)
//    5. 원격 플래그 갱신 → 캐시 (읽기는 언제나 네트워크 없이)
//    6. 프리플라이트 감사 → DEBUG 콘솔에만
//

import Foundation

/// LeeoKit 의 앱 수준 진입점.
public enum LeeoKit {

    /// 부트스트랩에서 실제로 켜진 것들 — 매니페스트·프리플라이트가 "선언만 하고 안 켰다"를 구분하는 근거.
    public struct Activation: Sendable, Equatable {
        public var engagement = false
        public var analytics = false
        public var diagnostics = false
        public var usageReporting = false
        public var remoteFlags = false
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var _activation = Activation()

    /// 이번 실행에서 켜진 항목.
    public static var activation: Activation {
        lock.lock(); defer { lock.unlock() }
        return _activation
    }

    private static func mutate(_ body: (inout Activation) -> Void) {
        lock.lock(); defer { lock.unlock() }
        body(&_activation)
    }

    // MARK: - 부트스트랩

    /// 계약에 선언된 것을 전부 켠다. 앱 시작 시 1회.
    ///
    /// - Parameters:
    ///   - spec: 앱 계약.
    ///   - engagement: 사용량 저장소 (앱 그룹을 쓰면 지정).
    ///   - diagnostics: MetricKit 크래시/행 진단 구독 여부.
    ///   - usageReporting: CloudKit 사용현황 스냅샷 전송 여부.
    ///   - preflight: DEBUG 에서 계약 감사 결과를 콘솔에 출력할지.
    public static func bootstrap<Spec: LeeoAppSpec>(
        _ spec: Spec.Type,
        engagement: LeeoEngagement = .shared,
        diagnostics: Bool = true,
        usageReporting: Bool = true,
        preflight: Bool = true
    ) {
        // 1. 사용량 — 리뷰/만족도 프롬프트가 이 값 없이는 동작하지 않는다.
        engagement.registerLaunch()
        mutate { $0.engagement = true }

        // 2. 분석 싱크 — no-op 이면 등록해도 아무 일도 없지만, 등록 자체는 해 둔다.
        LeeoAnalyticsCenter.register(spec)
        mutate { $0.analytics = !(Spec.analytics is LeeoNoopAnalytics) }

        // 3. 크래시·행 진단 (macOS/Catalyst 는 내부에서 자동 no-op).
        if diagnostics {
            LeeoDiagnostics.shared.start(spec: spec)
            mutate { $0.diagnostics = true }
        }

        // 4. 사용현황 스냅샷 — 분석을 켠 앱만. 안 켠 앱에 네트워크 비용을 물리지 않는다.
        if usageReporting, !(Spec.analytics is LeeoNoopAnalytics) {
            LeeoUsageReporter(spec: spec).reportInBackground(engagement: engagement)
            mutate { $0.usageReporting = true }
        }

        // 5. 계약 감사 — DEBUG 에서만 출력된다.
        if preflight {
            LeeoPreflight.report(spec, engagement: engagement)
        }
    }

    /// 원격 킬스위치까지 함께 켜는 형태.
    public static func bootstrap<Spec: LeeoAppSpec, F>(
        _ spec: Spec.Type,
        flags: F.Type,
        engagement: LeeoEngagement = .shared,
        diagnostics: Bool = true,
        usageReporting: Bool = true,
        preflight: Bool = true
    ) where F: LeeoRemoteFlag & CaseIterable & RawRepresentable, F.RawValue == String {
        bootstrap(spec, engagement: engagement, diagnostics: diagnostics,
                  usageReporting: usageReporting, preflight: preflight)
        LeeoRemoteFlags(spec: spec).refreshInBackground(flags)
        mutate { $0.remoteFlags = true }
    }

    /// 테스트용 — 활성화 기록 초기화.
    public static func resetActivationForTesting() {
        lock.lock(); defer { lock.unlock() }
        _activation = Activation()
    }
}
