import 'dart:io' show Platform;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:PiliPlus/utils/platform_utils.dart';

/// 四种形态共用同一份 UI，只按屏幕最短边与设备标志位切换尺寸。
enum HjForm { phone, tablet, tv, desktop }

/// 设备形态探测：TV 靠 Android 的 leanback / 无触摸屏特性判断，
/// 另提供 --dart-define=HJ_FORCE_TV=1 做验证。
abstract final class HjDevice {
  static HjForm _form = HjForm.phone;
  static bool _forcedTv = false;

  static HjForm get form => _forcedTv ? HjForm.tv : _form;

  static void setForcedTv(bool value) {
    _forcedTv = value;
  }

  static bool get forcedTv => _forcedTv;

  static Future<void> detect() async {
    const forceTv = bool.fromEnvironment('HJ_FORCE_TV', defaultValue: false);
    if (forceTv) {
      _forcedTv = true;
      return;
    }
    if (PlatformUtils.isDesktop) {
      _form = HjForm.desktop;
      return;
    }
    if (!Platform.isAndroid) {
      _form = HjForm.phone;
      return;
    }
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      final features = info.systemFeatures;
      final leanback = features.contains('android.software.leanback') ||
          features.contains('android.hardware.type.television');
      final hasTouch = features.contains('android.hardware.touchscreen');
      if (leanback && !hasTouch) {
        _form = HjForm.tv;
        return;
      }
    } catch (_) {
      // 探测失败时按平板/手机处理
    }
    final view = WidgetsBinding.instance.platformDispatcher.views.first;
    final shortest = (view.physicalSize / view.devicePixelRatio).shortestSide;
    _form = shortest >= 600 ? HjForm.tablet : HjForm.phone;
  }
}

/// 尺寸换算中心：所有字号与间距都必须经过这里，避免写死像素。
///
/// 关键点：桌面窗口可任意缩放，若沿用「最短边 / 390」会把 1080p 窗口
/// 放大 1.5 倍以上，导致海报与标题全部过大。所以桌面端字号锁定 1.0，
/// 只有间距随窗口宽度轻微浮动；TV 端才整体放大。
class HjMetrics {
  final HjForm form;
  final double shortest;
  final double width;
  final double height;

  const HjMetrics({
    required this.form,
    required this.shortest,
    required this.width,
    required this.height,
  });

  static HjMetrics of(BuildContext context) {
    final mq = MediaQuery.of(context);
    final size = mq.size;
    return HjMetrics(
      form: HjDevice.form,
      shortest: size.shortestSide,
      width: size.width,
      height: size.height,
    );
  }

  bool get isTv => form == HjForm.tv;
  bool get isDesktop => form == HjForm.desktop;
  bool get isCompact => form == HjForm.phone;

  /// 字号倍率：桌面固定 1.0，TV 放大 1.28，手机/平板按最短边微调。
  double get _fontScale => switch (form) {
    HjForm.phone => (shortest / 400).clamp(0.88, 1.06),
    HjForm.tablet => (shortest / 470).clamp(1.0, 1.14),
    HjForm.tv => 1.28,
    HjForm.desktop => 1.0,
  };

  /// 间距倍率：比字号更宽松一点，让宽屏不至于挤成一团。
  double get _spaceScale => switch (form) {
    HjForm.phone => (shortest / 400).clamp(0.88, 1.08),
    HjForm.tablet => (shortest / 450).clamp(1.0, 1.18),
    HjForm.tv => 1.34,
    HjForm.desktop => (width / 1500).clamp(0.94, 1.14),
  };

  double sp(double base) => base * _fontScale;

  double gap(double base) => base * _spaceScale;

  /// 海报列数：手机 3 / 平板 5 / TV 6 / 桌面按窗口宽度自适应
  int get posterColumns {
    if (form == HjForm.desktop) {
      return (width / 168).floor().clamp(4, 11);
    }
    return switch (form) {
      HjForm.phone => 3,
      HjForm.tablet => 5,
      HjForm.tv => 6,
      HjForm.desktop => 7,
    };
  }

  /// 内容区最大宽度（宽屏居中，避免一行拉得过长）
  double get contentMaxWidth => switch (form) {
    HjForm.phone => width,
    HjForm.tablet => 980,
    HjForm.tv => 1360,
    HjForm.desktop => 1360,
  };

  EdgeInsets get pagePadding => EdgeInsets.symmetric(
    horizontal: isTv ? gap(34) : gap(20),
    vertical: gap(10),
  );

  double get posterRadius => gap(isTv ? 11 : 8);

  /// Hero 高度：按内容区宽度算比例，并夹在合理区间。
  ///
  /// 桌面端刻意压低到内容宽度的 18%，一屏能同时看到 Hero 与第一排海报；
  /// 旧值 0.245 在 1600 宽窗口上会顶到 330dp，视觉上像一张大横幅。
  double get heroHeight {
    final w = contentMaxWidth;
    final raw = w * (isDesktop || isTv ? 0.165 : 0.34);
    return raw.clamp(gap(112), gap(215));
  }

  /// 首页横滑卡宽度：桌面 118dp（1424 宽内容区约 11 张），TV 稍大，手机 100dp。
  double get shelfCardWidth => isDesktop
      ? gap(118)
      : (isTv ? gap(126) : gap(100));

  /// 分类网格单格最小宽度：用来算列数，同时决定海报实际大小。
  /// 桌面 126dp ⇒ 1424 宽内容区约 10 列，海报约 138dp，既不空旷也不挤压。
  double get gridCellMin => isDesktop ? gap(126) : gap(108);
}