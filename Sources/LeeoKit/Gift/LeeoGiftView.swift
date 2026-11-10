//
//  LeeoGiftView.swift
//  LeeoKit
//
//  선물을 **권하고, 어떻게 전해지는지 알려 주고, 사게 하는** 화면.
//  산 뒤에는 같은 자리에 코드와 보내기 단추가 선다. 아래에는 보낸 선물과 받았는지가 남는다.
//  틀은 페이월 · 응원과 같은 `LeeoPurchaseScaffold` 다: 선물 그림 · 한 줄 → 고를 등급 → 떠 있는 선물하기 단추
//  → 아래에 전해지는 방법 · 안내 · 보낸 선물.
//
//  설정에서:
//      if let gift = store.gift {
//          if gift.isAvailable {   // 선물 판매를 연 계약(`sellsGifts`)만
//              NavigationLink(LeeoGiftText.sendEntry) { LeeoGiftView<MyAppSpec>(gift: gift) }
//          }
//          if gift.canRedeem {     // App Store 오퍼 코드 받기
//              NavigationLink(LeeoGiftText.redeemEntry) { LeeoGiftRedeemView<MyAppSpec>(gift: gift) }
//          }
//      }
//

// watchOS 에는 없다 — 선물 · 오퍼 코드 결제는 iPhone 에서.
#if !os(watchOS)
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
    /// 등급마다 선물을 팔 때의 설정 행 이름. 예: "Plus 선물하기". `gift.config.tierName` 을 넘긴다.
    public static func sendEntry(tier: String) -> String {
        String(format: L("%@ 선물하기", comment: "Gift: entry to send a paid tier as a gift. %@ = tier name, e.g. Plus or Pro (keep as is)"), tier)
    }
    public static var redeemEntry: String { L("선물 코드 입력", comment: "Gift: entry to enter a received gift code") }

    /// 받는 사람에게 보낼 글 — 오퍼 코드면 App Store 사용 링크, 예전 LeeoKit 코드면 코드와 앱 링크.
    public static func shareMessage(appName: String, gift: LeeoSentGift, appStoreID: String?, tierName: String = "Pro") -> String {
        guard gift.isOfferCode == true else {
            return shareMessage(appName: appName, code: gift.code, appStoreID: appStoreID)
        }
        let link = LeeoOfferCodePool.redeemURL(code: gift.code, appStoreID: appStoreID)?.absoluteString ?? gift.code
        return String(format: L("%1$@ %2$@를 선물로 보내요.\n링크를 누르고 '사용'을 누르면 %2$@가 열려요.\n%3$@",
                                comment: "Gift: message with an App Store offer code link. 1 = app name, 2 = tier name (Plus or Pro, keep as is), 3 = link"),
                      appName, tierName, link)
    }

    /// 보여 줄 코드. 예전 LeeoKit 코드는 `ABCD-EFGH`, 오퍼 코드는 그대로.
    static func displayCode(_ gift: LeeoSentGift) -> String {
        gift.isOfferCode == true ? gift.code : LeeoGiftCode.display(gift.code)
    }

    /// 예전 LeeoKit 코드의 글. 앱 링크가 있으면 끝에 붙인다.
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
    /// 고를 수 있는 선물(`LeeoGiftPickerView`). 둘 이상이면 머리말 대신 고르기가 선다.
    private var choices: [LeeoGiftStore] = []
    private var selection: Binding<String>?

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

    /// 고르기 모드 — `LeeoGiftPickerView` 가 쓴다.
    init(gift: LeeoGiftStore, choices: [LeeoGiftStore], selection: Binding<String>,
         showsRedeemLink: Bool, onContactSupport: (() -> Void)?) {
        self.init(gift: gift, showsRedeemLink: showsRedeemLink, onContactSupport: onContactSupport)
        self.choices = choices
        self.selection = selection
    }

    private var isPicking: Bool { choices.count > 1 && selection != nil }

    public var body: some View {
        LeeoPurchaseScaffold {
            header.padding(.horizontal, LeeoPurchaseScaffoldMetrics.margin)
        } options: {
            if let justSent {
                VStack(spacing: 14) {
                    LeeoGiftCodeCard<Spec>(gift: justSent, tierName: gift.config.tierName)
                    Button(L("새 선물 만들기", comment: "Gift: start another gift after one was created")) {
                        self.justSent = nil
                    }
                    .font(.subheadline)
                }
            } else if isPicking {
                VStack(spacing: 10) {
                    ForEach(choices, id: \.config.productID) { choice in
                        LeeoGiftOptionRow(gift: choice, selected: choice.config.productID == gift.config.productID) {
                            selection?.wrappedValue = choice.config.productID
                        }
                    }
                }
            }
        } button: {
            // 산 뒤에는 코드 카드의 보내기가 할 일이다. 단추를 또 띄우지 않는다
            if justSent == nil { buyButton }
        } details: {
            VStack(spacing: 20) {
                if let error = gift.lastError {
                    Text(error.localizedDescription)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
                pendingNotice
                if justSent == nil {
                    steps
                    notes
                }
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
                }
            }
        }
        .navigationTitle(isPicking ? "" : LeeoGiftText.sendEntry(tier: gift.config.tierName))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onChange(of: gift.config.productID) { _, _ in justSent = nil }
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

    /// 선물 그림과 한 줄. 고르기면 "고마운 사람에게...", 하나면 "{앱} {등급}를 선물하세요" 와 누가 쓰는지.
    private var header: some View {
        VStack(spacing: 12) {
            ZStack {
                Image(systemName: "gift.fill")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(theme.accent)
                    .frame(width: 84, height: 84)
                    .background(Circle().fill(theme.accent.opacity(0.14)))
                Image(systemName: "heart.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.pink)
                    .offset(x: 30, y: -30)
            }
            .accessibilityHidden(true)
            Text(isPicking
                 ? L("고마운 사람에게 이 좋은 경험을 선물하세요", comment: "Gift picker: headline. Give this good experience to someone you are grateful to")
                 : String(format: L("%1$@ %2$@를 선물하세요", comment: "Gift: send screen title. 1 = app name, 2 = tier name (Plus or Pro, keep as is)"),
                          Spec.displayName, gift.config.tierName))
                .font(.title2.bold())
                .foregroundStyle(theme.text)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if !isPicking {
                Text(String(format: L("결제는 보내는 분이 하고, %@는 받는 분이 써요.", comment: "Gift: send screen subtitle. %@ = tier name (Plus or Pro, keep as is)"),
                            gift.config.tierName))
                    .font(.body)
                    .foregroundStyle(theme.textMuted)
                    .multilineTextAlignment(.center)
            }
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
                 L("Apple 계정으로 결제하면 선물 링크가 만들어져요.", comment: "Gift step 1 detail (offer code link)"))
            step(2, L("링크를 보내요", comment: "Gift step 2 title (offer code link)"),
                 L("메시지로 링크를 보내 주세요.", comment: "Gift step 2 detail (offer code link)"))
            step(3, L("받는 분이 링크를 눌러요", comment: "Gift step 3 title (offer code link)"),
                 String(format: L("App Store가 열리고 '사용'을 누르면 %@가 열려요. 코드를 칠 필요가 없어요.",
                                  comment: "Gift step 3 detail (offer code link). %@ = tier name (Plus or Pro, keep as is)"), gift.config.tierName))
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

    /// 떠 있는 단추. 고르기면 값이 고른 줄에 있으니 "선물하기" 한마디, 하나면 "{값}에 선물하기".
    /// 미리보기면 보여 주기만 한다.
    private var buyButton: some View {
        LeeoPrimaryButton(title: buyTitle, isWorking: gift.isWorking || (previewPrice == nil && !hasProduct)) {
            guard previewPrice == nil else { return }
            #if canImport(StoreKit)
            Task {
                if let sent = await gift.purchase(using: { try await purchaseAction($0) }) {
                    justSent = sent
                }
            }
            #endif
        }
    }

    private var hasProduct: Bool {
        #if canImport(StoreKit)
        return gift.product != nil
        #else
        return false
        #endif
    }

    private var buyTitle: String {
        if isPicking { return L("선물하기", comment: "Gift picker: buy button") }
        #if canImport(StoreKit)
        let price = previewPrice ?? gift.product?.displayPrice
        #else
        let price = previewPrice
        #endif
        guard let price else { return L("선물하기", comment: "Gift picker: buy button") }
        return String(format: L("%@에 선물하기", comment: "Gift: buy button. %@ = price"), price)
    }

    private var notes: some View {
        VStack(alignment: .leading, spacing: 6) {
            note(L("코드 하나는 한 사람이 한 번 쓸 수 있어요.", comment: "Gift note: one-time code"))
            note(L("보내는 분만 iCloud에 로그인되어 있으면 돼요.", comment: "Gift note: only the sender needs iCloud (offer code link)"))
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
                    LeeoSentGiftRow<Spec>(gift: sent, tierName: gift.config.tierName)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - 고르기

/// 여러 등급의 선물을 한 화면에서 고르고 보낸다 — "고마운 사람에게 이 좋은 경험을 선물하세요".
/// 선물이 하나면 그 선물의 화면(`LeeoGiftView`)과 같다. `gifts` 순서대로 줄이 선다(싼 것부터 권한다).
public struct LeeoGiftPickerView<Spec: LeeoAppSpec>: View {
    private let gifts: [LeeoGiftStore]
    private let showsRedeemLink: Bool
    private let onContactSupport: (() -> Void)?
    @State private var selectedID: String

    public init(gifts: [LeeoGiftStore], showsRedeemLink: Bool = true, onContactSupport: (() -> Void)? = nil) {
        self.gifts = gifts
        self.showsRedeemLink = showsRedeemLink
        self.onContactSupport = onContactSupport
        // 처음에는 가장 높은 등급 — 받는 사람에게 가장 좋은 경험
        _selectedID = State(initialValue: gifts.last?.config.productID ?? "")
    }

    public var body: some View {
        if let gift = gifts.first(where: { $0.config.productID == selectedID }) ?? gifts.first {
            LeeoGiftView<Spec>(gift: gift, choices: gifts, selection: $selectedID,
                               showsRedeemLink: showsRedeemLink, onContactSupport: onContactSupport)
        }
    }
}

/// 고를 선물 한 줄: 등급 이름 · 값. 상품이 늦게 와도 값이 채워지게 줄마다 지켜본다.
struct LeeoGiftOptionRow: View {
    @ObservedObject var gift: LeeoGiftStore
    let selected: Bool
    let onSelect: () -> Void

    var body: some View {
        LeeoOptionRow(title: String(format: L("%@ 평생", comment: "Gift picker row: lifetime of the tier. %@ = tier name (Plus or Pro, keep as is)"),
                                    gift.config.tierName),
                      price: price, selected: selected, action: onSelect)
            .task {
                #if canImport(StoreKit)
                if gift.product == nil { await gift.loadProduct() }
                #endif
            }
    }

    private var price: String? {
        #if canImport(StoreKit)
        return gift.product?.displayPrice
        #else
        return nil
        #endif
    }
}

// MARK: - 코드 카드 (산 직후)

struct LeeoGiftCodeCard<Spec: LeeoAppSpec>: View {
    let gift: LeeoSentGift
    var tierName = "Pro"
    @Environment(\.leeoStyle) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var copied = false

    var body: some View {
        VStack(spacing: 14) {
            Text(L("선물이 준비됐어요", comment: "Gift: title after purchase"))
                .font(.headline)
                .foregroundStyle(theme.text)
                .accessibilityAddTraits(.isHeader)
            Text(LeeoGiftText.displayCode(gift))
                .speechSpellsOutCharacters()
                .font(.system(.largeTitle, design: .monospaced).weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .foregroundStyle(theme.text)
                .textSelection(.enabled)
            Text(gift.isOfferCode == true
                 ? L("이 링크를 받는 분께 보내 주세요.", comment: "Gift: instruction under the offer code")
                 : L("이 코드를 받는 분께 보내 주세요.", comment: "Gift: instruction under the code"))
                .font(.subheadline)
                .foregroundStyle(theme.textMuted)
            // 아주 큰 글자에서는 두 단추를 위아래로 세운다.
            let buttons = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 12)) : AnyLayout(HStackLayout(spacing: 12))
            buttons {
                Button {
                    LeeoGiftClipboard.copy(gift.isOfferCode == true
                        ? (LeeoOfferCodePool.redeemURL(code: gift.code, appStoreID: Spec.appStoreID)?.absoluteString ?? gift.code)
                        : LeeoGiftCode.display(gift.code))
                    copied = true
                    AccessibilityNotification.Announcement(L("복사했어요", comment: "Gift: copied confirmation")).post()
                } label: {
                    Label(copied ? L("복사했어요", comment: "Gift: copied confirmation")
                                 : (gift.isOfferCode == true ? L("링크 복사", comment: "Gift: copy offer code link button")
                                                             : L("코드 복사", comment: "Gift: copy code button")),
                          systemImage: copied ? "checkmark" : "doc.on.doc")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                ShareLink(item: LeeoGiftText.shareMessage(appName: Spec.displayName, gift: gift, appStoreID: Spec.appStoreID, tierName: tierName)) {
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
    var tierName = "Pro"
    @Environment(\.leeoStyle) private var theme

    var body: some View {
        HStack(spacing: 12) {
            // 코드 · 날짜 · 받았는지는 한 덩어리로 읽고, 보내기 단추는 따로 누르게 둔다.
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(LeeoGiftText.displayCode(gift))
                        .speechSpellsOutCharacters()
                        .font(.system(.body, design: .monospaced).weight(.semibold))
                        .foregroundStyle(theme.text)
                    Text(gift.createdAt, style: .date)
                        .font(.caption)
                        .foregroundStyle(theme.textMuted)
                }
                Spacer()
                // 오퍼 코드는 받았는지 App Store 만 안다 — "보냄" 까지만 말한다.
                Text(gift.isOfferCode == true ? L("보냄", comment: "Gift status: offer code link sent (redemption unknown)")
                     : gift.isRedeemed ? L("받음", comment: "Gift status: redeemed")
                                     : L("아직 안 받음", comment: "Gift status: not redeemed yet"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(gift.isRedeemed ? Color.green : theme.textMuted)
            }
            .accessibilityElement(children: .combine)
            if !gift.isRedeemed {
                ShareLink(item: LeeoGiftText.shareMessage(appName: Spec.displayName, gift: gift, appStoreID: Spec.appStoreID, tierName: tierName)) {
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
#endif
