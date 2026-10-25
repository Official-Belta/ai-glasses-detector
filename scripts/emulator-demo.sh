#!/bin/bash
# 에뮬레이터에 모의 모드 앱을 띄운다 (가짜 신호: 40초 신규 기기, 70초 메타 안경).
# 사전 조건: PowerShell 에서 `wsl -u root chmod 666 /dev/kvm` (재부팅마다 1회)
set -e
source ~/dev/env.sh
if ! adb devices | grep -q emulator; then
  nohup emulator -avd exam_phone -gpu swiftshader_indirect -no-snapshot-save -no-audio -no-boot-anim > ~/dev/emulator.log 2>&1 &
  echo "에뮬레이터 부팅 중..."
  until [ "$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = 1 ]; do sleep 3; done
fi
~/dev/sync.sh
cd ~/build/app
flutter build apk --release --dart-define=SIMULATE=true --target-platform android-x64
adb install -r build/app/outputs/flutter-apk/app-release.apk
adb shell am start -n kr.aiglasses.detector/kr.aiglasses.glasses_detector.MainActivity
echo "실행됨. 에뮬레이터 창에서 '감독 시작'을 누르세요."
