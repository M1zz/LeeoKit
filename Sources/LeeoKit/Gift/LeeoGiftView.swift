//
//  LeeoGiftView.swift
//  LeeoKit
//
//  선물을 **권하고, 어떻게 전해지는지 알려 주고, 사게 하는** 화면.
//  산 뒤에는 같은 자리에 코드와 보내기 단추가 선다. 아래에는 보낸 선물과 받았는지가 남는다.
//
//  설정에서 한 줄:
//      if let gift = store.gift, gift.isAvailable {
//          NavigationLink(LeeoGiftText.sendEntry) { LeeoGiftView<MyAppSpec>(gift: gift) }
//          NavigationLink(LeeoGiftText.redeemEntry) { LeeoGiftRedeemView<MyAppSpec>(gift: gift) }
//      }
//

import SwiftUI
#if canImport(StoreKit)
import StoreKit
#endif
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - 앱이 쓰는 문구

/// 앱이 설정 행 · 버튼에 쓰는 선물 문구. LeeoKit 카탈로그에 번역이 있어 앱이 다시 적지 않는다.
public enum LeeoGiftText {
    public static var sendEntry: String { L("Pro 선물하기", comment: "Gift: entry to send Pro as a gift") }
    public static var redeemEntry: String { L("선물 코드 입력", comment: "Gift: entry to enter a received gift code") }

    /// 받는 사람에게 보낼 글. 앱 링크가 있으면 끝에 붙인다.
    public static func shareMessage(appName: String, code: String, appStoreID: String?) -> String {
        let body = String(format: L("%1$@ Pro를 선물로 보내요.\n앱에서 '선물 코드 입력'을 열고 이 코드를 넣어 주세요: %2$@",
                                    comment: "Gift: message sent to the recipient. 1 = app name, 2 = gift code"),
                          appName, LeeoGiftCode.display(code))
        guard let id = appStoreID else { return body }
        return body + "\nhttps://apps.apple.com/app/id\(id)"
    }
}

// MARK: - 보내기 화면

public struct LeeoGiftView<Spec: LeeoAppSpec>: View {
    @ObservedObject private var gift: LeeoGiftStore
    @Environment(\.leeoStyle) private var theme
    #if canImport(StoreKit)
    @Environment(\.purchase) private var purchaseAction
    #endif
    /// 방금 산 선물. 있으면 사는 자리 대신 코드와 보내기가 선다.
    @State private var justSent: LeeoSentGift?
    private let showsRedeemLink: Bool
    /// 미리보기 가격. 있으면 상품을 기다리지 않고 이 값으로 단추를 그리며, 눌러도 결제하지 않는다.
    private let previewPrice: String?
    /// 선물이 안 될 때 문의 창을 연다(`LeeoGiftSupport`). nil 이면 문의 줄이 없다.
    private let onContactSupport: (() -> Void)?

    /// - Parameter showsRedeemLink: 아래에 "선물받은 코드가 있나요?" 링크를 둘지.
    ///   앱이 설정에 코드 입력 행을 따로 두면 false (화면 안에서 또 밀어 넣지 않게).
    /// - Parameter onContactSupport: 선물이 안 될 때 결제 내용과 함께 문의하게 할 창을 연다.
    ///   앱은 `LeeoFeedbackView(initialType: .bug, extraInfo: gift.supportLines, initialCategory: .purchase)` 를 띄운다.
    public init(gift: LeeoGiftStore, showsRedeemLink: Bool = true, onContactSupport: (() -> Void)? = nil) {
        self.gift = gift
        self.showsRedeemLink = showsRedeemLink
        self.previewPrice = nil
        self.onContactSupport = onContactSupport
    }

