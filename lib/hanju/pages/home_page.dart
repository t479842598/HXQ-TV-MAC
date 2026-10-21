import 'package:PiliPlus/hanju/models.dart';
import 'package:PiliPlus/hanju/store.dart';
import 'package:PiliPlus/hanju/ui/hj_theme.dart';
import 'package:PiliPlus/hanju/ui/responsive.dart';
import 'package:PiliPlus/hanju/widgets/poster_card.dart';
import 'package:material_ui/material_ui.dart';

/// 首页：Hero 精选 + 板块横滑。手机 / 平板 / TV / 桌面共用同一套布局。
class HjHomePage extends StatefulWidget {
  const HjHomePage({super.key, required this.onOpen});

  final void Function(HjSeries series) onOpen;

  @override
  State<HjHomePage> createState() => _HjHomePageState();
}

class _HjHomePageState extends State<HjHomePage>
    with AutomaticKeepAliveClientMixin {
  final _store = HjStore.instance;
  bool _booted = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _store.addListener(_onStore);
    _boot();
  }

  Future<void> _boot() async {
    if (_booted) return;
    _booted = true;
    await _store.bootstrap();
  }

  void _onStore() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _store.removeListener(_onStore);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final m = HjMetrics.of(context);
    final blocks = _store.blocks;
    if (blocks.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    final heroSeeds = <HjSeries>[
      for (final b in blocks)
        if (b.items.isNotEmpty) b.items.first,
    ].take(5).toList();

    return RefreshIndicator(
      onRefresh: _store.refreshAll,
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: m.contentMaxWidth),
          child: ListView(
            padding: EdgeInsets.symmetric(vertical: m.gap(6)),
            children: [
              if (heroSeeds.isNotEmpty)
                Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: m.pagePadding.horizontal,
                  ),
                  child: _HeroCarousel(
                    seeds: heroSeeds,
                    metrics: m,
                    onTap: widget.onOpen,
                  ),
                ),
              for (final b in blocks)
                _Shelf(block: b, metrics: m, onOpen: widget.onOpen),
              SizedBox(height: m.gap(18)),
            ],
          ),
        ),
      ),
    );
  }
}

/// 顶部精选：横向可滑动的大卡，图上叠字，高度随内容区宽度自适应。
class _HeroCarousel extends StatefulWidget {
  const _HeroCarousel({
    required this.seeds,
    required this.metrics,
    required this.onTap,
  });

  final List<HjSeries> seeds;
  final HjMetrics metrics;
  final void Function(HjSeries) onTap;

  @override
  State<_HeroCarousel> createState() => _HeroCarouselState();
}

class _HeroCarouselState extends State<_HeroCarousel> {
  final _ctrl = PageController(viewportFraction: 0.86);
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(() {
      final page = (_ctrl.page ?? 0).round();
      if (page != _index && mounted) setState(() => _index = page);
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.metrics;
    final h = m.heroHeight;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: h,
          child: PageView.builder(
            controller: _ctrl,
            padEnds: false,
            itemCount: widget.seeds.length,
            itemBuilder: (c, i) {
              final s = HjStore.instance.display(widget.seeds[i]);
              return Padding(
                padding: EdgeInsets.only(right: m.gap(10)),
                child: _HeroCard(
                  series: s,
                  metrics: m,
                  height: h,
                  onTap: () => widget.onTap(widget.seeds[i]),
                ),
              );
            },
          ),
        ),
        if (widget.seeds.length > 1) ...[
          SizedBox(height: m.gap(8)),
          Row(
            children: [
              for (var i = 0; i < widget.seeds.length; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  margin: EdgeInsets.only(right: m.gap(4)),
                  width: i == _index ? m.gap(14) : m.gap(5),
                  height: m.gap(3),
                  decoration: BoxDecoration(
                    color: i == _index
                        ? HjTheme.accent
                        : Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _HeroCard extends StatefulWidget {
  const _HeroCard({
    required this.series,
    required this.metrics,
    required this.height,
    required this.onTap,
  });

  final HjSeries series;
  final HjMetrics metrics;
  final double height;
  final VoidCallback onTap;

  @override
  State<_HeroCard> createState() => _HeroCardState();
}

class _HeroCardState extends State<_HeroCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final m = widget.metrics;
    final s = widget.series;
    final img = s.poster ?? s.thumb;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(m.gap(10)),
            boxShadow: _hover ? HjTheme.glow(0.18) : const <BoxShadow>[],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(m.gap(10)),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (img != null)
                  Image.network(
                    img,
                    fit: BoxFit.cover,
                    errorBuilder: (c, e, st) => const ColoredBox(
                      color: Color(0xFF241C2E),
                    ),
                  )
                else
                  const ColoredBox(color: Color(0xFF241C2E)),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x11000000), Color(0xE6000000)],
                      stops: [0.25, 1.0],
                    ),
                  ),
                ),
                Positioned(
                  left: m.gap(12),
                  right: m.gap(12),
                  bottom: m.gap(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: m.gap(7),
                          vertical: m.gap(2),
                        ),
                        decoration: BoxDecoration(
                          gradient: HjTheme.brand,
                          borderRadius: BorderRadius.circular(m.gap(5)),
                        ),
                        child: Text(
                          '精选',
                          style: TextStyle(
                            fontSize: m.sp(8.5),
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      SizedBox(height: m.gap(4)),
                      Text(
                        s.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: m.sp(14),
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          height: 1.2,
                        ),
                      ),
                      SizedBox(height: m.gap(3)),
                      Text(
                        s.crew?.isNotEmpty == true ? s.crew! : s.statusText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: m.sp(9.5),
                          color: Colors.white.withValues(alpha: 0.72),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Shelf extends StatelessWidget {
  const _Shelf({
    required this.block,
    required this.metrics,
    required this.onOpen,
  });

  final HjBlock block;
  final HjMetrics metrics;
  final void Function(HjSeries) onOpen;

  @override
  Widget build(BuildContext context) {
    final m = metrics;
    if (block.items.isEmpty) return const SizedBox.shrink();
    // 海报宽度：桌面 ~92dp（一屏约 13 张），TV 稍大，手机 96dp
    final cardW = m.shelfCardWidth;
    return Padding(
      padding: EdgeInsets.only(top: m.gap(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: m.pagePadding.horizontal,
            ),
            child: Row(
              children: [
                Container(
                  width: m.gap(3),
                  height: m.gap(11),
                  decoration: BoxDecoration(
                    gradient: HjTheme.brand,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                SizedBox(width: m.gap(7)),
                Text(
                  block.cleanTitle,
                  style: TextStyle(
                    fontSize: m.sp(12.5),
                    fontWeight: FontWeight.w800,
                    color: ColorScheme.of(context).onSurface,
                  ),
                ),
                SizedBox(width: m.gap(6)),
                Text(
                  '${block.items.length}',
                  style: TextStyle(
                    fontSize: m.sp(10),
                    color: HjTheme.muted(context),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: m.gap(8)),
          SizedBox(
            height: cardW / HjTheme.posterAspect + m.gap(31),
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(
                horizontal: m.pagePadding.horizontal,
              ),
              itemCount: block.items.length,
              separatorBuilder: (_, _) => SizedBox(width: m.gap(8)),
              itemBuilder: (c, i) {
                final s = block.items[i];
                return SizedBox(
                  width: cardW,
                  child: HjPosterCard(
                    series: s,
                    metrics: m,
                    width: cardW,
                    onTap: () => onOpen(s),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}