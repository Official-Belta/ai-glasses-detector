// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../scan/ble_scanner.dart';
import '../session/exam_session.dart';
import 'common.dart';
import 'countdown_screen.dart';
import 'device_screen.dart';
import 'summary_screen.dart';
import 'theme.dart';

class SessionScreen extends StatefulWidget {
  const SessionScreen({super.key, required this.session, required this.scanner, this.keepAwake = true});

  final ExamSession session;
  final ScanSource scanner;

  /// 감독 중 화면 꺼짐 방지. Android는 화면이 꺼지면 필터 없는 스캔을 멈춘다.
  final bool keepAwake;

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen> {
  late final Timer _clock;
  StreamSubscription<ScannerState>? _stateSub;
  ScannerState _scannerState = ScannerState.unknown;
  bool _showAll = false;
  DateTime? _scrub;

  ExamSession get session => widget.session;

  @override
  void initState() {
    super.initState();
    if (widget.keepAwake) WakelockPlus.enable();
    session.onAlert = (d) {
      // AI 안경 의심은 설정대로, 새 기기는 짧게 한 번(끄기면 없음).
      final mode = session.settings.alarm;
      if (mode == AlarmMode.off) return;
      final times = d.alert == AlertLevel.signature && mode == AlarmMode.long ? 3 : 1;
      for (var i = 0; i < times; i++) {
        Future.delayed(Duration(milliseconds: 300 * i), HapticFeedback.heavyImpact);
      }
    };
    session.addListener(_refresh);
    _stateSub = widget.scanner.states.listen((s) => setState(() => _scannerState = s));
    widget.scanner.start(session.onAdvertisement);
    if (session.phase == SessionPhase.idle) session.start();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      session.tick();
      _refresh();
    });
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _clock.cancel();
    _stateSub?.cancel();
    session.removeListener(_refresh);
    widget.scanner.dispose();
    if (widget.keepAwake) WakelockPlus.disable();
    super.dispose();
  }

  Future<void> _confirmEnd() async {
    final c = context.c;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('감독을 끝낼까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('계속', style: T.bodyStrong.copyWith(color: c.ink2)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('끝내기', style: T.bodyStrong.copyWith(color: c.danger)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    widget.scanner.stop();
    session.end();
    await Navigator.of(context).pushReplacement(fadeRoute(SummaryScreen(session: session)));
  }

  String _elapsed(DateTime now) {
    final d = now.difference(session.startedAt ?? now);
    String two(int n) => n.toString().padLeft(2, '0');
    final h = d.inHours;
    return h > 0 ? '$h:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}' : '${d.inMinutes}:${two(d.inSeconds % 60)}';
  }

  String? _scannerProblem() => switch (_scannerState) {
        ScannerState.poweredOff => '블루투스가 꺼져 있습니다',
        ScannerState.unauthorized => '블루투스 권한이 없습니다',
        ScannerState.locationOff => '위치 서비스(GPS)를 켜 주세요',
        ScannerState.unsupported => '이 폰은 BLE를 지원하지 않습니다',
        _ => null,
      };

  String _left(DateTime now) {
    final left = session.settings.baselineDuration - now.difference(session.startedAt ?? now);
    return '0:${left.inSeconds.clamp(0, 59).toString().padLeft(2, '0')}';
  }

  /// 수신 기록표 폭: 최소 10분, 넘으면 10분 단위로 늘린다.
  Duration _span(DateTime now) {
    final mins = now.difference(session.startedAt ?? now).inMinutes;
    return Duration(minutes: ((mins ~/ 10) + 1) * 10);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final now = DateTime.now();
    final alerts = session.alerts;
    final reds = alerts.where((d) => d.alert == AlertLevel.signature).length;
    final yellows = alerts.length - reds;
    final problem = _scannerProblem();
    final checking = session.phase == SessionPhase.baseline;
    // 새로 잡힌 기기는 아래에 붙인다. 위쪽 행이 흔들리지 않게.
    final nearby = session.devices.where((d) => now.difference(d.lastSeen).inSeconds < 60).toList()
      ..sort((a, b) => a.number.compareTo(b.number));
    final list = _showAll ? nearby : alerts;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmEnd();
      },
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: const Text('AI 안경 탐지기'),
          actions: [
            if (checking)
              TextButton(
                onPressed: session.finishBaseline,
                child: Text('바로 시작', style: T.bodyStrong.copyWith(color: c.ink2)),
              ),
            const SizedBox(width: 8),
          ],
        ),
        body: SafeArea(
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                sliver: SliverList.list(
                  children: [
                    if (problem != null)
                      Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(color: c.panel, borderRadius: BorderRadius.circular(8)),
                        child: Text(problem, style: T.bodyStrong.copyWith(color: c.danger)),
                      ),
                    // 1초마다 바뀌는 시계·기록표가 화면 전체를 다시 그리지 않도록 그리는 범위를 나눈다.
                    RepaintBoundary(
                      child: StatusBlock(
                      checking: checking,
                      scrub: _scrub,
                      timer: checking ? _left(now) : _elapsed(now),
                      reds: reds,
                      yellows: yellows,
                      nearby: nearby.length,
                    ),
                    ),
                    const SizedBox(height: 24),
                    RepaintBoundary(
                      child: PresenceRaster(
                        session: session,
                        devices: alerts,
                        start: session.startedAt!,
                        span: _span(now),
                        now: now,
                        onScrub: (t) => setState(() => _scrub = t),
                      ),
                    ),
                    const SizedBox(height: 32),
                    Segmented<bool>(
                      values: const [false, true],
                      labels: ['경고 ${alerts.length}', '주변 기기 ${nearby.length}'],
                      selected: _showAll,
                      onChanged: (v) => setState(() => _showAll = v),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                // 키로 행을 붙잡아 두면 새 행만 열리며 나타나고, 있던 행은 그대로 있는다.
                sliver: SliverList.list(
                  children: [
                    for (final d in list)
                      AppearIn(
                        key: ValueKey('${_showAll ? 'n' : 'a'}${d.number}'),
                        child: DeviceRow(
                          device: d,
                          onTap: () => Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => DeviceScreen(session: session, device: d),
                          )),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(disclaimerLine, style: T.aux.copyWith(color: c.ink2), textAlign: TextAlign.center),
                const SizedBox(height: 12),
                AppButton(label: '감독 끝내기', kind: ButtonKind.secondary, onPressed: _confirmEnd),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

