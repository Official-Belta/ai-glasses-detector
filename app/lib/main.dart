// SPDX-License-Identifier: AGPL-3.0-or-later
// AI 안경 탐지기: Nearby Glasses(Yves Jeanrenaud, AGPL-3.0)를 바탕으로 한 한국 시험 감독용 포크.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'src/model/signatures.dart';
import 'src/scan/simulated_scanner.dart';
import 'src/ui/consent_screen.dart';
import 'src/ui/home_screen.dart';
import 'src/ui/summary_screen.dart';
import 'src/ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(['Barlow'], await rootBundle.loadString('assets/fonts/Barlow-OFL.txt'));
  });
  cleanExportFiles();
  if (simulateScan) _logFrameTimings();
  final signatures = SignatureDb.fromJsonString(await rootBundle.loadString('assets/signatures.json'));
  runApp(GlassesDetectorApp(signatures: signatures));
}

/// 개발용(모의 모드)에서만: 5초마다 프레임 수와 16.7ms(60fps)를 넘긴 프레임 수를 로그로 남긴다.
/// `adb logcat -s flutter` 로 본다. 버벅임을 감이 아니라 숫자로 확인하려고 둔다.
void _logFrameTimings() {
  final build = <int>[], raster = <int>[];
  var last = DateTime.now();
  int p90(List<int> xs) => (xs..sort())[(xs.length * 0.9).floor().clamp(0, xs.length - 1)];
  SchedulerBinding.instance.addTimingsCallback((timings) {
    for (final t in timings) {
      build.add(t.buildDuration.inMicroseconds);
      raster.add(t.rasterDuration.inMicroseconds);
    }
    final now = DateTime.now();
    if (now.difference(last).inSeconds < 5 || build.isEmpty) return;
    last = now;
    final slow = [for (var i = 0; i < build.length; i++) if (build[i] + raster[i] > 16667) i].length;
    debugPrint('[frames] ${build.length}개, 16.7ms 초과 $slow개, '
        '앱 계산 p90 ${(p90(build) / 1000).toStringAsFixed(1)}ms, 그리기 p90 ${(p90(raster) / 1000).toStringAsFixed(1)}ms');
    build.clear();
    raster.clear();
  });
}

class GlassesDetectorApp extends StatelessWidget {
  const GlassesDetectorApp({super.key, required this.signatures});

  final SignatureDb signatures;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI 안경 탐지기',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      // 다크 우선: 시험장에서 화면 빛이 덜 튄다.
      themeMode: ThemeMode.dark,
      locale: const Locale('ko'),
      supportedLocales: const [Locale('ko')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: _ConsentGate(signatures: signatures),
    );
  }
}

/// 동의한 약관 버전이 지금과 같으면 바로 홈, 아니면 동의 화면부터.
class _ConsentGate extends StatefulWidget {
  const _ConsentGate({required this.signatures});

  final SignatureDb signatures;

  @override
  State<_ConsentGate> createState() => _ConsentGateState();
}

class _ConsentGateState extends State<_ConsentGate> {
  bool? _accepted;

  @override
  void initState() {
    super.initState();
    hasConsent().then((v) {
      if (mounted) setState(() => _accepted = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    final accepted = _accepted;
    if (accepted == null) return const Scaffold();
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      child: accepted
          ? HomeScreen(key: const ValueKey('home'), signatures: widget.signatures)
          : ConsentScreen(key: const ValueKey('consent'), onAccepted: () => setState(() => _accepted = true)),
    );
  }
}
