// SPDX-License-Identifier: AGPL-3.0-or-later
// 공용 부품: 버튼, 세그먼트, 신호 막대, 수신 기록표, 거리 눈금, 신호 기록 막대, 이름-값 줄.
// 그림마다 감독관의 질문 하나에 답한다: 얼마나 가까운가(신호 막대·거리 눈금), 언제 나타났나(수신 기록표).

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../session/exam_session.dart';
import '../session/report.dart';
import 'theme.dart';

const disclaimerLine = '경고는 참고 신호이며 부정행위의 증거가 아닙니다.';

Color alertColorOf(BuildContext context, AlertLevel a) => switch (a) {
      AlertLevel.signature => context.c.danger,
      AlertLevel.newDevice => context.c.warn,
      AlertLevel.none => context.c.ink2,
    };

/// 신호 세기 → 단계 0(약함)~3(가장 셈). 위치가 아니라 감독관 폰에 들어오는 신호의 세기를 말한다.
int proximityLevel(num rssi) {
  if (rssi >= -55) return 3;
  if (rssi >= -67) return 2;
  if (rssi >= -80) return 1;
  return 0;
}

/// 목록·게이지에 쓰는 짧은 이름. 가장 센 단계는 단어 없이 '!'.
const proximityNames = ['약함', '보통', '강함', '!'];

/// 문장 속에서 쓰는 이름 ("가장 강할 때 강함!").
const proximityWords = ['약함', '보통', '강함', '강함!'];

String proximityWord(num rssi) => proximityWords[proximityLevel(rssi)];

String proximityText(num rssi) => proximityNames[proximityLevel(rssi)];

String signed(num v) => v > 0 ? '+$v' : v < 0 ? '−${-v}' : '0';

String kindLabel(TrackedDevice d) => switch (d.alert) {
      AlertLevel.signature => 'AI 안경 의심',
      AlertLevel.newDevice => '새 기기',
      AlertLevel.none => d.inBaseline ? '기존 기기' : '새로 잡힘',
    };

enum ButtonKind { primary, secondary }

/// 모션 곡선. 들어오는 움직임은 빠르게 시작해 부드럽게 멈추고(out), 누름은 즉시 반응한다.
const easeOut = Cubic(0.22, 1, 0.36, 1);

/// 누를 수 있는 모든 것의 공통 반응(토스식): 손가락이 닿는 즉시 [pressedScale]로 줄고 살짝 어두워지며,
/// 놓으면 부드럽게 돌아온다. 탭은 손을 뗄 때 실행되고, 끌어서 벗어나면 취소된다.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    required this.onTap,
    this.pressedScale = 0.96,
    this.haptic = true,
  });

  final Widget child;
  final VoidCallback? onTap;
  final double pressedScale;
  final bool haptic;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> with SingleTickerProviderStateMixin {
  // 누를 때 80ms로 빠르게, 놓을 때 220ms로 천천히 돌아온다.
  late final AnimationController _a = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 80),
    reverseDuration: const Duration(milliseconds: 220),
  );
  late final Animation<double> _t = CurvedAnimation(parent: _a, curve: Curves.easeOut, reverseCurve: easeOut);

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  void _down() => _a.forward();
  void _up() => _a.reverse();

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: enabled ? (_) => _down() : null,
      onTapUp: enabled ? (_) => _up() : null,
      onTapCancel: enabled ? _up : null,
      onTap: enabled
          ? () {
              if (widget.haptic) HapticFeedback.selectionClick();
              widget.onTap!();
            }
          : null,
      child: AnimatedBuilder(
        animation: _t,
        child: widget.child,
        builder: (context, child) => Transform.scale(
          scale: 1 - (1 - widget.pressedScale) * _t.value,
          child: Opacity(opacity: 1 - 0.12 * _t.value, child: child),
        ),
      ),
    );
  }
}

/// 사각 버튼. 채운 색(primary)은 화면에 하나만 쓴다. 켜지고 꺼질 때 색이 부드럽게 바뀐다.
class AppButton extends StatelessWidget {
  const AppButton({super.key, required this.label, required this.onPressed, this.kind = ButtonKind.primary});

