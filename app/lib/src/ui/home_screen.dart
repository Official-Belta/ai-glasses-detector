// SPDX-License-Identifier: AGPL-3.0-or-later
// 첫 화면: 가운데 동그란 '감독 시작' 하나. 누르면 설정 시트가 올라오고, 거기서 시작한다.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../model/signatures.dart';
import '../scan/ble_scanner.dart';
import '../scan/simulated_scanner.dart';
import '../session/exam_session.dart';
import 'about_screen.dart';
import 'common.dart';
import 'countdown_screen.dart';
import 'theme.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.signatures});

  final SignatureDb signatures;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // 앱이 켜져 있는 동안 마지막 설정을 기억한다.
  int _checkSeconds = 30;
  int _range = -80;
  AlarmMode _alarm = AlarmMode.long;

  Future<void> _openSetup() async {
    final start = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: context.c.panel,
      isScrollControlled: true,
      sheetAnimationStyle: const AnimationStyle(
        duration: Duration(milliseconds: 350),
        reverseDuration: Duration(milliseconds: 250),
        curve: easeOut,
      ),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(10))),
      builder: (ctx) => _SetupSheet(
        checkSeconds: _checkSeconds,
        range: _range,
        alarm: _alarm,
        onChanged: (s, r, a) => setState(() {
          _checkSeconds = s;
          _range = r;
          _alarm = a;
        }),
      ),
    );
    if (start == true && mounted) await _start();
  }

  Future<void> _start() async {
    final ScanSource scanner;
    if (simulateScan) {
      scanner = SimulatedScanner();
    } else {
      final ble = BleScanner();
      final granted = await ble.requestPermissions();
      if (!mounted) return;
      if (!granted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('설정에서 "주변 기기" 권한을 허용해 주세요.'),
        ));
        ble.dispose();
        return;
      }
      scanner = ble;
    }
    final session = ExamSession(
      signatures: widget.signatures,
      settings: SessionSettings(
        baselineDuration: Duration(seconds: _checkSeconds),
        newDeviceRssiThreshold: _range,
        alarm: _alarm,
      ),
    );
    await Navigator.of(context).push(fadeRoute(CountdownScreen(session: session, scanner: scanner)));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI 안경 탐지기'),
        actions: [
          IconButton(
            tooltip: '앱 정보',
            icon: Icon(Icons.info_outline, color: c.ink2),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => AboutScreen(signatures: widget.signatures),
            )),
          ),
        ],
      ),
      // 시작 화면(검은 바탕 + 아이콘)에서 넘어올 때 버튼이 살짝 커지며 나타난다.
      body: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 600),
        curve: const Cubic(0.22, 1, 0.36, 1),
        builder: (context, t, child) => Opacity(
          opacity: t,
          child: Transform.scale(scale: 0.92 + 0.08 * t, child: child),
        ),
        child: Stack(
          children: [
            Center(child: _StartCircle(onTap: _openSetup)),
            if (simulateScan)
              Positioned(
                left: 0,
                right: 0,
                bottom: 32,
                child: Text('개발용 모의 모드', textAlign: TextAlign.center, style: T.bodyStrong.copyWith(color: c.warn)),
              ),
          ],
        ),
      ),
    );
  }
}

/// 가운데 동그란 버튼. 바깥 링이 천천히 퍼졌다 사라지며 대기 중임을 보인다.
class _StartCircle extends StatefulWidget {
  const _StartCircle({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_StartCircle> createState() => _StartCircleState();
}

class _StartCircleState extends State<_StartCircle> with SingleTickerProviderStateMixin {
  late final AnimationController _ring = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 동작 줄이기 설정이면 링을 멈춘다.
    if (MediaQuery.of(context).disableAnimations) {
      _ring.stop();
    } else if (!_ring.isAnimating) {
      _ring.repeat();
    }
  }

  @override
  void dispose() {
    _ring.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    const size = 220.0;
    return Semantics(
      button: true,
      label: '감독 시작',
      child: Pressable(
        haptic: false,
        pressedScale: 0.95,
        onTap: () {
          HapticFeedback.mediumImpact();
          widget.onTap();
        },
        child: SizedBox(
          width: size * 1.6,
          height: size * 1.6,
          child: AnimatedBuilder(
            animation: _ring,
            builder: (context, child) {
              final t = Curves.easeOutCubic.transform(_ring.value);
              return Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: size * (1 + 0.55 * t),
                    height: size * (1 + 0.55 * t),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: c.brand.withValues(alpha: 0.5 * (1 - t)), width: 1.5),
                    ),
                  ),
                  child!,
                ],
              );
            },
            child: RepaintBoundary(
              child: Container(
                width: size,
                height: size,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: c.brand, shape: BoxShape.circle),
                child: Text('감독 시작', style: T.title.copyWith(color: Colors.black, fontWeight: FontWeight.w800)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 설정 시트: 교실 기기 확인 시간, 새 기기 알림 범위, 의심 시 알람. 맨 아래 '시작'.
class _SetupSheet extends StatefulWidget {
  const _SetupSheet({required this.checkSeconds, required this.range, required this.alarm, required this.onChanged});

  final int checkSeconds;
  final int range;
  final AlarmMode alarm;
  final void Function(int checkSeconds, int range, AlarmMode alarm) onChanged;

  @override
  State<_SetupSheet> createState() => _SetupSheetState();
}

class _SetupSheetState extends State<_SetupSheet> {
  late int _check = widget.checkSeconds;
  late int _range = widget.range;
  late AlarmMode _alarm = widget.alarm;

  void _changed() => widget.onChanged(_check, _range, _alarm);

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    Widget field(String label, Widget control) => Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: T.bodyStrong.copyWith(color: c.ink)),
              const SizedBox(height: 12),
              control,
            ],
          ),
        );

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(color: c.line, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 24),
            field(
              '교실 기기 확인',
              Segmented<int>(
                values: const [20, 30, 60],
                labels: const ['20초', '30초', '60초'],
                selected: _check,
                onChanged: (v) => setState(() {
                  _check = v;
                  _changed();
                }),
              ),
            ),
            field(
              '새 기기 알림 범위',
              Segmented<int>(
                values: const [-70, -80, -90],
                labels: const ['교실 앞', '교실 전체', '넓게'],
                selected: _range,
                onChanged: (v) => setState(() {
                  _range = v;
                  _changed();
                }),
              ),
            ),
            field(
              '의심 시 알람',
              Segmented<AlarmMode>(
                values: const [AlarmMode.long, AlarmMode.short, AlarmMode.off],
                labels: const ['진동 길게', '진동 짧게', '끄기'],
                selected: _alarm,
                onChanged: (v) => setState(() {
                  _alarm = v;
                  _changed();
                }),
              ),
            ),
            const SizedBox(height: 8),
            AppButton(label: '시작', onPressed: () => Navigator.pop(context, true)),
          ],
        ),
      ),
    );
  }
}
