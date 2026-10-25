// SPDX-License-Identifier: AGPL-3.0-or-later
// 화면 캡처 (폰 390×844, 3배). 실기기 없이 디자인을 눈으로 확인하는 용도.
//
//   SHOT_FONT=/경로/NotoSansCJKkr-Regular.otf SHOT_FONT_BOLD=/경로/NotoSansCJKkr-Bold.otf \
//   flutter test tool/screenshots/screenshots_test.dart --update-goldens
//
// 결과: tool/screenshots/out/*.png

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glasses_detector/main.dart';
import 'package:glasses_detector/src/model/advertisement.dart';
import 'package:glasses_detector/src/model/signatures.dart';
import 'package:glasses_detector/src/scan/ble_scanner.dart';
import 'package:glasses_detector/src/session/exam_session.dart';
import 'package:glasses_detector/src/ui/countdown_screen.dart';
import 'package:glasses_detector/src/ui/device_screen.dart';
import 'package:glasses_detector/src/ui/session_screen.dart';
import 'package:glasses_detector/src/ui/summary_screen.dart';
import 'package:glasses_detector/src/ui/theme.dart';
import 'package:glasses_detector/src/version.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeScanner implements ScanSource {
  void Function(Advertisement)? feed;
  @override
  Stream<ScannerState> get states => const Stream.empty();
  @override
  void start(void Function(Advertisement) onAdvertisement) => feed = onAdvertisement;
  @override
  void stop() => feed = null;
  @override
  void dispose() {}
}

Future<void> loadFonts() async {
  Future<void> family(String name, List<String?> paths) async {
    final loader = FontLoader(name);
    for (final p in paths.whereType<String>()) {
      loader.addFont(Future.value(ByteData.sublistView(File(p).readAsBytesSync())));
    }
    await loader.load();
  }

  final regular = Platform.environment['SHOT_FONT'];
  final bold = Platform.environment['SHOT_FONT_BOLD'];
  await family('Roboto', [regular, bold]);
  await family('Barlow', [
    'assets/fonts/BarlowCondensed-SemiBold.ttf',
    'assets/fonts/BarlowCondensed-BoldItalic.ttf',
    'assets/fonts/BarlowCondensed-ExtraBoldItalic.ttf',
  ]);
  final flutterRoot = Platform.environment['FLUTTER_ROOT'] ?? '${Platform.environment['HOME']}/dev/flutter';
  await family('MaterialIcons', ['$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf']);
}

void main() {
  final db = SignatureDb.fromJsonString(File('assets/signatures.json').readAsStringSync());

  setUpAll(loadFonts);
  // ignore: invalid_use_of_visible_for_testing_member
  setUp(() => SharedPreferences.setMockInitialValues({'consent.termsVersion': termsVersion}));

  Future<void> phone(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  Widget app(Widget home, {Brightness b = Brightness.dark}) =>
      MaterialApp(debugShowCheckedModeBanner: false, theme: buildTheme(b), home: home);

  /// 20분짜리 감독을 빠르게 재생한다. 기준선 뒤에 신규 기기, 15분쯤 메타 안경이 나타난다.
  /// 세션 시계를 20분 전에서 시작해 1초씩 당긴다.
  final end = DateTime.now();
  var now = end.subtract(const Duration(minutes: 20));

  void replay(ExamSession s, FakeScanner scanner) {
    final rnd = math.Random(7);
    Advertisement adv(String id, int rssi, {int? company, String name = ''}) => Advertisement(
          deviceId: id,
          name: name,
          companyIds: company == null ? const [] : [company],
          serviceUuids: const [],
          rssi: rssi + rnd.nextInt(7) - 3,
          seenAt: now,
        );
    for (var t = 0; t <= 1200; t++) {
      now = end.subtract(Duration(seconds: 1200 - t));
      final crowd = t < 120 ? 10 + t ~/ 12 : 19 + (t ~/ 97) % 3;
      for (var i = 0; i < crowd; i++) {
        scanner.feed?.call(adv('phone$i', -58 - i * 2, company: i.isEven ? 0x004C : 0x0075));
      }
      if (t > 300) scanner.feed?.call(adv('new', -74, company: 0x0157, name: 'Smart Band 9'));
      if (t > 900) {
        final approach = -84 + ((t - 900) / 300 * 26).round();
        scanner.feed?.call(adv('meta', approach, company: 0x01AB));
      }
      if (t == 30) s.finishBaseline();
      s.tick();
    }
  }

  testWidgets('home', (tester) async {
    await phone(tester);
    await tester.pumpWidget(GlassesDetectorApp(signatures: db));
    // 동의 상태 확인(비동기) 뒤 홈이 0.6초에 걸쳐 나타난다.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('out/1_home_dark.png'));
  });

  testWidgets('home light', (tester) async {
    await phone(tester);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await tester.pumpWidget(GlassesDetectorApp(signatures: db));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('out/1_home_light.png'));
  });

  testWidgets('countdown', (tester) async {
    await phone(tester);
    final s = ExamSession(signatures: db);
    await tester.pumpWidget(app(CountdownScreen(session: s, scanner: FakeScanner(), keepAwake: false)));
    await tester.pump(const Duration(milliseconds: 500));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('out/1b_countdown.png'));
    await tester.pump(const Duration(milliseconds: 3700));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('out/1c_scan_on.png'));
    await tester.pumpWidget(const SizedBox());
    s.dispose();
  });

  testWidgets('session', (tester) async {
    await phone(tester);
    final scanner = FakeScanner();
    now = end.subtract(const Duration(minutes: 20));
    final session = ExamSession(signatures: db, clock: () => now);
    await tester.pumpWidget(app(SessionScreen(session: session, scanner: scanner, keepAwake: false)));
    replay(session, scanner);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 800));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('out/2_session.png'));

    final meta = session.devices.firstWhere((d) => d.alert == AlertLevel.signature);
    await tester.pumpWidget(app(DeviceScreen(session: session, device: meta)));
    await tester.pump(const Duration(milliseconds: 600));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('out/3_device.png'));

    session.end();
    await tester.pumpWidget(app(SummaryScreen(session: session)));
    await tester.pump();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('out/4_summary.png'));
    await tester.pumpWidget(const SizedBox());
  });
}
