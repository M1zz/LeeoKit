//
//  LeeoMetricsSummary.swift
//  LeeoKit
//
//  MetricKit 성능 묶음(`MXMetricPayload`, 하루 한 번)을 **한 줄**로 줄인다.
//
//  허브는 이 줄을 버전별로 모아 "앞 버전보다 느려졌나"를 판정한다. App Store Connect 의 성능 값은
//  사용자가 충분히 모인 앱에만 나오지만, 이 줄은 설치 하나에서도 생긴다.
//
//  나오는 모양 (`CrashReport` 레코드의 `detail`, kind 는 "metrics"):
//      launch_ms=420 hang_s_per_h=1.2 peak_mb=180 fg_min=48
//  모르는 값은 적지 않는다(0으로 적지 않는다).
//
//  MetricKit 에 기대지 않는 순수 함수라 macOS `swift test` 에서도 시험한다.
//

import Foundation

public enum LeeoMetricsSummary {

    /// 진단과 같은 레코드 타입에 싣는다 — 새 타입은 운영 스키마 배포가 따로 든다.
    /// 허브는 이 kind 를 진단 목록에서 뺀다.
    public static let kind = "metrics"

    /// 히스토그램 한 칸 — 시작 · 끝(같은 단위)과 그 칸에 든 수.
    public struct Bucket: Sendable, Equatable {
        public let start: Double
        public let end: Double
        public let count: Int
        public init(start: Double, end: Double, count: Int) {
            self.start = start; self.end = end; self.count = count
        }
    }

    /// - Parameters:
    ///   - launchMilliseconds: 첫 화면까지 걸린 시간(ms) 히스토그램.
    ///   - hangSeconds: 멈춤 시간(초) 히스토그램. MetricKit 은 250ms 넘는 멈춤만 센다.
    ///   - foregroundSeconds: 앞에 떠 있던 시간. 멈춤을 "한 시간에 몇 초"로 바꾸는 데 쓴다.
    ///   - peakMemoryMB: 가장 많이 쓴 메모리.
    public static func line(launchMilliseconds: [Bucket],
                            hangSeconds: [Bucket],
                            foregroundSeconds: Double?,
                            peakMemoryMB: Double?) -> String? {
        var parts: [String] = []
        if let launch = median(launchMilliseconds) {
            parts.append("launch_ms=\(Int(launch.rounded()))")
        }
        if let foreground = foregroundSeconds, foreground >= 60 {
            let hang = hangSeconds.reduce(0) { $0 + ($1.start + $1.end) / 2 * Double($1.count) }
            parts.append("hang_s_per_h=" + String(format: "%.2f", hang / (foreground / 3600)))
        }
        if let peak = peakMemoryMB, peak > 0 {
            parts.append("peak_mb=\(Int(peak.rounded()))")
        }
        if let foreground = foregroundSeconds, foreground > 0 {
            parts.append("fg_min=\(Int((foreground / 60).rounded()))")
        }
        // 앞에 떠 있던 시간 하나만으로는 볼 것이 없다.
        guard parts.contains(where: { !$0.hasPrefix("fg_min=") }) else { return nil }
        return parts.joined(separator: " ")
    }

    /// 히스토그램의 가운데 값 — 그 칸의 가운데로 어림한다. 평균은 드문 긴 실행 하나에 끌려간다.
    static func median(_ buckets: [Bucket]) -> Double? {
        let total = buckets.reduce(0) { $0 + $1.count }
        guard total > 0 else { return nil }
        var seen = 0
        for bucket in buckets.sorted(by: { $0.start < $1.start }) {
            seen += bucket.count
            if seen * 2 >= total { return (bucket.start + bucket.end) / 2 }
        }
        return nil
    }
}
