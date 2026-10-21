import 'package:material_ui/material_ui.dart';

/// 韩小圈品牌色：粉紫渐变，深色底。全部页面共用这一套。
abstract final class HjTheme {
  static const Color accent = Color(0xFFFF4F94);
  static const Color accent2 = Color(0xFFA05AFF);
  static const Color accent3 = Color(0xFF5CBDFF);

  static const LinearGradient brand = LinearGradient(
    colors: [accent, accent2],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient brandWide = LinearGradient(
    colors: [accent, accent2, accent3],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// 海报 3:4
  static const double posterAspect = 3 / 4;

  static Color cardOf(BuildContext context) =>
      ColorScheme.of(context).surfaceContainerHigh;

  static Color muted(BuildContext context) =>
      ColorScheme.of(context).onSurfaceVariant;

  static List<BoxShadow> glow([double alpha = 0.30]) => [
    BoxShadow(
      color: accent.withValues(alpha: alpha),
      blurRadius: 18,
      offset: const Offset(0, 6),
    ),
  ];
}
