//
//  LeeoBugProbe.swift
//  LeeoKit
//
//  버그 신고에 **묻지 않고 붙이는 진단.** 분류(`LeeoBugCategory.probes`)마다 다르다.
//
//  원칙
//  - 사용자가 적은 내용은 읽지 않는다. 기기와 계정의 **상태**만 읽는다.
//  - 결과는 보내기 전에 "자동 첨부 정보" 카드에 그대로 보인다. 숨겨서 보내는 것은 없다.
//  - 한 줄 하나, `[이름] 열쇠=값` 꼴. 받는 쪽(허브)이 눈으로도, 글자 찾기로도 읽는다.
//    사람이 아니라 개발자가 읽는 줄이라 번역하지 않는다(첫 줄 `App 5.1.7 | iPhone17,2` 과 같다).
//  - 하나라도 늦으면 기다리지 않는다(`timeout`). 진단 때문에 신고를 못 보내는 일은 없어야 한다.
//
//  ⚠️ 이 패키지는 앱 익스텐션에서도 컴파일된다(APPLICATION_EXTENSION_API_ONLY).
//     `UIApplication.shared` 가 필요한 값(백그라운드 앱 새로고침 등)은 여기서 읽지 않는다.
//     필요하면 앱이 `extraInfo` 로 넘긴다.
//
//  각 줄을 어떻게 읽는지는 `docs/BUG_CATEGORIES.md`.
//

import Foundation
import CloudKit
#if canImport(StoreKit)
import StoreKit
#endif
#if canImport(UserNotifications)
import UserNotifications
#endif
#if canImport(WidgetKit)
import WidgetKit
#endif
#if canImport(UIKit)
import UIKit
#endif

public enum LeeoBugProbe: String, CaseIterable, Sendable {
    /// 남은 저장 공간 · 메모리 · 저전력 모드 · 발열.
    case device
    /// 이 기기가 Apple 에게서 돌려받는 결제 권한 전부와, 회수(환불)된 결제.
    case purchases
    /// 앱을 처음 받은 날 · 처음 받은 빌드 · 설치 환경(App Store / TestFlight / Xcode).
    case appReceipt
    /// App Store 국가 · 결제 가능 여부(스크린 타임 제한).
    case storefront
    /// iCloud 로그인 상태.
    case iCloud
    /// 알림 허용 · 잠금 화면 · 시간 민감 · 예약 요약 · 기다리는 알림 수.
    case notifications
    /// 홈 화면에 놓인 이 앱의 위젯.
    case widgets
    /// 언어 · 지역 · 글자 크기 · 굵은 글씨 · 다크 모드.
    case display

    /// 진단 하나에 주는 시간. 넘으면 `timeout` 이라고 적고 넘어간다.
    static let timeout: Duration = .seconds(3)

    // MARK: - 모으기

    /// 여러 진단을 한꺼번에 모은다. 순서는 넘긴 순서 그대로다.
    /// - Parameter container: iCloud 상태를 물을 컨테이너(피드백 컨테이너면 된다).
    public static func collect(_ probes: [LeeoBugProbe], container: String) async -> [String] {
        var lines: [String] = []
        for probe in probes {
            lines.append(contentsOf: await probe.lines(container: container))
        }
        return lines
    }

    /// 이 진단의 줄들. 시간이 넘으면 한 줄로 그렇게 적는다.
    public func lines(container: String) async -> [String] {
        let name = rawValue
        let result = await Self.withTimeout { await self.read(container: container) }
        return result ?? ["[\(name)] timeout"]
    }

    private func read(container: String) async -> [String] {
        switch self {
        case .device:        return [Self.deviceLine()]
        case .purchases:     return await Self.purchaseLines()
        case .appReceipt:    return [await Self.receiptLine()]
        case .storefront:    return [await Self.storefrontLine()]
        case .iCloud:        return [await Self.iCloudLine(container: container)]
        case .notifications: return await Self.notificationLines()
        case .widgets:       return [await Self.widgetLine()]
        case .display:       return [await Self.displayLine()]
        }
    }

    // MARK: - device

