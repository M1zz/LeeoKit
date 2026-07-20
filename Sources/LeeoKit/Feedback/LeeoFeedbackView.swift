//
//  LeeoFeedbackView.swift
//  LeeoKit
//
//  사용자 피드백 제출 화면. 1차: CloudKit Public DB 직접 제출(메일 앱 불필요),
//  실패 시 폴백: emailFallback 클로저(앱의 메일 컴포저) → mailto: 링크.
//
//  사용 예:
//      LeeoFeedbackView<MyAppSpec>()
//          .leeoStyle(myStyle)   // 선택 — 없으면 시스템 색
//

import SwiftUI

public struct LeeoFeedbackView<Spec: LeeoAppSpec>: View {
    @Environment(\.leeoStyle) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var selectedType: LeeoFeedbackType
    @State private var message: String = ""
    @State private var contactName: String
    @State private var contactEmail: String
    @State private var showMailFallback = false
    @State private var didSend = false
    @State private var isSending = false

    private let types: [LeeoFeedbackType]
    private let showsContactFields: Bool

    /// 앱 자체 메일 컴포저가 있으면 주입 — (제목, 본문)을 받아 처리했으면 true.
    /// nil이거나 false를 반환하면 mailto: 링크로 폴백한다.
    private let emailFallback: ((String, String) -> Bool)?

    /// - Parameters:
    ///   - types: 유형 선택지 구성 (앱별로 다르면 지정, 기본 bug/feature/question/other)
    ///   - initialType: 진입 시 미리 선택할 유형 (넛지에서 특정 유형으로 들어오는 경우 등)
    ///   - showsContactFields: 회신용 이름/이메일 입력 섹션 노출 여부
    ///   - initialContactName/Email: 회신 정보 초기값 (앱의 프로필 저장소에서 프리필)
    public init(
        types: [LeeoFeedbackType] = LeeoFeedbackType.defaultTypes,
        initialType: LeeoFeedbackType? = nil,
        showsContactFields: Bool = false,
        initialContactName: String = "",
        initialContactEmail: String = "",
        emailFallback: ((String, String) -> Bool)? = nil
    ) {
        self.types = types
        self.showsContactFields = showsContactFields
        self.emailFallback = emailFallback
        self._selectedType = State(initialValue: initialType ?? types.first ?? .bug)
        self._contactName = State(initialValue: initialContactName)
        self._contactEmail = State(initialValue: initialContactEmail)
    }

