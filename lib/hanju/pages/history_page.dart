import 'package:PiliPlus/hanju/history.dart';
import 'package:PiliPlus/hanju/store.dart';
import 'package:PiliPlus/hanju/ui/hj_theme.dart';
import 'package:PiliPlus/hanju/ui/responsive.dart';
import 'package:material_ui/material_ui.dart';

/// 历史页：继续观看 + 全部记录，点击直接续播。
class HjHistoryPage extends StatefulWidget {
  const HjHistoryPage({super.key, required this.onResume});

  final void Function(HjHistoryEntry entry) onResume;

  @override
  State<HjHistoryPage> createState() => _HjHistoryPageState();
}

class _HjHistoryPageState extends State<HjHistoryPage> {
  final _history = HjHistory.instance;
  final _store = HjStore.instance;

  @override
  void initState() {
    super.initState();
    _history.addListener(_onChanged);
    _store.addListener(_onChanged);
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _history.removeListener(_onChanged);
    _store.removeListener(_onChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = HjMetrics.of(context);
    final cont = _history.continueWatching;
    final all = _history.entries;

    if (all.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.history_rounded,
              size: m.gap(44),
              color: HjTheme.muted(context),
            ),
            SizedBox(height: m.gap(12)),
            Text(
              '还没有观看记录',
              style: TextStyle(
                fontSize: m.sp(13),
                fontWeight: FontWeight.w600,
                color: HjTheme.muted(context),
              ),
            ),
            SizedBox(height: m.gap(6)),
            Text(
              '播放任意一期后会自动记录进度',
              style: TextStyle(
                fontSize: m.sp(11),
                color: HjTheme.muted(context),
              ),
            ),
          ],
        ),
      );
    }

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: m.contentMaxWidth),
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            m.pagePadding.horizontal,
            m.gap(9),
            m.pagePadding.horizontal,
            m.gap(28),
          ),
          children: [
            Row(
              children: [
                Text(
                  '观看记录',
                  style: TextStyle(
                    fontSize: m.sp(17),
                    fontWeight: FontWeight.w900,
                    color: ColorScheme.of(context).onSurface,
                  ),
                ),
                SizedBox(width: m.gap(10)),
                Text(
                  '${all.length} 条',
                  style: TextStyle(
                    fontSize: m.sp(10.5),
                    color: HjTheme.muted(context),
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: _history.clear,
                  child: Text(
                    '清空',
                    style: TextStyle(
                      fontSize: m.sp(10.5),
                      color: HjTheme.muted(context),
                    ),
                  ),
                ),
              ],
            ),
            if (cont.isNotEmpty) ...[
              SizedBox(height: m.gap(8)),
              Text(
                '继续观看',
                style: TextStyle(
                  fontSize: m.sp(13.5),
                  fontWeight: FontWeight.w800,
                  color: ColorScheme.of(context).onSurface,
                ),
              ),
              SizedBox(height: m.gap(10)),
              SizedBox(
                height: m.gap(150),
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: cont.length,
                  separatorBuilder: (_, _) => SizedBox(width: m.gap(11)),
                  itemBuilder: (c, i) => _ContinueCard(
                    entry: cont[i],
                    metrics: m,
                    onTap: () => widget.onResume(cont[i]),
                  ),
                ),
              ),
              SizedBox(height: m.gap(20)),
            ],
            Text(
              '全部记录',
              style: TextStyle(
                fontSize: m.sp(12.5),
                fontWeight: FontWeight.w800,
                color: ColorScheme.of(context).onSurface,
              ),
            ),
            SizedBox(height: m.gap(8)),
            for (final e in all) ...[
              _HistoryRow(
                entry: e,
                metrics: m,
                onTap: () => widget.onResume(e),
                onRemove: () => _history.remove(e.id),
              ),
              SizedBox(height: m.gap(6)),
            ],
          ],
        ),
      ),
    );
  }
}

class _ContinueCard extends StatelessWidget {
  const _ContinueCard({
    required this.entry,
    required this.metrics,
    required this.onTap,
  });

  final HjHistoryEntry entry;
  final HjMetrics metrics;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final m = metrics;
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: m.gap(190),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(m.gap(9)),
              child: Stack(
                children: [
                  AspectRatio(
                    aspectRatio: 16 / 9,
                    child: entry.poster != null
                        ? Image.network(
                            entry.poster!,
                            fit: BoxFit.cover,
                            errorBuilder: (c, e, s) => Container(
                              color: Colors.white.withValues(alpha: 0.06),
                            ),
                          )
                        : Container(
                            color: Colors.white.withValues(alpha: 0.06),
                          ),
                  ),
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.72),
                          ],
                          stops: const [0.45, 1.0],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: m.gap(8),
                    right: m.gap(8),
                    bottom: m.gap(8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.seriesName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: m.sp(12),
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          '第${entry.serialNo}期 · ${entry.positionText}',
                          style: TextStyle(
                            fontSize: m.sp(10),
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: ClipRRect(
                      borderRadius: BorderRadius.vertical(
                        bottom: Radius.circular(m.gap(9)),
                      ),
                      child: LinearProgressIndicator(
                        value: entry.progress.clamp(0.0, 1.0),
                        minHeight: 2.5,
                        backgroundColor: Colors.white24,
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          HjTheme.accent,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryRow extends StatefulWidget {
  const _HistoryRow({
    required this.entry,
    required this.metrics,
    required this.onTap,
    required this.onRemove,
  });

  final HjHistoryEntry entry;
  final HjMetrics metrics;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  State<_HistoryRow> createState() => _HistoryRowState();
}

class _HistoryRowState extends State<_HistoryRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final m = widget.metrics;
    final e = widget.entry;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: EdgeInsets.all(m.gap(9)),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: _hover ? 0.07 : 0.035),
            borderRadius: BorderRadius.circular(m.gap(10)),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(m.gap(7)),
                child: SizedBox(
                  width: m.gap(72),
                  height: m.gap(40),
                  child: e.poster != null
                      ? Image.network(
                          e.poster!,
                          fit: BoxFit.cover,
                          errorBuilder: (c, err, st) => Container(
                            color: Colors.white.withValues(alpha: 0.06),
                          ),
                        )
                      : Container(
                          color: Colors.white.withValues(alpha: 0.06),
                        ),
                ),
              ),
              SizedBox(width: m.gap(11)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      e.seriesName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: m.sp(12.5),
                        fontWeight: FontWeight.w700,
                        color: ColorScheme.of(context).onSurface,
                      ),
                    ),
                    SizedBox(height: m.gap(2)),
                    Text(
                      '第${e.serialNo}期 · ${e.epTitle}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: m.sp(10.5),
                        color: HjTheme.muted(context),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: m.gap(10)),
              SizedBox(
                width: m.gap(110),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${e.positionText} / ${e.durationText}',
                      style: TextStyle(
                        fontSize: m.sp(10.5),
                        color: HjTheme.muted(context),
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    SizedBox(height: m.gap(4)),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: e.progress.clamp(0.0, 1.0),
                        minHeight: 2.5,
                        backgroundColor: Colors.white.withValues(alpha: 0.10),
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          HjTheme.accent,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: m.gap(6)),
              if (_hover)
                GestureDetector(
                  onTap: widget.onRemove,
                  child: Icon(
                    Icons.close_rounded,
                    size: m.sp(14),
                    color: HjTheme.muted(context),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
