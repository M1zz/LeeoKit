//
//  LeeoCelebration.swift
//  LeeoKit
//
//  **모든 사용자가 적어도 한 번은 축하나 감사를 받는다.**
//
//  - 방금 유료가 됐다(구매 · 선물 코드 · 등급 올림) → 콘페티 + "축하합니다! 이제 Pro입니다"
//  - 이미 유료다(업데이트 뒤 · 새 기기 · 복원)       → 하트 + "감사합니다! Pro로 함께해 주셔서 고마워요"  (등급마다 한 번)
//  - 무료 사용자                                    → 하트 + "반가워요!" (처음) / "감사합니다!" (원래 쓰던 사람)  (한 번)
//
//  판정은 `LeeoStore` 가 권한을 다시 읽을 때마다 알아서 한다 — 앱은 결제 화면마다 축하를 붙일 일이 없다.
//  앱이 할 일은 루트 화면에 한 줄뿐이다(온보딩이 끝난 뒤 보이는 화면):
//
//      ContentView()
//          .leeoCelebrations(appName: MyAppSpec.displayName)
//

import SwiftUI

// MARK: - 순간

public enum LeeoCelebrationMoment: Equatable, Sendable {
    /// 앱을 쓰는 중에 유료 등급이 생겼거나 올랐다. 콘페티.
    case upgraded(tier: String)
    /// 이미 유료다. 하트.
    case paidThanks(tier: String)
    /// 무료 사용자에게 한 번. `firstTime` 이면 처음 설치한 사람.
    case welcome(appName: String, firstTime: Bool)

    /// 한꺼번에 오면 높은 쪽이 이긴다.
    var rank: Int {
        switch self {
        case .upgraded: return 2
        case .paidThanks: return 1
        case .welcome: return 0
        }
    }

    var isConfetti: Bool { if case .upgraded = self { return true }; return false }

    var title: String {
        switch self {
        case .upgraded: return L("축하합니다!", comment: "Celebration: title right after becoming a paid user")
        case .paidThanks: return L("감사합니다!", comment: "Celebration: title thanking a paid user")
        case .welcome(_, let first):
            return first ? L("반가워요!", comment: "Celebration: title welcoming a new user")
                         : L("감사합니다!", comment: "Celebration: title thanking a paid user")
        }
    }

    var lines: [String] {
        switch self {
        case .upgraded(let tier):
            return [String(format: L("이제 %@입니다", comment: "Celebration: you are now on this plan. %@ = plan name such as Pro or Plus"), tier),
                    L("응원해 주셔서 고마워요.", comment: "Celebration: thanks for supporting, under the plan line")]
        case .paidThanks(let tier):
            return [String(format: L("%@로 함께해 주셔서 고마워요.", comment: "Celebration: thanks for being on this plan. %@ = plan name such as Pro or Plus"), tier)]
        case .welcome(let app, let first):
            return [first ? String(format: L("%@에 와 주셔서 고마워요.", comment: "Celebration: welcome a new user. %@ = app name"), app)
                          : L("늘 함께해 주셔서 고마워요.", comment: "Celebration: thank a returning user")]
        }
    }
}

// MARK: - 판정

@MainActor
public final class LeeoCelebration: ObservableObject {
    public static let shared = LeeoCelebration()

    /// 지금 보여 줄 순간. 닫으면 nil.
    @Published public private(set) var current: LeeoCelebrationMoment?

    private let defaults: UserDefaults
    private static let doneKey = "leeo.celebration.done"
    /// 한 실행 안에서 이미 축하한 등급 — 스토어가 여럿이어도 한 번만.
    private var upgradedThisRun: Set<String> = []

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    private var done: Set<String> { Set(defaults.stringArray(forKey: Self.doneKey) ?? []) }
    private func markDone(_ key: String) { defaults.set(Array(done.union([key])), forKey: Self.doneKey) }

    private func show(_ moment: LeeoCelebrationMoment) {
        if let current, current.rank > moment.rank { return }
        current = moment
    }

    /// 유료 등급을 알려 준다. `LeeoStore` 를 쓰면 저절로 불린다 — 자체 스토어를 쓰는 앱만 권한을 다시 읽은 뒤 부른다.
    /// `justNow` 면 이 실행에서 생겼거나 오른 것(축하), 아니면 이미 유료(등급마다 한 번 감사).
    /// TestFlight · 개발 강제 해제처럼 산 게 아닌 권한으로는 부르지 않는다.
    public func noteOwned(tierID: String, tierName: String, justNow: Bool) {
        let key = "tier." + tierID
        if justNow {
            guard !upgradedThisRun.contains(key) else { return }
            upgradedThisRun.insert(key)
            markDone(key)
            show(.upgraded(tier: tierName))
        } else if !done.contains(key) {
            markDone(key)
            show(.paidThanks(tier: tierName))
        }
    }

    /// 무료 사용자에게 한 번(유료 감사를 이미 받았으면 건너뛴다). 루트 화면이 뜬 뒤 부른다.
    func welcomeOnce(appName: String, firstTime: Bool) {
        let seen = done
        guard !seen.contains("welcome") else { return }
        markDone("welcome")
        guard current == nil, !seen.contains(where: { $0.hasPrefix("tier.") }) else { return }
        show(.welcome(appName: appName, firstTime: firstTime))
    }

    public func dismiss() { current = nil }
}

// MARK: - 화면

// 손목에는 띄우지 않는다.
#if !os(watchOS)
public extension View {
    /// 축하 · 감사를 이 화면 위에 띄운다. 앱의 루트(온보딩이 끝난 뒤 보이는 화면)에 한 번 붙인다.
    func leeoCelebrations(appName: String) -> some View {
        modifier(LeeoCelebrationHost(appName: appName))
    }
}

