// SPDX-License-Identifier: AGPL-3.0-or-later
// 감독 기록 텍스트 보고서. MAC 주소 등 기기 식별자는 넣지 않고 세션 내 번호만 쓴다.

import 'exam_session.dart';
import '../model/signatures.dart';

const disclaimer = '이 기록은 블루투스 신호를 바탕으로 한 참고 자료이며 부정행위의 증거가 아닙니다. '
    '같은 제조사의 다른 기기(예: VR 헤드셋, 이어폰)에서도 같은 신호가 나올 수 있고, '
    '신호 세기로는 좌석 단위 위치를 특정할 수 없습니다. 확인은 감독관이 직접 해야 합니다.';

String _two(int n) => n.toString().padLeft(2, '0');
String formatTime(DateTime t) => '${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}';
String formatDateTime(DateTime t) => '${t.year}-${_two(t.month)}-${_two(t.day)} ${formatTime(t)}';

String alertLabel(AlertLevel a) => switch (a) {
      AlertLevel.signature => 'AI 안경 의심',
      AlertLevel.newDevice => '새 기기',
      AlertLevel.none => '-',
    };

String buildReport(ExamSession s, {String appVersion = ''}) {
  final b = StringBuffer();
  b.writeln('AI 안경 탐지기: 시험 감독 기록');
  if (appVersion.isNotEmpty) b.writeln('앱 버전 $appVersion / 시그니처 v${s.signatures.version} (${s.signatures.updated})');
  b.writeln('=' * 40);
  b.writeln('※ $disclaimer');
  b.writeln();
  if (s.startedAt != null) b.writeln('시작: ${formatDateTime(s.startedAt!)}');
  if (s.monitoringStartedAt != null) b.writeln('교실 기기 확인 끝: ${formatDateTime(s.monitoringStartedAt!)} (기존 기기 ${s.baselineCount}대)');
  if (s.endedAt != null) b.writeln('종료: ${formatDateTime(s.endedAt!)}');
  b.writeln('수신된 기기 총 ${s.devices.length}대 (주소 변경으로 같은 기기가 여러 번 셀 수 있음)');
  b.writeln();

  b.writeln('[시간순 기록]');
  for (final e in s.events) {
    b.writeln('${formatTime(e.at)}  ${e.message}');
  }
  b.writeln();

  final flagged = s.devices.where((d) => d.alert != AlertLevel.none).toList()
    ..sort((a, c) => a.number.compareTo(c.number));
  b.writeln('[경고 기기 상세] ${flagged.length}건');
  if (flagged.isEmpty) b.writeln('없음');
  for (final d in flagged) {
    b.writeln('-' * 40);
    b.writeln('기기 #${d.number}  [${alertLabel(d.alert)}]${d.ignored ? ' (감독관 무시 처리)' : ''}');
    // 광고된 기기 이름은 사람 이름이 들어갈 수 있어 기록에 넣지 않는다.
    b.writeln('  분류: ${d.exportLabel}');
    if (d.companyIds.isNotEmpty) b.writeln('  제조사 ID: ${d.companyIds.map(hex4).join(', ')}');
    for (final m in d.matches) {
      b.writeln('  근거: ${m.reason} (${m.signature.note})');
    }
    b.writeln('  처음 수신 ${formatTime(d.firstSeen)} / 마지막 수신 ${formatTime(d.lastSeen)} / ${d.sightings}회');
    b.writeln('  신호(dBm) 최소 ${d.minRssi} / 평균 ${d.avgRssi} / 최대 ${d.maxRssi}');
    final minutes = d.perMinute.keys.toList()..sort();
    if (minutes.isNotEmpty) {
      b.writeln('  분당 평균 신호:');
      for (final m in minutes) {
        final v = d.perMinute[m]!;
        b.writeln('    ${_two(m.hour)}:${_two(m.minute)}  ${(v[0] / v[1]).round()}dBm');
      }
    }
  }
  return b.toString();
}
