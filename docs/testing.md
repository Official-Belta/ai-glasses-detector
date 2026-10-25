# 테스트 방법 (실물 안경 없이)

## 1. 단위 테스트

```bash
~/dev/sync.sh && cd ~/build/app && source ~/dev/env.sh && flutter test
```

시그니처 매칭, 기준선 처리, 신규 기기 감지, MAC 랜덤화 대응, 보고서에 주소가 빠지는지를 검사한다 (`app/test/detection_test.dart`).

## 2. 실기기 설치

폰에서 개발자 옵션과 USB 디버깅을 켠다. Windows에 연결한 폰은 WSL에서 바로 보이지 않으므로 둘 중 하나를 쓴다.

- APK 파일을 폰으로 옮겨 설치: `~/build/app/build/app/outputs/flutter-apk/app-release.apk`
- 무선 디버깅(Android 11+): 폰에서 "무선 디버깅"을 켠 뒤 `adb pair <IP:포트>` 다음 `adb connect <IP:포트>`, 그다음 `flutter run`

## 3. 가짜 AI 안경 (남는 안드로이드 폰 + nRF Connect)

1. 송신용 폰에 **nRF Connect for Mobile**(Nordic) 설치
2. ADVERTISER 탭에서 새 광고 추가
3. Advertising data에서 Add record 다음 **Manufacturer Data**
   - Company ID: `0x01AB` (Meta). 다른 시그니처는 `0x058E`, `0x0D53`, `0x03C2`, `0x05D6`
   - Data: 아무 값 (예: `0102`)
4. Options에서 Connectable은 상관없고, Legacy advertising을 쓴다.
5. 광고 시작

## 4. 시나리오별 기대 결과

| 시나리오 | 방법 | 기대 결과 |
|---|---|---|
| 처음부터 안경 착용 | 송신 폰을 켠 채로 감독 시작 | 기준선 수집 중에도 즉시 빨간 경고 + 진동 |
| 검사 후 바꿔 끼기 | 기준선이 끝난 뒤 송신 시작 | 빨간 경고 (시그니처 일치 시) |
| 미확보 기종 | Company ID를 목록에 없는 값(예: `0x0157`)으로, 기준선 이후 송신 | 노란 경고 (신규 기기) |
| 원래 있던 폰 | 기준선 전부터 있던 기기 | 경고 없음 |
| 거리 감지 | 빨간 경고 기기를 눌러 신호 세기 화면을 연 뒤 송신 폰에서 멀어졌다 가까워지기 | dBm 값과 신호 세기 변화 표시가 바뀜 |
| 블루투스 끔 | 감독 중 감독관 폰의 블루투스 끄기 | 빨간 배너, 다시 켜면 자동으로 스캔 재개 |
| 기록 | 감독을 종료한 다음 기록 내보내기 | 텍스트 파일에 이벤트, 분당 신호가 기록되고 MAC 주소는 없음 |

## 5. 실전 검증 (출시 전 권장)

- 통신3사 매장, 백화점, 안경원에 있는 레이밴 메타 시연품 옆에서 스캔
- 라운즈 안경원 체험존(로키드, 레이네오)에서 미확보 기종의 패킷 수집: "주변 기기 전체" 화면에서 제조사 ID와 이름을 기록해 `signatures.json`에 추가

## 6. PC 에뮬레이터에서 모의 모드로 보기

1. PowerShell: `wsl -u root chmod 666 /dev/kvm` (재부팅마다 1회)
2. WSL: `bash scripts/emulator-demo.sh`
3. 에뮬레이터 창에서 "감독 시작"을 누른다. 40초에 신규 기기(노랑), 70초에 메타 안경(빨강)이 나타나고, 메타 안경 신호는 40초 주기로 세졌다 약해진다.

모의 모드는 `--dart-define=SIMULATE=true`로 빌드할 때만 켜진다(`app/lib/src/scan/simulated_scanner.dart`). 배포 빌드에는 들어가지 않는다.
에뮬레이터용 리눅스 라이브러리는 sudo 없이 `apt download`로 받아 `~/dev/emu-libs`에 풀어 두었다(`~/dev/env.sh`의 `LD_LIBRARY_PATH`).
