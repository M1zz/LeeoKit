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

## 개발

```bash
swift build
swift test
```

## 플랫폼

iOS 17+ · macOS 14+ · Mac Catalyst 17+