  final String label;
  final VoidCallback? onPressed;
  final ButtonKind kind;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final enabled = onPressed != null;
    final primary = kind == ButtonKind.primary;
    final bg = primary ? (enabled ? c.brand : c.panel2) : c.panel2;
    final fg = primary ? (enabled ? Colors.black : c.ink3) : (enabled ? c.ink : c.ink3);
    return Semantics(
      button: true,
      enabled: enabled,
      child: Pressable(
        onTap: onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: easeOut,
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 200),
            style: T.bodyStrong.copyWith(color: fg),
            child: Text(label),
          ),
        ),
      ),
    );
  }
}

/// 세그먼트: 바깥 panel2, 고른 칸 표시(bg)가 옆으로 미끄러진다. 칸 폭이 같아 자리가 흔들리지 않는다.
class Segmented<V> extends StatelessWidget {
  const Segmented({super.key, required this.values, required this.labels, required this.selected, required this.onChanged});

  final List<V> values;
  final List<String> labels;
  final V selected;
  final ValueChanged<V> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final n = values.length;
    final index = values.indexOf(selected).clamp(0, n - 1);
    return Container(
      height: 44,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: c.panel2, borderRadius: BorderRadius.circular(8)),
      child: Stack(
        children: [
          AnimatedAlign(
            duration: const Duration(milliseconds: 250),
            curve: easeOut,
            alignment: Alignment(n == 1 ? 0 : -1 + 2 * index / (n - 1), 0),
            child: FractionallySizedBox(
              widthFactor: 1 / n,
              heightFactor: 1,
              child: DecoratedBox(decoration: BoxDecoration(color: c.bg, borderRadius: BorderRadius.circular(6))),
            ),
          ),
          Row(
            children: [
              for (var i = 0; i < n; i++)
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      if (values[i] != selected) {
                        HapticFeedback.selectionClick();
                        onChanged(values[i]);
                      }
                    },
                    child: Center(
                      child: AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 200),
                        style: T.aux.copyWith(
                          color: i == index ? c.ink : c.ink2,
                          fontWeight: i == index ? FontWeight.w600 : FontWeight.w400,
                        ),
                        child: Text(labels[i]),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 폰 안테나처럼 4칸. 거리 구간과 같은 기준.
class SignalBars extends StatelessWidget {
  const SignalBars({super.key, required this.rssi, required this.color, this.stale = false});

  final num rssi;
  final Color color;
  final bool stale;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final level = stale ? -1 : proximityLevel(rssi);
    return SizedBox(
      height: 18,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < 4; i++) ...[
            if (i > 0) const SizedBox(width: 2),
            Container(
              width: 4,
              height: 6.0 + i * 4,
              decoration: BoxDecoration(
                color: i <= level ? color : c.line,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 수신 기록표: 경고 기기마다 한 줄, 신호가 잡힌 칸을 칠한다(진할수록 가까움).
/// 감독 시작에서 [span] 뒤까지를 칸으로 나눠 왼쪽부터 채운다.
class PresenceRaster extends StatefulWidget {
  const PresenceRaster({
    super.key,
    required this.session,
    required this.devices,
    required this.start,
    required this.span,
    required this.now,
    this.onScrub,
    this.maxRows = 3,
  });

  final ExamSession session;
  final List<TrackedDevice> devices;

  /// 높이를 이 줄 수만큼 미리 잡아 둔다. 경고가 생겨도 아래 내용이 밀리지 않는다.
  final int maxRows;
  final DateTime start;
  final Duration span;
  final DateTime now;
  final ValueChanged<DateTime?>? onScrub;

  @override
  State<PresenceRaster> createState() => _PresenceRasterState();
}

class _PresenceRasterState extends State<PresenceRaster> {
  static const labelW = 48.0;
  double? _x;

  void _scrub(double x, double width) {
    final plotW = width - labelW;
    final f = ((x - labelW) / plotW).clamp(0.0, 1.0);
    final t = widget.start.add(widget.span * f);
    if (t.isAfter(widget.now)) return;
    setState(() => _x = x.clamp(labelW, width));
    widget.onScrub?.call(t);
  }

  void _end() {
    setState(() => _x = null);
    widget.onScrub?.call(null);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final rows = widget.devices.take(widget.maxRows).toList();
    final height = widget.maxRows * 22 + 8 + 20.0;
    return LayoutBuilder(
      builder: (context, box) => GestureDetector(
        onHorizontalDragStart: (d) => _scrub(d.localPosition.dx, box.maxWidth),
        onHorizontalDragUpdate: (d) => _scrub(d.localPosition.dx, box.maxWidth),
        onHorizontalDragEnd: (_) => _end(),
        onHorizontalDragCancel: _end,
        child: SizedBox(
          width: double.infinity,
          height: height,
          child: CustomPaint(
            painter: _RasterPainter(
              session: widget.session,
              rows: rows,
              rowColors: [for (final d in rows) alertColorOf(context, d.alert)],
              start: widget.start,
              span: widget.span,
              now: widget.now,
              c: c,
              scrubX: _x,
              textStyle: DefaultTextStyle.of(context).style,
            ),
          ),
        ),
      ),
    );
  }
}

class _RasterPainter extends CustomPainter {
  _RasterPainter({
    required this.session,
    required this.rows,
    required this.rowColors,
    required this.start,
    required this.span,
    required this.now,
    required this.c,
    required this.textStyle,
    this.scrubX,
  });

  final ExamSession session;
  final List<TrackedDevice> rows;
  final List<Color> rowColors;
  final DateTime start, now;
  final Duration span;
  final AppColors c;
  final TextStyle textStyle;
  final double? scrubX;

  static const cols = 30;
  static const labelW = _PresenceRasterState.labelW;

  void _text(Canvas canvas, String s, Offset at, Color color, {TextAlign align = TextAlign.left, double? width}) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: textStyle.merge(T.aux).copyWith(color: color, fontFeatures: tabular)),
      textDirection: TextDirection.ltr,
      textAlign: align,
    )..layout(minWidth: width ?? 0, maxWidth: width ?? double.infinity);
    tp.paint(canvas, at);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final plotW = size.width - labelW;
    final colW = plotW / cols;
    final slotMs = span.inMilliseconds / cols;
    final startMs = start.millisecondsSinceEpoch;
    final nowCol = ((now.millisecondsSinceEpoch - startMs) / slotMs).floor().clamp(0, cols - 1);
    double colX(int i) => labelW + i * colW;

    // 경고가 없으면 지금까지 흐른 칸만 보이는 빈 줄 하나.
    if (rows.isEmpty) {
      for (var i = 0; i <= nowCol; i++) {
        canvas.drawRect(Rect.fromLTWH(colX(i) + 1, 2, colW - 2, 16), Paint()..color = c.panel2);
      }
    }

    // 경고 기기 줄
    var y = 0.0;
    for (var r = 0; r < rows.length; r++) {
      final d = rows[r];
      _text(canvas, '#${d.number}', Offset(0, y), rowColors[r]);
      final best = List<int?>.filled(cols, null);
      d.slots.forEach((slot, rssi) {
        final i = ((slot * 5000 - startMs) / slotMs).floor();
        if (i >= 0 && i < cols && (best[i] == null || rssi > best[i]!)) best[i] = rssi;
      });
      for (var i = 0; i < cols; i++) {
        final rect = Rect.fromLTWH(colX(i) + 1, y + 2, colW - 2, 16);
        final v = best[i];
        if (v == null) {
          if (i <= nowCol) canvas.drawRect(rect, Paint()..color = c.panel2);
          continue;
        }
        final strength = ((v + 100) / 60).clamp(0.0, 1.0);
        canvas.drawRect(rect, Paint()..color = rowColors[r].withValues(alpha: 0.25 + 0.75 * strength));
      }
      y += 22;
    }

    final bottom = size.height - 28;

    // 시간 눈금
    _text(canvas, formatTime(start).substring(0, 5), Offset(labelW, bottom + 6), c.ink2);
    _text(canvas, formatTime(start.add(span)).substring(0, 5), Offset(size.width - 80, bottom + 6), c.ink2,
        align: TextAlign.right, width: 80);

    // 훑는 위치
    if (scrubX != null) {
      canvas.drawLine(Offset(scrubX!, 0), Offset(scrubX!, bottom), Paint()..color = c.ink..strokeWidth = 1.5);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

/// 신호 세기 눈금: 약함·보통·강함·! 네 구간 위에 지금 값과 최근 10초 자취.
class ProximityScale extends StatelessWidget {
  const ProximityScale({super.key, required this.device, required this.color, required this.stale});

  final TrackedDevice device;
  final Color color;
  final bool stale;

  /// 구간마다 같은 폭으로 놓고, 구간 안에서는 선형.
  static double position(num rssi) {
    const edges = [-100.0, -80.0, -67.0, -55.0, -40.0];
    final v = rssi.toDouble().clamp(-100.0, -40.0);
    for (var i = 0; i < 4; i++) {
      if (v < edges[i + 1] || i == 3) {
        return (i + (v - edges[i]) / (edges[i + 1] - edges[i])) / 4;
      }
    }
    return 1;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final now = DateTime.now();
    final trail = device.recent.where((s) => now.difference(s.at).inSeconds < 10).toList();
    final level = stale ? -1 : proximityLevel(device.smoothedRssi);
    return Column(
      children: [
        LayoutBuilder(
          builder: (context, box) {
            final w = box.maxWidth;
            final x = ProximityScale.position(device.smoothedRssi) * w;
            return SizedBox(
              height: 40,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    top: 8,
                    bottom: 8,
                    child: Row(
                      children: [
                        for (var i = 0; i < 4; i++) ...[
                          if (i > 0) const SizedBox(width: 3),
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                color: i <= level ? color.withValues(alpha: 0.18 + 0.12 * i) : c.panel2,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  for (final s in trail)
                    Positioned(
                      left: ProximityScale.position(s.rssi) * w - 1,
                      top: 12,
                      bottom: 12,
                      child: Container(width: 2, color: c.ink2.withValues(alpha: 0.35)),
                    ),
                  if (!stale)
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 150),
                      curve: const Cubic(0.22, 1, 0.36, 1),
                      left: x - 2,
                      top: 0,
                      bottom: 0,
                      child: Container(
                        width: 4,
                        decoration: BoxDecoration(color: c.ink, borderRadius: BorderRadius.circular(2)),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (var i = 0; i < 4; i++)
              Expanded(
                child: Text(
                  proximityNames[i],
                  textAlign: TextAlign.center,
                  style: T.aux.copyWith(
                    color: i == level ? c.ink : c.ink2,
                    fontWeight: i == level ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// 최근 2분 신호 기록: 2초 칸마다 막대(높을수록 가까움). 가장 최근 칸만 색.
class SignalHistory extends StatelessWidget {
  const SignalHistory({super.key, required this.samples, required this.color});

  final List<RssiSample> samples;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(
      children: [
        SizedBox(
          height: 72,
          width: double.infinity,
          child: CustomPaint(painter: _HistoryPainter(List.of(samples), color, c)),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('2분 전', style: T.aux.copyWith(color: c.ink2)),
            Text('지금', style: T.aux.copyWith(color: c.ink2)),
          ],
        ),
      ],
    );
  }
}

class _HistoryPainter extends CustomPainter {
  _HistoryPainter(this.samples, this.color, this.c);

  final List<RssiSample> samples;
  final Color color;
  final AppColors c;

  @override
  void paint(Canvas canvas, Size size) {
    const cols = 60;
    final now = DateTime.now();
    final best = List<int?>.filled(cols, null);
    for (final s in samples) {
      final age = now.difference(s.at).inMilliseconds;
      final i = cols - 1 - age ~/ 2000;
      if (i >= 0 && i < cols && (best[i] == null || s.rssi > best[i]!)) best[i] = s.rssi;
    }
    final w = size.width / cols;
    var last = -1;
    for (var i = cols - 1; i >= 0; i--) {
      if (best[i] != null) {
        last = i;
        break;
      }
    }
    for (var i = 0; i < cols; i++) {
      final v = best[i];
      if (v == null) {
        canvas.drawRect(Rect.fromLTWH(i * w + 1, size.height - 2, w - 2, 2), Paint()..color = c.line);
        continue;
      }
      final h = math.max(3.0, size.height * ProximityScale.position(v));
      canvas.drawRect(Rect.fromLTWH(i * w + 1, size.height - h, w - 2, h), Paint()..color = i == last ? color : c.ink3);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

/// 이름 왼쪽 · 값 오른쪽 한 줄. 아래 1px 선.
class KVRow extends StatelessWidget {
  const KVRow(this.label, this.value, {super.key, this.valueColor});

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.line))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: T.body.copyWith(color: c.ink2)),
          const SizedBox(width: 16),
          Expanded(
            child: Text(value,
                textAlign: TextAlign.right, style: T.body.copyWith(color: valueColor ?? c.ink, fontFeatures: tabular)),
          ),
        ],
      ),
    );
  }
}

/// 경고·기기 목록 한 줄: 이름과 종류 / 신호 막대 / dBm.
class DeviceRow extends StatelessWidget {
  const DeviceRow({super.key, required this.device, this.onTap, this.trailing, this.label});

  final TrackedDevice device;

  /// 이름 칸을 바꿀 때 (공유되는 기록 카드: 광고 이름 대신 [TrackedDevice.exportLabel]).
  final String? label;
  final VoidCallback? onTap;

  /// 오른쪽 칸을 바꿀 때 (기록 화면: 시각).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final d = device;
    final color = alertColorOf(context, d.alert);
    final stale = DateTime.now().difference(d.lastSeen).inSeconds > 20;
    final rssi = d.smoothedRssi.round();
    final kind = kindLabel(d);
    final row = Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.line))),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label ?? d.displayLabel, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.bodyStrong.copyWith(color: c.ink)),
                const SizedBox(height: 2),
                Text.rich(TextSpan(children: [
                  TextSpan(text: '#${d.number}  ', style: T.aux.copyWith(color: c.ink2, fontFeatures: tabular)),
                  TextSpan(
                    text: d.ignored ? '$kind · 무시함' : kind,
                    style: T.aux.copyWith(color: d.alert == AlertLevel.none || d.ignored ? c.ink2 : color),
                  ),
                ])),
              ],
            ),
          ),
          const SizedBox(width: 16),
          trailing ??
              Row(
                children: [
                  SignalBars(rssi: rssi, color: d.alert == AlertLevel.none ? c.ink : color, stale: stale),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 84,
                    child: Text(stale ? '신호 끊김' : proximityText(rssi),
                        textAlign: TextAlign.right, style: T.bodyStrong.copyWith(color: stale ? c.ink2 : c.ink)),
                  ),
                ],
              ),
        ],
      ),
    );
    return onTap == null ? row : Pressable(onTap: onTap, pressedScale: 0.98, child: row);
  }
}

/// 처음 그려질 때 높이가 열리며 나타난다. 목록에 새 행이 끼어들 때 화면이 툭 밀리지 않게.
class AppearIn extends StatefulWidget {
  const AppearIn({super.key, required this.child});

  final Widget child;

  @override
  State<AppearIn> createState() => _AppearInState();
}

class _AppearInState extends State<AppearIn> with SingleTickerProviderStateMixin {
  late final AnimationController _a = AnimationController(vsync: this, duration: const Duration(milliseconds: 350))
    ..forward();
  late final Animation<double> _t = CurvedAnimation(parent: _a, curve: const Cubic(0.22, 1, 0.36, 1));

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizeTransition(
        sizeFactor: _t,
        alignment: Alignment.topCenter,
        child: FadeTransition(opacity: _t, child: widget.child),
      );
}

/// 위치 찾기 게이지: 270° 원호가 신호 세기만큼 차고(바늘 대신 호), 가운데에 % 와 거리 말.
/// 값이 바뀌면 호가 부드럽게 따라간다.
class ProximityGauge extends StatelessWidget {
  const ProximityGauge({super.key, required this.rssi, required this.color, required this.stale});

  final num rssi;
  final Color color;
  final bool stale;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final target = stale ? 0.0 : ProximityScale.position(rssi);
    return TweenAnimationBuilder<double>(
      tween: Tween(end: target),
      duration: const Duration(milliseconds: 400),
      curve: const Cubic(0.22, 1, 0.36, 1),
      builder: (context, v, _) => SizedBox(
        width: 260,
        height: 260,
        child: CustomPaint(
          painter: _GaugePainter(v, color, c.panel2),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(stale ? '—' : '${(v * 100).round()}', style: T.hero.copyWith(color: stale ? c.ink3 : c.ink)),
                    if (!stale) Text('%', style: T.stat.copyWith(color: c.ink2)),
                  ],
                ),
                const SizedBox(height: 4),
                Text(stale ? '신호 끊김' : proximityText(rssi),
                    style: T.title.copyWith(color: stale ? c.ink3 : color, fontWeight: FontWeight.w800)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  _GaugePainter(this.value, this.color, this.track);

  final double value;
  final Color color, track;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 14.0;
    final rect = Rect.fromLTWH(stroke / 2, stroke / 2, size.width - stroke, size.height - stroke);
    const start = math.pi * 0.75, sweep = math.pi * 1.5;
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, start, sweep, false, p..color = track);
    // 구간 경계(약함·보통·강함·!) 눈금
    for (var i = 1; i < 4; i++) {
      final a = start + sweep * i / 4;
      final r1 = rect.width / 2 - stroke - 4, r2 = r1 - 8;
      final o = rect.center;
      canvas.drawLine(o + Offset(math.cos(a) * r1, math.sin(a) * r1), o + Offset(math.cos(a) * r2, math.sin(a) * r2),
          Paint()
            ..color = track
            ..strokeWidth = 2);
    }
    if (value > 0) canvas.drawArc(rect, start, sweep * value, false, p..color = color);
  }

  @override
  bool shouldRepaint(_GaugePainter old) => old.value != value || old.color != color;
}

/// 상단 상태 블록: 감독 시간을 크게, 아래에 숫자 셋. 상태에 따라 블록 전체 색이 바뀐다
/// (정상 어두운 면, 새 기기 노랑, AI 안경 의심 빨강). 멀리서 흘끗 봐도 읽히게.
class StatusBlock extends StatelessWidget {
  const StatusBlock({super.key, 
    required this.checking,
    required this.scrub,
    required this.timer,
    required this.reds,
    required this.yellows,
    required this.nearby,
    this.ended = false,
  });

  /// 기록 화면: 상태 문구를 '감독 끝'으로, 셋째 칸을 '수신 기기'로.
  final bool ended;
  final bool checking;
  final DateTime? scrub;
  final String timer;
  final int reds, yellows, nearby;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final Color bg, fg, fg2;
    final String state;
    if (reds > 0) {
      bg = c.danger;
      fg = Colors.white;
      fg2 = Colors.white70;
      state = 'AI 안경 의심';
    } else if (yellows > 0) {
      bg = c.warn;
      fg = Colors.black;
      fg2 = Colors.black54;
      state = '새 기기 발견';
    } else {
      bg = c.panel;
      fg = c.ink;
      fg2 = c.ink2;
      state = ended ? '이상 없음 · 감독 끝' : (checking ? '교실 기기 확인 중' : '이상 없음');
    }

    Widget stat(int n, String label) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                transitionBuilder: (child, a) => FadeTransition(
                  opacity: a,
                  child: SlideTransition(
                    position: Tween(begin: const Offset(0, 0.3), end: Offset.zero).animate(a),
                    child: child,
                  ),
                ),
                child: Text('$n', key: ValueKey(n), style: T.stat.copyWith(color: fg)),
              ),
              const SizedBox(height: 2),
              Text(label, style: T.aux.copyWith(color: fg2)),
            ],
          ),
        );

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: const Cubic(0.22, 1, 0.36, 1),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(scrub != null ? formatTime(scrub!) : state,
                    style: T.bodyStrong.copyWith(color: fg, fontWeight: FontWeight.w800)),
              ),
              Text(checking ? '확인 남은 시간' : '감독 시간', style: T.aux.copyWith(color: fg2)),
            ],
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: Text(timer, style: T.hero.copyWith(color: fg)),
          ),
          const SizedBox(height: 12),
          Container(height: 1, color: fg.withValues(alpha: 0.15)),
          const SizedBox(height: 12),
          Row(
            children: [
              stat(reds, 'AI 안경 의심'),
              stat(yellows, '새 기기'),
              stat(nearby, ended ? '수신 기기' : '주변 기기'),
            ],
          ),
        ],
      ),
    );
  }
}