    private let deviceInfo: String = {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-"
        #if os(iOS)
        let device = UIDevice.current
        return "App \(version) | \(device.model) | \(device.systemName) \(device.systemVersion)"
        #else
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return "App \(version) | macOS \(os.majorVersion).\(os.minorVersion)"
        #endif
    }()

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    typeSelector
                    messageEditor
                    if showsContactFields { contactFields }
                    deviceInfoCard
                    sendButton
                    Spacer(minLength: 40)
                }
                .padding(20)
            }
            // 입력창 밖 스크롤 시 키보드 내리기 (달빛 v4.0.5 UX 수정에서 이식)
            .scrollDismissesKeyboard(.interactively)
            .background(theme.bg.ignoresSafeArea())
            .navigationTitle(L("피드백 보내기", comment: "Feedback view title"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("닫기", comment: "Close")) { dismiss() }
                }
            }
            .alert(
                L("메일 앱을 열 수 없습니다", comment: "Mail unavailable alert title"),
                isPresented: $showMailFallback
            ) {
                Button(L("다른 메일 앱으로 열기", comment: "Open with another mail app"), action: openMailtoURL)
                Button(L("취소", comment: "Cancel"), role: .cancel) {}
            } message: {
                Text(L("Mail 앱이 설정되어 있지 않습니다. mailto: 링크로 다른 메일 앱을 열겠습니까?", comment: "Mail unavailable alert message"))
            }
            .overlay(alignment: .center) {
                if didSend { sentConfirmation }
            }
        }
    }

    // MARK: - Type Selector

    private var typeSelector: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("문의 유형", comment: "Feedback type label"))
                .font(.body)
                .fontWeight(.semibold)
                .foregroundColor(theme.text)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(types, id: \.self) { type in
                    typeChip(type)
                }
            }
        }
    }

    private func typeChip(_ type: LeeoFeedbackType) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { selectedType = type }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: type.icon)
                    .font(.body)
                Text(type.localizedName)
                    .font(.body)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .padding(.horizontal, 8)
            .background(selectedType == type ? theme.accent : theme.surfaceAlt)
            .foregroundColor(selectedType == type ? .white : theme.text)
            .cornerRadius(theme.radiusSm)
            .overlay(
                RoundedRectangle(cornerRadius: theme.radiusSm)
                    .stroke(selectedType == type ? theme.accent : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selectedType == type ? .isSelected : [])
        .accessibilityLabel(type.localizedName)
    }

    // MARK: - Message Editor

    private var messageEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("내용", comment: "Feedback message label"))
                .font(.body)
                .fontWeight(.semibold)
                .foregroundColor(theme.text)

            ZStack(alignment: .topLeading) {
                TextEditor(text: $message)
                    .font(.body)
                    .frame(minHeight: 140)
                    .padding(10)
                    .background(theme.surfaceAlt)
                    .cornerRadius(theme.radiusSm)
                    .scrollContentBackground(.hidden)
                    .accessibilityLabel(L("피드백 내용", comment: "Feedback content field a11y label"))
                    .accessibilityHint(L("불편하신 점이나 제안 사항을 자유롭게 적어주세요", comment: "Feedback content field hint"))

                if message.isEmpty {
                    Text(placeholderText)
                        .font(.body)
                        .foregroundColor(theme.textMuted)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 18)
                        .allowsHitTesting(false)
                }
            }
        }
    }

    private var placeholderText: String {
        switch selectedType {
        case .bug:
            return L("어떤 상황에서 문제가 발생했는지 알려주세요.\n예) 단축어를 저장할 때 앱이 종료됩니다.", comment: "Bug report placeholder")
        case .feature:
            return L("어떤 기능이 있으면 좋겠나요?\n예) 단축어를 폴더로 묶는 기능이 필요해요.", comment: "Feature request placeholder")
        case .question:
            return L("어떤 부분이 궁금하신가요?\n예) 클립보드 히스토리는 어떻게 보나요?", comment: "Usage question placeholder")
        case .improvement:
            return L("어떤 점이 불편하셨나요? 어떻게 바뀌면 더 좋을지 알려주세요.", comment: "Improvement suggestion placeholder")
        case .other:
            return L("자유롭게 의견을 남겨주세요.", comment: "Other feedback placeholder")
        }
    }

    // MARK: - Contact Fields (선택)

    private var contactFields: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("회신 정보", comment: "Contact info section label"))
                .font(.body)
                .fontWeight(.semibold)
                .foregroundColor(theme.text)

            VStack(spacing: 8) {
                TextField(L("이름 (선택)", comment: "Contact name placeholder"), text: $contactName)
                    .textContentType(.name)
                    .padding(12)
                    .background(theme.surfaceAlt)
                    .cornerRadius(theme.radiusSm)
                TextField(L("회신 받을 이메일 (선택)", comment: "Contact email placeholder"), text: $contactEmail)
                    .textContentType(.emailAddress)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    #endif
                    .padding(12)
                    .background(theme.surfaceAlt)
                    .cornerRadius(theme.radiusSm)
            }

            Text(L("남겨주시면 답변을 드릴 수 있어요.", comment: "Contact info footer"))
                .font(.caption)
                .foregroundColor(theme.textMuted)
        }
    }

    // MARK: - Device Info Card

    private var deviceInfoCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L("자동 첨부 정보", comment: "Auto-attached info section label"))
                .font(.body)
                .fontWeight(.semibold)
                .foregroundColor(theme.textMuted)

            Text(deviceInfo)
                .font(.body)
                .foregroundColor(theme.textMuted)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.surfaceAlt)
                .cornerRadius(theme.radiusSm)
        }
    }

    // MARK: - Send Button

    private var sendButton: some View {
        let isDisabled = message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending
        return Button(action: sendFeedback) {
            HStack(spacing: 8) {
                if isSending {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "paperplane.fill")
                }
                Text(isSending
                     ? L("보내는 중…", comment: "Sending feedback progress")
                     : L("보내기", comment: "Send feedback button"))
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(isDisabled ? theme.textMuted.opacity(0.3) : theme.accent)
            .foregroundColor(.white)
            .cornerRadius(theme.radiusSm)
        }
        .disabled(isDisabled)
        .accessibilityLabel(L("피드백 보내기", comment: "Send feedback a11y label"))
        .accessibilityHint(isDisabled
            ? L("내용을 입력하면 활성화됩니다", comment: "Send button disabled hint")
            : L("탭하면 개발자에게 바로 전송됩니다", comment: "Send button enabled hint"))
    }

    // MARK: - Sent Confirmation Overlay

    private var sentConfirmation: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundColor(.green)
            Text(L("피드백을 보냈습니다!\n소중한 의견 감사합니다 🙏", comment: "Feedback sent confirmation message"))
                .font(.headline)
                .multilineTextAlignment(.center)
                .foregroundColor(theme.text)
        }
        .padding(32)
        .background(theme.surface)
        .cornerRadius(theme.radiusLg)
        .shadow(color: .black.opacity(0.15), radius: 16, x: 0, y: 8)
        .padding(40)
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
    }

    // MARK: - Send Logic

    /// 1차: CloudKit Public DB로 직접 제출 (메일 앱 불필요, iCloud 로그인만 필요).
    /// 실패 시 폴백: 이메일 경로.
    private func sendFeedback() {
        isSending = true
        Task {
            do {
                try await LeeoFeedbackService(spec: Spec.self).submit(
                    type: selectedType.rawValue,
                    message: message,
                    deviceInfo: deviceInfo,
                    contactName: contactName.trimmingCharacters(in: .whitespacesAndNewlines),
                    contactEmail: contactEmail.trimmingCharacters(in: .whitespacesAndNewlines)
                )
                await MainActor.run {
                    isSending = false
                    handleSent()
                }
            } catch {
                print("⚠️ [LeeoFeedbackView.sendFeedback] CloudKit 제출 실패 → 이메일 폴백: \(error)")
                await MainActor.run {
                    isSending = false
                    sendViaEmail()
                }
            }
        }
    }

    private func sendViaEmail() {
        let subject = selectedType.emailSubject(appName: Spec.appName)
        let body = buildEmailBody()
        if let emailFallback, emailFallback(subject, body) {
            handleSent()
            return
        }
        #if os(iOS)
        showMailFallback = true
        #else
        openMailtoURL()
        handleSent()
        #endif
    }

    private func buildEmailBody() -> String {
        var lines = [message, "", "---", deviceInfo]
        let name = contactName.trimmingCharacters(in: .whitespacesAndNewlines)
        let email = contactEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { lines.append("\(L("이름", comment: "Contact name label")): \(name)") }
        if !email.isEmpty { lines.append("\(L("이메일", comment: "Contact email label")): \(email)") }
        return lines.joined(separator: "\n")
    }

    private func openMailtoURL() {
        let subject = selectedType.emailSubject(appName: Spec.appName)
        let raw = "mailto:\(Spec.developerEmail)?subject=\(subject)&body=\(buildEmailBody())"
        guard let encoded = raw.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: encoded) else { return }
        #if os(iOS)
        UIApplication.shared.open(url)
        #elseif os(macOS)
        NSWorkspace.shared.open(url)
        #endif
    }

    private func handleSent() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { didSend = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { dismiss() }
    }
}