struct LeeoCelebrationHost: ViewModifier {
    let appName: String
    @ObservedObject private var center = LeeoCelebration.shared

    func body(content: Content) -> some View {
        content
            .overlay {
                if let moment = center.current {
                    LeeoCelebrationView(moment: moment) { center.dismiss() }
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: center.current)
            // 새 버전이 나왔으면 무엇이 좋아졌는지 아래쪽 카드로 한 번 (LeeoUpdate).
            .leeoUpdateBanner()
            .task {
                // 스토어가 권한을 먼저 읽을 틈을 준다 — 유료 사용자에게 '반가워요' 가 먼저 뜨지 않게.
                try? await Task.sleep(for: .seconds(2))
                center.welcomeOnce(appName: appName, firstTime: LeeoEngagement.shared.launchCount <= 1)
            }
    }
}

struct LeeoCelebrationView: View {
    let moment: LeeoCelebrationMoment
    let onClose: () -> Void
    @Environment(\.leeoStyle) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)
                .accessibilityHidden(true)

            if !reduceMotion {
                LeeoParticles(kind: moment.isConfetti ? .confetti : .hearts, accent: theme.accent)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }

            VStack(spacing: 14) {
                if moment.isConfetti {
                    Image(systemName: "party.popper.fill")
                        .font(.system(size: 52, weight: .semibold))
                        .foregroundStyle(theme.accent)
                        .accessibilityHidden(true)
                } else {
                    LeeoThanksHeart(color: theme.accent)
                }
                Text(moment.title)
                    .font(.title.bold())
                    .foregroundStyle(theme.text)
                ForEach(Array(moment.lines.enumerated()), id: \.offset) { index, line in
                    Text(line)
                        .font(index == 0 && moment.isConfetti ? .title3.weight(.semibold) : .body)
                        .foregroundStyle(index == 0 && moment.isConfetti ? theme.text : theme.textMuted)
                }
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

                Button(action: onClose) {
                    Text(L("좋아요", comment: "Celebration: close button"))
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(RoundedRectangle(cornerRadius: theme.radiusSm + 4, style: .continuous).fill(theme.accent))
                }
                .buttonStyle(.plain)
                .padding(.top, 6)
            }
            .padding(28)
            .frame(maxWidth: 340)
            .background(RoundedRectangle(cornerRadius: theme.radiusLg, style: .continuous).fill(theme.surface))
            .shadow(color: .black.opacity(0.2), radius: 24, y: 8)
            .padding(24)
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
        }
        .onAppear {
            AccessibilityNotification.Announcement(([moment.title] + moment.lines).joined(separator: " ")).post()
            #if canImport(UIKit) && !os(visionOS)
            HapticManager.shared.success()
            #endif
        }
    }
}

// MARK: - 콘페티 · 하트

struct LeeoParticles: View {
    enum Kind { case confetti, hearts }
    let kind: Kind
    let accent: Color

    private struct Particle {
        let x: Double, delay: Double, speed: Double, drift: Double, spin: Double, size: Double, color: Color, round: Bool
    }

    private static let duration = 3.2
    @State private var start = Date()
    @State private var particles: [Particle] = []

    var body: some View {
        TimelineView(.animation(paused: Date().timeIntervalSince(start) > Self.duration + 1)) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSince(start)
                let heart = context.resolve(Image(systemName: "heart.fill"))
                for p in particles {
                    let life = (t - p.delay) / (Self.duration - p.delay)
                    guard life > 0, life < 1 else { continue }
                    let opacity = life > 0.75 ? (1 - life) / 0.25 : 1
                    var ctx = context
                    ctx.opacity = opacity
                    switch kind {
                    case .confetti:
                        // 위에서 흩날리며 떨어진다
                        let y = -20 + life * (size.height + 40) * p.speed
                        let x = p.x * size.width + sin(life * .pi * 2 * p.drift) * 24
                        ctx.translateBy(x: x, y: y)
                        ctx.rotate(by: .radians(life * p.spin))
                        let rect = CGRect(x: -p.size / 2, y: -p.size / 4, width: p.size, height: p.round ? p.size : p.size / 2)
                        ctx.fill(p.round ? Path(ellipseIn: rect) : Path(rect), with: .color(p.color))
                    case .hearts:
                        // 아래에서 떠오른다
                        let y = size.height + 20 - life * (size.height * 0.75) * p.speed
                        let x = p.x * size.width + sin(life * .pi * 2 * p.drift) * 18
                        ctx.translateBy(x: x, y: y)
                        ctx.scaleBy(x: p.size / 18, y: p.size / 18)
                        ctx.addFilter(.colorMultiply(p.color))
                        ctx.draw(heart, at: .zero)
                    }
                }
            }
        }
        .onAppear {
            start = Date()
            let palette: [Color] = kind == .confetti
                ? [accent, .pink, .yellow, .mint, .orange, .purple, .blue]
                : [.pink, .red, accent, .pink.opacity(0.7)]
            particles = (0..<(kind == .confetti ? 90 : 26)).map { _ in
                Particle(x: .random(in: 0...1), delay: .random(in: 0...(kind == .confetti ? 0.6 : 1.2)),
                         speed: .random(in: 0.8...1.15), drift: .random(in: 0.5...1.5),
                         spin: .random(in: -12...12), size: kind == .confetti ? .random(in: 7...12) : .random(in: 14...30),
                         color: palette.randomElement()!, round: .random())
            }
        }
    }
}
#endif
