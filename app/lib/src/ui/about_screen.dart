// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../model/signatures.dart';
import '../version.dart';
import 'common.dart';
import 'doc_screen.dart';
import 'theme.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key, required this.signatures});

  final SignatureDb signatures;

  @override
  Widget build(BuildContext context) {
    final c = context.c;

    Widget section(String title, List<String> paragraphs) => Container(
          padding: const EdgeInsets.symmetric(vertical: 24),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: c.line))),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: T.section.copyWith(color: c.ink)),
              for (final p in paragraphs) ...[
                const SizedBox(height: 12),
                Text(p, style: T.body.copyWith(color: c.ink)),
              ],
            ],
          ),
        );

    // 같은 이름은 한 줄로 묶고 제조사 ID를 모은다.
    final targets = <String, List<String>>{};
    for (final s in signatures.signatures) {
      targets.putIfAbsent(s.label, () => []).addAll([
        ...(s.companyIds.toList()..sort()).map(hex4),
        if (s.serviceUuids.isNotEmpty) 'UUID',
        if (s.nameContains.isNotEmpty) '이름',
      ]);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('앱 정보')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
          children: [
            Text('AI 안경 탐지기', style: T.title.copyWith(color: c.ink)),
            const SizedBox(height: 4),
            Text('버전 $appVersion · 시그니처 ${signatures.updated}', style: T.body.copyWith(color: c.ink2)),
            const SizedBox(height: 24),
            section('탐지 방법', [
              'AI 안경은 폰과 연결하려고 블루투스 저전력(BLE) 광고 신호를 계속 내보냅니다. '
                  '이 앱은 그 신호를 듣기만 하고, 신호에 담긴 제조사 번호·서비스 번호·기기 이름이 알려진 AI 안경과 같으면 빨간색으로 알립니다.',
              '감독을 시작할 때 교실에 있던 기기를 기억해 두었다가, 그 뒤에 새로 나타난 기기는 노란색으로 알립니다.',
            ]),
            Container(
              padding: const EdgeInsets.only(top: 24, bottom: 24),
              decoration: BoxDecoration(border: Border(top: BorderSide(color: c.line))),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('찾는 안경', style: T.section.copyWith(color: c.ink)),
                  const SizedBox(height: 4),
                  for (final e in targets.entries)
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.line))),
                      child: Row(
                        children: [
                          Expanded(child: Text(e.key, style: T.body.copyWith(color: c.ink))),
                          const SizedBox(width: 12),
                          Text(e.value.toSet().join('  '), style: T.aux.copyWith(color: c.ink2, fontFeatures: tabular)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            section('한계', [
              '경고는 참고 신호이며 부정행위의 증거가 아닙니다. 메타 퀘스트나 같은 칩을 쓰는 이어폰도 같은 신호를 낼 수 있습니다.',
              '신호 세기는 몸과 책상에 가려 크게 흔들립니다. 교실 단위까지는 의미가 있지만 좌석은 특정할 수 없습니다.',
              '블루투스를 끈 채 녹화만 하는 기기는 탐지할 수 없습니다. 실시간으로 답을 받으려면 연결이 필요하므로 커닝 방지에는 효과가 있습니다.',
              '아직 신호를 확보하지 못한 제품(일부 디스플레이형 안경 등)은 새 기기로만 잡힐 수 있습니다.',
            ]),
            section('개인정보', [
              '이 앱에는 인터넷 권한이 없습니다. 서버, 광고, 분석 도구가 없습니다.',
              '기기에 연결하거나 신호 내용을 해독하지 않습니다. 기록은 감독 중 폰 메모리에만 있고, 직접 내보내지 않으면 사라집니다. 내보낸 기록에도 기기 주소는 들어가지 않습니다.',
            ]),
            section('원작과 라이선스', [
              '이 앱은 Yves Jeanrenaud의 Nearby Glasses($upstreamUrl)를 바탕으로 한국 시험 감독용으로 만든 포크입니다. '
                  '탐지 방법과 시그니처는 원작 프로젝트의 연구에서 왔습니다. 원작과는 별개의 앱이며 원작자가 이 앱을 보증하지 않습니다.',
              'GNU AGPL-3.0으로 배포하며, 전체 소스 코드는 $sourceUrl 에 있습니다.',
              'Meta, Ray-Ban, Oakley, Snap Spectacles 등은 각 소유자의 상표입니다. 이 앱은 해당 회사와 제휴하거나 보증받은 앱이 아닙니다.',
            ]),
            Container(
              padding: const EdgeInsets.only(top: 24),
              decoration: BoxDecoration(border: Border(top: BorderSide(color: c.line))),
              child: Column(
                children: [
                  for (final (label, asset) in const [
                    ('이용약관', 'assets/docs/terms.md'),
                    ('개인정보처리방침', 'assets/docs/privacy.md'),
                    ('사용 지침', 'assets/docs/guide.md'),
                    ('업데이트 기록', 'assets/docs/changelog.md'),
                  ])
                    Pressable(pressedScale: 0.98, 
                      onTap: () => Navigator.of(context)
                          .push(MaterialPageRoute(builder: (_) => DocScreen(title: label, asset: asset))),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.line))),
                        child: Row(
                          children: [
                            Expanded(child: Text(label, style: T.body.copyWith(color: c.ink))),
                            Icon(Icons.chevron_right, color: c.ink3),
                          ],
                        ),
                      ),
                    ),
                  Pressable(pressedScale: 0.98, 
                    onTap: () async {
                      await Clipboard.setData(const ClipboardData(text: contactEmail));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('메일 주소를 복사했습니다.')));
                      }
                    },
                    child: KVRow('문의', contactEmail),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            AppButton(
              label: '오픈소스 라이선스',
              kind: ButtonKind.secondary,
              onPressed: () => showLicensePage(
                context: context,
                applicationName: 'AI 안경 탐지기',
                applicationVersion: appVersion,
                applicationLegalese: 'AGPL-3.0. Nearby Glasses © Yves Jeanrenaud 기반.',
              ),
            ),
            const SizedBox(height: 16),
            Text(disclaimerLine, style: T.aux.copyWith(color: c.ink2)),
          ],
        ),
      ),
    );
  }
}
