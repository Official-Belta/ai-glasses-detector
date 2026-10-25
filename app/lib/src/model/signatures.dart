// SPDX-License-Identifier: AGPL-3.0-or-later
// 탐지 시그니처. 데이터는 assets/signatures.json 에 있고 코드에 하드코딩하지 않는다.

import 'dart:convert';

import 'advertisement.dart';

class Signature {
  Signature({
    required this.id,
    required this.label,
    required this.note,
    required this.companyIds,
    required this.serviceUuids,
    required this.nameContains,
  });

  factory Signature.fromJson(Map<String, dynamic> json) {
    final match = (json['match'] as Map<String, dynamic>?) ?? const {};
    List<String> strings(String key) =>
        ((match[key] as List?) ?? const []).map((e) => e.toString()).toList();
    return Signature(
      id: json['id'] as String,
      label: json['label'] as String,
      note: (json['note'] as String?) ?? '',
      companyIds: strings('companyIds').map(_parseHex).toSet(),
      serviceUuids: strings('serviceUuids').map(Advertisement.normalizeUuid).toSet(),
      nameContains: strings('nameContains').map((s) => s.toLowerCase()).toList(),
    );
  }

  final String id;
  final String label;
  final String note;
  final Set<int> companyIds;
  final Set<String> serviceUuids;
  final List<String> nameContains;

  static int _parseHex(String s) {
    final t = s.trim().toLowerCase();
    return t.startsWith('0x') ? int.parse(t.substring(2), radix: 16) : int.parse(t);
  }
}

class SignatureMatch {
  const SignatureMatch(this.signature, this.reason);
  final Signature signature;

  /// 사람이 읽는 근거 (예: "제조사 ID 0x01AB").
  final String reason;
}

class SignatureDb {
  SignatureDb(this.signatures, {this.version = 0, this.updated = ''});

  factory SignatureDb.fromJsonString(String source) {
    final json = jsonDecode(source) as Map<String, dynamic>;
    final list = (json['signatures'] as List)
        .map((e) => Signature.fromJson(e as Map<String, dynamic>))
        .toList();
    return SignatureDb(
      list,
      version: (json['version'] as num?)?.toInt() ?? 0,
      updated: (json['updated'] as String?) ?? '',
    );
  }

  final List<Signature> signatures;
  final int version;
  final String updated;

  List<SignatureMatch> match(Advertisement adv) {
    final results = <SignatureMatch>[];
    final name = adv.name.toLowerCase();
    for (final sig in signatures) {
      for (final id in adv.companyIds) {
        if (sig.companyIds.contains(id)) {
          results.add(SignatureMatch(sig, '제조사 ID ${hex4(id)}'));
        }
      }
      for (final uuid in adv.serviceUuids) {
        if (sig.serviceUuids.contains(uuid)) {
          results.add(SignatureMatch(sig, '서비스 UUID $uuid'));
        }
      }
      if (name.isNotEmpty) {
        for (final needle in sig.nameContains) {
          if (name.contains(needle)) {
            // 전체 이름("홍길동의 Ray-Ban")에는 사람 이름이 들어갈 수 있어 일치한 검색어만 남긴다.
            results.add(SignatureMatch(sig, '기기 이름에 "$needle" 포함'));
            break;
          }
        }
      }
    }
    return results;
  }
}

String hex4(int id) => '0x${id.toRadixString(16).toUpperCase().padLeft(4, '0')}';
