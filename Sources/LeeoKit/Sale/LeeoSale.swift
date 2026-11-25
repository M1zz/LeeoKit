//
//  LeeoSale.swift
//  LeeoKit
//
//  **할인 기간에 앱을 열면 전면 배너로 알린다.**
//
//  할인 값은 App Store Connect 가 정한다(첫 구독 오퍼). 이 파일은 "언제 · 어느 앱에서 · 누구에게"
//  배너를 띄울지만 정한다. 그 일정은 레포 맨 위의 `sale.json` 에 있고, 앱은 하루에 한 번 받아 온다 —
//  다음 할인은 앱을 새로 내지 않고 그 파일만 고치면 된다. 받은 적이 없으면 `builtIn` 을 쓴다.
//
//  배너는 `.leeoPaywallLink` 에 함께 실려 있다. 앱이 할 일은 없다.
//  LeeoStore 를 쓰지 않는 앱만 파는 상품 ID 를 알려 준다(첫 구독 할인을 받을 수 있는 사람인지 보려고):
//
//      LeeoSale.productIDs = StoreKitManager.allIds
//

import Foundation
#if canImport(StoreKit)
import StoreKit
#endif

/// 할인 한 번. 날짜는 `yyyy-MM-dd`, 사용자 기기의 날짜로 그날 하루 전체를 포함한다.
public struct LeeoSaleCampaign: Codable, Equatable, Sendable {
    public var id: String
    /// 알려진 이름(`blackFriday`)이면 LeeoKit 이 모든 언어로 이름을 붙인다. 모르면 "특별 할인".
    public var kind: String?
    /// 이날부터 "곧 시작해요" 로 미리 알린다. 없으면 시작일부터.
    public var announce: String?
    public var start: String
    public var end: String
    /// 배너의 큰 숫자 "최대 N%". 할인 중에는 실제 값에서 계산한 것이 있으면 그것을 쓴다.
    public var percent: Int
    /// 띄울 앱의 번들 ID. 비어 있으면 아무 앱에도 띄우지 않는다.
    public var apps: [String]

    public enum Phase: Equatable, Sendable { case upcoming, live }

    /// 오늘이 미리 알림 기간인가, 할인 중인가. 둘 다 아니면 nil.
    public func phase(on date: Date, calendar: Calendar = .current) -> Phase? {
        guard let startDay = Self.day(start, calendar), let endDay = Self.day(end, calendar) else { return nil }
        let today = calendar.startOfDay(for: date)
        if today >= startDay && today <= endDay { return .live }
        let announceDay = announce.flatMap { Self.day($0, calendar) } ?? startDay
        if today >= announceDay && today < startDay { return .upcoming }
        return nil
    }

    /// 끝나는 날까지 남은 날(오늘이 마지막 날이면 0).
    public func daysLeft(on date: Date, calendar: Calendar = .current) -> Int {
        guard let endDay = Self.day(end, calendar) else { return 0 }
        return max(0, calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: endDay).day ?? 0)
    }

    public func startDate(_ calendar: Calendar = .current) -> Date? { Self.day(start, calendar) }
    public func endDate(_ calendar: Calendar = .current) -> Date? { Self.day(end, calendar) }

    public func includes(bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return apps.contains { $0.caseInsensitiveCompare(bundleID) == .orderedSame }
    }

    var title: String {
        switch kind {
        case "blackFriday": return L("블랙 프라이데이", comment: "Sale banner: campaign name for Black Friday")
        default: return L("특별 할인", comment: "Sale banner: generic campaign name")
        }
    }

    private static func day(_ text: String, _ calendar: Calendar) -> Date? {
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}

struct LeeoSaleSchedule: Codable, Equatable {
    var campaigns: [LeeoSaleCampaign]
}

@MainActor
public enum LeeoSale {

    /// LeeoStore 를 쓰지 않는 앱이 파는 상품 ID. LeeoStore 를 쓰면 비워 둔다(스토어가 알려 준다).
    public static var productIDs: [String] = []

    static let remoteURL = URL(string: "https://raw.githubusercontent.com/M1zz/LeeoKit/main/sale.json")!
    private static let cacheKey = "leeo.sale.schedule"
    private static let fetchedAtKey = "leeo.sale.schedule.fetchedAt"
    private static let refreshInterval: TimeInterval = 12 * 60 * 60

