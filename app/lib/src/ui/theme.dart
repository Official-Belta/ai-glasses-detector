// SPDX-License-Identifier: AGPL-3.0-or-later
// 디자인 토큰. 다크 우선, 그림자 없이 1px 선, 모서리 8px 이하, 채운 색 버튼은 화면당 하나.
// 서체는 플랫폼 기본(Android Roboto·Noto Sans CJK, iOS SF·Apple SD Gothic Neo). 숫자는 고정폭 숫자.

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.bg,
    required this.panel,
    required this.panel2,
    required this.line,
    required this.ink,
    required this.ink2,
    required this.ink3,
    required this.brand,
    required this.danger,
    required this.warn,
  });

  final Color bg, panel, panel2, line, ink, ink2, ink3;

  /// 감독 중 상태와 주 버튼에만.
  final Color brand;

  /// AI 안경 의심.
  final Color danger;

  /// 새 기기.
  final Color warn;

  static const dark = AppColors(
    bg: Color(0xFF0A0B0D),
    panel: Color(0xFF131519),
    panel2: Color(0xFF1B1E23),
    line: Color(0xFF24282F),
    ink: Color(0xFFF2F4F6),
    ink2: Color(0xFFA2A9B4),
    ink3: Color(0xFF6B7280),
    // 볼트(형광 연두). 주 버튼·정상 상태·카운트다운에만.
    brand: Color(0xFFD4FF00),
    danger: Color(0xFFFF3B3B),
    warn: Color(0xFFFFB020),
  );

  static const light = AppColors(
    bg: Color(0xFFFFFFFF),
    panel: Color(0xFFF6F7F8),
    panel2: Color(0xFFEEF0F2),
    line: Color(0xFFE3E6EA),
    ink: Color(0xFF0A0B0D),
    ink2: Color(0xFF4E5562),
    ink3: Color(0xFF8B929E),
    brand: Color(0xFF00A653),
    danger: Color(0xFFE5303A),
    warn: Color(0xFFC27803),
  );

  @override
  AppColors copyWith() => this;

  @override
  AppColors lerp(AppColors? other, double t) => t < 0.5 ? this : (other ?? this);
}

extension AppColorsX on BuildContext {
  AppColors get c => Theme.of(this).extension<AppColors>()!;
}

const tabular = [FontFeature.tabularFigures()];

/// 글자 단계: 큰 숫자(Barlow 압축 이탤릭) 96·64·40 / 페이지 제목 24 / 구역 제목 20 / 본문 16 / 보조 14.
/// Barlow는 숫자·영문에만 쓴다. 한글은 플랫폼 기본 서체로 떨어진다.
class T {
  static const hero = TextStyle(
      fontFamily: 'Barlow', fontSize: 96, height: 0.95, fontWeight: FontWeight.w800, fontStyle: FontStyle.italic, fontFeatures: tabular);
  static const big = TextStyle(
      fontFamily: 'Barlow', fontSize: 64, height: 1, fontWeight: FontWeight.w800, fontStyle: FontStyle.italic, fontFeatures: tabular);
  static const stat = TextStyle(
      fontFamily: 'Barlow', fontSize: 40, height: 1, fontWeight: FontWeight.w700, fontStyle: FontStyle.italic, fontFeatures: tabular);
  static const display = TextStyle(fontSize: 40, height: 1.1, fontWeight: FontWeight.w800, letterSpacing: -1);
  static const title = TextStyle(fontSize: 24, height: 1.3, fontWeight: FontWeight.w600);
  static const section = TextStyle(fontSize: 20, height: 1.4, fontWeight: FontWeight.w600);
  static const body = TextStyle(fontSize: 16, height: 1.5);
  static const bodyStrong = TextStyle(fontSize: 16, height: 1.5, fontWeight: FontWeight.w600);
  static const aux = TextStyle(fontSize: 14, height: 1.5);
  static const num = TextStyle(fontSize: 16, height: 1.5, fontWeight: FontWeight.w600, fontFeatures: tabular);
}

ThemeData buildTheme(Brightness brightness) {
  final c = brightness == Brightness.dark ? AppColors.dark : AppColors.light;
  final base = ThemeData(brightness: brightness, useMaterial3: true);
  // 플랫폼 기본 서체를 유지하려고 기본 글자 스타일에 크기·굵기만 덮는다.
  TextStyle inherit(TextStyle t) => base.textTheme.bodyLarge!.merge(t);
  return base.copyWith(
    scaffoldBackgroundColor: c.bg,
    canvasColor: c.bg,
    dividerColor: c.line,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    // 토스처럼 옆에서 밀려 들어오고, 손으로 밀어 뒤로 갈 수 있는 전환. 안드로이드 기본(확대)은 무겁게 느껴진다.
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: CupertinoPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
    }),
    colorScheme: base.colorScheme.copyWith(
      surface: c.bg,
      onSurface: c.ink,
      primary: c.brand,
      onPrimary: Colors.black,
      error: c.danger,
      outline: c.line,
      outlineVariant: c.line,
    ),
    textTheme: base.textTheme.apply(bodyColor: c.ink, displayColor: c.ink),
    appBarTheme: AppBarTheme(
      backgroundColor: c.bg,
      foregroundColor: c.ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: inherit(T.bodyStrong.copyWith(color: c.ink)),
    ),
    dividerTheme: DividerThemeData(color: c.line, thickness: 1, space: 1),
    dialogTheme: DialogThemeData(
      backgroundColor: c.panel,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      titleTextStyle: inherit(T.section.copyWith(color: c.ink)),
      contentTextStyle: inherit(T.body.copyWith(color: c.ink2)),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: c.panel2,
      contentTextStyle: inherit(T.body.copyWith(color: c.ink)),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
    extensions: [c],
  );
}
