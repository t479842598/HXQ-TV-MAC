import 'package:PiliPlus/hanju/models.dart';
import 'package:PiliPlus/hanju/store.dart';
import 'package:PiliPlus/hanju/ui/hj_theme.dart';
import 'package:PiliPlus/hanju/ui/responsive.dart';
import 'package:material_ui/material_ui.dart';

/// 海报卡：3:4 竖图 + 名称 + 状态。桌面 / TV / 手机同一套，尺寸由 HjMetrics 决定。
class HjPosterCard extends StatefulWidget {
  const HjPosterCard({
    super.key,
    required this.series,
    required this.metrics,
    this.onTap,
    this.width,
    this.showRank = true,
  });

  final HjSeries series;
  final HjMetrics metrics;
  final VoidCallback? onTap;
  final double? width;
  final bool showRank;

  @override
  State<HjPosterCard> createState() => _HjPosterCardState();
}

class _HjPosterCardState extends State<HjPosterCard> {
  bool _hover = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final m = widget.metrics;
    final s = HjStore.instance.display(widget.series);
    final radius = m.posterRadius;
    final active = _hover || _focused;
    final src = s.thumb ?? s.poster;
    final cardW = widget.width ?? m.shelfCardWidth;

    final poster = ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: AspectRatio(
        aspectRatio: HjTheme.posterAspect,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (src != null && src.isNotEmpty)
              Image.network(
                src,
                fit: BoxFit.cover,
                cacheWidth: (cardW * 2).round(),
                gaplessPlayback: true,
                errorBuilder: (c, e, st) => _fallback(context, m),
                loadingBuilder: (c, child, progress) =>
                    progress == null ? child : _fallback(context, m),
              )
            else
              _fallback(context, m),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x00000000), Color(0x4D000000)],
                  stops: [0.6, 1.0],
                ),
              ),
            ),
            if (widget.showRank && s.rankText != null)
              Positioned(
                left: m.gap(6),
                top: m.gap(6),
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: m.gap(5),
                    vertical: m.gap(1.5),
                  ),
                  decoration: BoxDecoration(
                    gradient: HjTheme.brand,
                    borderRadius: BorderRadius.circular(m.gap(4)),
                  ),
                  child: Text(
                    s.rankText!,
                    style: TextStyle(
                      fontSize: m.sp(9.5),
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      height: 1.1,
                    ),
                  ),
                ),
              ),
            if (s.finished == 1)
              Positioned(
                right: m.gap(6),
                top: m.gap(6),
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: m.gap(5),
                    vertical: m.gap(1.5),
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(m.gap(4)),
                  ),
                  child: Text(
                    '全',
                    style: TextStyle(
                      fontSize: m.sp(9.5),
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      height: 1.1,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Focus(
        onFocusChange: (v) => setState(() => _focused = v),
        child: GestureDetector(
          onTap: widget.onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedScale(
                scale: active ? 1.025 : 1.0,
                duration: const Duration(milliseconds: 120),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(radius),
                    border: Border.all(
                      color: active
                          ? HjTheme.accent
                          : Colors.white.withValues(alpha: 0.05),
                      width: active ? 1.6 : 1.0,
                    ),
                    boxShadow: active
                        ? HjTheme.glow(0.24)
                        : const <BoxShadow>[],
                  ),
                  child: poster,
                ),
              ),
              SizedBox(height: m.gap(4)),
              Text(
                s.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: m.sp(11),
                  fontWeight: FontWeight.w600,
                  height: 1.25,
                  color: active
                      ? HjTheme.accent
                      : ColorScheme.of(context).onSurface,
                ),
              ),
              SizedBox(height: m.gap(1)),
              Text(
                s.statusText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: m.sp(9.2),
                  height: 1.25,
                  color: HjTheme.muted(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fallback(BuildContext context, HjMetrics m) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            HjTheme.accent.withValues(alpha: 0.18),
            HjTheme.accent2.withValues(alpha: 0.10),
          ],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.live_tv_rounded,
          size: m.gap(20),
          color: Colors.white.withValues(alpha: 0.35),
        ),
      ),
    );
  }
}