    /// 원격 파일을 받아 본 적이 없을 때 쓰는 일정 — 이 버전이 나갈 때의 `sale.json` 과 같다.
    static let builtIn = LeeoSaleSchedule(campaigns: [
        LeeoSaleCampaign(
            id: "blackfriday-2026", kind: "blackFriday",
            announce: "2026-11-24", start: "2026-11-27", end: "2026-12-04", percent: 80,
            apps: ["com.leeo.slidesnap", "com.Ysoup.TokenMemo", "com.leeo.LullabyRecipe", "com.Ysoup.LeaveWise",
                   "com.leeo.PixelMe", "com.leeo.HandsFreeMetronome", "com.devkoan.ScheduleDensityApp",
                   "com.example.ScheduleDensityApp", "com.xa.toki", "com.ysoup.RoutineCamera", "com.leeo.TetraTint",
                   "com.leeo.yeoul", "com.devkoan.IndonesianSmallTalk", "com.leeo.FootprintDiary",
                   "com.burningparchment.app", "com.leeo.JuniorDevMistakes", "com.leeo.higgym", "com.leeo.thinkflow",
                   "com.lectureq.LectureQ", "com.devkoan.StaffSinger", "com.leeo.SkyDex", "com.leeo.sunflower",
                   "com.leeo.StickyPresenter", "com.devkoan.worryparking", "com.leeo.geusaie", "com.example.MoonlitOrder",
                   "com.leeo.DontGoMart", "com.leeo.wifisnap", "com.leeo.ReboundJournal", "com.leeo.bookmarkshot",
                   "com.family.FamilyBank", "com.devkoan.CalendarSnap", "com.leeo.JuJob", "com.family.familycourt",
                   "com.Ysoup.restaurantmap", "com.Ysoup.CoolTime", "com.devkoan.FireTracker", "com.devkoan.StampCamera"])
    ])

    /// 남겨 둔 일정(받은 것), 없으면 `builtIn`.
    static func cachedSchedule(_ defaults: UserDefaults = .standard) -> LeeoSaleSchedule {
        guard let data = defaults.data(forKey: cacheKey),
              let schedule = try? JSONDecoder().decode(LeeoSaleSchedule.self, from: data) else { return builtIn }
        return schedule
    }

    /// 오늘 이 앱에 해당하는 할인.
    static func current(in schedule: LeeoSaleSchedule, bundleID: String?, now: Date) -> (LeeoSaleCampaign, LeeoSaleCampaign.Phase)? {
        for campaign in schedule.campaigns where campaign.includes(bundleID: bundleID) {
            if let phase = campaign.phase(on: now) { return (campaign, phase) }
        }
        return nil
    }

    /// 반나절에 한 번 원격 일정을 받는다. 실패하면 남겨 둔 것을 그대로 쓴다.
    static func refresh(_ defaults: UserDefaults = .standard, session: URLSession = .shared) async -> LeeoSaleSchedule {
        let cached = cachedSchedule(defaults)
        if let last = defaults.object(forKey: fetchedAtKey) as? Date, Date().timeIntervalSince(last) < refreshInterval {
            return cached
        }
        var request = URLRequest(url: remoteURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.httpMethod = "GET"
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let schedule = try? JSONDecoder().decode(LeeoSaleSchedule.self, from: data) else { return cached }
        defaults.set(data, forKey: cacheKey)
        defaults.set(Date(), forKey: fetchedAtKey)
        return schedule
    }

    // MARK: 얼마나 자주

    private static let lastShownKey = "leeo.sale.lastShown"
    private static let snoozeKey = "leeo.sale.snoozedUntil"

    /// 하루에 한 번, "3일 동안 보지 않기" 를 눌렀으면 그동안 쉰다.
    static func isDue(now: Date, defaults: UserDefaults = .standard, calendar: Calendar = .current) -> Bool {
        if let until = defaults.object(forKey: snoozeKey) as? Date, now < until { return false }
        if let last = defaults.object(forKey: lastShownKey) as? Date, calendar.isDate(last, inSameDayAs: now) { return false }
        return true
    }

    static func markShown(now: Date = Date(), defaults: UserDefaults = .standard) {
        defaults.set(now, forKey: lastShownKey)
    }

    static func snooze(days: Int = 3, now: Date = Date(), defaults: UserDefaults = .standard) {
        defaults.set(now.addingTimeInterval(TimeInterval(days) * 24 * 60 * 60), forKey: snoozeKey)
    }
}

// MARK: - 누구에게 · 얼마나

/// 배너 한 장에 들어갈 것.
struct LeeoSaleOffer: Equatable {
    var campaign: LeeoSaleCampaign
    var phase: LeeoSaleCampaign.Phase
    /// "최대 N%"
    var percent: Int
    /// 할인 중이고 값을 읽었으면 가장 많이 깎인 상품 하나.
    var best: Deal?

