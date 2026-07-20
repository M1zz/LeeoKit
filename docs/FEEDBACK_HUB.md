# 공용 피드백 허브 (FeedbackHub)

여러 앱의 피드백을 CloudKit 컨테이너 **하나**로 모아, 인박스 한 곳에서 전부 확인하는 구성.

- 컨테이너: `iCloud.com.Ysoup.FeedbackHub` (모든 앱이 같은 팀이라 공유 가능)
- 레코드 구분: `appId` 필드에 각 앱의 번들 ID 저장
- 앱 쪽 설정:
  ```swift
  static let feedback = LeeoFeedbackConfig(
      containerIdentifier: "iCloud.com.Ysoup.FeedbackHub",
      appIdentifier: "com.Ysoup.MyApp"   // 이 앱의 번들 ID
  )
  ```
- 인박스는 자동으로 자기 앱(appId) 것만 필터한다. 전체 앱을 한꺼번에 보려면
  `appIdentifier: nil` 설정의 `LeeoFeedbackInboxView`를 쓰는 개발자용 화면을 아무 앱에나 두면 된다.

## Xcode 설정 (앱별 1회)

1. 타겟 → Signing & Capabilities → iCloud → CloudKit 체크
2. Containers에 `iCloud.com.Ysoup.FeedbackHub` 추가 (+ 버튼으로 새 컨테이너 등록 가능)
   - entitlements 파일에는 `com.apple.developer.icloud-container-identifiers`에 추가된다
   - 기존 앱 전용 컨테이너는 그대로 두고 **추가**만 하면 된다

## CloudKit Dashboard 설정 (허브 전체 1회)

https://icloud.developer.apple.com → FeedbackHub 컨테이너:

1. **스키마 생성**: Development 환경에서 앱으로 피드백 1건 제출하면 `Feedback` 레코드 타입이
   자동 생성된다 (appId 포함 전 필드).
2. **인덱스**: `recordName` Queryable + `createdTimestamp` Sortable 추가 (인박스 조회용).
3. **Security Roles**:
   - `_world`: create만 허용, read 제거 (다른 사용자가 피드백을 못 읽게)
   - admin 역할 생성: read + write 권한, 개발자 본인 userRecordName 등록
     (userRecordName은 인박스 화면 하단에서 복사 가능)
4. **Production 배포**: Schema → Deploy Schema Changes to Production.

⚠️ 기존 앱(클립키보드)은 자기 컨테이너(`iCloud.com.Ysoup.TokenMemo`)에 이미 Production
스키마와 접수 데이터가 있으므로 허브로 옮기지 않는다 (appIdentifier: nil 유지).
새 앱부터 허브를 쓴다.
