// SPDX-License-Identifier: AGPL-3.0-or-later
// 탐지 로직 단위 테스트 (실물 안경·블루투스 없이 실행).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:glasses_detector/src/model/advertisement.dart';
import 'package:glasses_detector/src/model/signatures.dart';
import 'package:glasses_detector/src/session/exam_session.dart';
import 'package:glasses_detector/src/session/report.dart';

void main() {
  final db = SignatureDb.fromJsonString(File('assets/signatures.json').readAsStringSync());
  var now = DateTime(2026, 11, 2, 9, 0, 0);

  Advertisement adv(String id,
          {int? company, List<String> uuids = const [], String name = '', int rssi = -60}) =>
      Advertisement(
        deviceId: id,
        name: name,
        companyIds: company == null ? const [] : [company],
        serviceUuids: uuids.map(Advertisement.normalizeUuid).toList(),
        rssi: rssi,
        seenAt: now,
      );

  group('시그니처', () {
    test('Meta·Luxottica·Snap·Jieli 제조사 ID 일치', () {
      for (final id in [0x01AB, 0x058E, 0x0D53, 0x03C2, 0x05D6]) {
        expect(db.match(adv('a', company: id)), isNotEmpty, reason: hex4(id));
      }
    });

    test('Apple(0x004C)·삼성(0x0075)은 일치하지 않음', () {
      expect(db.match(adv('a', company: 0x004C)), isEmpty);
      expect(db.match(adv('a', company: 0x0075)), isEmpty);
    });

    test('HeyCyan 서비스 UUID (소문자 입력)', () {
      expect(db.match(adv('a', uuids: ['7905fff0-b5ce-4e99-a40f-4b1e122d00d0'])), isNotEmpty);
    });

    test('기기 이름 매칭은 대소문자 무시', () {
      expect(db.match(adv('a', name: 'Ray-Ban Meta 1234')), isNotEmpty);
      expect(db.match(adv('a', name: 'HeyCyan-AB12')), isNotEmpty);
      expect(db.match(adv('a', name: 'Galaxy Buds')), isEmpty);
    });

    test('제조사 데이터 앞 2바이트는 리틀엔디언 회사 ID', () {
      expect(Advertisement.companyIdFromManufacturerData([0xAB, 0x01, 0x99]), 0x01AB);
      expect(Advertisement.companyIdFromManufacturerData([0xAB]), isNull);
      expect(Advertisement.normalizeUuid('fff0'), '0000FFF0-0000-1000-8000-00805F9B34FB');
    });
  });

  group('감독 세션', () {
    late ExamSession s;

    setUp(() {
      now = DateTime(2026, 11, 2, 9, 0, 0);
      s = ExamSession(signatures: db, clock: () => now);
      s.start();
    });

    tearDown(() => s.dispose());

    void see(Advertisement a, {int times = 3}) {
      for (var i = 0; i < times; i++) {
        s.onAdvertisement(a);
      }
    }

    test('기준선 중이어도 시그니처는 즉시 빨간 경고', () {
      see(adv('glasses', company: 0x01AB), times: 1);
      expect(s.alerts.single.alert, AlertLevel.signature);
    });

    test('기준선에 있던 기기는 신규로 잡지 않음', () {
      see(adv('phone', company: 0x004C));
      s.finishBaseline();
      see(adv('phone', company: 0x004C));
      expect(s.alerts, isEmpty);
    });

    test('기준선 이후 새로 나타난 기기는 노란 주의', () {
      see(adv('phone', company: 0x004C));
      s.finishBaseline();
      see(adv('new', company: 0x0157, name: 'Unknown Glasses'));
      expect(s.alerts.single.alert, AlertLevel.newDevice);
    });

    test('MAC이 바뀌어도 같은 모양이면 신규로 잡지 않음', () {
      see(adv('aa:aa', company: 0x004C));
      s.finishBaseline();
      see(adv('bb:bb', company: 0x004C));
      expect(s.alerts, isEmpty);
    });

    test('약한 신호·한두 번 스친 신호는 무시', () {
      s.finishBaseline();
      see(adv('far', company: 0x0157, rssi: -95));
      see(adv('blip', company: 0x0158), times: 2);
      expect(s.alerts, isEmpty);
    });

    test('검사 후 안경 바꿔 끼기: 감독 중 시그니처 등장 시 빨간 경고가 노란색보다 위', () {
      s.finishBaseline();
      see(adv('new', company: 0x0157, rssi: -50));
      see(adv('swap', company: 0x0D53, rssi: -70));
      expect(s.alerts.map((d) => d.alert), [AlertLevel.signature, AlertLevel.newDevice]);
    });

    test('무시 처리하면 경고 목록에서 빠지고 기록에는 남음', () {
      see(adv('g', company: 0x01AB));
      s.ignore(s.alerts.single);
      expect(s.alerts, isEmpty);
      s.end();
      final report = buildReport(s);
      expect(report, contains('무시 처리'));
      expect(report, contains('부정행위의 증거가 아닙니다'));
    });

    test('보고서에 기기 주소(MAC)가 들어가지 않음', () {
      see(adv('AA:BB:CC:DD:EE:FF', company: 0x01AB));
      s.end();
      expect(buildReport(s), isNot(contains('AA:BB:CC')));
    });

    test('보고서·시간순 기록에 광고된 기기 이름이 들어가지 않음', () {
      see(adv('a', name: "Hong Gildong's Ray-Ban Meta"));
      s.finishBaseline();
      see(adv('b', company: 0x0157, name: "Kim's Galaxy Buds"));
      s.end();
      final report = buildReport(s);
      expect(report, isNot(contains('Hong')));
      expect(report, isNot(contains('Kim')));
      expect(report, contains('기기 이름에 "ray-ban" 포함'));
    });

    test('종료 후에는 수신을 무시', () {
      s.end();
      see(adv('g', company: 0x01AB));
      expect(s.devices, isEmpty);
    });
  });
}