    /// **결제하지 않는** 미리보기. 인앱 상품 심사 이미지 · SwiftUI 미리보기처럼 StoreKit 상품이 없는 곳에서
    /// 화면을 그대로 그린다. 단추는 주어진 가격을 보여 주기만 한다.
    public init(previewPrice: String, gift: LeeoGiftStore) {
        self.gift = gift
        self.showsRedeemLink = false
        self.previewPrice = previewPrice
        self.onContactSupport = nil
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                header
                if let justSent {
                    LeeoGiftCodeCard<Spec>(gift: justSent)
                    Button(L("새 선물 만들기", comment: "Gift: start another gift after one was created")) {
                        self.justSent = nil
                    }
                    .font(.subheadline)
                } else {
                    steps
                    buyButton
                    notes
                }
                if let error = gift.lastError {
                    Text(error.localizedDescription)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
                pendingNotice
                if let onContactSupport {
                    LeeoGiftSupportRow(gift: gift, onContact: onContactSupport)
                }
                sentList
                if showsRedeemLink {
                    NavigationLink {
                        LeeoGiftRedeemView<Spec>(gift: gift)
                    } label: {
                        Text(L("선물받은 코드가 있나요?", comment: "Gift: link from send screen to redeem screen"))
                            .font(.subheadline)
                    }
                    .padding(.top, 4)
                }
            }
            .padding(20)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .background(theme.bg.ignoresSafeArea())
        .navigationTitle(LeeoGiftText.sendEntry)
        .task {
            guard previewPrice == nil else { return }
            #if canImport(StoreKit)
            await gift.loadProduct()
            await gift.resumePending()
            #endif
            await gift.refresh()
        }
    }

