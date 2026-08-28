//
//  LeeoUsageStatsView.swift
//  LeeoKit
//
//  개발자 전용 사용 통계 화면 — UsageSnapshot을 모아 설치 수·활성·버전 분포 등을 보여준다.
//  진입점 노출(마스터 모드 게이트)은 앱이 책임진다. (LeeoSupportSection/앱 설정에서)
//
//  ⚠️ 전체를 읽으려면 컨테이너 read 권한이 필요하다(피드백 인박스와 동일).
//

import SwiftUI

public struct LeeoUsageStatsView<Spec: LeeoAppSpec>: View {
    @Environment(\.leeoStyle) private var theme

    @State private var snaps: [LeeoUsageReporter.UsageSnapshot] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    /// 조회가 왜 멈췄는지. 받는 중이면 nil. 화면이 "다 받았다"를 말할 수 있는 유일한 근거다.
    @State private var stop: LeeoCloudStop?
    /// 지금까지 받은 페이지 수 — 진행이 실제로 일어나고 있다는 증거.
    @State private var pages = 0
    /// 지금 보이는 숫자가 언제 기준인지.
    @State private var loadedAt: Date?

    private var reporter: LeeoUsageReporter { LeeoUsageReporter(spec: Spec.self) }

    public init() {}

    public var body: some View {
        List {
            // 아직 한 페이지도 못 받았을 때만 화면을 스피너에 내준다.
            if isLoading && snaps.isEmpty {
                Section {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text(L("불러오는 중…", comment: "Loading")).font(.body)
                    }
                }
            } else {
                // 부분만 받았어도 받은 건 그대로 보여준다 — 에러는 위에 덧붙인다.
                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.body)
                            .foregroundStyle(.red)
                    } footer: {
                        Text(L("전체 통계를 읽으려면 CloudKit 컨테이너의 read 권한이 필요해요.", comment: "Usage stats read permission footer"))
                            .font(.body)
                    }
                }

                statusSection

                if snaps.isEmpty {
                    if errorMessage == nil {
                        Section {
                            Text(L("아직 수집된 사용 데이터가 없어요.", comment: "No usage data"))
                                .font(.body)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    summarySection
                    if !metricAverages.isEmpty { metricsSection }
                    versionSection
                    platformSection
                }
            }
        }
        .navigationTitle(L("사용 통계", comment: "Usage stats title"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: - 어디까지 왔나

    /// 지금 보이는 숫자가 중간 집계인지 최종본인지 화면이 직접 말한다.
    /// 나눠 받는 조회에서 이 한 줄이 없으면, 낮은 숫자가 "아직 받는 중"인지
    /// "원래 그만큼"인지 "중간에 끊긴 것"인지 사람이 구분할 방법이 없다.
    /// 셋은 해야 할 일이 서로 다르다 — 기다리기 / 그대로 믿기 / 다시 받기.
    @ViewBuilder
    private var statusSection: some View {
        if isLoading {
            Section {
                HStack(spacing: 10) {
                    ProgressView()
                    Text(String(format: L("불러오는 중… %lld건 (%lld페이지)", comment: "Usage stats: loading progress"),
                                snaps.count, pages))
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text(L("한 번에 200건씩 나눠 받아요. 지금 숫자는 중간 집계라 계속 올라가요.", comment: "Usage stats: paged loading footer"))
                    .font(.body)
            }
        } else if let stop {
            Section {
                Label {
                    Text(statusText(for: stop)).font(.body)
                } icon: {
                    Image(systemName: stop.isComplete ? "checkmark.circle" : "exclamationmark.triangle")
                }
                .foregroundStyle(stop.isComplete ? Color.secondary : Color.orange)
            }
        }
    }

    private func statusText(for stop: LeeoCloudStop) -> String {
        switch stop {
        case .exhausted:
            let at = loadedAt.map { DateFormatter.localizedString(from: $0, dateStyle: .none, timeStyle: .short) } ?? "-"
            return String(format: L("설치 %lld건을 전부 불러왔어요 (%@ 기준).", comment: "Usage stats: fully loaded"),
                          snaps.count, at)
        case .reachedLimit:
            return String(format: L("상한인 %lld건까지만 불러왔어요. 서버엔 더 있을 수 있어요.", comment: "Usage stats: stopped at limit"),
                          snaps.count)
        case .cancelled:
            return L("불러오다 멈췄어요. 당겨서 새로고침하면 다시 받아요.", comment: "Usage stats: cancelled")
        case .failed(let why):
            return String(format: L("중간에 끊겨 %lld건까지만 받았어요: %@", comment: "Usage stats: interrupted"),
                          snaps.count, why)
        }
    }

    // MARK: - Sections

    private var summarySection: some View {
        Section(L("요약", comment: "Usage stats: summary")) {
            statRow(L("총 설치", comment: "Total installs"), "\(snaps.count)")
            statRow(L("최근 7일 활성", comment: "Active in last 7 days"), "\(activeCount(days: 7))")
            statRow(L("최근 30일 활성", comment: "Active in last 30 days"), "\(activeCount(days: 30))")
            statRow(L("누적 실행", comment: "Total launches"), "\(totalLaunches)")
            statRow(L("누적 주요 행동", comment: "Total significant events"), "\(totalEvents)")
        }
    }

    private var versionSection: some View {
        Section(L("버전 분포", comment: "Version distribution")) {
            ForEach(distribution(\.appVersion), id: \.key) { item in
                statRow(item.key, "\(item.count)")
            }
        }
    }

    private var platformSection: some View {
        Section(L("플랫폼", comment: "Platform distribution")) {
            ForEach(distribution(\.platform), id: \.key) { item in
                statRow(item.key, "\(item.count)")
            }
        }
    }

    private var metricsSection: some View {
        Section(L("앱 지표 (설치당 평균)", comment: "App metrics average")) {
            ForEach(metricAverages, id: \.key) { item in
                statRow(item.key, Self.format(item.value))
            }
        }
    }

    private func statRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(theme.text)
            Spacer()
            Text(value).font(.body.monospacedDigit().weight(.semibold)).foregroundStyle(.secondary)
        }
    }

    // MARK: - 집계 (클라이언트 계산)

    private func activeCount(days: Int) -> Int {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        return snaps.filter { ($0.lastActiveAt ?? .distantPast) >= cutoff }.count
    }
    private var totalLaunches: Int { snaps.reduce(0) { $0 + $1.launchCount } }
    private var totalEvents: Int { snaps.reduce(0) { $0 + $1.eventCount } }

    private struct Bucket: Identifiable { let key: String; let count: Int; var id: String { key } }
    private func distribution(_ keyPath: KeyPath<LeeoUsageReporter.UsageSnapshot, String>) -> [Bucket] {
        Dictionary(grouping: snaps) { $0[keyPath: keyPath] }
            .map { Bucket(key: $0.key, count: $0.value.count) }
            .sorted { $0.count > $1.count }
    }

    private struct MetricAvg: Identifiable { let key: String; let value: Double; var id: String { key } }
    /// 각 지표 키를, 그 값을 가진 설치들의 평균으로 집계.
    private var metricAverages: [MetricAvg] {
        var sums: [String: (total: Double, n: Int)] = [:]
        for snap in snaps {
            for (k, v) in snap.metrics {
                let cur = sums[k] ?? (0, 0)
                sums[k] = (cur.total + v, cur.n + 1)
            }
        }
        return sums
            .map { MetricAvg(key: $0.key, value: $0.value.n > 0 ? $0.value.total / Double($0.value.n) : 0) }
            .sorted { $0.key < $1.key }
    }

    private static func format(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
    }

    // MARK: - Load

    private func load() async {
        isLoading = true
        errorMessage = nil
        stop = nil
        pages = 0
        do {
            // 200건씩 이어 받으며 그때그때 화면을 갱신한다. 진행 상황(건수·페이지)과
            // 마지막에 "왜 멈췄는지"까지 같은 통로로 받아, 화면이 상태를 말할 수 있게 한다.
            snaps = try await reporter.fetchSnapshots { progress in
                snaps = progress.items
                pages = progress.pages
                stop = progress.stop
            }
            loadedAt = Date()
        } catch {
            // 첫 페이지부터 실패했을 때만 여기로 온다(그 뒤의 실패는 부분 결과 + stop으로 끝난다).
            errorMessage = String(format: L("불러오지 못했어요: %@", comment: "Usage stats load failed"),
                                  error.localizedDescription)
        }
        isLoading = false
    }
}
