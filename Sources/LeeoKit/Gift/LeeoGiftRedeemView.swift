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
    @FocusState private var focused: Bool

    private let onContactSupport: (() -> Void)?

    /// - Parameters:
    ///   - code: 링크로 들어왔을 때 미리 채울 코드.
    ///   - onContactSupport: 받기가 안 될 때 문의 창을 연다(`LeeoGiftSupport`). nil 이면 문의 줄이 없다.
    public init(gift: LeeoGiftStore, code: String = "", onContactSupport: (() -> Void)? = nil) {
        self.gift = gift
        _input = State(initialValue: code)
        self.onContactSupport = onContactSupport
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: gift.redeemed == nil ? "giftcard.fill" : "checkmark.seal.fill")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(gift.redeemed == nil ? theme.accent : Color.green)
                    .frame(width: 84, height: 84)
                    .background(Circle().fill((gift.redeemed == nil ? theme.accent : Color.green).opacity(0.14)))
                    .accessibilityHidden(true)
                    .padding(.top, 8)

                if gift.redeemed != nil {
                    done
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
    }

    private var form: some View {
        VStack(spacing: 16) {
            Text(L("받은 코드를 넣으면 Pro가 바로 열려요. 받은 메시지를 통째로 붙여넣어도 돼요.",
                   comment: "Gift: redeem screen explanation"))
                .font(.body)
                .foregroundStyle(theme.textMuted)
                .multilineTextAlignment(.center)

            TextField(text: $input) { Text(verbatim: "XXXX-XXXX") }
                .font(.system(.title2, design: .monospaced).weight(.semibold))
                .multilineTextAlignment(.center)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.characters)
                #endif
                .focused($focused)
                .padding(.vertical, 14)
                .background(RoundedRectangle(cornerRadius: theme.radiusSm + 4, style: .continuous).fill(theme.surface))
                .onSubmit(redeem)

            PasteButton(payloadType: String.self) { strings in
                guard let text = strings.first else { return }
                Task { @MainActor in
                    input = LeeoGiftCode.extract(from: text).map(LeeoGiftCode.display) ?? text
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
            Text(L("선물받은 Pro가 열렸어요", comment: "Gift: redeem success title"))
                .font(.title2.bold())
                .foregroundStyle(theme.text)
                .multilineTextAlignment(.center)
            Text(L("같은 iCloud 계정이면 다른 기기에서도 이전 구매 복원으로 다시 열려요.",
                   comment: "Gift: redeemed gift restores on other devices"))
                .font(.body)
                .foregroundStyle(theme.textMuted)
                .multilineTextAlignment(.center)
        }
    }

    private var canSubmit: Bool {
        !gift.isWorking && !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func redeem() {
        guard canSubmit else { return }
        focused = false
        Task { await gift.redeem(input) }
    }
}