    static func deviceLine() -> String {
        let info = ProcessInfo.processInfo
        let memoryGB = Double(info.physicalMemory) / 1_073_741_824
        var parts = ["memory=\(String(format: "%.0f", memoryGB))GB"]
        if let free = freeDiskBytes() {
            parts.insert("freeDisk=\(String(format: "%.1f", Double(free) / 1_000_000_000))GB", at: 0)
        }
        parts.append("lowPower=\(onOff(info.isLowPowerModeEnabled))")
        parts.append("thermal=\(thermalName(info.thermalState))")
        return "[device] " + parts.joined(separator: " ")
    }

    /// 사용자가 실제로 쓸 수 있는 공간(`importantUsage`). 1GB 아래면 저장 실패 · 꺼짐이 먼저 의심된다.
    static func freeDiskBytes() -> Int64? {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        let values = try? home.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }

    static func thermalName(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal:  return "nominal"
        case .fair:     return "fair"
        case .serious:  return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown"
        }
    }

    // MARK: - purchases

    /// 지금 권한 전부 + 회수된 결제.
    ///
    /// ⚠️ 회수(환불 · 가족 공유 해제)는 `currentEntitlements` 에 **안 나온다.** "샀는데 사라졌다" 의
    ///    가장 흔한 답이 환불이라 `Transaction.all` 을 따로 훑는다.
    static func purchaseLines() async -> [String] {
        #if canImport(StoreKit)
        var owned: [String] = []
        for await result in Transaction.currentEntitlements {
            owned.append(describe(result))
        }
        var revoked: [String] = []
        for await result in Transaction.all {
            guard case .verified(let t) = result, let at = t.revocationDate else { continue }
            revoked.append("\(t.productID)(revoked \(day(at)))")
        }
        return [
            "[purchases] owned=" + (owned.isEmpty ? "none" : owned.joined(separator: ", ")),
            "[purchases] revoked=" + (revoked.isEmpty ? "none" : revoked.joined(separator: ", "))
        ]
        #else
        return ["[purchases] unavailable"]
        #endif
    }

    #if canImport(StoreKit)
    static func describe(_ result: VerificationResult<Transaction>) -> String {
        switch result {
        case .verified(let t):
            var bits = [day(t.purchaseDate), t.ownershipType == .familyShared ? "family" : "own"]
            if let expires = t.expirationDate { bits.append("expires \(day(expires))") }
            if t.isUpgraded { bits.append("upgraded") }
            return "\(t.productID)(\(bits.joined(separator: " ")))"
        case .unverified(let t, _):
            return "\(t.productID)(unverified)"
        }
    }
    #endif

    // MARK: - appReceipt

    /// 처음 받은 날은 다시 깔아도, 기기를 바꿔도 같다(Apple 계정에 묶여 있다).
    /// 그래서 "예전부터 쓰던 사람" 인지, "유료 앱이던 시절에 산 사람" 인지를 이 줄 하나가 가른다.
    static func receiptLine() async -> String {
        #if canImport(StoreKit)
        do {
            switch try await AppTransaction.shared {
            case .verified(let t):
                return "[appReceipt] firstDownload=\(day(t.originalPurchaseDate)) "
                    + "firstBuild=\(t.originalAppVersion) env=\(t.environment.rawValue)"
            case .unverified(let t, _):
                return "[appReceipt] unverified firstDownload=\(day(t.originalPurchaseDate))"
            }
        } catch {
            return "[appReceipt] error=\(shortError(error))"
        }
        #else
        return "[appReceipt] unavailable"
        #endif
    }

    // MARK: - storefront

    static func storefrontLine() async -> String {
        #if canImport(StoreKit)
        let country = await Storefront.current?.countryCode ?? "-"
        return "[storefront] country=\(country) canPay=\(onOff(AppStore.canMakePayments))"
        #else
        return "[storefront] unavailable"
        #endif
    }

    // MARK: - iCloud

    static func iCloudLine(container: String) async -> String {
        do {
            let status = try await CKContainer(identifier: container).accountStatus()
            return "[iCloud] account=\(accountName(status))"
        } catch {
            return "[iCloud] error=\(shortError(error))"
        }
    }

    static func accountName(_ status: CKAccountStatus) -> String {
        switch status {
        case .available:              return "available"
        case .noAccount:              return "noAccount"
        case .restricted:             return "restricted"
        case .couldNotDetermine:      return "couldNotDetermine"
        case .temporarilyUnavailable: return "temporarilyUnavailable"
        @unknown default:             return "unknown"
        }
    }

    // MARK: - notifications

    static func notificationLines() async -> [String] {
        #if canImport(UserNotifications)
        let center = UNUserNotificationCenter.current()
        let s = await center.notificationSettings()
        let pending = await center.pendingNotificationRequests().count
        var parts = [
            "auth=\(authName(s.authorizationStatus))",
            "alert=\(settingName(s.alertSetting))",
            "sound=\(settingName(s.soundSetting))",
            "lockScreen=\(settingName(s.lockScreenSetting))",
            "center=\(settingName(s.notificationCenterSetting))"
        ]
        #if os(iOS)
        parts.append("timeSensitive=\(settingName(s.timeSensitiveSetting))")
        // 예약 요약에 묶이면 알림이 정한 시각이 아니라 요약 시각에 몰려 온다. "늦게 와요" 의 단골 원인.
        parts.append("summary=\(settingName(s.scheduledDeliverySetting))")
        #endif
        return ["[notifications] " + parts.joined(separator: " "),
                "[notifications] pending=\(pending)"]
        #else
        return ["[notifications] unavailable"]
        #endif
    }

    #if canImport(UserNotifications)
    static func authName(_ status: UNAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: return "notDetermined"
        case .denied:        return "denied"
        case .authorized:    return "authorized"
        case .provisional:   return "provisional"
        case .ephemeral:     return "ephemeral"
        @unknown default:    return "unknown"
        }
    }

    static func settingName(_ setting: UNNotificationSetting) -> String {
        switch setting {
        case .enabled:       return "on"
        case .disabled:      return "off"
        case .notSupported:  return "n/a"
        @unknown default:    return "unknown"
        }
    }
    #endif

    // MARK: - widgets

    static func widgetLine() async -> String {
        #if canImport(WidgetKit) && !os(watchOS)
        // 비동기판(`currentConfigurations()`)은 iOS 18 부터라 콜백판을 감싼다.
        let result: Result<[WidgetInfo], Error> = await withCheckedContinuation { done in
            WidgetCenter.shared.getCurrentConfigurations { done.resume(returning: $0) }
        }
        switch result {
        case .success(let configs):
            if configs.isEmpty { return "[widgets] placed=0" }
            let kinds = configs.map { "\($0.kind)/\($0.family)" }
            return "[widgets] placed=\(configs.count) " + kinds.joined(separator: ", ")
        case .failure(let error):
            return "[widgets] error=\(shortError(error))"
        }
        #else
        return "[widgets] unavailable"
        #endif
    }

    // MARK: - display

    @MainActor
    static func displayLine() -> String {
        let langs = Locale.preferredLanguages.prefix(3).joined(separator: ",")
        let appLang = Bundle.main.preferredLocalizations.first ?? "-"
        let region = Locale.current.region?.identifier ?? "-"
        var parts = ["langs=\(langs)", "appLang=\(appLang)", "region=\(region)"]
        #if canImport(UIKit) && !os(watchOS)
        let traits = UITraitCollection.current
        parts.append("textSize=\(traits.preferredContentSizeCategory.rawValue)")
        parts.append("bold=\(onOff(UIAccessibility.isBoldTextEnabled))")
        parts.append("dark=\(onOff(traits.userInterfaceStyle == .dark))")
        #endif
        return "[display] " + parts.joined(separator: " ")
    }

    // MARK: - 도우미

    static func onOff(_ value: Bool) -> String { value ? "on" : "off" }

    /// 날짜만. 시각은 필요 없고, 시간대가 섞이면 읽는 쪽이 헷갈린다(UTC 로 고정).
    static func day(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    static func shortError(_ error: Error) -> String {
        let ns = error as NSError
        return "\(ns.domain)#\(ns.code)"
    }

    /// 일을 시키고 `timeout` 안에 안 끝나면 nil.
    static func withTimeout<T: Sendable>(_ work: @escaping @Sendable () async -> T) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask { await work() }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
}
