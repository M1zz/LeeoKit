//
//  LeeoVoice.swift
//  LeeoKit
//
//  잘 쓰고 있는 사람에게 가끔, 한 문장만 묻는다.
//
//  만족도("즐겁게 쓰고 계신가요?")는 좋다 · 아쉽다 둘 중 하나만 알려 준다. 개발자가 알고 싶은 것은
//  그 너머다 — 어느 순간에 진짜 쓸모 있었는지, 무엇을 기대했는데 안 됐는지, 무엇이 더 있었으면
//  하는지. 긴 설문은 닫히니, 세 질문을 돌아가며 한 번에 하나, 한 문장만 받는다.
//
//  누구에게: 여러 날 여러 번 써 본 사람(`LeeoVoicePolicy`). 처음 써 보는 사람에게는 묻지 않는다.
//  언제: 마지막으로 물은 뒤 며칠이 지나고 그사이 새로 해낸 일(또는 실행)이 있을 때만.
//        리뷰 프롬프트를 띄운 직후에는 묻지 않는다. 연달아 넘기면 한 달 동안 조용히 있는다.
//  어디로: 피드백과 같은 허브(`LeeoFeedbackService`). `type` 이 `voice.*` 라 허브가 따로 묶는다.
//
//  앱이 할 일은 없다 — `.leeoSatisfactionCheck` 가 리뷰를 물을 때가 아니면 이것을 묻는다.
//  해낸 순간에 직접 묻고 싶으면 그 화면에 `.leeoVoiceCheck(Spec.self)` 를 단다.
//

#if !os(watchOS)
import SwiftUI

// MARK: - 질문

/// 돌아가며 묻는 세 질문. rawValue 는 허브 레코드의 `type` 에 그대로 저장된다 — 바꾸지 않는다.
public enum LeeoVoiceQuestion: String, CaseIterable, Identifiable, Sendable {
    /// 쓸모 있었던 순간 — 무엇이 이 앱의 진짜 쓰임인지.
    case useful = "voice.useful"
    /// 기대했는데 안 된 것 — 무엇을 약속한 줄 알았는지.
    case unmet = "voice.unmet"
    /// 하나 더 있었으면 하는 것.
    case wish = "voice.wish"

    public var id: String { rawValue }

    /// 분석 이벤트 꼬리표(`voice_shown:useful`).
    var tag: String { String(rawValue.dropFirst("voice.".count)) }

    public var title: String {
        switch self {
        case .useful: return L("요즘 가장 쓸모 있었던 순간은 언제였나요?", comment: "Voice question: most useful moment")
        case .unmet:  return L("기대했는데 안 돼서 아쉬웠던 게 있나요?", comment: "Voice question: unmet expectation")
        case .wish:   return L("딱 하나 더 생긴다면 무엇이면 좋겠어요?", comment: "Voice question: one wished feature")
        }
    }
}

// MARK: - 정책

public struct LeeoVoicePolicy: Sendable {
    /// 잘 쓰는 사람 — 이만큼 켰고, 설치한 지 이만큼 지났고,
    public var minLaunches: Int
    public var minDaysSinceInstall: Int
    /// 해낸 일이 이만큼 있거나(`registerSignificantEvent`), 그것을 세지 않는 앱이면 이만큼 켰다.
    public var minSignificantEvents: Int
    public var minLaunchesWithoutEvents: Int
    /// 한 번 물은 뒤 다시 묻기까지 — 날짜와, 그사이 새로 해낸 일(없으면 새 실행).
    public var intervalDays: Int
    public var newEventsSinceLast: Int
    public var newLaunchesSinceLast: Int
    /// 리뷰 프롬프트를 띄운 뒤 이만큼은 묻지 않는다 — 한자리에서 두 번 묻지 않게.
    public var daysAfterReviewPrompt: Int
    /// 연달아 이만큼 넘기면 `quietDays` 동안 묻지 않는다.
    public var skipsBeforeQuiet: Int
    public var quietDays: Int

