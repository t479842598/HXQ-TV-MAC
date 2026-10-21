import 'dart:ui' show ImageFilter;

import 'package:PiliPlus/hanju/models.dart';
import 'package:PiliPlus/hanju/store.dart';
import 'package:PiliPlus/hanju/ui/hj_theme.dart';
import 'package:PiliPlus/hanju/ui/responsive.dart';
import 'package:material_ui/material_ui.dart';

/// 剧集详情：海报 + 简介（可展开）+ 选集网格 + 仅看已收录筛选。
class HjDetailPage extends StatefulWidget {
  const HjDetailPage({
    super.key,
    required this.series,
    required this.onPlay,
  });

  final HjSeries series;
  final void Function(
    HjSeries series,
    HjPlayItem episode,
    String dir,
    List<HjPlayItem> episodes,
  )
  onPlay;

  @override
  State<HjDetailPage> createState() => _HjDetailPageState();
}

class _HjDetailPageState extends State<HjDetailPage> {
  final _store = HjStore.instance;
  bool _introExpanded = false;
  bool _onlyAvailable = false;
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    _store.addListener(_onStore);
    _store.loadDetail(widget.series.sid);
  }

  void _onStore() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _store.removeListener(_onStore);
    super.dispose();
  }

  Future<void> _play(HjPlayItem ep, List<HjPlayItem> episodes) async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      final dir = _store.playDir(widget.series.sid, ep.serialNo);
      if (dir == null) return;
      widget.onPlay(widget.series, ep, dir, episodes);
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = HjMetrics.of(context);
    final info = _store.detail(widget.series.sid)?.series;
    final episodes = _store.detail(widget.series.sid)?.playItems ?? const [];
    final display = _store.display(widget.series);
    final state = _store.state(widget.series.sid);

    final visible = _onlyAvailable
        ? episodes
              .where((e) => _store.playDir(widget.series.sid, e.serialNo) != null)
              .toList()
        : episodes;

    return Scaffold(
      backgroundColor: ColorScheme.of(context).surface,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: m.isTv ? m.gap(238) : m.gap(196),
            backgroundColor: ColorScheme.of(context).surface,
            flexibleSpace: FlexibleSpaceBar(
              background: _Hero(
                series: display,
                info: info,
                metrics: m,
                episodes: episodes,
                opening: _opening,
                onPlayFirst: () {
                  if (episodes.isNotEmpty) _play(episodes.first, episodes);
                },
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: m.contentMaxWidth),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: m.pagePadding.horizontal,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(height: m.gap(14)),
                      if (info != null && info.plainIntro.isNotEmpty)
                        _introBlock(info.plainIntro, m),
                      SizedBox(height: m.gap(18)),
                      _episodeHeader(episodes, m),
                      SizedBox(height: m.gap(10)),
                      if (state == HjLoadState.loading && episodes.isEmpty)
                        _skeleton(m)
                      else if (episodes.isEmpty)
                        Padding(
                          padding: EdgeInsets.symmetric(vertical: m.gap(30)),
                          child: Center(
                            child: Text(
                              '暂无选集数据',
                              style: TextStyle(
                                fontSize: m.sp(12),
                                color: HjTheme.muted(context),
                              ),
                            ),
                          ),
                        )
                      else
                        _episodeGrid(visible, episodes, m),
                      SizedBox(height: m.gap(40)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<HjPlayItem> episodes0(HjSeriesInfo? info, bool b) {
    return _store.detail(widget.series.sid)?.playItems ?? const [];
  }

  Widget _introBlock(String text, HjMetrics m) {
    final long = text.length > 90;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(m.gap(13)),
      decoration: BoxDecoration(
        color: ColorScheme.of(context).surfaceContainerHigh,
        borderRadius: BorderRadius.circular(m.gap(12)),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '简介',
                style: TextStyle(
                  fontSize: m.sp(12),
                  fontWeight: FontWeight.w800,
                  color: ColorScheme.of(context).onSurface,
                ),
              ),
              const Spacer(),
              if (long)
                GestureDetector(
                  onTap: () =>
                      setState(() => _introExpanded = !_introExpanded),
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: m.gap(8),
                      vertical: m.gap(3),
                    ),
                    decoration: BoxDecoration(
                      color: HjTheme.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(m.gap(12)),
                    ),
                    child: Text(
                      _introExpanded ? '收起' : '展开',
                      style: TextStyle(
                        fontSize: m.sp(10.5),
                        fontWeight: FontWeight.w700,
                        color: HjTheme.accent,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          SizedBox(height: m.gap(8)),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            alignment: Alignment.topCenter,
            child: Text(
              text,
              maxLines: _introExpanded ? null : 3,
              overflow: _introExpanded
                  ? TextOverflow.visible
                  : TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: m.sp(11.5),
                height: 1.55,
                color: HjTheme.muted(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _episodeHeader(List<HjPlayItem> eps, HjMetrics m) {
    final local = eps
        .where((e) => _store.playDir(widget.series.sid, e.serialNo) != null)
        .length;
    return Row(
      children: [
        Text(
          '选集',
          style: TextStyle(
            fontSize: m.sp(14),
            fontWeight: FontWeight.w800,
            color: ColorScheme.of(context).onSurface,
          ),
        ),
        SizedBox(width: m.gap(8)),
        Text(
          '${eps.length} 期',
          style: TextStyle(fontSize: m.sp(11), color: HjTheme.muted(context)),
        ),
        if (local > 0) ...[
          SizedBox(width: m.gap(8)),
          Text(
            '已收录 $local 集',
            style: TextStyle(
              fontSize: m.sp(10.5),
              fontWeight: FontWeight.w600,
              color: HjTheme.accent,
            ),
          ),
        ],
        const Spacer(),
        _toggleChip(
          label: '仅看已收录',
          value: _onlyAvailable,
          metrics: m,
          onTap: () => setState(() => _onlyAvailable = !_onlyAvailable),
        ),
      ],
    );
  }

  Widget _toggleChip({
    required String label,
    required bool value,
    required HjMetrics metrics,
    required VoidCallback onTap,
  }) {
    final m = metrics;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: m.gap(9),
          vertical: m.gap(4),
        ),
        decoration: BoxDecoration(
          color: value
              ? HjTheme.accent.withValues(alpha: 0.16)
              : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(m.gap(14)),
          border: Border.all(
            color: value
                ? HjTheme.accent.withValues(alpha: 0.45)
                : Colors.white.withValues(alpha: 0.08),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              value ? Icons.check_rounded : Icons.tune_rounded,
              size: m.sp(12),
              color: value ? HjTheme.accent : HjTheme.muted(context),
            ),
            SizedBox(width: m.gap(4)),
            Text(
              label,
              style: TextStyle(
                fontSize: m.sp(10.5),
                fontWeight: FontWeight.w600,
                color: value ? HjTheme.accent : HjTheme.muted(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _episodeGrid(
    List<HjPlayItem> visible,
    List<HjPlayItem> all,
    HjMetrics m,
  ) {
    final cols = m.isTv ? 8 : (m.width >= 600 ? 6 : 4);
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: visible.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: cols,
        mainAxisSpacing: m.gap(8),
        crossAxisSpacing: m.gap(8),
        childAspectRatio: 2.15,
      ),
      itemBuilder: (c, i) {
        final ep = visible[i];
        final has = _store.playDir(widget.series.sid, ep.serialNo) != null;
        return _EpisodeTile(
          ep: ep,
          available: has,
          metrics: m,
          onTap: has ? () => _play(ep, all) : null,
        );
      },
    );
  }

  Widget _skeleton(HjMetrics m) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 8,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: m.isTv ? 8 : 4,
        mainAxisSpacing: m.gap(8),
        crossAxisSpacing: m.gap(8),
        childAspectRatio: 2.15,
      ),
      itemBuilder: (c, i) => Container(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(m.gap(8)),
        ),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({
    required this.series,
    required this.info,
    required this.metrics,
    required this.episodes,
    required this.opening,
    required this.onPlayFirst,
  });

  final HjSeries series;
  final HjSeriesInfo? info;
  final HjMetrics metrics;
  final List<HjPlayItem> episodes;
  final bool opening;
  final VoidCallback onPlayFirst;

  @override
  Widget build(BuildContext context) {
    final m = metrics;
    final cover = series.poster ?? series.thumb;
    final posterW = m.isTv ? m.gap(104) : m.gap(86);
    return Stack(
      fit: StackFit.expand,
      children: [
        if (cover != null)
          ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
            child: Image.network(
              cover,
              fit: BoxFit.cover,
              cacheWidth: 480,
              errorBuilder: (c, e, st) =>
                  const ColoredBox(color: Color(0xFF241C2E)),
            ),
          )
        else
          const ColoredBox(color: Color(0xFF241C2E)),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.45),
                ColorScheme.of(context).surface.withValues(alpha: 0.82),
                ColorScheme.of(context).surface,
              ],
              stops: const [0.0, 0.72, 1.0],
            ),
          ),
        ),
        Positioned(
          left: m.pagePadding.horizontal,
          right: m.pagePadding.horizontal,
          bottom: m.gap(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(m.gap(9)),
                child: SizedBox(
                  width: posterW,
                  height: posterW / HjTheme.posterAspect,
                  child: posterW <= 0
                      ? const SizedBox.shrink()
                      : (series.thumb != null
                          ? Image.network(
                              series.thumb!,
                              fit: BoxFit.cover,
                              cacheWidth: 320,
                              errorBuilder: (c, e, st) =>
                                  const ColoredBox(color: Color(0xFF2A2136)),
                            )
                          : const ColoredBox(color: Color(0xFF2A2136))),
                ),
              ),
              SizedBox(width: m.gap(13)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      series.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: m.sp(18),
                        fontWeight: FontWeight.w900,
                        height: 1.2,
                        color: Colors.white,
                      ),
                    ),
                    if (info?.crew?.isNotEmpty == true) ...[
                      SizedBox(height: m.gap(5)),
                      Text(
                        info!.crew!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: m.sp(10.5),
                          color: Colors.white.withValues(alpha: 0.62),
                        ),
                      ),
                    ],
                    SizedBox(height: m.gap(9)),
                    Wrap(
                      spacing: m.gap(6),
                      runSpacing: m.gap(6),
                      children: _metaChips(context, m, info, episodes),
                    ),
                  ],
                ),
              ),
              SizedBox(width: m.gap(12)),
              _PlayButton(
                metrics: m,
                enabled: episodes.isNotEmpty,
                opening: opening,
                onTap: onPlayFirst,
              ),
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _metaChips(
    BuildContext context,
    HjMetrics m,
    HjSeriesInfo? info,
    List<HjPlayItem> eps,
  ) {
    final chips = <Widget>[];
    final rank = info?.rank;
    if (rank != null && rank > 0) {
      chips.add(_pill(context, m, '${rank ~/ 10}.${rank % 10} 分', brand: true));
    }
    if (info?.isFinished == true) {
      chips.add(_pill(context, m, '已完结'));
    } else if (info?.count != null && info!.count! > 0) {
      chips.add(_pill(context, m, '共 ${info.count} 期'));
    }
    final q = info?.scopeQualities.isNotEmpty == true
        ? info!.scopeQualities.first.resolution
        : null;
    if (q != null && q.isNotEmpty) chips.add(_pill(context, m, q));
    final local = eps
        .where((e) => HjStore.instance.playDir(series.sid, e.serialNo) != null)
        .length;
    if (local > 0) chips.add(_pill(context, m, '本地 $local 集', brand: true));
    return chips;
  }

  Widget _pill(
    BuildContext context,
    HjMetrics m,
    String text, {
    bool brand = false,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: m.gap(8), vertical: m.gap(3)),
      decoration: BoxDecoration(
        color: brand
            ? HjTheme.accent.withValues(alpha: 0.18)
            : Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(m.gap(20)),
        border: Border.all(
          color: brand
              ? HjTheme.accent.withValues(alpha: 0.40)
              : Colors.white.withValues(alpha: 0.10),
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: m.sp(10),
          fontWeight: FontWeight.w600,
          color: brand ? HjTheme.accent : Colors.white.withValues(alpha: 0.88),
        ),
      ),
    );
  }
}

