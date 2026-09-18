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
#if canImport(UIKit)
import UIKit
import PhotosUI
#endif

public struct LeeoFeedbackView<Spec: LeeoAppSpec>: View {
    @Environment(\.leeoStyle) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var selectedType: LeeoFeedbackType
    /// 칸을 나눠 받은 답. 열쇠는 `LeeoFeedbackPrompt.id` (번역해도 안 바뀐다).
    @State private var answers: [String: String] = [:]
    /// 나눠 묻지 않는 유형의 자유 입력이자, 나눠 묻는 유형의 덧붙임.
    @State private var message: String = ""
    #if canImport(UIKit)
    /// 증상 사진. 최대 `maxScreenshots` 장.
    @State private var screenshots: [LeeoFeedbackShot] = []
    @State private var pickerItems: [PhotosPickerItem] = []
    #endif
    @State private var contactName: String
    @State private var contactEmail: String
    @State private var showMailFallback = false
    @State private var showMailComposer = false
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
    ///   - initialContactName/Email: 회신 정보 초기값 (앱의 프로필 저장소에서 프리필).
    ///     비워두면 **지난번에 보낸 값**이 자동으로 채워진다 - 앱이 값을 주면 그쪽이 이긴다.
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
        // 앱이 프로필을 갖고 있으면 그 값이, 없으면 지난번에 이 기기에서 보낸 값이 채워진다.
        let remembered = LeeoFeedbackService(spec: Spec.self)
        self._contactName = State(initialValue: initialContactName.isEmpty
            ? remembered.rememberedContactName : initialContactName)
        self._contactEmail = State(initialValue: initialContactEmail.isEmpty
            ? remembered.rememberedContactEmail : initialContactEmail)
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
                    guidedFields
                    messageEditor
                    #if canImport(UIKit)
                    if acceptsScreenshots { screenshotPicker }
                    #endif
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
            #if canImport(MessageUI)
            // CloudKit 실패 시 LeeoKit 내장 네이티브 메일 컴포저 (앱별 EmailController 불필요).
            .sheet(isPresented: $showMailComposer) {
                LeeoMailComposer(
                    recipient: Spec.developerEmail,
                    subject: selectedType.emailSubject(appName: Spec.appName),
                    body: buildEmailBody(),
                    attachments: screenshotData,
                    onFinish: {
                        showMailComposer = false
                        handleSent()
                    }
                )
                .ignoresSafeArea()
            }
            #endif
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

    // MARK: - 나눠 묻는 칸