    public init(minLaunches: Int = 5, minDaysSinceInstall: Int = 3,
                minSignificantEvents: Int = 3, minLaunchesWithoutEvents: Int = 10,
                intervalDays: Int = 5, newEventsSinceLast: Int = 2, newLaunchesSinceLast: Int = 3,
                daysAfterReviewPrompt: Int = 2, skipsBeforeQuiet: Int = 3, quietDays: Int = 30) {
        self.minLaunches = minLaunches
        self.minDaysSinceInstall = minDaysSinceInstall
        self.minSignificantEvents = minSignificantEvents
        self.minLaunchesWithoutEvents = minLaunchesWithoutEvents
        self.intervalDays = intervalDays
        self.newEventsSinceLast = newEventsSinceLast
        self.newLaunchesSinceLast = newLaunchesSinceLast
        self.daysAfterReviewPrompt = daysAfterReviewPrompt
        self.skipsBeforeQuiet = skipsBeforeQuiet
        self.quietDays = quietDays
    }

    public static let `default` = LeeoVoicePolicy()
}

// MARK: - 언제 무엇을 묻나

public enum LeeoVoice {
    /// 한 문장이라도 길게 쓰는 사람이 있다. 이보다 길면 자른다.
    public static let maxLength = 280

    /// 지금 물을 질문. 물을 때가 아니면 nil.
    public static func nextQuestion(policy: LeeoVoicePolicy = .default,
                                    engagement: LeeoEngagement = .shared,
                                    now: Date = Date()) -> LeeoVoiceQuestion? {
        let events = engagement.significantEventCount
        let launches = engagement.launchCount
        guard launches >= policy.minLaunches,
              engagement.daysSinceInstall >= policy.minDaysSinceInstall,
              events >= policy.minSignificantEvents || launches >= policy.minLaunchesWithoutEvents
        else { return nil }

        if let quiet = engagement.voiceValue("quietUntil") as? Date, now < quiet { return nil }
        if let review = engagement.lastPromptDate(LeeoReviewRequest.promptID),
           days(from: review, to: now) < policy.daysAfterReviewPrompt { return nil }
        if let last = engagement.voiceValue("lastAsked") as? Date {
            guard days(from: last, to: now) >= policy.intervalDays else { return nil }
            let eventsThen = engagement.voiceValue("eventsAtAsk") as? Int ?? 0
            let launchesThen = engagement.voiceValue("launchesAtAsk") as? Int ?? 0
            let movedOn = events > 0
                ? events - eventsThen >= policy.newEventsSinceLast
                : launches - launchesThen >= policy.newLaunchesSinceLast
            guard movedOn else { return nil }
        }
        let index = engagement.voiceValue("nextIndex") as? Int ?? 0
        return LeeoVoiceQuestion.allCases[index % LeeoVoiceQuestion.allCases.count]
    }

    /// 띄우는 순간 — 닫혀도 같은 질문을 바로 다시 묻지 않게 먼저 적는다.
    public static func markShown(_ question: LeeoVoiceQuestion, engagement: LeeoEngagement = .shared,
                                 now: Date = Date()) {
        engagement.setVoiceValue(now, "lastAsked")
        engagement.setVoiceValue(engagement.significantEventCount, "eventsAtAsk")
        engagement.setVoiceValue(engagement.launchCount, "launchesAtAsk")
        let index = LeeoVoiceQuestion.allCases.firstIndex(of: question) ?? 0
        engagement.setVoiceValue(index + 1, "nextIndex")
        LeeoAnalyticsCenter.track(.custom(name: "voice_shown:\(question.tag)", parameters: [:]))
    }

    static func markSent(_ question: LeeoVoiceQuestion, engagement: LeeoEngagement = .shared) {
        engagement.setVoiceValue(0, "skips")
        LeeoAnalyticsCenter.track(.custom(name: "voice_sent:\(question.tag)", parameters: [:]))
    }

    static func markSkipped(policy: LeeoVoicePolicy = .default, engagement: LeeoEngagement = .shared,
                            now: Date = Date()) {
        let skips = (engagement.voiceValue("skips") as? Int ?? 0) + 1
        if skips >= policy.skipsBeforeQuiet {
            engagement.setVoiceValue(Calendar.current.date(byAdding: .day, value: policy.quietDays, to: now), "quietUntil")
            engagement.setVoiceValue(0, "skips")
        } else {
            engagement.setVoiceValue(skips, "skips")
        }
    }

