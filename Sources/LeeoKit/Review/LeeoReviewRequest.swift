//
//  LeeoReviewRequest.swift
//  LeeoKit
//
//  App Store 리뷰 요청. 시스템 평점 프롬프트(StoreKit)를 정책 조건이 맞을 때만 띄우고,
//  "리뷰 남기기" 버튼용으로 App Store 작성 페이지 딥링크도 제공한다.
//
//  SwiftUI 에서:
//      @Environment(\.requestReview) private var requestReview
//      ...
//      LeeoReviewRequest.requestIfAppropriate { requestReview() }
//

import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// 리뷰 프롬프트를 언제 띄울지 결정하는 정책.
public struct LeeoReviewPolicy: Sendable {
    /// 최소 실행 횟수
    public var minLaunches: Int
    /// 설치 후 최소 경과일
    public var minDaysSinceInstall: Int
    /// 최소 긍정 행동 수 (registerSignificantEvent)
    public var minSignificantEvents: Int
    /// 한 번 물어본 뒤 다시 묻기까지 최소 간격(일)
    public var cooldownDays: Int
    /// 같은 앱 버전에서는 한 번만 요청
    public var oncePerVersion: Bool

    public init(
        minLaunches: Int = 3,
        minDaysSinceInstall: Int = 2,
        minSignificantEvents: Int = 1,
        cooldownDays: Int = 120,
        oncePerVersion: Bool = true
    ) {
        self.minLaunches = minLaunches
        self.minDaysSinceInstall = minDaysSinceInstall
        self.minSignificantEvents = minSignificantEvents
        self.cooldownDays = cooldownDays
        self.oncePerVersion = oncePerVersion
    }

    /// 무난한 기본값: 실행 3회 · 설치 2일 · 긍정행동 1회 이상, 버전당 1회, 120일 쿨다운.
    public static let `default` = LeeoReviewPolicy()
}

public enum LeeoReviewRequest {
    static let promptID = "review"

    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"
    }

    /// 정책 조건을 모두 만족하는지 (프롬프트를 띄워도 되는 시점인지).
    public static func shouldRequest(
        policy: LeeoReviewPolicy = .default,
        engagement: LeeoEngagement = .shared
    ) -> Bool {
        if engagement.launchCount < policy.minLaunches { return false }
        if engagement.daysSinceInstall < policy.minDaysSinceInstall { return false }
        if engagement.significantEventCount < policy.minSignificantEvents { return false }
        if policy.oncePerVersion, engagement.lastPromptedVersion(promptID) == appVersion { return false }
        if let last = engagement.lastPromptDate(promptID) {
            let days = Calendar.current.dateComponents([.day], from: last, to: Date()).day ?? 0
            if days < policy.cooldownDays { return false }
        }
        return true
    }

    /// 정책 조건을 만족할 때만 시스템 리뷰 프롬프트를 띄운다.
    /// - Parameter requestReview: SwiftUI `@Environment(\.requestReview)` 를 감싸 전달.
    /// - Returns: 실제로 요청을 띄웠으면 true.
    @discardableResult
    @MainActor
    public static func requestIfAppropriate(
        policy: LeeoReviewPolicy = .default,
        engagement: LeeoEngagement = .shared,
        using requestReview: @MainActor () -> Void
    ) -> Bool {
        guard shouldRequest(policy: policy, engagement: engagement) else { return false }
        markRequested(engagement: engagement)
        requestReview()
        return true
    }

    /// 쿨다운/버전 기록만 남긴다 (프롬프트를 띄웠거나 넛지를 노출했을 때).
    public static func markRequested(engagement: LeeoEngagement = .shared) {
        engagement.markPrompted(promptID)
        engagement.markPromptedVersion(promptID, appVersion)
    }

    /// App Store 리뷰 작성 페이지를 직접 연다 ("리뷰 남기기" 버튼용). appStoreID 필요.
    @MainActor
    public static func openWriteReview(appStoreID: String) {
        guard let url = URL(string: "https://apps.apple.com/app/id\(appStoreID)?action=write-review") else { return }
        #if canImport(UIKit)
        UIApplication.shared.open(url)
        #elseif canImport(AppKit)
        NSWorkspace.shared.open(url)
        #endif
    }
}
