//
//  LeeoMailComposer.swift
//  LeeoKit
//
//  CloudKit 제출 실패 시 LeeoFeedbackView가 내부적으로 띄우는 네이티브 메일 컴포저.
//  앱마다 EmailController를 다시 만들 필요 없이, LeeoKit이 CloudKit → 네이티브 컴포저 →
//  mailto: 순으로 자동 폴백한다. (MessageUI가 없는 macOS는 mailto: 로만 폴백)
//

#if canImport(MessageUI)
import SwiftUI
import MessageUI

struct LeeoMailComposer: UIViewControllerRepresentable {
    let recipient: String
    let subject: String
    let body: String
    let onFinish: () -> Void

    /// 이 기기에서 Mail 컴포저를 띄울 수 있는지.
    static var canSendMail: Bool { MFMailComposeViewController.canSendMail() }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let vc = MFMailComposeViewController()
        vc.mailComposeDelegate = context.coordinator
        vc.setToRecipients([recipient])
        vc.setSubject(subject)
        vc.setMessageBody(body, isHTML: false)
        return vc
    }

    func updateUIViewController(_ vc: MFMailComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let onFinish: () -> Void
        init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }

        func mailComposeController(_ controller: MFMailComposeViewController,
                                   didFinishWith result: MFMailComposeResult,
                                   error: Error?) {
            onFinish()
        }
    }
}
#endif