    // MARK: 부분

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "gift.fill")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(theme.accent)
                .frame(width: 84, height: 84)
                .background(Circle().fill(theme.accent.opacity(0.14)))
                .accessibilityHidden(true)
            Text(String(format: L("%@ Pro를 선물하세요", comment: "Gift: send screen title. %@ = app name"), Spec.displayName))
                .font(.title2.bold())
                .foregroundStyle(theme.text)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text(L("결제는 보내는 분이 하고, Pro는 받는 분이 써요.", comment: "Gift: send screen subtitle"))
                .font(.body)
                .foregroundStyle(theme.textMuted)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 8)
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L("이렇게 전해져요", comment: "Gift: heading of the how-it-works steps"))
                .font(.headline)
                .foregroundStyle(theme.text)
                .accessibilityAddTraits(.isHeader)
            step(1, L("선물을 결제해요", comment: "Gift step 1 title"),
                 L("Apple 계정으로 결제하면 선물 코드가 만들어져요.", comment: "Gift step 1 detail"))
            step(2, L("코드를 보내요", comment: "Gift step 2 title"),
                 L("메시지로 코드와 앱 링크를 보내 주세요.", comment: "Gift step 2 detail"))
            step(3, L("받는 분이 코드를 넣어요", comment: "Gift step 3 title"),
                 L("앱에서 '선물 코드 입력'을 열고 코드를 넣으면 바로 Pro가 열려요.", comment: "Gift step 3 detail"))
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: theme.radiusLg, style: .continuous).fill(theme.surface))
    }

    private func step(_ number: Int, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.subheadline.bold())
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(Circle().fill(theme.accent))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(theme.text)
                Text(detail).font(.subheadline).foregroundStyle(theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var buyButton: some View {
        if let previewPrice {
            buyLabel(price: previewPrice)
        } else {
            storeBuyButton
        }
    }

    private func buyLabel(price: String) -> some View {
        HStack {
            if gift.isWorking { ProgressView().tint(.white) }
            Text(String(format: L("%@에 선물하기", comment: "Gift: buy button. %@ = price"), price))
                .font(.headline)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, minHeight: 52)
        .background(RoundedRectangle(cornerRadius: theme.radiusSm + 4, style: .continuous).fill(theme.accent))
    }

    @ViewBuilder
    private var storeBuyButton: some View {
        #if canImport(StoreKit)
        if let product = gift.product {
            Button {
                Task {
                    if let sent = await gift.purchase(using: { try await purchaseAction($0) }) {
                        justSent = sent
                    }
                }
            } label: {
                buyLabel(price: product.displayPrice)
            }
            .buttonStyle(.plain)
            .disabled(gift.isWorking)
        } else {
            ProgressView().frame(minHeight: 52)
        }
        #endif
    }

    private var notes: some View {
        VStack(alignment: .leading, spacing: 6) {
            note(L("코드 하나는 한 사람이 한 번 쓸 수 있어요.", comment: "Gift note: one-time code"))
            note(L("보내는 분과 받는 분 모두 iCloud에 로그인되어 있어야 해요.", comment: "Gift note: iCloud required"))
            note(L("환불은 결제한 분의 Apple 계정으로만 받을 수 있어요.", comment: "Gift note: refunds go to the purchaser only"))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func note(_ text: String) -> some View {
        Label {
            Text(text).font(.footnote).foregroundStyle(theme.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "info.circle").font(.footnote).foregroundStyle(theme.textFaint)
        }
    }

    @ViewBuilder
    private var pendingNotice: some View {
        if gift.pendingCount > 0 {
            VStack(spacing: 8) {
                Text(String(format: L("코드를 아직 못 만든 선물: %d개", comment: "Gift: paid gifts whose code is not created yet. %d = count"), gift.pendingCount))
                    .font(.subheadline)
                    .foregroundStyle(theme.text)
                #if canImport(StoreKit)
                Button(L("다시 시도", comment: "Gift: retry creating pending codes")) {
                    Task { await gift.resumePending() }
                }
                .disabled(gift.isWorking)
                #endif
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: theme.radiusSm, style: .continuous).fill(Color.orange.opacity(0.12)))
        }
    }

    @ViewBuilder
    private var sentList: some View {
        let others = gift.sentGifts.filter { $0.id != justSent?.id }
        if !others.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(L("보낸 선물", comment: "Gift: list of gifts I sent"))
                    .font(.headline)
                    .foregroundStyle(theme.text)
                    .accessibilityAddTraits(.isHeader)
                ForEach(others) { sent in
                    LeeoSentGiftRow<Spec>(gift: sent)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - 코드 카드 (산 직후)

struct LeeoGiftCodeCard<Spec: LeeoAppSpec>: View {
    let gift: LeeoSentGift
    @Environment(\.leeoStyle) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var copied = false

    var body: some View {
        VStack(spacing: 14) {
            Text(L("선물이 준비됐어요", comment: "Gift: title after purchase"))
                .font(.headline)
                .foregroundStyle(theme.text)
                .accessibilityAddTraits(.isHeader)
            Text(LeeoGiftCode.display(gift.code))
                .speechSpellsOutCharacters()
                .font(.system(.largeTitle, design: .monospaced).weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .foregroundStyle(theme.text)
                .textSelection(.enabled)
            Text(L("이 코드를 받는 분께 보내 주세요.", comment: "Gift: instruction under the code"))
                .font(.subheadline)
                .foregroundStyle(theme.textMuted)
            // 아주 큰 글자에서는 두 단추를 위아래로 세운다.
            let buttons = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 12)) : AnyLayout(HStackLayout(spacing: 12))
            buttons {
                Button {
                    LeeoGiftClipboard.copy(LeeoGiftCode.display(gift.code))
                    copied = true
                    AccessibilityNotification.Announcement(L("복사했어요", comment: "Gift: copied confirmation")).post()
                } label: {
                    Label(copied ? L("복사했어요", comment: "Gift: copied confirmation")
                                 : L("코드 복사", comment: "Gift: copy code button"),
                          systemImage: copied ? "checkmark" : "doc.on.doc")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                ShareLink(item: LeeoGiftText.shareMessage(appName: Spec.displayName, code: gift.code, appStoreID: Spec.appStoreID)) {
                    Label(L("보내기", comment: "Gift: share button"), systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: theme.radiusLg, style: .continuous).fill(theme.surface))
    }
}

// MARK: - 보낸 선물 한 줄

struct LeeoSentGiftRow<Spec: LeeoAppSpec>: View {
    let gift: LeeoSentGift
    @Environment(\.leeoStyle) private var theme

    var body: some View {
        HStack(spacing: 12) {
            // 코드 · 날짜 · 받았는지는 한 덩어리로 읽고, 보내기 단추는 따로 누르게 둔다.
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(LeeoGiftCode.display(gift.code))
                        .speechSpellsOutCharacters()
                        .font(.system(.body, design: .monospaced).weight(.semibold))
                        .foregroundStyle(theme.text)
                    Text(gift.createdAt, style: .date)
                        .font(.caption)
                        .foregroundStyle(theme.textMuted)
                }
                Spacer()
                Text(gift.isRedeemed ? L("받음", comment: "Gift status: redeemed")
                                     : L("아직 안 받음", comment: "Gift status: not redeemed yet"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(gift.isRedeemed ? Color.green : theme.textMuted)
            }
            .accessibilityElement(children: .combine)
            if !gift.isRedeemed {
                ShareLink(item: LeeoGiftText.shareMessage(appName: Spec.displayName, code: gift.code, appStoreID: Spec.appStoreID)) {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel(L("보내기", comment: "Gift: share button"))
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: theme.radiusSm, style: .continuous).fill(theme.surface))
    }
}

// MARK: - 클립보드

enum LeeoGiftClipboard {
    @MainActor static func copy(_ text: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}
