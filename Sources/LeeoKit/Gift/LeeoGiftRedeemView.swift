//
//  LeeoGiftRedeemView.swift
//  LeeoKit
//
//  받은 선물 코드를 넣는 화면. 받은 메시지를 통째로 붙여넣어도 코드를 찾아낸다.
//

import SwiftUI

public struct LeeoGiftRedeemView<Spec: LeeoAppSpec>: View {
    @ObservedObject private var gift: LeeoGiftStore
    @Environment(\.leeoStyle) private var theme
    @State private var input: String
    private let onContactSupport: (() -> Void)?

    /// - Parameters:
    ///   - code: 링크로 들어왔을 때 미리 채울 코드.
    ///   - onContactSupport: 받기가 안 될 때 문의 창을 연다(`LeeoGiftSupport`). nil 이면 문의 줄이 없다.
    public init(gift: LeeoGiftStore, code: String = "", onContactSupport: (() -> Void)? = nil) {
        self.gift = gift
        _input = State(initialValue: LeeoGiftCode.typed(code))
        self.onContactSupport = onContactSupport
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: isDone ? "checkmark.seal.fill" : "giftcard.fill")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(isDone ? Color.green : theme.accent)
                    .frame(width: 84, height: 84)
                    .background(Circle().fill((isDone ? Color.green : theme.accent).opacity(0.14)))
                    .accessibilityHidden(true)
                    .padding(.top, 8)

