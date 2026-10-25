// SPDX-License-Identifier: AGPL-3.0-or-later
// 위치 찾기: 감독관이 교실을 돌며 신호가 세지는 쪽을 찾는다.

import 'dart:async';

import 'package:flutter/material.dart';

import '../model/signatures.dart';
import '../session/exam_session.dart';
import '../session/report.dart';
import 'common.dart';
import 'theme.dart';

class DeviceScreen extends StatefulWidget {
  const DeviceScreen({super.key, required this.session, required this.device});

  final ExamSession session;
  final TrackedDevice device;

  @override
  State<DeviceScreen> createState() => _DeviceScreenState();
}

class _DeviceScreenState extends State<DeviceScreen> {
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  /// 최근 5초 평균 − 그 전 5초 평균 (dB). 양수면 신호가 세지는 중.
  int? _change() {
    final now = DateTime.now();
    double? avg(int fromSec, int toSec) {
      final xs = widget.device.recent.where((s) {
        final age = now.difference(s.at).inMilliseconds / 1000;
        return age >= fromSec && age < toSec;
      }).map((s) => s.rssi);
      if (xs.isEmpty) return null;
      return xs.reduce((a, b) => a + b) / xs.length;
    }

    final newer = avg(0, 5), older = avg(5, 10);
    if (newer == null || older == null) return null;
    return (newer - older).round();
  }

  Future<void> _ignore() async {
    final c = context.c;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('#${widget.device.number} 경고를 끌까요?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('취소', style: T.bodyStrong.copyWith(color: c.ink2))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text('끄기', style: T.bodyStrong.copyWith(color: c.ink))),
        ],
      ),
    );
    if (ok == true && mounted) {
      widget.session.ignore(widget.device);
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final d = widget.device;
    final color = alertColorOf(context, d.alert);
    final stale = DateTime.now().difference(d.lastSeen).inSeconds > 10;
    final rssi = d.smoothedRssi.round();
    final change = stale ? null : _change();
    final markColor = d.alert == AlertLevel.none ? c.ink : color;

    final String move;
    final Color moveColor;
    if (stale) {
      move = '${formatTime(d.lastSeen)} 이후 안 잡힘';
      moveColor = c.ink2;
    } else if (change == null || change.abs() <= 3) {
      move = '신호 그대로';
      moveColor = c.ink2;
    } else if (change > 0) {
      move = '신호 세지는 중';
      moveColor = c.brand;
    } else {
      move = '신호 약해지는 중';
      moveColor = c.ink2;
    }

    return Scaffold(
      appBar: AppBar(title: Text('#${d.number}  ${kindLabel(d)}', style: T.bodyStrong.copyWith(color: markColor))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          children: [
            Text(d.displayLabel, style: T.body.copyWith(color: c.ink)),
            const SizedBox(height: 24),
            Center(child: ProximityGauge(rssi: d.smoothedRssi, color: markColor, stale: stale)),
            const SizedBox(height: 16),
            Center(child: Text(move, style: T.bodyStrong.copyWith(color: moveColor))),
            const SizedBox(height: 40),
            SignalHistory(samples: d.recent, color: markColor),
            const SizedBox(height: 40),
            KVRow('처음 잡힘', formatTime(d.firstSeen)),
            KVRow('마지막', formatTime(d.lastSeen)),
            KVRow('가장 강할 때', proximityWord(d.maxRssi)),
            KVRow('신호 세기', stale ? '—' : '${signed(rssi)} dBm'),
            if (d.name.isNotEmpty) KVRow('기기 이름', d.name),
            if (d.companyIds.isNotEmpty) KVRow('제조사 ID', d.companyIds.map(hex4).join(', ')),
            for (final m in d.matches) KVRow('일치', m.reason),
            if (d.alert != AlertLevel.none && !d.ignored) ...[
              const SizedBox(height: 24),
              AppButton(label: '확인함, 경고 끄기', kind: ButtonKind.secondary, onPressed: _ignore),
            ],
          ],
        ),
      ),
    );
  }
}
