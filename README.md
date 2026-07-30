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

## 원격 킬스위치 (LeeoRemoteFlags)

심사 없이 문제 기능을 끄는 최소 장치. 피드백·통계와 **같은 CloudKit 컨테이너**를 쓰므로
새 인프라가 필요 없다.

```swift
enum MyFlag: String, LeeoRemoteFlag, CaseIterable {
    case syncEnabled, paywallEnabled
}

// 앱 시작 시 1회 (App Group 을 주면 키보드·위젯도 같은 값을 읽는다)
LeeoRemoteFlags(spec: MyAppSpec.self, appGroupSuiteName: "group.com.x.y")
    .refreshInBackground(MyFlag.self)

// 쓰는 곳 — 네트워크를 타지 않고 즉시 반환
guard LeeoRemoteFlags.isEnabled(MyFlag.syncEnabled) else { return }
```

- ⚠️ **조회 실패 = 켬.** 네트워크가 없다고 기능이 꺼지면 킬스위치가 장애 원인이 된다.
- ⚠️ 갱신은 기본 6시간 쓰로틀 + 백그라운드. **즉시 전파되지 않는다.**
- Dashboard: 레코드 타입 `RemoteFlags` / recordName `flags_<appIdentifier>` /
  각 플래그 rawValue 를 **Int64**(1=켬, 0=끔). 필드를 안 만들면 켬으로 동작한다.

## 크래시·행 진단 (LeeoDiagnostics)

MetricKit 진단을 같은 허브에 쌓는다. 외부 SDK 0개 원칙을 유지하면서
**키보드·위젯 익스텐션의 메모리 종료(jetsam)까지** 잡을 수 있는 게 핵심이다.

```swift
// 앱 시작 시 1회 — 구독만 하고 즉시 반환(런치 비용 없음)
LeeoDiagnostics.shared.start(spec: MyAppSpec.self,
                             isEnabled: { LeeoRemoteFlags.isEnabled(MyFlag.diagnostics) })

// 뷰어(맥 앱 등)에서 조회
let reports = try await LeeoDiagnosticsReader.fetch(spec: MyAppSpec.self)
```

- ⚠️ 페이로드는 iOS 가 **하루 한 번꼴로 묶어서** 준다 → 실시간 알림용이 아니다.
- ⚠️ 시뮬레이터에선 거의 안 온다. macOS/Catalyst 는 자동으로 no-op.
- 보내는 것: 콜스택·앱 버전·OS·기기 종류. **설치 식별자도 안 붙인다.**
  App Privacy 는 `CrashData`(미연결·비추적)로 신고할 것.
- Dashboard: 레코드 타입 `CrashReport` (appId·kind·detail·appVersion·osVersion·deviceType·stack)

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

## 리뷰 요청 · 만족도 프롬프트

좋은 인상일 때만 App Store 리뷰를 유도하고, 불편한 사용자는 별점 대신 피드백으로 흡수한다.

```swift
// 1) 앱 시작 시 사용량 기록 (1회)
LeeoEngagement.shared.registerLaunch()

// 2) 저장/완료/공유 등 "만족했을 법한" 행동 뒤에
LeeoEngagement.shared.registerSignificantEvent()

// 3) 루트 화면에 한 줄 — 조건이 맞으면 스스로 "즐겁게 쓰고 계신가요?"를 물어본다
//    만족 → 시스템 리뷰 요청 / 아쉬움 → 피드백 화면
RootView()
    .leeoSatisfactionCheck(MyAppSpec.self)
```

- 노출 조건은 `LeeoReviewPolicy` (기본: 실행 3회·설치 2일·긍정행동 1회↑, 버전당 1회, 120일 쿨다운)
- 직접 제어: `.leeoReviewGate(MyAppSpec.self, isPresented: $flag)`
- 시스템 프롬프트만 바로: `LeeoReviewRequest.requestIfAppropriate { requestReview() }`
  (SwiftUI `@Environment(\.requestReview)`)
- 설정의 `LeeoSupportSection`에는 **"리뷰 남기기"** 행이 자동 포함된다
  (`MyAppSpec.appStoreID` 지정 시 작성 페이지 딥링크, 없으면 시스템 평점 프롬프트)
- App Store ID(선택): `LeeoAppSpec`에 `static let appStoreID: String? = "1234567890"`

## 페이월 · 인앱 결제 (StoreKit 2)

앱마다 결제 코드를 새로 짜지 않는다. 계약에 상품 ID만 채우면 로드·구매·복원·권한 판정은
`LeeoStore`가, 화면은 `LeeoPaywallView`가 담당한다. 트랜잭션 갱신(환불·가족 공유·타기기 구매)은
백그라운드 리스너가 자동 반영한다.

```swift
// 1) 계약에 상품 구성 (선택 항목 — 페이월 안 쓰는 앱은 생략)
enum MyAppSpec: LeeoAppSpec {
    static let appName = "MyApp"
    static let developerEmail = "leeo@kakao.com"
    static let feedback = LeeoFeedbackConfig(containerIdentifier: "iCloud.com.Ysoup.MyApp")
    static let paywall = LeeoPaywallConfig(
        productIDs: ["com.Ysoup.MyApp.pro.monthly", "com.Ysoup.MyApp.pro.yearly"],
        termsURL: URL(string: "https://ysoup.io/terms"),
        privacyURL: URL(string: "https://ysoup.io/privacy")
    )
}

// 2) 페이월을 시트로 — 이 한 줄. 구매/복원 성공 시 자동으로 닫힌다
SomeView()
    .leeoPaywallSheet(MyAppSpec.self, isPresented: $showPaywall,
                      features: ["광고 제거", "무제한 저장", "프리미엄 테마"])

// 3) 권한을 앱 전역에서 관찰하려면 스토어를 한 번 만들어 주입
@StateObject private var store = LeeoStore(config: MyAppSpec.paywall!)
WindowGroup { RootView().environmentObject(store) }
// 어디서든:  if store.hasPro { ... } else { showPaywall = true }
```

- 화면은 `.leeoStyle(...)`로 앱 테마 룩 주입 (없으면 시스템 색)
- 구독 상품은 가격 옆에 "월/년" 기간이 자동 표기, 상품 카드 순서 = `productIDs` 순서
- `entitlementIDs`로 "판매는 안 하지만 권한만 인정할" ID를 따로 지정 가능 (기본: 판매 상품 전체)
- 다국어(ko/en/ja)는 패키지에 내장 (미번역 키는 한국어로 폴백)
- 테스트는 Xcode의 `.storekit` Configuration 또는 샌드박스 계정으로 확인

## 개발

```bash
swift build
swift test
```

## 플랫폼

iOS 17+ · macOS 14+ · Mac Catalyst 17+
