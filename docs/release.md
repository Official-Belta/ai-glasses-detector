# 출시 절차

## 0. 개발 환경 (WSL)

설치 위치: `~/dev` (JDK 17, Flutter, Android SDK). 환경변수는 `source ~/dev/env.sh`로 불러온다.

**주의: 한글 경로 문제.** Dart 분석기와 테스트가 `C:\Users\정경준` 같은 한글 경로에서 깨진다(LSP 길이 계산 버그).
원본은 바탕화면 `app/`에서 편집하고 빌드, 분석, 테스트는 리눅스 쪽 복사본에서 한다.

```bash
~/dev/sync.sh                 # 바탕화면 app/ 를 ~/build/app 으로 동기화
cd ~/build/app && source ~/dev/env.sh
flutter analyze && flutter test
flutter build appbundle --release
```

`flutter pub add`나 아이콘 재생성처럼 `~/build/app`에서 파일이 바뀌는 명령을 실행했다면, 바뀐 파일(`pubspec.yaml`, `pubspec.lock`, `android/app/src/main/res`, `ios/Runner/Assets.xcassets`)을 바탕화면으로 다시 복사한다.

SDK 플랫폼 37 메모: AGP 9.1은 `android-37` 이름을 찾는데 SDK 매니저는 `android-37.0`으로 설치한다.
`~/dev/android-sdk/platforms/android-37`은 37.0을 가리키는 별칭으로 만들어 두었다. 새 PC에서는 같은 처리를 하거나 Android Studio로 SDK를 설치할 것.

## 1. 출시 전 확정할 것

- [ ] **앱 ID**: 현재 `kr.aiglasses.detector`(Android, iOS 공통). Play에 한 번 올리면 바꿀 수 없다.
- [ ] **앱 이름**: 현재 "AI 안경 탐지기". 원작 "Nearby Glasses"와 헷갈리지 않는 이름이어야 한다.
- [ ] **GitHub 저장소 주소**: `app/lib/src/version.dart`의 `sourceUrl` 수정. AGPL상 앱 안에서 소스 위치를 알려야 한다.
- [ ] `PRIVACY.md`를 GitHub에 올린 뒤 그 URL을 Play Console 개인정보처리방침 칸에 입력.
- [ ] 실기기 E2E 테스트 ([testing.md](testing.md)).

## 2. Android 업로드 키 만들기 (최초 1회)

```bash
source ~/dev/env.sh
keytool -genkey -v -keystore ~/upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

`app/android/key.properties` 파일을 만든다. 이 파일은 git에서 제외되어 있다.

```properties
storePassword=<입력한 비밀번호>
keyPassword=<입력한 비밀번호>
keyAlias=upload
storeFile=/home/jj/upload-keystore.jks
```

키스토어 파일과 비밀번호는 별도로 백업할 것. Play App Signing을 쓰면 업로드 키를 잃어도 재설정은 가능하지만 며칠 걸린다.
`key.properties`가 없으면 릴리스 빌드가 디버그 키로 서명되며 이 빌드는 Play에 올릴 수 없다.

## 3. Play 스토어

1. Google Play Console 개발자 등록 ($25, 1회)
2. **신규 개인 계정은 출시 전 비공개 테스트가 필수다(테스터 12명 이상, 14일 연속).** 수능 일정(11/19)을 맞추려면 지금 바로 시작해야 한다. 목표 시점까지 빠듯하면 GitHub Releases에 APK를 먼저 올리고, IzzyOnDroid(F-Droid 저장소)에 등록하는 방법을 병행한다.
3. `flutter build appbundle --release` 실행 다음 `build/app/outputs/bundle/release/app-release.aab` 업로드
4. 스토어 등록 정보: `fastlane/metadata/android/ko-KR/` 문구 사용. 아이콘 512px은 `app/assets/icon/play_store_512.png`
5. 데이터 보안 양식: "데이터를 수집하거나 공유하지 않음"
6. 권한 신고: 위치 권한은 `maxSdkVersion=30`으로 제한되어 있다. Android 11 이하에서 BLE 스캔에 시스템이 요구하기 때문이라고 설명한다.
7. 콘텐츠 등급 설문, 타깃층(성인/교사)

## 4. iOS (보류 중, Mac 필요)

코드와 설정(`Info.plist` 블루투스 사용 문구, 번들 ID, 아이콘)은 준비되어 있다. Mac에서 다음을 한다.

```bash
cd app && flutter build ios --release   # 처음엔 Xcode에서 Runner 서명 팀 지정
```

- Apple Developer Program ($99/년)
- iOS는 앱이 화면에 떠 있을 때만 스캔된다. 감독 중에는 앱이 화면을 켜 둔다.
- Mac이 없으면 Codemagic 같은 클라우드 CI로 빌드할 수 있다. 서명 인증서는 Apple 계정이 있어야 만들 수 있다.
