// SPDX-License-Identifier: AGPL-3.0-or-later
// 개발용 모의 송신기. 에뮬레이터·실물 안경 없는 환경에서 감독 흐름을 실제 시간으로 재현한다.
// `flutter run --dart-define=SIMULATE=true` 일 때만 쓰인다. 배포 빌드에는 켜지지 않는다.
//
// 시나리오: 교실 기기 20대(폰·이어폰) → 40초 뒤 새 기기(스마트 밴드) → 70초 뒤 메타 안경.
// 메타 안경 신호는 감독관이 다가갔다 멀어지는 것처럼 40초 주기로 세졌다 약해진다.

import 'dart:async';
import 'dart:math' as math;

import '../model/advertisement.dart';
import 'ble_scanner.dart';

const simulateScan = bool.fromEnvironment('SIMULATE');

class SimulatedScanner implements ScanSource {
  final _states = StreamController<ScannerState>.broadcast();
  final _rnd = math.Random();
  Timer? _timer;
  DateTime? _startedAt;

  @override
  Stream<ScannerState> get states => _states.stream;

  @override
  void start(void Function(Advertisement) onAdvertisement) {
    _startedAt = DateTime.now();
    _timer = Timer.periodic(const Duration(milliseconds: 500), (_) => _emit(onAdvertisement));
  }

  void _emit(void Function(Advertisement) on) {
    final now = DateTime.now();
    final t = now.difference(_startedAt!).inMilliseconds / 1000;
    Advertisement adv(String id, double rssi, {int? company, String name = ''}) => Advertisement(
          deviceId: id,
          name: name,
          companyIds: company == null ? const [] : [company],
          serviceUuids: const [],
          rssi: (rssi + _rnd.nextInt(9) - 4).round(),
          seenAt: now,
        );

    for (var i = 0; i < 20; i++) {
      // 모든 기기가 매번 잡히지는 않는다 (실제 스캔처럼 듬성듬성).
      if (_rnd.nextDouble() < 0.6) {
        on(adv('sim-room-$i', -56.0 - i * 1.6, company: i % 3 == 0 ? 0x0075 : 0x004C, name: i == 4 ? 'Galaxy Buds3' : ''));
      }
    }
    if (t > 40) on(adv('sim-band', -72, company: 0x0157, name: 'Smart Band 9'));
    if (t > 70) {
      final phase = (t - 70) / 40 * 2 * math.pi;
      on(adv('sim-meta', -74 + 16 * math.sin(phase - math.pi / 2), company: 0x01AB));
    }
  }

  @override
  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    stop();
    _states.close();
  }
}