    struct Deal: Equatable {
        var name: String
        var regularPrice: String
        var offerPrice: String
        /// 첫 주 · 첫 달 · 첫 해
        var periodLabel: String
    }
}

#if canImport(StoreKit)
extension LeeoSale {

    /// 이 사람에게 띄울 배너. 이미 유료이거나, 첫 구독 할인을 받을 수 없으면 nil.
    static func offer(for campaign: LeeoSaleCampaign, phase: LeeoSaleCampaign.Phase) async -> LeeoSaleOffer? {
        let stores = LeeoStore.all
        if stores.contains(where: \.hasPro) { return nil }
        for await result in Transaction.currentEntitlements {
            if case .verified = result { return nil }
        }

        let ids = Array(Set(stores.flatMap(\.config.productIDs) + productIDs))
        let products = ids.isEmpty ? [] : ((try? await Product.products(for: ids)) ?? [])
        let subscriptions = products.filter { $0.type == .autoRenewable }
        // 상품을 못 읽었으면(오프라인 등) 일정만 믿고 띄운다. 구독이 하나도 없는 앱이면 받을 할인이 없다.
        if products.isEmpty { return LeeoSaleOffer(campaign: campaign, phase: phase, percent: campaign.percent) }
        guard !subscriptions.isEmpty else { return nil }

        var eligible = false
        var best: (percent: Int, deal: LeeoSaleOffer.Deal)?
        for product in subscriptions {
            guard let info = product.subscription, await info.isEligibleForIntroOffer else { continue }
            eligible = true
            guard phase == .live, let intro = info.introductoryOffer,
                  let percent = discount(regular: product.price, period: info.subscriptionPeriod, offer: intro) else { continue }
            if best == nil || percent > best!.percent {
                best = (percent, .init(name: product.displayName, regularPrice: product.displayPrice,
                                       offerPrice: intro.displayPrice, periodLabel: firstPeriodLabel(info.subscriptionPeriod)))
            }
        }
        guard eligible else { return nil }
        return LeeoSaleOffer(campaign: campaign, phase: phase, percent: best?.percent ?? campaign.percent, best: best?.deal)
    }

    /// 첫 한 기간을 깎아 주는 오퍼만 센다(무료 체험 · 여러 기간 묶음은 할인율로 말하기 어렵다).
    static func discount(regular: Decimal, period: Product.SubscriptionPeriod,
                         offer: Product.SubscriptionOffer) -> Int? {
        guard offer.paymentMode == .payAsYouGo || offer.paymentMode == .payUpFront,
              offer.period == period, offer.periodCount == 1 else { return nil }
        return percentOff(regular: regular, offer: offer.price)
    }

    static func firstPeriodLabel(_ period: Product.SubscriptionPeriod) -> String {
        switch period.unit {
        case .day: return L("첫 기간", comment: "Sale banner: price label for the first billing period (generic)")
        case .week: return L("첫 주", comment: "Sale banner: price label for the first week of a subscription")
        case .month: return L("첫 달", comment: "Sale banner: price label for the first month of a subscription")
        case .year: return L("첫 해", comment: "Sale banner: price label for the first year of a subscription")
        @unknown default: return L("첫 기간", comment: "Sale banner: price label for the first billing period (generic)")
        }
    }
}
#endif

extension LeeoSale {
    /// 깎인 비율(내림). 원래 값이 0 이하이거나 오퍼가 더 비싸면 nil.
    nonisolated static func percentOff(regular: Decimal, offer: Decimal) -> Int? {
        guard regular > 0, offer < regular else { return nil }
        let ratio = NSDecimalNumber(decimal: (regular - offer) / regular).doubleValue
        return Int((ratio * 100).rounded(.down))
    }
}
