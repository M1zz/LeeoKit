# 백업 금고 (LeeoVault) — iCloud 설정

LeeoVault 는 앱마다 하루 한 번 최신 백업을 **사용자 본인 iCloud 의 private 데이터베이스**에 올린다.
컨테이너는 피드백 허브(`iCloud.com.Ysoup.FeedbackHub`, 앱의 `Spec.feedback.containerIdentifier`)다.
private DB 라 개발자는 내용을 볼 수 없고, 사용자의 iCloud 용량을 쓴다.

## 한 번만: Production 스키마

CloudKit 은 Production 에서 새 레코드 타입을 만들지 않는다. 한 번 배포해야 올리기가 된다.

1. https://icloud.developer.apple.com → `iCloud.com.Ysoup.FeedbackHub` → **Development** 환경
2. Schema → Record Types → **+** → 이름 `LeeoBackup`, 필드:

   | 필드 | 타입 |
   |---|---|
   | `appId` | String |
   | `createdAt` | Date/Time |
   | `appVersion` | String |
   | `device` | String |
   | `bytes` | Int(64) |
   | `archive` | Asset |

   (또는 개발 빌드에서 "백업 및 복원 → iCloud 에 자동 백업" 을 한 번 켜면 Development 에 저절로 생긴다)
3. **Deploy Schema Changes…** → Production

인덱스 · 보안 역할은 필요 없다. 레코드는 ID(`LeeoBackup.<번들ID>.<0~2>`)로만 읽고 쓴다.

## 앱 쪽

- entitlements 의 `com.apple.developer.icloud-container-identifiers` 에 위 컨테이너가 있어야 한다.
  없는 앱은 `static let vaultUsesICloud = false` — 없는 컨테이너를 열면 앱이 죽는다.
- 위젯 · 익스텐션과 나눠 쓰는 앱 그룹은 `static let appGroups = [...]` 에 적는다.
