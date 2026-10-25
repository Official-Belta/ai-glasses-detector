// SPDX-License-Identifier: AGPL-3.0-or-later
// 감독 시작 전 3·2·1, 이어서 신호 막대가 차오르며 탐지기가 켜지는 장면. 끝나면 감독 화면으로 넘어간다.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../scan/ble_scanner.dart';
import '../session/exam_session.dart';
import 'session_screen.dart';
import 'theme.dart';

Route<R> fadeRoute<R>(Widget page) => PageRouteBuilder<R>(
      transitionDuration: const Duration(milliseconds: 350),
      reverseTransitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (_, _, _) => page,
      transitionsBuilder: (_, a, _, child) => FadeTransition(
        opacity: CurvedAnimation(parent: a, curve: const Cubic(0.22, 1, 0.36, 1)),
        child: child,
      ),
    );

class CountdownScreen extends StatefulWidget {
  const CountdownScreen({super.key, required this.session, required this.scanner, this.keepAwake = true});

  final ExamSession session;
  final ScanSource scanner;
  final bool keepAwake;

  @override
  State<CountdownScreen> createState() => _CountdownScreenState();
}

class _CountdownScreenState extends State<CountdownScreen> with TickerProviderStateMixin {
  // 0~3초: 3·2·1, 3~4.4초: 신호 막대 4칸이 차례로 켜짐.
  late final AnimationController _t = AnimationController(vsync: this, duration: const Duration(milliseconds: 4400));
  int _lastBeat = -1;
  bool _left = false;

  @override
  void initState() {
    super.initState();
    _t.addListener(_beat);
    _t.addStatusListener((s) {
      if (s == AnimationStatus.completed) _go();
    });
    _t.forward();
  }

  void _beat() {
    final ms = _t.value * 4400;
    final beat = ms < 3000 ? ms ~/ 1000 : 3 + ((ms - 3000) ~/ 250).clamp(0, 4);
    if (beat != _lastBeat) {
      _lastBeat = beat;
      if (beat < 3) {
        HapticFeedback.mediumImpact();
      } else if (beat <= 6) {
        HapticFeedback.selectionClick();
      } else {
        HapticFeedback.heavyImpact();
      }
    }
  }

  void _go() {
    if (_left || !mounted) return;
    _left = true;
    Navigator.of(context).pushReplacement(fadeRoute(
      SessionScreen(session: widget.session, scanner: widget.scanner, keepAwake: widget.keepAwake),
    ));
  }

  void _cancel() {
    if (_left) return;
    _left = true;
    _t.stop();
    widget.scanner.dispose();
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _cancel();
      },
      child: AnimatedBuilder(
        animation: _t,
        builder: (context, _) {
          final ms = _t.value * 4400;
          // 3·2·1 동안은 화면 전체가 볼트색, 끝나면 0.2초 만에 검게 꺼지며 탐지 장면으로.
          final out = Curves.easeInCubic.transform(((ms - 3000) / 200).clamp(0.0, 1.0));
          final bg = Color.lerp(c.brand, c.bg, out)!;
          final onVolt = ms < 3000;
          return Scaffold(
            backgroundColor: bg,
            body: SafeArea(
              child: Stack(
                children: [
                  Center(child: onVolt ? _number(ms) : _scanner(c, ms - 3000)),
                  Positioned(
                    left: 20,
                    right: 20,
                    bottom: 16,
                    child: TextButton(
                      onPressed: _cancel,
                      child: Text('취소', style: T.bodyStrong.copyWith(color: onVolt ? Colors.black54 : c.ink2)),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// 숫자 하나가 1초 동안: 아래에서 크게 밀려 들어오고(0~300ms), 머물다가, 위로 빠지며 사라짐(800~1000ms).
  Widget _number(double ms) {
    final n = 3 - ms ~/ 1000;
    final local = ms % 1000;
    final appear = const Cubic(0.22, 1, 0.36, 1).transform((local / 300).clamp(0.0, 1.0));
    final vanish = Curves.easeInCubic.transform(((local - 800) / 200).clamp(0.0, 1.0));
    return Opacity(
      opacity: (1 - vanish),
      child: Transform.translate(
        offset: Offset(0, 80 * (1 - appear) - 60 * vanish),
        child: Transform.scale(
          scale: 1.25 - 0.25 * appear,
          child: Text('$n', style: T.hero.copyWith(fontSize: 300, color: Colors.black, height: 1)),
        ),
      ),
    );
  }

  /// 신호 막대 4칸이 차례로 켜지고, 마지막에 '탐지 시작'.
  Widget _scanner(AppColors c, double ms) {
    final appear = Curves.easeOutCubic.transform(((ms - 150) / 200).clamp(0.0, 1.0));
    return Opacity(
      opacity: appear,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 120,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < 4; i++) ...[
                  if (i > 0) const SizedBox(width: 12),
                  _bar(c, i, ms),
                ],
              ],
            ),
          ),
          const SizedBox(height: 32),
          Opacity(
            opacity: ((ms - 1000) / 200).clamp(0.0, 1.0),
            child: Text('탐지 시작', style: T.display.copyWith(color: c.ink)),
          ),
        ],
      ),
    );
  }

  Widget _bar(AppColors c, int i, double ms) {
    final on = const Cubic(0.22, 1, 0.36, 1).transform(((ms - 250 - i * 180) / 220).clamp(0.0, 1.0));
    final h = 36.0 + i * 28;
    return Container(
      width: 24,
      height: h,
      alignment: Alignment.bottomCenter,
      decoration: BoxDecoration(color: c.panel2, borderRadius: BorderRadius.circular(3)),
      child: Container(
        width: 24,
        height: h * on,
        decoration: BoxDecoration(color: c.brand, borderRadius: BorderRadius.circular(3)),
      ),
    );
  }
}