class _PlayButton extends StatefulWidget {
  const _PlayButton({
    required this.metrics,
    required this.enabled,
    required this.opening,
    required this.onTap,
  });

  final HjMetrics metrics;
  final bool enabled;
  final bool opening;
  final VoidCallback onTap;

  @override
  State<_PlayButton> createState() => _PlayButtonState();
}

class _PlayButtonState extends State<_PlayButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final m = widget.metrics;
    final on = widget.enabled && !widget.opening;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: on ? widget.onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: EdgeInsets.symmetric(
            horizontal: m.gap(15),
            vertical: m.gap(9),
          ),
          decoration: BoxDecoration(
            gradient: on ? HjTheme.brand : null,
            color: on ? null : Colors.white.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(m.gap(18)),
            boxShadow: _hover && on ? HjTheme.glow(0.28) : const <BoxShadow>[],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.play_arrow_rounded,
                size: m.sp(16),
                color: Colors.white.withValues(alpha: on ? 1 : 0.5),
              ),
              SizedBox(width: m.gap(4)),
              Text(
                widget.opening ? '准备中…' : '立即播放',
                style: TextStyle(
                  fontSize: m.sp(11.5),
                  fontWeight: FontWeight.w700,
                  color: Colors.white.withValues(alpha: on ? 1 : 0.5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EpisodeTile extends StatefulWidget {
  const _EpisodeTile({
    required this.ep,
    required this.available,
    required this.metrics,
    this.onTap,
  });

  final HjPlayItem ep;
  final bool available;
  final HjMetrics metrics;
  final VoidCallback? onTap;

  @override
  State<_EpisodeTile> createState() => _EpisodeTileState();
}

class _EpisodeTileState extends State<_EpisodeTile> {
  bool _hover = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final m = widget.metrics;
    final active = (_hover || _focused) && widget.available;
    final ep = widget.ep;
    final label = ep.serialNo > 0 ? '第${ep.serialNo}期' : ep.title;
    return Focus(
      onFocusChange: (v) => setState(() => _focused = v),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: EdgeInsets.symmetric(
              horizontal: m.gap(9),
              vertical: m.gap(7),
            ),
            decoration: BoxDecoration(
              gradient: active ? HjTheme.brand : null,
              color: active
                  ? null
                  : ColorScheme.of(context).surfaceContainerHigh,
              borderRadius: BorderRadius.circular(m.gap(9)),
              border: Border.all(
                color: active
                    ? Colors.transparent
                    : Colors.white.withValues(alpha: 0.05),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: m.sp(11),
                          fontWeight: FontWeight.w700,
                          color: active
                              ? Colors.white
                              : ColorScheme.of(context).onSurface,
                        ),
                      ),
                    ),
                    if (!widget.available) ...[
                      SizedBox(width: m.gap(4)),
                      Icon(
                        Icons.inbox_outlined,
                        size: m.sp(11),
                        color: HjTheme.muted(context),
                      ),
                    ],
                  ],
                ),
                SizedBox(height: m.gap(2)),
                Text(
                  ep.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: m.sp(9.5),
                    color: active
                        ? Colors.white.withValues(alpha: 0.85)
                        : HjTheme.muted(context),
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