// SPDX-License-Identifier: AGPL-3.0-or-later
// BLE 광고 패킷에서 앱이 쓰는 메타데이터만 추린 값 객체.
// 패킷 내용(페이로드)은 해석하지 않는다. 제조사 ID, 서비스 UUID, 이름, RSSI만 쓴다.

class Advertisement {
  Advertisement({
    required this.deviceId,
    required this.name,
    required this.companyIds,
    required this.serviceUuids,
    required this.rssi,
    required this.seenAt,
  });

  /// 플랫폼이 준 기기 식별자 (Android: MAC, iOS: 임시 UUID). 메모리에서만 쓴다.
  final String deviceId;
  final String name;

  /// Bluetooth SIG 제조사 ID (예: 0x01AB).
  final List<int> companyIds;

  /// 대문자 128비트 UUID 문자열.
  final List<String> serviceUuids;
  final int rssi;
  final DateTime seenAt;

  /// 16/32비트 축약 UUID를 128비트 표준 형태로 맞춘다.
  static String normalizeUuid(String raw) {
    final s = raw.trim().toUpperCase();
    if (s.length == 4) return '0000$s-0000-1000-8000-00805F9B34FB';
    if (s.length == 8) return '$s-0000-1000-8000-00805F9B34FB';
    return s;
  }

  /// 제조사 데이터 앞 2바이트(리틀엔디언)가 회사 ID.
  static int? companyIdFromManufacturerData(List<int> data) {
    if (data.length < 2) return null;
    return data[0] | (data[1] << 8);
  }
}