                if gift.redeemed != nil {
                    done
                } else if gift.testRedeemedCode != nil {
                    testDone
                } else {
                    form
                }
                if let onContactSupport {
                    LeeoGiftSupportRow(gift: gift, onContact: onContactSupport)
                }
            }
            .padding(20)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .background(theme.bg.ignoresSafeArea())
        .navigationTitle(LeeoGiftText.redeemEntry)
        .onDisappear { gift.clearTestResult() }
        // 입력칸이 사라지고 결과가 서는 것을 VoiceOver 에도 말해 준다.
        .onChange(of: isDone) { _, done in
            guard done else { return }
            AccessibilityNotification.Announcement(gift.redeemed != nil ? doneTitle : testDoneTitle).post()
        }
    }

    private var isDone: Bool { gift.redeemed != nil || gift.testRedeemedCode != nil }
    private var doneTitle: String { L("선물받은 Pro가 열렸어요", comment: "Gift: redeem success title") }
    private var testDoneTitle: String {
        L("시험 선물이 끝까지 처리됐어요", comment: "Gift (developer test): test gift went through the whole redeem path")
    }

    private var form: some View {
        VStack(spacing: 16) {
            Text(L("받은 코드를 넣으면 Pro가 바로 열려요. 받은 메시지를 통째로 붙여넣어도 돼요.",
                   comment: "Gift: redeem screen explanation"))
                .font(.body)
                .foregroundStyle(theme.textMuted)
                .multilineTextAlignment(.center)

            LeeoGiftCodeBoxes(code: $input, onSubmit: redeem)
            PasteButton(payloadType: String.self) { strings in
                guard let text = strings.first else { return }
                Task { @MainActor in
                    input = LeeoGiftCode.typed(text)
                }
            }
            .labelStyle(.titleAndIcon)

            Button(action: redeem) {
                HStack {
                    if gift.isWorking { ProgressView().tint(.white) }
                    Text(L("선물 받기", comment: "Gift: redeem button")).font(.headline)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(RoundedRectangle(cornerRadius: theme.radiusSm + 4, style: .continuous)
                    .fill(theme.accent.opacity(canSubmit ? 1 : 0.4)))
            }
            .buttonStyle(.plain)
            .disabled(!canSubmit)

            if let error = gift.lastError {
                Text(error.localizedDescription)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var done: some View {
        VStack(spacing: 10) {
            Text(doneTitle)
                .font(.title2.bold())
                .foregroundStyle(theme.text)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text(L("같은 iCloud 계정이면 다른 기기에서도 이전 구매 복원으로 다시 열려요.",
                   comment: "Gift: redeemed gift restores on other devices"))
                .font(.body)
                .foregroundStyle(theme.textMuted)
                .multilineTextAlignment(.center)
        }
    }

    /// 시험 선물이 끝까지 지나갔다. **Pro 는 열리지 않았다**는 것을 분명히 말한다.
    private var testDone: some View {
        VStack(spacing: 10) {
            Text(testDoneTitle)
                .font(.title2.bold())
                .foregroundStyle(theme.text)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text(L("시험 코드라 Pro는 열리지 않아요. 같은 코드를 다시 넣으면 이미 받은 선물로 나와야 맞아요.",
                   comment: "Gift (developer test): explains a test code does not unlock Pro, and re-entering it should say already used"))
                .font(.body)
                .foregroundStyle(theme.textMuted)
                .multilineTextAlignment(.center)
            Button {
                gift.clearTestResult()
                input = ""
            } label: {
                Text(L("다시 넣어 보기", comment: "Gift (developer test): try entering a code again"))
                    .font(.headline)
            }
            .padding(.top, 6)
        }
    }

    /// 여덟 칸이 다 차야 보낸다. 칸에는 코드에 쓰는 글자만 들어간다(`LeeoGiftCode.typed`).
    private var canSubmit: Bool {
        !gift.isWorking && input.count == LeeoGiftCode.length
    }

    private func redeem() {
        guard canSubmit else { return }
        Task { await gift.redeem(input) }
    }
}

// MARK: - 여덟 칸

/// 선물 코드를 넣는 여덟 칸. 넷 · 넷으로 나누고 사이에 줄표를 **그려 둔다.**
///
/// 왜 칸인가: 코드는 `ABCD-EFGH` 로 보이지만 칠 때 줄표를 넣을지 말지 헷갈린다. 한 줄 입력칸이면
/// 넣은 사람과 안 넣은 사람의 글자 수가 달라 몇 자를 더 쳐야 하는지 안 보였다. 칸이면 남은 칸이 보이고,
/// 줄표는 칸 사이에 이미 그려져 있어 칠 필요가 없다.
///
/// ⚠️ 실제로 받는 것은 보이지 않는 입력칸 하나다. 칸마다 입력칸을 두면 붙여넣기 · 지우기 · 음성 입력이
///    칸을 넘나들 때 어긋난다. 받은 메시지를 통째로 붙여넣어도 코드만 골라 넣는다.
/// ⚠️ 그 입력칸은 칸들 **뒤에 같은 폭으로** 깐다. VoiceOver 는 칸 자리를 만지면 입력칸을 찾고,
///    음성 명령은 "선물 코드 탭" 으로 누른다. 1pt 짜리였을 때는 손가락으로 찾을 수 없었다.
struct LeeoGiftCodeBoxes: View {
    @Binding var code: String
    var onSubmit: () -> Void

    @Environment(\.leeoStyle) private var theme
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<LeeoGiftCode.length, id: \.self) { index in
                if index == LeeoGiftCode.length / 2 {
                    Text(verbatim: "-")
                        .font(.system(.title3, design: .monospaced).weight(.semibold))
                        .foregroundStyle(theme.textMuted)
                }
                box(at: index)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
        .accessibilityHidden(true)
        .background { field }
        .onAppear {
            // 링크로 코드가 다 채워져 온 게 아니면 바로 칠 수 있게.
            if code.count < LeeoGiftCode.length { focused = true }
        }
    }

    private var field: some View {
        TextField("", text: Binding(get: { code }, set: { code = LeeoGiftCode.typed($0) }))
            .focused($focused)
            .autocorrectionDisabled()
            #if os(iOS)
            .textInputAutocapitalization(.characters)
            .keyboardType(.asciiCapable)
            #endif
            .onSubmit(onSubmit)
            .foregroundStyle(.clear)
            .tint(.clear)
            .opacity(0.02)
            .accessibilityLabel(L("선물 코드", comment: "Gift: accessibility label of the 8-character code field"))
            // 한 글자씩 읽는다. 붙여 읽으면 "ABCD" 가 낱말처럼 들린다.
            .accessibilityValue(Text(LeeoGiftCode.display(code)).speechSpellsOutCharacters())
            .accessibilityHint(L("영문과 숫자 8자리", comment: "Gift: accessibility hint of the code field, the code is 8 letters or digits"))
    }

    private func box(at index: Int) -> some View {
        let chars = Array(code)
        let char = index < chars.count ? String(chars[index]) : ""
        // 다음에 칠 칸만 강조한다. 다 찼으면 어느 칸도 강조하지 않는다.
        let isNext = focused && index == min(chars.count, LeeoGiftCode.length - 1) && chars.count < LeeoGiftCode.length
        return Text(verbatim: char)
            .font(.system(.title2, design: .monospaced).weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .foregroundStyle(theme.text)
            .frame(maxWidth: 44, minHeight: 52)
            .background(RoundedRectangle(cornerRadius: theme.radiusSm + 2, style: .continuous).fill(theme.surface))
            .overlay(
                RoundedRectangle(cornerRadius: theme.radiusSm + 2, style: .continuous)
                    .strokeBorder(isNext ? theme.accent : Color.clear, lineWidth: 2)
            )
            .animation(.easeOut(duration: 0.12), value: isNext)
    }
}
