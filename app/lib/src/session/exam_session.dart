// SPDX-License-Identifier: AGPL-3.0-or-later
// 시험 감독 세션: 기준선 수집 → 감독(시그니처 탐지 + 새 기기 감지) → 종료.
// 모든 데이터는 메모리에만 있고, 사용자가 직접 내보내지 않으면 세션과 함께 사라진다.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../model/advertisement.dart';
import '../model/signatures.dart';

enum SessionPhase { idle, baseline, monitoring, ended }

enum AlertLevel { none, newDevice, signature }

/// 경고가 생길 때 진동. 시험장이라 소리는 내지 않는다.
enum AlarmMode { long, short, off }

class SessionSettings {
  const SessionSettings({
    this.baselineDuration = const Duration(seconds: 30),
    this.newDeviceRssiThreshold = -80,
    this.newDeviceMinSightings = 3,
    this.alarm = AlarmMode.long,
  });

  final AlarmMode alarm;

  /// 시험 시작 직후 교실 기기를 기준선으로 모으는 시간.
  final Duration baselineDuration;

  /// 이보다 약한 새 기기는 복도·옆 교실로 보고 노란 주의를 띄우지 않는다.
  final int newDeviceRssiThreshold;

  /// 한두 번 스친 신호에 반응하지 않도록 최소 수신 횟수.
  final int newDeviceMinSightings;
}

class RssiSample {
  const RssiSample(this.at, this.rssi);
  final DateTime at;
  final int rssi;
}

class TrackedDevice {
  TrackedDevice({
    required this.number,
    required this.deviceId,
    required this.fingerprint,
    required this.firstSeen,
  }) : lastSeen = firstSeen;

  /// 화면·로그에 쓰는 번호. MAC 대신 이 번호로만 기기를 부른다.
  final int number;
  final String deviceId;
  final String fingerprint;
  final DateTime firstSeen;
  DateTime lastSeen;

  String name = '';
  List<int> companyIds = const [];
  List<String> serviceUuids = const [];
  List<SignatureMatch> matches = const [];

  bool inBaseline = false;
  bool ignored = false;
  AlertLevel alert = AlertLevel.none;
  DateTime? alertedAt;

  int sightings = 0;
  double smoothedRssi = -100;
  int minRssi = 0;
  int maxRssi = -200;
  int _rssiSum = 0;

  /// 핫콜드 화면용 최근 2분 샘플.
  final List<RssiSample> recent = [];

  /// 로그용 분 단위 평균 (분 시작 시각 → 합계/개수).
  final Map<DateTime, List<int>> perMinute = {};

  /// 수신 기록표용 5초 칸별 최대 신호 (epoch초 ~/ 5 → dBm).
  final Map<int, int> slots = {};

  int get avgRssi => sightings == 0 ? 0 : (_rssiSum / sightings).round();

  String get displayLabel {
    if (matches.isNotEmpty) return matches.first.signature.label;
    if (name.isNotEmpty) return name;
    if (companyIds.isNotEmpty) return '제조사 ${companyIds.map(hex4).join(', ')}';
    return '이름 없는 BLE 기기';
  }

  /// 내보내는 기록용 이름. 광고된 기기 이름("홍길동의 AirPods" 등)에는 사람 이름이 들어갈 수 있어
  /// 기록에는 시그니처 분류나 제조사만 쓴다. 화면에서는 [displayLabel]을 그대로 보여 준다.
  String get exportLabel {
    if (matches.isNotEmpty) return matches.first.signature.label;
    if (companyIds.isNotEmpty) return '제조사 ${companyIds.map(hex4).join(', ')}';
    return '이름 없는 BLE 기기';
  }

  void _record(Advertisement adv) {
    lastSeen = adv.seenAt;
    sightings++;
    if (adv.name.isNotEmpty) name = adv.name;
    if (adv.companyIds.isNotEmpty) companyIds = adv.companyIds;
    if (adv.serviceUuids.isNotEmpty) serviceUuids = adv.serviceUuids;

    final r = adv.rssi;
    smoothedRssi = sightings == 1 ? r.toDouble() : smoothedRssi * 0.7 + r * 0.3;
    minRssi = sightings == 1 ? r : math.min(minRssi, r);
    maxRssi = math.max(maxRssi, r);
    _rssiSum += r;

    recent.add(RssiSample(adv.seenAt, r));
    final cutoff = adv.seenAt.subtract(const Duration(minutes: 2));
    while (recent.isNotEmpty && recent.first.at.isBefore(cutoff)) {
      recent.removeAt(0);
    }

    final t = adv.seenAt;
    final minute = DateTime(t.year, t.month, t.day, t.hour, t.minute);
    final slot = t.millisecondsSinceEpoch ~/ 5000;
    final prev = slots[slot];
    if (prev == null || r > prev) slots[slot] = r;

    final bucket = perMinute.putIfAbsent(minute, () => [0, 0]);
    bucket[0] += r;
    bucket[1] += 1;
  }
}

class CountSample {
  const CountSample(this.at, this.count);
  final DateTime at;
  final int count;
}

enum LogKind { info, signature, newDevice }

class LogEvent {
  const LogEvent(this.at, this.kind, this.message);
  final DateTime at;
  final LogKind kind;
  final String message;
}

/// MAC 랜덤화 때문에 같은 기기가 다른 주소로 다시 나타날 수 있다.
/// 주소 대신 광고 내용의 "모양"으로 같은 종류의 기기인지 근사한다.
String fingerprintOf(Advertisement adv) {
  final ids = [...adv.companyIds]..sort();
  final uuids = [...adv.serviceUuids]..sort();
  return 'c:${ids.join(',')}|s:${uuids.join(',')}|n:${adv.name.toLowerCase()}';
}