    private static func days(from: Date, to: Date) -> Int {
        Calendar.current.dateComponents([.day], from: from, to: to).day ?? 0
    }
}

// MARK: - 화면

struct LeeoVoiceSheet<Spec: LeeoAppSpec>: View {
    let question: LeeoVoiceQuestion
    let policy: LeeoVoicePolicy
    let engagement: LeeoEngagement

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var sent = false
    @State private var answered = false
    @FocusState private var focused: Bool

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if sent {
                Label(L("고마워요! 잘 전해졌어요.", comment: "Voice: sent thanks"), systemImage: "heart.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                Text(question.title)
                    .font(.title3.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(L("개발자가 한 줄씩 직접 읽어요.", comment: "Voice: the developer reads each line"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextField(L("한 문장이면 충분해요", comment: "Voice: answer placeholder"), text: $text, axis: .vertical)
                    .lineLimit(1...4)
                    .textFieldStyle(.roundedBorder)
                    .focused($focused)
                    .onChange(of: text) { _, new in
                        if new.count > LeeoVoice.maxLength { text = String(new.prefix(LeeoVoice.maxLength)) }
                    }
                    .onSubmit(send)
                HStack {
                    Button(L("다음에", comment: "Voice: not now")) { dismiss() }
                        .buttonStyle(.bordered)
                    Spacer()
                    Button(L("보내기", comment: "Voice: send"), action: send)
                        .buttonStyle(.borderedProminent)
                        .disabled(trimmed.isEmpty)
                }
            }
        }
        .padding(20)
        #if os(iOS) || os(visionOS)
        .presentationDetents([.height(300)])
        #else
        .frame(minWidth: 380)
        #endif
        .onAppear { focused = true }
        // 보내지 않고 닫았으면 넘긴 것으로 센다 — "다음에" 든 쓸어내리기든.
        .onDisappear { if !answered { LeeoVoice.markSkipped(policy: policy, engagement: engagement) } }
    }

    private func send() {
        let message = trimmed
        guard !message.isEmpty, !answered else { return }
        answered = true
        LeeoVoice.markSent(question, engagement: engagement)
        // 보내기는 기다리지 않는다 — 못 가면(오프라인 · iCloud 없음) 그 한 줄은 놓친다. 다시 묻지 않는다.
        Task.detached {
            do {
                try await LeeoFeedbackService(spec: Spec.self).submit(
                    type: question.rawValue, message: message,
                    deviceInfo: LeeoFeedbackService.composeDeviceInfo(base: LeeoFeedbackService.baseDeviceInfo(),
                                                                      extra: ["질문: \(question.tag)"]))
            } catch {
                print("⚠️ [LeeoVoice.send] 한 문장을 보내지 못했습니다: \(error)")
            }
        }
        withAnimation { sent = true }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            dismiss()
        }
    }
}

// MARK: - 자동으로 묻기

struct LeeoVoiceCheckModifier<Spec: LeeoAppSpec>: ViewModifier {
    let policy: LeeoVoicePolicy
    let engagement: LeeoEngagement
    let delay: Double
    @State private var question: LeeoVoiceQuestion?

    func body(content: Content) -> some View {
        content
            .task {
                guard let next = LeeoVoice.nextQuestion(policy: policy, engagement: engagement) else { return }
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                LeeoVoice.markShown(next, engagement: engagement)
                question = next
            }
            .sheet(item: $question) { question in
                LeeoVoiceSheet<Spec>(question: question, policy: policy, engagement: engagement)
            }
    }
}

public extension View {
    /// 잘 쓰는 사람에게 때가 되면 한 문장을 묻는다(`LeeoVoicePolicy`). `.leeoSatisfactionCheck` 를 단 앱은
    /// 이미 들어 있다 — 해낸 순간의 화면(저장을 마친 화면 등)에서 따로 묻고 싶을 때 단다.
    func leeoVoiceCheck<Spec: LeeoAppSpec>(_ spec: Spec.Type,
                                           policy: LeeoVoicePolicy = .default,
                                           engagement: LeeoEngagement = .shared,
                                           delay: Double = 1.2) -> some View {
        modifier(LeeoVoiceCheckModifier<Spec>(policy: policy, engagement: engagement, delay: delay))
    }
}
#endif
