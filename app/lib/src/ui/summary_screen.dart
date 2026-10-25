// SPDX-License-Identifier: AGPL-3.0-or-later
// 감독 기록. 위쪽 카드를 그대로 PNG로 공유하고, 세부 로그는 txt로 내보낸다.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../session/exam_session.dart';
import '../session/report.dart';
import '../version.dart';
import 'common.dart';
import 'theme.dart';

/// 공유용으로 만든 기록 파일(감독기록_*.png, 감독로그_*.txt)을 지운다.
/// 공유 직후 바로 지우면 파일을 나중에 읽는 앱(메신저 등)에서 공유가 깨질 수 있어서,
/// 다음 내보내기 직전·기록 화면을 나갈 때·앱을 켤 때 지운다.
Future<void> cleanExportFiles() async {
  try {
    final dir = await getTemporaryDirectory();
    await for (final f in dir.list()) {
      final name = f.uri.pathSegments.last;
      if (f is File && (name.startsWith('감독기록_') || name.startsWith('감독로그_'))) {
        await f.delete();
      }
    }
  } catch (_) {
    // 지우지 못해도 다음 기회에 다시 지운다.
  }
}

class SummaryScreen extends StatefulWidget {
  const SummaryScreen({super.key, required this.session});

  final ExamSession session;

  @override
  State<SummaryScreen> createState() => _SummaryScreenState();
}

class _SummaryScreenState extends State<SummaryScreen> {
  final _card = GlobalKey();
  bool _busy = false;

  ExamSession get session => widget.session;

  @override
  void dispose() {
    cleanExportFiles();
    super.dispose();
  }

  String get _stamp {
    final t = session.startedAt ?? DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}${two(t.month)}${two(t.day)}_${two(t.hour)}${two(t.minute)}';
  }

  String _duration(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return d.inHours > 0
        ? '${d.inHours}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}'
        : '${d.inMinutes}:${two(d.inSeconds % 60)}';
  }

  Rect? _origin() {
    final box = context.findRenderObject() as RenderBox?;
    return box == null ? null : box.localToGlobal(Offset.zero) & box.size;
  }

  Future<void> _shareImage() async {
    setState(() => _busy = true);
    try {
      final origin = _origin();
      final boundary = _card.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await cleanExportFiles();
      final file = File('${(await getTemporaryDirectory()).path}/감독기록_$_stamp.png');
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path, mimeType: 'image/png')],
        sharePositionOrigin: origin,
      ));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _shareLog() async {
    final origin = _origin();
    await cleanExportFiles();
    final file = File('${(await getTemporaryDirectory()).path}/감독로그_$_stamp.txt');
    await file.writeAsString(buildReport(session, appVersion: appVersion));
    await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path, mimeType: 'text/plain')],
      sharePositionOrigin: origin,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final flagged = session.devices.where((d) => d.alert != AlertLevel.none).toList()
      ..sort((a, b) {
        final level = b.alert.index.compareTo(a.alert.index);
        return level != 0 ? level : a.firstSeen.compareTo(b.firstSeen);
      });
    final reds = flagged.where((d) => d.alert == AlertLevel.signature).length;
    final yellows = flagged.length - reds;
    final start = session.startedAt!, end = session.endedAt!;
    final minutes = end.difference(start).inMinutes;

    final card = RepaintBoundary(
      key: _card,
      child: Container(
        color: c.bg,
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('AI 안경 탐지기 감독 기록', style: T.bodyStrong.copyWith(color: c.ink)),
            const SizedBox(height: 2),
            Text('${formatDateTime(start).substring(0, 16)} – ${formatTime(end).substring(0, 5)} · $minutes분',
                style: T.body.copyWith(color: c.ink2, fontFeatures: tabular)),
            const SizedBox(height: 20),
            StatusBlock(
              checking: false,
              ended: true,
              scrub: null,
              timer: _duration(end.difference(start)),
              reds: reds,
              yellows: yellows,
              nearby: session.devices.length,
            ),
            if (flagged.isNotEmpty) ...[
              const SizedBox(height: 24),
              PresenceRaster(
                session: session,
                devices: flagged,
                start: start,
                span: end.difference(start) + const Duration(seconds: 1),
                now: end,
                maxRows: flagged.length.clamp(1, 6),
              ),
              const SizedBox(height: 16),
              for (final d in flagged)
                DeviceRow(
                  device: d,
                  label: d.exportLabel,
                  trailing: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('${formatTime(d.firstSeen).substring(0, 5)}–${formatTime(d.lastSeen).substring(0, 5)}',
                          style: T.num.copyWith(color: c.ink)),
                      const SizedBox(height: 2),
                      Text('가장 강할 때 ${proximityWord(d.maxRssi)}', style: T.aux.copyWith(color: c.ink2)),
                    ],
                  ),
                ),
            ],
            const SizedBox(height: 16),
            Text(disclaimerLine, style: T.aux.copyWith(color: c.ink2)),
          ],
        ),
      ),
    );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('기록을 지우고 나갈까요?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('취소', style: T.bodyStrong.copyWith(color: c.ink2))),
              TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text('나가기', style: T.bodyStrong.copyWith(color: c.danger))),
            ],
          ),
        );
        if (ok == true && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
      appBar: AppBar(title: const Text('감독 기록')),
      body: SafeArea(
        child: ListView(
          children: [
            card,
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('시간순', style: T.section.copyWith(color: c.ink)),
                  const SizedBox(height: 4),
                  for (final e in session.events)
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.line))),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 76,
                            child: Text(formatTime(e.at), style: T.aux.copyWith(color: c.ink2, fontFeatures: tabular)),
                          ),
                          Expanded(
                            child: Text(e.message,
                                style: T.aux.copyWith(
                                  color: switch (e.kind) {
                                    LogKind.signature => c.danger,
                                    LogKind.newDevice => c.warn,
                                    LogKind.info => c.ink,
                                  },
                                )),
                          ),
                        ],
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
          child: Row(
            children: [
              Expanded(child: AppButton(label: '세부 로그', kind: ButtonKind.secondary, onPressed: _shareLog)),
              const SizedBox(width: 8),
              Expanded(flex: 2, child: AppButton(label: _busy ? '만드는 중' : '기록 이미지 공유', onPressed: _busy ? null : _shareImage)),
            ],
          ),
        ),
      ),
    ),
    );
  }
}
