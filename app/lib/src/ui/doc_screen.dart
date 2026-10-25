// SPDX-License-Identifier: AGPL-3.0-or-later
// assets/docs/*.md 를 앱 안에서 보여 준다. 같은 파일이 GitHub에도 올라가므로 내용은 한 곳에서만 고친다.
// 지원하는 문법: '# ', '## ', '- ', '1. ', 빈 줄로 나눈 문단.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme.dart';

/// 간이 마크다운을 위젯 목록으로. 제목(#)은 화면 제목으로 쓰므로 [skipTitle]이면 뺀다.
List<Widget> renderDoc(BuildContext context, String source, {bool skipTitle = true}) {
  final c = context.c;
  final out = <Widget>[];
  final para = <String>[];

  void flush() {
    if (para.isEmpty) return;
    out.add(Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(para.join(' '), style: T.body.copyWith(color: c.ink)),
    ));
    para.clear();
  }

  for (final raw in source.split('\n')) {
    final line = raw.trimRight();
    if (line.trim().isEmpty) {
      flush();
    } else if (line.startsWith('# ')) {
      flush();
      if (!skipTitle) out.add(Text(line.substring(2), style: T.title.copyWith(color: c.ink)));
    } else if (line.startsWith('## ')) {
      flush();
      out.add(Padding(
        padding: EdgeInsets.only(top: out.isEmpty ? 0 : 20, bottom: 8),
        child: Text(line.substring(3), style: T.section.copyWith(color: c.ink)),
      ));
    } else if (line.startsWith('### ')) {
      flush();
      out.add(Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 6),
        child: Text(line.substring(4), style: T.bodyStrong.copyWith(color: c.ink)),
      ));
    } else {
      final bullet = RegExp(r'^\s*(- |\d+\. )').firstMatch(line);
      if (bullet != null) {
        flush();
        final mark = bullet.group(1)!.trim();
        out.add(Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 24,
                child: Text(mark == '-' ? '·' : mark, style: T.body.copyWith(color: c.ink2, fontFeatures: tabular)),
              ),
              Expanded(child: Text(line.substring(bullet.end), style: T.body.copyWith(color: c.ink))),
            ],
          ),
        ));
      } else {
        para.add(line.trim());
      }
    }
  }
  flush();
  return out;
}

class DocScreen extends StatelessWidget {
  const DocScreen({super.key, required this.title, required this.asset});

  final String title;

  /// 예: 'assets/docs/terms.md'
  final String asset;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: FutureBuilder<String>(
          future: rootBundle.loadString(asset),
          builder: (context, snap) {
            if (!snap.hasData) return const SizedBox.shrink();
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: renderDoc(context, snap.data!),
            );
          },
        ),
      ),
    );
  }
}