    /// 유형이 정한 질문들(`LeeoFeedbackType.prompts`). 없으면 아무것도 안 그린다.
    ///
    /// ⚠️ 유형을 바꿔도 적어 둔 답은 지우지 않는다. 버그로 적다가 제안으로 옮겼을 때
    ///    글이 사라지면 그 자리에서 창을 닫는다. 조립할 때 지금 유형의 칸만 읽으므로
    ///    남아 있는 답이 섞여 나가지도 않는다(`LeeoFeedbackComposer.compose`).
    @ViewBuilder
    private var guidedFields: some View {
        if !selectedType.prompts.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(selectedType.prompts) { prompt in
                    promptField(prompt)
                }
            }
        }
    }

    private func promptField(_ prompt: LeeoFeedbackPrompt) -> some View {
        let binding = Binding(
            get: { answers[prompt.id] ?? "" },
            set: { answers[prompt.id] = $0 }
        )
        return VStack(alignment: .leading, spacing: 8) {
            Text(prompt.label)
                .font(.body)
                .fontWeight(.semibold)
                .foregroundColor(theme.text)

            if prompt.isMultiline {
                ZStack(alignment: .topLeading) {
                    TextEditor(text: binding)
                        .font(.body)
                        .frame(minHeight: 84)
                        .padding(10)
                        .background(theme.surfaceAlt)
                        .cornerRadius(theme.radiusSm)
                        .scrollContentBackground(.hidden)
                    if binding.wrappedValue.isEmpty {
                        Text(prompt.placeholder)
                            .font(.body)
                            .foregroundColor(theme.textMuted)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 18)
                            .allowsHitTesting(false)
                    }
                }
            } else {
                TextField(prompt.placeholder, text: binding)
                    .font(.body)
                    .padding(12)
                    .background(theme.surfaceAlt)
                    .cornerRadius(theme.radiusSm)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(prompt.label)
    }

    // MARK: - 증상 사진

    #if canImport(UIKit)
    /// 이 앱이 사진을 받기로 했는가. Dashboard 에 사진 필드를 배포한 앱만 켠다.
    private var acceptsScreenshots: Bool {
        Spec.feedback.acceptsScreenshots && selectedType.invitesScreenshot
    }

    /// 사진은 셋까지. 레코드의 사진 필드 수와 같은 값이다.
    private static var maxScreenshots: Int { 3 }

    private var screenshotPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("증상 사진 (선택)", comment: "Screenshot section label"))
                .font(.body)
                .fontWeight(.semibold)
                .foregroundColor(theme.text)

            Text(L("화면 한 장이 글보다 빠릅니다. 스크린샷을 붙여 주시면 훨씬 정확하게 고칠 수 있어요.",
                   comment: "Screenshot section hint"))
                .font(.caption)
                .foregroundColor(theme.textMuted)
                .fixedSize(horizontal: false, vertical: true)

            if !screenshots.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(screenshots) { shot in
                            shotThumbnail(shot)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            if screenshots.count < Self.maxScreenshots {
                PhotosPicker(
                    selection: $pickerItems,
                    maxSelectionCount: Self.maxScreenshots - screenshots.count,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    HStack(spacing: 6) {
                        Image(systemName: "photo.badge.plus")
                        Text(L("사진 붙이기", comment: "Attach screenshot button"))
                    }
                    .font(.body)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .background(theme.surfaceAlt)
                    .foregroundColor(theme.text)
                    .cornerRadius(theme.radiusSm)
                }
                .onChange(of: pickerItems) { _, items in
                    guard !items.isEmpty else { return }
                    Task { await loadPicked(items) }
                }
            }
        }
    }

    private func shotThumbnail(_ shot: LeeoFeedbackShot) -> some View {
        Image(uiImage: shot.image)
            .resizable()
            .scaledToFill()
            .frame(width: 72, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: theme.radiusSm))
            .overlay(alignment: .topTrailing) {
                Button {
                    screenshots.removeAll { $0.id == shot.id }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.body)
                        .foregroundStyle(.white, .black.opacity(0.5))
                        .padding(3)
                }
                .accessibilityLabel(L("이 사진 떼기", comment: "Remove attached screenshot"))
            }
            .accessibilityLabel(L("붙인 사진", comment: "Attached screenshot a11y label"))
    }

    /// 고른 사진을 **줄여서** 들고 있는다. 원본 그대로 올리면 한 장이 몇 MB 라
    /// CloudKit 저장이 느려지고, 받는 쪽에서 볼 때도 원본이 필요하지 않다.
    private func loadPicked(_ items: [PhotosPickerItem]) async {
        var loaded: [LeeoFeedbackShot] = []
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data),
                  let small = image.constrainedSize(maxDimension: 1400),
                  let jpeg = small.jpegData(compressionQuality: 0.7) else { continue }
            loaded.append(LeeoFeedbackShot(image: small, jpeg: jpeg))
        }
        await MainActor.run {
            let room = Self.maxScreenshots - screenshots.count
            screenshots.append(contentsOf: loaded.prefix(max(room, 0)))
            pickerItems = []
        }
    }
    #endif

    // MARK: - Message Editor

    private var messageEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(selectedType.prompts.isEmpty
                 ? L("내용", comment: "Feedback message label")
                 : L("덧붙일 말 (선택)", comment: "Feedback extra note label"))
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
        // 칸을 나눠 물은 유형에서는 이 칸이 덧붙임이다. 같은 예시를 두 번 내밀지 않는다.
        if !selectedType.prompts.isEmpty {
            return L("더 하실 말씀이 있으면 적어 주세요.", comment: "Extra note placeholder")
        }
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

            Text(L("남겨주시면 답변을 드릴 수 있어요. 이 기기에만 저장해 다음에 다시 채워드려요.", comment: "Contact info footer"))
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
        let isDisabled = !LeeoFeedbackComposer.canSend(
            type: selectedType, answers: answers, note: message) || isSending
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
            ? L("빈 칸을 채우면 활성화됩니다", comment: "Send button disabled hint v2")
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
                    message: composedMessage,
                    deviceInfo: deviceInfo,
                    contactName: contactName.trimmingCharacters(in: .whitespacesAndNewlines),
                    contactEmail: contactEmail.trimmingCharacters(in: .whitespacesAndNewlines),
                    screenshots: screenshotData
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
        // 1) 앱이 직접 주입한 폴백이 있으면 우선 사용(기존 계약 유지).
        if let emailFallback, emailFallback(subject, body) {
            handleSent()
            return
        }
        // 2) LeeoKit 내장 네이티브 메일 컴포저 (iOS/macCatalyst) — 앱별 EmailController 불필요.
        #if canImport(MessageUI)
        if LeeoMailComposer.canSendMail {
            showMailComposer = true
            return
        }
        #endif
        // 3) mailto: 링크 폴백.
        #if os(iOS)
        showMailFallback = true
        #else
        openMailtoURL()
        handleSent()
        #endif
    }

    /// 나눠 받은 답을 보낼 글 하나로 조립한 것. CloudKit·메일·mailto 가 같은 글을 쓴다.
    private var composedMessage: String {
        LeeoFeedbackComposer.compose(type: selectedType, answers: answers, note: message)
    }

    /// 붙인 사진의 JPEG. 사진을 안 받는 앱에서는 늘 빈 배열이다.
    private var screenshotData: [Data] {
        #if canImport(UIKit)
        return Spec.feedback.acceptsScreenshots ? screenshots.map(\.jpeg) : []
        #else
        return []
        #endif
    }

    private func buildEmailBody() -> String {
        var lines = [composedMessage, "", "---", deviceInfo]
        let name = contactName.trimmingCharacters(in: .whitespacesAndNewlines)
        let email = contactEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { lines.append("\(L("이름", comment: "Contact name label")): \(name)") }
        if !email.isEmpty { lines.append("\(L("이메일", comment: "Contact email label")): \(email)") }
        return lines.joined(separator: "\n")
    }

    /// 사진은 mailto 로 보낼 수 없다. 붙였는데 조용히 빠지면 보낸 사람은 갔다고 믿는다.
    private var mailtoBody: String {
        let shots = screenshotData.count
        guard shots > 0 else { return buildEmailBody() }
        let note = String(format: L("사진 %d장을 붙이셨는데 이 경로로는 함께 보낼 수 없어요. 메일에 직접 첨부해 주세요.",
                                    comment: "mailto cannot attach screenshots note"), shots)
        return buildEmailBody() + "\n\n" + note
    }

    private func openMailtoURL() {
        let subject = selectedType.emailSubject(appName: Spec.appName)
        let raw = "mailto:\(Spec.developerEmail)?subject=\(subject)&body=\(mailtoBody)"
        guard let encoded = raw.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: encoded) else { return }
        #if os(iOS)
        UIApplication.shared.open(url)
        #elseif os(macOS)
        NSWorkspace.shared.open(url)
        #endif
    }

    private func handleSent() {
        // 보내기에 성공한 값만 기억한다 - 쓰다 만 이메일을 다음번에 들이밀지 않기 위해서다.
        if showsContactFields {
            LeeoFeedbackService(spec: Spec.self)
                .rememberContact(name: contactName, email: contactEmail)
        }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { didSend = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { dismiss() }
    }
}
