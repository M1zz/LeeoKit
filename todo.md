# LeeoKit todo

## 완료: CloudKit 조회를 페이지로 나눠 받기 (v3.3)

> 계기: ClipKeyboard 사용 통계가 설치 900건에서 통째로 죽었다.
> `Your request contains 900 items which is more than the maximum number of
> items in a single request (400)` — CloudKit은 한 요청에 400개가 상한인데
> `fetchSnapshots(limit: 1000)` 이 그걸 한 방에 요구하고 있었다.
> 데이터가 늘면 언젠가 반드시 터지는 자리였고, 실제로 터졌다.

- [x] `LeeoCloudPage.collect` — 커서로 200건씩 이어 받는 공용 조회.
      한 요청 크기(`size`)와 전체 상한(`limit`)을 분리해서, 상한을 올려도 요청은 안 커진다
- [x] 페이지가 도착할 때마다 `onPage`로 "지금까지"를 넘긴다 → 화면이 자라면서 채워진다.
      900건을 다 받을 때까지 빈 화면을 보고 있지 않아도 된다
- [x] 중간 페이지가 실패하면 거기까지를 결과로 돌려준다. **첫 페이지부터** 실패했을 때만
      throw — 권한/스키마 문제는 말해야 하지만, 그 외에는 부분이라도 숫자를 보여주는 게 낫다
- [x] `LeeoUsageReporter.fetchSnapshots(limit:onPage:)` · `LeeoFeedbackService.fetchAll` ·
      `LeeoDiagnosticsReader.fetch` 셋 다 같은 방식으로 교체 (뒤 둘은 기본값이 100·200이라
      아직 안 터졌을 뿐, 같은 지뢰였다)
- [x] `LeeoCloudProgress` / `LeeoCloudStop` — 데이터와 함께 **어디까지 왔고 왜 멈췄는지**를
      넘긴다. 나눠 받기 시작하면 화면에 새 의무가 생긴다: 낮은 숫자가 "아직 받는 중"인지
      "원래 그만큼"인지 "중간에 끊긴 것"인지 사람이 구분할 수 없다. 셋은 할 일이 다르다 —
      기다리기 / 그대로 믿기 / 다시 받기
- [x] `LeeoUsageStatsView` — 부분 결과 + 에러를 **함께** 보여준다. 예전엔 에러가 나면
      받아 둔 숫자까지 화면에서 사라졌다. 받는 중엔 "불러오는 중… N건 (M페이지)",
      끝나면 "전부 불러왔어요 (9:13 기준)" 또는 상한/중단 사유를 명시


## 완료: 성숙도 계약 레이어 (v3.0)

> 목표: **"LeeoKit을 import했다면 그 앱은 성숙한 서비스다"** 가 참이 되도록,
> 앱마다 매번 다시 고민하던 판단을 계약(타입)으로 묶는다.
> 구현체(페이월 레이아웃 등)가 아니라 **판단 로직 + 제약**만 담당한다.

- [x] `LeeoMonetization` — 수익모델을 선언으로 치환 (페이월 필요 여부가 판단이 아니라 타입)
      · 구독은 `termsURL` 이 옵셔널이 아니라 약관 없이는 컴파일 불가
      · `paywallConfig(legal:)` 로 `LeeoPaywallConfig` 자동 유도
- [x] `LeeoGatePolicy` / `LeeoGate` — "지금 페이월을 띄워야 하나" 순수 판정 함수
      · 무료 한도 · 프로 전용 · 사전 경고(`warnWhenRemaining`) · 체험(`LeeoTrial`)
      · `LeeoStore.gate` 로 권한과 자동 결합
- [x] `LeeoLegalConfig` — 개인정보·지원·약관·데이터삭제 링크를 계약 필수 항목으로
      · `LeeoSupportSection` 이 설정 화면에 링크 행을 자동 노출
- [x] `LeeoAnalytics` — SDK 결합 없는 싱크 프로토콜 + 이벤트 규약 (기본 no-op)
      · 페이월 노출·구매 시작/성공/실패/복원을 LeeoKit 이 스스로 발화
- [x] `LeeoCapability` / `LeeoCapabilities` — 완성도 체크리스트 52항목을 코드 선언으로
      · `.implemented` / `.notApplicable(이유 필수)` / `.unknown` 3분법
- [x] `LeeoManifest` — 선언을 JSON으로 내보내 포트폴리오 탐색기가 추정 대신 실측하게
- [x] `LeeoPreflight` — 컴파일로 못 잡는 것을 DEBUG 런타임/테스트에서 감사
- [x] `LeeoKit.bootstrap(_:)` — 계약을 실제로 켜는 한 줄 (사용량·분석·진단·플래그·감사)
- [x] `LeeoAppSpec` 확장 (`legal`·`monetization` 필수, `paywall` 파생화)
- [x] 순수 로직 단위 테스트 34개 추가 (전체 68개 통과)
- [x] README / OPERATING_POLICY 갱신 (§0-1 계약 레이어는 세 번 규칙 예외)

## 다음 (필요해질 때만 — 로드맵 아님)

- [ ] 매니페스트 추출 실행 경로 — 앱 테스트 타깃에서 JSON을 뽑아 파일로 떨구기
- [ ] `docs/portfolio-explorer.html` 이 매니페스트 JSON을 읽도록 수정
      (현재는 소스 grep 추정 — 46개 중 21개만 스캔됨)
- [ ] 첫 실제 앱 마이그레이션 — 다음에 유료 앱을 만질 때 그 앱 안에서 2.0 적용
- [ ] `LeeoEvent` 발화 지점 확대 (피드백 제출·만족도 프롬프트 노출)
