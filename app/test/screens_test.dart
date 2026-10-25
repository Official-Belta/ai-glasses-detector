// SPDX-License-Identifier: AGPL-3.0-or-later
// 화면 스모크 테스트: 블루투스 플러그인을 쓰지 않는 화면이 오류 없이 그려지는지 확인.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glasses_detector/main.dart';
import 'package:glasses_detector/src/model/advertisement.dart';
import 'package:glasses_detector/src/model/signatures.dart';
import 'package:glasses_detector/src/session/exam_session.dart';
import 'package:glasses_detector/src/ui/about_screen.dart';
import 'package:glasses_detector/src/ui/device_screen.dart';
import 'package:glasses_detector/src/ui/summary_screen.dart';
import 'package:glasses_detector/src/ui/theme.dart';
import 'package:glasses_detector/src/version.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final db = SignatureDb.fromJsonString(File('assets/signatures.json').readAsStringSync());

  Widget wrap(Widget child) => MaterialApp(theme: buildTheme(Brightness.dark), home: child);

  ExamSession sampleSession() {
    final s = ExamSession(signatures: db)..start();
    final now = DateTime.now();
    for (var i = 0; i < 3; i++) {
      s.onAdvertisement(Advertisement(
          deviceId: 'g', name: '', companyIds: const [0x01AB], serviceUuids: const [], rssi: -60 - i, seenAt: now));
    }
    s.end();
    return s;
  }

  testWidgets('처음 실행: 동의 전에는 시작 버튼이 꺼져 있고, 동의하면 홈으로', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(GlassesDetectorApp(signatures: db));
    await tester.pumpAndSettle();
    expect(find.text('동의하고 시작'), findsOneWidget);
    await tester.tap(find.text('동의하고 시작'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('감독 시작'), findsNothing);
    await tester.tap(find.textContaining('동의하고 개인정보처리방침'));
    await tester.pump();
    await tester.tap(find.text('동의하고 시작'));
    await tester.pump(const Duration(milliseconds: 1000));
    expect(find.text('감독 시작'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('consent.termsVersion'), termsVersion);
  });

  testWidgets('홈 화면', (tester) async {
    SharedPreferences.setMockInitialValues({'consent.termsVersion': termsVersion});
    await tester.pumpWidget(GlassesDetectorApp(signatures: db));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.text('감독 시작'), findsOneWidget);
    // 누르면 설정 시트가 올라온다.
    await tester.tap(find.text('감독 시작'));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('교실 기기 확인'), findsOneWidget);
    expect(find.text('새 기기 알림 범위'), findsOneWidget);
    expect(find.text('의심 시 알람'), findsOneWidget);
    expect(find.text('시작'), findsOneWidget);
  });

  testWidgets('앱 정보 화면에 찾는 안경 목록', (tester) async {
    await tester.pumpWidget(wrap(AboutScreen(signatures: db)));
    expect(find.text('찾는 안경'), findsOneWidget);
    expect(find.text('0x01AB  0x058E'), findsOneWidget);
  });

  testWidgets('앱 정보 화면에 원작자 크레딧', (tester) async {
    await tester.pumpWidget(wrap(AboutScreen(signatures: db)));
    await tester.scrollUntilVisible(find.textContaining('Nearby Glasses'), 300);
    expect(find.textContaining('Yves Jeanrenaud'), findsOneWidget);
  });

  testWidgets('감독 기록 화면', (tester) async {
    final s = sampleSession();
    await tester.pumpWidget(wrap(SummaryScreen(session: s)));
    expect(find.text('기록 이미지 공유'), findsOneWidget);
    expect(find.textContaining('증거가 아닙니다'), findsOneWidget);
    expect(find.textContaining('Meta'), findsWidgets);
    s.dispose();
  });

  testWidgets('핫콜드 화면', (tester) async {
    final s = sampleSession();
    await tester.pumpWidget(wrap(DeviceScreen(session: s, device: s.devices.first)));
    expect(find.text('강함'), findsWidgets);
    await tester.pumpWidget(const SizedBox()); // 타이머 정리
    s.dispose();
  });
}
