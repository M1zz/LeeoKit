//
//  LeeoLadder.swift
//  LeeoKit
//
//  무료 · Plus · Pro 세 칸 요금제의 공통 규칙(2026-10 페이월 개편).
//
//   · 유료 칸마다 연 구독과 평생을 나란히 둔다. 평생은 연 구독의 3배 이상이다.
//   · 구독 중인 사람에게는 6개월째와 갱신 7일 전에 '구독 졸업' 평생가를 한 번씩 보인다(`LeeoGraduation`).
//   · 언제나 평생 패스 하나로 모든 앱이 열린다(`LeeoForeverPass`).
//
//  칸마다 무엇이 열리는지는 앱이 정한다. 여기는 앱마다 같은 것만 둔다.
//

import Foundation
#if canImport(StoreKit)
import StoreKit
#endif

/// 유료 칸을 사는 두 가지 길.
public enum LeeoPlanTerm: String, CaseIterable, Sendable {
    case yearly, lifetime
}

// MARK: - 구독 졸업

/// 구독 중인 사람이 평생으로 옮겨 갈 때를 정한다.
///
/// 평생 가격을 연 구독의 3배 이상으로 높게 둔 만큼, 이미 구독료를 낸 사람에게는 졸업가(평생의 약 30% 할인)로
/// 길을 터 준다. 구독에 묶였다고 느끼는 사람이 언제든 나갈 수 있게 하는 것이 목적이다.
public enum LeeoGraduation {

    /// 지금 살아 있는 구독 하나.
    public struct Subscription: Equatable, Sendable {
        public let productID: String
        /// 처음 구독한 날(갱신을 거쳐도 그대로).
        public let since: Date
        /// 다음 갱신일. 모르면 nil.
        public let renewsAt: Date?
        /// 갱신이 켜져 있는가. 이미 해지했으면 갱신 앞 제안은 하지 않는다.
        public let willRenew: Bool

        public init(productID: String, since: Date, renewsAt: Date?, willRenew: Bool) {
            self.productID = productID
            self.since = since
            self.renewsAt = renewsAt
            self.willRenew = willRenew
        }
    }

    /// 6개월째에 한 번.
    public static let firstOfferAfterMonths = 6
    /// 갱신 며칠 전에 한 번.
    public static let daysBeforeRenewal = 7

    /// 지금 졸업가를 보일 때인가. 창(6개월째 · 갱신 7일 전)마다 한 번만 보인다.
    /// - Parameter lastOffered: 마지막으로 보인 때(`markOffered`).
    public static func isDue(_ sub: Subscription, now: Date = Date(), lastOffered: Date?,
                             calendar: Calendar = .current) -> Bool {
        var windows: [Date] = []
        if let sixMonths = calendar.date(byAdding: .month, value: firstOfferAfterMonths, to: sub.since), sixMonths <= now {
            windows.append(sixMonths)
        }
        if sub.willRenew, let renews = sub.renewsAt,
           let start = calendar.date(byAdding: .day, value: -daysBeforeRenewal, to: renews),
           start <= now, now < renews {
            windows.append(start)
        }
        guard let latest = windows.max() else { return false }
        return (lastOffered ?? .distantPast) < latest
    }

    private static let offeredKey = "leeo.graduation.lastOffered"

    public static func lastOffered(defaults: UserDefaults = .standard) -> Date? {
        defaults.object(forKey: offeredKey) as? Date
    }

    public static func markOffered(_ date: Date = Date(), defaults: UserDefaults = .standard) {
        defaults.set(date, forKey: offeredKey)
    }

    #if canImport(StoreKit)
    /// `productIDs` 가운데 지금 살아 있는 자동 갱신 구독. 없으면 nil.
    public static func currentSubscription(among productIDs: Set<String>) async -> Subscription? {
        for await result in Transaction.currentEntitlements {
            guard case .verified(let tx) = result,
                  tx.productType == .autoRenewable,
                  productIDs.contains(tx.productID),
                  tx.revocationDate == nil else { continue }
            var willRenew = true
            if let product = try? await Product.products(for: [tx.productID]).first,
               let statuses = try? await product.subscription?.status,
               let mine = statuses.first(where: {
                   if case .verified(let t) = $0.transaction { return t.originalID == tx.originalID }
                   return false
               }),
               case .verified(let renewal) = mine.renewalInfo {
                willRenew = renewal.willAutoRenew
            }
            return Subscription(productID: tx.productID, since: tx.originalPurchaseDate,
                                renewsAt: tx.expirationDate, willRenew: willRenew)
        }
        return nil
    }
    #endif
}

// MARK: - 평생 가격 안내

/// 평생 가격을 올리기 전에 알리는 날. 그날 전까지만 페이월에 한 줄을 보인다(`LeeoLifetimePriceNotice`).
/// 이미 산 사람은 그대로 쓴다.
public enum LeeoLadderSchedule {
    /// 2026-10 개편의 평생 가격 인상일(App Store Connect 가격 일정과 같은 날).
    public static let lifetimePriceChange: Date = {
        var c = DateComponents()
        c.year = 2026; c.month = 11; c.day = 17
        return Calendar(identifier: .gregorian).date(from: c) ?? .distantPast
    }()

    public static func showsLifetimeNotice(now: Date = Date()) -> Bool { now < lifetimePriceChange }
}

// MARK: - 언제나 평생 패스