class ExamSession extends ChangeNotifier {
  ExamSession({required this.signatures, this.settings = const SessionSettings(), DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final SignatureDb signatures;
  final SessionSettings settings;
  final DateTime Function() _clock;

  SessionPhase phase = SessionPhase.idle;
  DateTime? startedAt;
  DateTime? monitoringStartedAt;
  DateTime? endedAt;

  final Map<String, TrackedDevice> _devices = {};
  final Set<String> _baselineFingerprints = {};
  final List<LogEvent> events = [];

  /// 시간에 따른 주변 기기 수 (최근 30초 안에 수신된 기기). 감독 화면 차트용.
  final List<CountSample> deviceCounts = [];
  int _nextNumber = 1;
  Timer? _baselineTimer;
  Timer? _notifyTimer;

  /// 새 경고가 생길 때 호출 (진동 등).
  void Function(TrackedDevice device)? onAlert;

  Iterable<TrackedDevice> get devices => _devices.values;
  int get baselineCount => _devices.values.where((d) => d.inBaseline).length;

  List<TrackedDevice> get alerts {
    final list = _devices.values.where((d) => d.alert != AlertLevel.none && !d.ignored).toList();
    list.sort((a, b) {
      final level = b.alert.index.compareTo(a.alert.index);
      if (level != 0) return level;
      // 신호 세기로 정렬하면 행이 계속 자리를 바꾼다. 경고가 생긴 순서(최근 위)로 고정.
      return b.alertedAt!.compareTo(a.alertedAt!);
    });
    return list;
  }

  /// 시그니처 일치 기기는 기준선 수집 중에도 즉시 빨간 경고.
  void start() {
    assert(phase == SessionPhase.idle);
    final now = _clock();
    startedAt = now;
    phase = SessionPhase.baseline;
    _log(LogKind.info, '감독 시작. 교실 기기 확인 ${settings.baselineDuration.inSeconds}초');
    _baselineTimer = Timer(settings.baselineDuration, finishBaseline);
    notifyListeners();
  }

  void finishBaseline() {
    if (phase != SessionPhase.baseline) return;
    _baselineTimer?.cancel();
    phase = SessionPhase.monitoring;
    monitoringStartedAt = _clock();
    _log(LogKind.info, '교실 기기 확인 끝: $baselineCount대');
    notifyListeners();
  }

  /// 최근 30초 안에 신호가 잡힌 기기 수.
  int get activeCount {
    final now = _clock();
    return _devices.values.where((d) => now.difference(d.lastSeen).inSeconds < 30).length;
  }

  /// 화면 시계에서 1초마다 부른다. 주변 기기 수를 기록한다.
  void tick() {
    if (phase != SessionPhase.baseline && phase != SessionPhase.monitoring) return;
    deviceCounts.add(CountSample(_clock(), activeCount));
  }

  void end() {
    if (phase == SessionPhase.ended || phase == SessionPhase.idle) return;
    _baselineTimer?.cancel();
    phase = SessionPhase.ended;
    endedAt = _clock();
    _log(LogKind.info, '감독 종료. 경고 ${alerts.length}건');
    notifyListeners();
  }

  void ignore(TrackedDevice d) {
    d.ignored = true;
    _log(LogKind.info, '기기 #${d.number} 감독관이 무시 처리');
    notifyListeners();
  }

  void onAdvertisement(Advertisement adv) {
    if (phase != SessionPhase.baseline && phase != SessionPhase.monitoring) return;

    final fp = fingerprintOf(adv);
    final device = _devices.putIfAbsent(
      adv.deviceId,
      () => TrackedDevice(number: _nextNumber++, deviceId: adv.deviceId, fingerprint: fp, firstSeen: adv.seenAt),
    );
    device._record(adv);

    if (phase == SessionPhase.baseline) {
      device.inBaseline = true;
      _baselineFingerprints.add(fp);
    }

    if (device.alert != AlertLevel.signature) {
      final matches = signatures.match(adv);
      if (matches.isNotEmpty) {
        device.matches = matches;
        _raise(device, AlertLevel.signature,
            '기기 #${device.number} AI 안경 시그니처 일치: ${matches.first.signature.label} '
            '(${matches.map((m) => m.reason).toSet().join(', ')}, 신호 ${adv.rssi}dBm)');
      }
    }

    if (phase == SessionPhase.monitoring &&
        device.alert == AlertLevel.none &&
        !device.inBaseline &&
        !_baselineFingerprints.contains(device.fingerprint) &&
        device.sightings >= settings.newDeviceMinSightings &&
        device.smoothedRssi >= settings.newDeviceRssiThreshold) {
      _raise(device, AlertLevel.newDevice,
          '기기 #${device.number} 새로 나타남: ${device.exportLabel} '
          '(신호 ${device.smoothedRssi.round()}dBm)');
    }

    _throttledNotify();
  }

  // 광고는 초당 수백 개가 들어올 수 있어 화면 갱신을 묶는다. 경고·단계 변화는 즉시 알린다.
  void _throttledNotify() {
    if (_notifyTimer != null) return;
    _notifyTimer = Timer(const Duration(milliseconds: 400), () {
      _notifyTimer = null;
      notifyListeners();
    });
  }

  void _raise(TrackedDevice d, AlertLevel level, String message) {
    d.alert = level;
    d.alertedAt = _clock();
    _log(level == AlertLevel.signature ? LogKind.signature : LogKind.newDevice, message);
    onAlert?.call(d);
    notifyListeners();
  }

  void _log(LogKind kind, String message) {
    events.add(LogEvent(_clock(), kind, message));
  }

  @override
  void dispose() {
    _baselineTimer?.cancel();
    _notifyTimer?.cancel();
    super.dispose();
  }
}
