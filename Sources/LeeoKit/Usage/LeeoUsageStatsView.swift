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

    private var reporter: LeeoUsageReporter { LeeoUsageReporter(spec: Spec.self) }

    public init() {}

    public var body: some View {
        List {
            if isLoading && snaps.isEmpty {
                Section {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text(L("불러오는 중…", comment: "Loading")).font(.body)
                    }
                }
            } else if let errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.body)
                        .foregroundStyle(.red)
                } footer: {
                    Text(L("전체 통계를 읽으려면 CloudKit 컨테이너의 read 권한이 필요해요.", comment: "Usage stats read permission footer"))
                        .font(.body)
                }
            } else if snaps.isEmpty {
                Section {
                    Text(L("아직 수집된 사용 데이터가 없어요.", comment: "No usage data"))
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            } else {
                summarySection
                versionSection
                platformSection
            }
        }
        .navigationTitle(L("사용 통계", comment: "Usage stats title"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await load() }
        .refreshable { await load() }
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

    // MARK: - Load

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            snaps = try await reporter.fetchSnapshots()
        } catch {
            errorMessage = String(format: L("불러오지 못했어요: %@", comment: "Usage stats load failed"),
                                  error.localizedDescription)
        }
        isLoading = false
    }
}
