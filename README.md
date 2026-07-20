# LeeoKit

여러 iOS/macOS 앱에서 반복되던 코드를 한 곳에서 관리하는 공유 Swift 패키지.

> 운영 규칙은 [docs/OPERATING_POLICY.md](docs/OPERATING_POLICY.md)를 따른다.
> 요약: **로드맵 없는 인프라.** 작업 중인 앱이 필요로 할 때만 그 자리에서 고치고,
> 안 쓰는 앱은 옛 버전에 핀 고정해 둔다.

## 설치

로컬 (개발/검증):
```swift
.package(path: "../LeeoKit")
```

원격 (안정화 후):
```swift
.package(url: "git@github.com:<me>/LeeoKit.git", from: "1.0.0")
```

## 수록 모듈

```swift
import LeeoKit

// 색상 hex 변환
let c = Color(hex: "#4FACFE")
let hex = c?.toHex()                 // "4FACFE"
let named = Color.fromName("blue")

// 이미지 유틸 (UIKit 환경)
let b64 = uiImage.toBase64()
let thumb = uiImage.constrainedSize(maxDimension: 1024)

// 햅틱 (macOS native에선 no-op)
HapticManager.shared.success()
```

## 앱 계약 (LeeoAppSpec)

앱이 공통으로 가져야 하는 항목을 컴파일 타임에 강제하는 프로토콜.
LeeoKit의 기능 컴포넌트는 이 준수 없이는 생성할 수 없다 — 항목을 빼먹으면 빌드가 실패한다.

```swift
enum MyAppSpec: LeeoAppSpec {
    static let appName = "MyApp"
    static let developerEmail = "leeo@kakao.com"
    static let feedback = LeeoFeedbackConfig(containerIdentifier: "iCloud.com.Ysoup.MyApp")
}
```

## 피드백 시스템

사용자 피드백을 CloudKit Public DB로 접수하고, 개발자는 앱 내 인박스에서 확인·완료 처리한다.
클립키보드에서 검증된 구현을 그대로 이식 (제출 + 이메일 폴백 + 인박스 + 푸시 알림 구독).

```swift
// 설정 화면 List 안에 — 이 한 줄이면 끝
Section("지원") {
    LeeoSupportSection<MyAppSpec>(showInbox: masterModeEnabled)
}

// 또는 개별 화면 사용
LeeoFeedbackView<MyAppSpec>()          // 제출 화면
LeeoFeedbackInboxView<MyAppSpec>()     // 개발자 인박스
```

- 앱 테마 주입(선택): `.leeoStyle(LeeoStyle(accent: ..., bg: ...))` — 없으면 시스템 색
- 유형 구성/초기값(선택): `LeeoFeedbackView<Spec>(types: [.improvement, .bug, .feature, .other], initialType: .improvement)`
- 회신 연락처(선택): `showsContactFields: true, initialContactName:, initialContactEmail:` — 비어 있으면 서버 필드 미기록
- 다국어(ko/en/ja)는 패키지에 내장
- CloudKit Dashboard 설정(앱별 1회)은 `LeeoFeedbackService.swift` 상단 주석 참고
- 여러 앱이 컨테이너 하나를 공유하는 피드백 허브는 `LeeoFeedbackConfig(appIdentifier:)`로 지원
  (Production 스키마에 appId 필드 배포 필요)

## 개발

```bash
swift build
swift test
```

## 플랫폼

iOS 17+ · macOS 14+ · Mac Catalyst 17+
