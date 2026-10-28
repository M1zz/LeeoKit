//
//  LeeoGiftSupport.swift
//  LeeoKit
//
//  선물이 안 될 때 **결제 내용과 함께** 문의하게 하는 길.
//
//  선물은 서버 없이 Apple 결제 기록 + iCloud 로 돈다. 사람마다 iCloud 상태가 다르고 아직 다듬는 중이라
//  막히는 사람이 나온다. 그때 "돈은 냈는데 아무것도 없다" 로 끝나지 않게, 화면 아래에 문의 줄을 두고,
//  문제가 보이면(오류 · 코드를 못 만든 결제) 그 줄을 앞으로 꺼낸다.
//
//  문의에는 개발자가 바로 찾아볼 수 있는 것만 붙는다(`LeeoGiftStore.supportLines`):
//  결제 번호 · 코드 · 받았는지 · 마지막 오류. 서명 원문(JWS)이나 iCloud 계정 정보는 붙이지 않는다.
//
//  앱이 하는 일: 피드백 창을 여는 것뿐이다.
//      LeeoGiftView<Spec>(gift: gift, onContactSupport: { showSupport = true })
//      .sheet(isPresented: $showSupport) {
//          LeeoFeedbackView<Spec>(initialType: .bug, extraInfo: gift.supportLines, initialCategory: .purchase)
//      }
//

import SwiftUI

// MARK: - 붙일 정보

public extension LeeoGiftStore {

    /// 문의에 붙일 줄들. 사람이 읽어도 알 수 있게, 개발자가 결제 번호로 바로 찾을 수 있게.
    var supportLines: [String] {
        var lines: [String] = []
        for gift in sentGifts.prefix(5) {
            lines.append("gift.sent code=\(LeeoGiftCode.display(gift.code)) tx=\(gift.transactionID) redeemed=\(gift.isRedeemed ? "yes" : "no")")
        }
        for (txid, code) in pendingSupportCodes.sorted(by: { $0.key < $1.key }) {
            lines.append("gift.pending code=\(LeeoGiftCode.display(code)) tx=\(txid)")
        }
        if let redeemed {
            lines.append("gift.redeemed code=\(LeeoGiftCode.display(redeemed.code)) tx=\(redeemed.transactionID)")
        }
        if let lastError {
            lines.append("gift.lastError \(lastError)")
        }
        if lines.isEmpty { lines.append("gift.none") }
        return lines
    }

    /// 지금 문의를 앞으로 꺼낼 만한가. 오류가 났거나, 결제는 됐는데 코드를 못 만든 선물이 있다.
    var needsSupport: Bool { lastError != nil || pendingCount > 0 }
}

// MARK: - 문의 줄

/// 선물 화면 · 코드 입력 화면 아래의 문의 줄. 문제가 보이면 강조한 카드로, 아니면 작은 링크로.
struct LeeoGiftSupportRow: View {
    @ObservedObject var gift: LeeoGiftStore
    @Environment(\.leeoStyle) private var theme
    let onContact: () -> Void

    var body: some View {
        if gift.needsSupport {
            VStack(alignment: .leading, spacing: 10) {
                Label(L("선물이 잘 안 되나요?", comment: "Gift support: title"), systemImage: "questionmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.text)
                Text(L("아직 다듬는 중인 기능이에요. 결제했는데 코드가 나오지 않았거나 받지 못했다면, 결제 내용과 함께 알려 주세요. 확인해서 꼭 해결해 드릴게요.",
                       comment: "Gift support: explanation shown when something went wrong"))
                    .font(.footnote)
                    .foregroundStyle(theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                Button(action: onContact) {
                    Text(L("결제 내용과 함께 문의하기", comment: "Gift support: contact button"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Capsule().fill(theme.accent))
                }
                .buttonStyle(.plain)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: theme.radiusSm + 4, style: .continuous).fill(Color.orange.opacity(0.12)))
        } else {
            Button(action: onContact) {
                Label(L("선물이 잘 안 되나요?", comment: "Gift support: title"), systemImage: "questionmark.circle")
                    .font(.footnote)
                    .foregroundStyle(theme.textMuted)
            }
            .buttonStyle(.plain)
            .accessibilityHint(L("결제 내용과 함께 문의하기", comment: "Gift support: contact button"))
        }
    }
}