/// 한 번 사면 이 개발자의 **모든 앱**이 Plus · Pro 평생으로 열리는 패스.
///
/// App Store 상품은 앱마다 따로라서, 앱마다 같은 끝자리의 상품(`<번들 ID>.forever` …)을 판다.
/// 산 앱은 Apple 이 서명한 결제(JWS)를 같은 Apple 계정의 iCloud(피드백 허브 컨테이너의 비공개 DB)에 남기고,
/// 다른 앱은 그 서명을 확인해서 연다(`LeeoGiftJWS`, 선물과 같은 확인).
///
/// ⚠️ CloudKit Dashboard: 개발 환경에서 한 번 사면 비공개 DB 에 `LeeoForeverPass` 타입이 생긴다.
///    **스키마를 Production 으로 배포해야** 출시 빌드끼리 패스를 나눠 본다. 배포 전에도 산 앱에서는 열린다.
/// ⚠️ 새 앱이 생기면 `family` 에 번들 ID 를 더한다. 더하기 전 버전의 앱은 그 앱에서 산 패스를 모른다.
public enum LeeoForeverPassRule {

    /// 패스 상품의 끝자리. 앞에 그 앱의 번들 ID 가 붙는다.
    public enum Kind: String, CaseIterable, Sendable {
        /// 평생.
        case lifetime = "forever"
        /// 연 구독.
        case yearly = "forever.yearly"
        /// 어느 앱이든 평생 Pro 를 산 사람의 패스.
        case upgrade = "forever.upgrade"
        /// 패스 구독자의 졸업가.
        case graduate = "forever.graduate"
    }

    public static func productID(_ kind: Kind, bundleID: String) -> String { "\(bundleID).\(kind.rawValue)" }

    public static func productIDs(bundleID: String) -> [String] {
        Kind.allCases.map { productID($0, bundleID: bundleID) }
    }

    /// 패스를 믿는 앱들(App Store Connect 의 이 개발자 계정 앱, 2026-10-27).
    public static let family: Set<String> = [
        "club.strollerway.app",
        "com.Ysoup.CoolTime",
        "com.Ysoup.LeaveWise",
        "com.Ysoup.TokenMemo",
        "com.Ysoup.restaurantmap",
        "com.bucketclimb.app",
        "com.burningparchment.app",
        "com.devkoan.AccessibilityNeeds",
        "com.devkoan.CalendarSnap",
        "com.devkoan.FireTracker",
        "com.devkoan.IndonesianSmallTalk",
        "com.devkoan.PairCompass",
        "com.devkoan.ScheduleDensityApp",
        "com.devkoan.StaffSinger",
        "com.devkoan.StampCamera",
        "com.devkoan.TimeExchange",
        "com.devkoan.externalize",
        "com.devkoan.jamband",
        "com.devkoan.shutterlink",
        "com.devkoan.worryparking",
        "com.example.MoonlitOrder",
        "com.example.PohangExplorer",
        "com.example.ScheduleDensityApp",
        "com.family.FamilyBank",
        "com.family.familycourt",
        "com.gaebaljari.JLPTN3Resources",
        "com.hyunholee.TrackpadServer",
        "com.kora.leeo",
        "com.lectureq.LectureQ",
        "com.leeo.BartenderPractice",
        "com.leeo.DDayCounter",
        "com.leeo.DontGoMart",
        "com.leeo.FindMe",
        "com.leeo.FootprintDiary",
        "com.leeo.HandsFreeLab",
        "com.leeo.HandsFreeMetronome",
        "com.leeo.JuJob",
        "com.leeo.JuniorDevMistakes",
        "com.leeo.KACCoachingLog",
        "com.leeo.LeeoCon",
        "com.leeo.LullabyRecipe",
        "com.leeo.PixelMe",
        "com.leeo.ReboundJournal",
        "com.leeo.RotoscopeiPad",
        "com.leeo.SkyDex",
        "com.leeo.SoundLab",
        "com.leeo.StickyPresenter",
        "com.leeo.StickyPresenter.Remote",
        "com.leeo.StoryMood",
        "com.leeo.TetraTint",
        "com.leeo.TrackpadRemote",
        "com.leeo.balancedmenu",
        "com.leeo.bookmarkshot",
        "com.leeo.comfortcoach",
        "com.leeo.geusaie",
        "com.leeo.higgym",
        "com.leeo.japantransit",
        "com.leeo.manmulpouch",
        "com.leeo.moa",
        "com.leeo.slidesnap",
        "com.leeo.sunflower",
        "com.leeo.thinkflow",
        "com.leeo.wifisnap",
        "com.leeo.yeoul",
        "com.lottochecker.app",
        "com.querio.app",
        "com.xa.toki",
        "com.ysoup.RapportMap",
        "com.ysoup.RoutineCamera",
        "com.ysoup.TokenMemo-tap",
    ]

    /// 확인을 마친 결제가 **지금** 패스를 여는가.
    /// - Parameter acceptsSandbox: 출시 빌드는 false. 시험 결제(샌드박스 · TestFlight)로 출시 앱이 열리지 않게.
    static func opens(_ tx: LeeoSignedGiftTransaction, now: Date = Date(), acceptsSandbox: Bool) -> Bool {
        guard family.contains(tx.bundleID),
              Kind.allCases.contains(where: { tx.productID == productID($0, bundleID: tx.bundleID) }),
              tx.revocationDate == nil else { return false }
        if !acceptsSandbox && tx.environment != "Production" { return false }
        if let expires = tx.expiresDate, expires <= now { return false }
        return true
    }
}
