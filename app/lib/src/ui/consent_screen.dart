// SPDX-License-Identifier: AGPL-3.0-or-later
// 첫 실행 동의 화면. 약관 버전([termsVersion])이 바뀌면 다시 보인다.
// 동의 여부·버전·시각은 이 폰 안(shared_preferences)에만 저장한다.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../version.dart';
import 'common.dart';
import 'doc_screen.dart';
import 'theme.dart';

const _kVersion = 'consent.termsVersion';
const _kAt = 'consent.acceptedAt';

Future<bool> hasConsent() async {
  final p = await SharedPreferences.getInstance();
  return p.getInt(_kVersion) == termsVersion;
}

Future<void> saveConsent() async {
  final p = await SharedPreferences.getInstance();
  await p.setInt(_kVersion, termsVersion);
  await p.setString(_kAt, DateTime.now().toIso8601String());
}

class ConsentScreen extends StatefulWidget {
  const ConsentScreen({super.key, required this.onAccepted});

  final VoidCallback onAccepted;

  @override
  State<ConsentScreen> createState() => _ConsentScreenState();
}

class _ConsentScreenState extends State<ConsentScreen> {
  bool _checked = false;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Scaffold(
      body: SafeArea(
        child: FutureBuilder<String>(
          future: rootBundle.loadString('assets/docs/consent.md'),
          builder: (context, snap) {
            if (!snap.hasData) return const SizedBox.shrink();
            // consent.md 구성: 제목(#) · 항목(-) · 체크 문장(목록 뒤 마지막 일반 문단) · 약관 버전 · 시행일.
            // 체크 문장은 체크 칸에 쓰고 본문에서는 뺀다. 버전·시행일 줄은 화면에 보이지 않는다.
            final lines = snap.data!
                .split('\n')
                .where((l) => !l.startsWith('약관 버전') && !l.startsWith('시행일'))
                .toList();
            final title = lines.firstWhere((l) => l.startsWith('# '), orElse: () => '# 시작 전에 확인해 주세요');
            final checkIndex = lines.lastIndexWhere(
                (l) => l.trim().isNotEmpty && !l.startsWith('#') && !l.trimLeft().startsWith('- '));
            final checkText = checkIndex >= 0 ? lines[checkIndex].trim() : '위 내용을 확인했습니다';
            final source = [for (var i = 0; i < lines.length; i++) if (i != checkIndex) lines[i]].join('\n');
            return Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 32, 20, 16),
                    children: [
                      Text(title.substring(2), style: T.title.copyWith(color: c.ink, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 24),
                      ...renderDoc(context, source),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          _Link('이용약관', 'assets/docs/terms.md'),
                          const SizedBox(width: 16),
                          _Link('개인정보처리방침', 'assets/docs/privacy.md'),
                        ],
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                  child: Column(
                    children: [
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() => _checked = !_checked);
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Row(
                            children: [
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  color: _checked ? c.brand : Colors.transparent,
                                  border: Border.all(color: _checked ? c.brand : c.ink3, width: 2),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: _checked ? const Icon(Icons.check, size: 18, color: Colors.black) : null,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(checkText, style: T.bodyStrong.copyWith(color: c.ink)),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      AppButton(
                        label: '동의하고 시작',
                        onPressed: _checked
                            ? () async {
                                await saveConsent();
                                widget.onAccepted();
                              }
                            : null,
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Link extends StatelessWidget {
  const _Link(this.label, this.asset);

  final String label;
  final String asset;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return GestureDetector(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => DocScreen(title: label, asset: asset))),
      child: Text(label,
          style: T.bodyStrong.copyWith(color: c.ink2, decoration: TextDecoration.underline, decorationColor: c.ink2)),
    );
  }
}
