// SPDX-License-Identifier: AGPL-3.0-or-later
// BLE 광고 수동 수신. 연결·페어링·패킷 해독은 하지 않는다.
//
// Android는 startScan을 30초에 5번 넘게 부르면 결과가 조용히 끊기므로
// 세션 동안 스캔 하나를 길게 유지하고, 블루투스가 꺼졌다 켜질 때만 다시 시작한다.

import 'dart:async';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';

import '../model/advertisement.dart';

enum ScannerState { ready, poweredOff, unauthorized, locationOff, unsupported, unknown }

/// 감독 화면이 쓰는 스캔 원천. 실제로는 [BleScanner], 테스트에서는 가짜 송신기.
abstract class ScanSource {
  Stream<ScannerState> get states;
  void start(void Function(Advertisement) onAdvertisement);
  void stop();
  void dispose();
}

class BleScanner implements ScanSource {
  BleScanner({FlutterReactiveBle? ble}) : _ble = ble ?? FlutterReactiveBle();

  final FlutterReactiveBle _ble;
  StreamSubscription<DiscoveredDevice>? _scanSub;
  StreamSubscription<BleStatus>? _statusSub;
  final _states = StreamController<ScannerState>.broadcast();
  void Function(Advertisement)? _onAdvertisement;
  ScannerState _state = ScannerState.unknown;
  bool _locationRequired = false;

  @override
  Stream<ScannerState> get states => _states.stream;
  ScannerState get state => _state;

  /// 필요한 권한을 요청한다. 허용되면 true.
  /// Android 12+: 주변 기기 권한(위치 미사용). Android 11 이하: 시스템상 위치 권한이 필수.
  Future<bool> requestPermissions() async {
    if (Platform.isAndroid) {
      final sdk = (await DeviceInfoPlugin().androidInfo).version.sdkInt;
      _locationRequired = sdk < 31;
      final perms = sdk >= 31
          ? [Permission.bluetoothScan, Permission.bluetoothConnect]
          : [Permission.locationWhenInUse];
      final result = await perms.request();
      return result.values.every((s) => s.isGranted);
    }
    // iOS는 스캔을 시작할 때 CoreBluetooth가 직접 권한을 묻는다. 거부되면 상태 스트림이 unauthorized를 알린다.
    return true;
  }

  @override
  void start(void Function(Advertisement) onAdvertisement) {
    _onAdvertisement = onAdvertisement;
    _statusSub ??= _ble.statusStream.listen(_onStatus);
    if (_ble.status == BleStatus.ready) _startScan();
  }

  @override
  void stop() {
    _onAdvertisement = null;
    _scanSub?.cancel();
    _scanSub = null;
    _statusSub?.cancel();
    _statusSub = null;
  }

  void _onStatus(BleStatus status) {
    _state = switch (status) {
      BleStatus.ready => ScannerState.ready,
      BleStatus.poweredOff => ScannerState.poweredOff,
      BleStatus.unauthorized => ScannerState.unauthorized,
      BleStatus.locationServicesDisabled => ScannerState.locationOff,
      BleStatus.unsupported => ScannerState.unsupported,
      BleStatus.unknown => ScannerState.unknown,
    };
    _states.add(_state);
    if (status == BleStatus.ready) {
      _startScan();
    } else {
      _scanSub?.cancel();
      _scanSub = null;
    }
  }

  void _startScan() {
    if (_scanSub != null || _onAdvertisement == null) return;
    _scanSub = _ble
        .scanForDevices(
          withServices: const [],
          scanMode: ScanMode.lowLatency,
          requireLocationServicesEnabled: _locationRequired,
        )
        .listen(_onDevice, onError: (Object e) {
      _scanSub = null;
      _states.add(ScannerState.unknown);
    });
  }

  void _onDevice(DiscoveredDevice d) {
    final companyId = Advertisement.companyIdFromManufacturerData(d.manufacturerData);
    final uuids = <String>{
      ...d.serviceUuids.map((u) => Advertisement.normalizeUuid(u.toString())),
      ...d.serviceData.keys.map((u) => Advertisement.normalizeUuid(u.toString())),
    };
    _onAdvertisement?.call(Advertisement(
      deviceId: d.id,
      name: d.name,
      companyIds: companyId == null ? const [] : [companyId],
      serviceUuids: uuids.toList(),
      rssi: d.rssi,
      seenAt: DateTime.now(),
    ));
  }

  @override
  void dispose() {
    stop();
    _states.close();
  }
}
