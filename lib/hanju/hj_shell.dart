import 'package:PiliPlus/hanju/history.dart';
import 'package:PiliPlus/hanju/models.dart';
import 'package:PiliPlus/hanju/pages/category_page.dart';
import 'package:PiliPlus/hanju/pages/detail_page.dart';
import 'package:PiliPlus/hanju/pages/history_page.dart';
import 'package:PiliPlus/hanju/pages/home_page.dart';
import 'package:PiliPlus/hanju/pages/player_page.dart';
import 'package:PiliPlus/hanju/store.dart';
import 'package:PiliPlus/hanju/ui/hj_theme.dart';
import 'package:PiliPlus/hanju/ui/responsive.dart';
import 'package:material_ui/material_ui.dart';

/// 应用外壳：一套代码同时适配手机 / 平板 / TV / 桌面。
///
/// 宽屏（桌面、TV、横屏平板）走左侧导航，窄屏走底部导航；
/// 所有可点元素都可用方向键 / 遥控器焦点操作。
class HjShell extends StatefulWidget {
  const HjShell({super.key});

  @override
  State<HjShell> createState() => _HjShellState();
}

class _HjShellState extends State<HjShell> {
  final _store = HjStore.instance;
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _store.addListener(_onStore);
    HjHistory.instance.init();
    HjHistory.instance.addListener(_onStore);
    _boot();
  }

  Future<void> _boot() async {
    await _store.bootstrap();
  }

  void _onStore() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _store.removeListener(_onStore);
    HjHistory.instance.removeListener(_onStore);
    super.dispose();
  }

  void _openSeries(HjSeries series) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (ctx) => HjDetailPage(
          series: series,
          onPlay: (s, ep, dir, episodes) {
            final idx = episodes.indexWhere((e) => e.pid == ep.pid);
            Navigator.of(ctx).push(
              MaterialPageRoute<void>(
                fullscreenDialog: true,
                builder: (_) => HjPlayerPage(
                  series: s,
                  episodes: episodes,
                  startIndex: idx < 0 ? 0 : idx,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _resume(HjHistoryEntry entry) async {
    final series = _store.allItems
        .where((s) => s.sid == entry.sid)
        .cast<HjSeries?>()
        .firstWhere((s) => true, orElse: () => null);
    if (series == null) return;
    await _store.loadDetail(series.sid);
    final eps = _store.detail(series.sid)?.playItems ?? const <HjPlayItem>[];
    if (eps.isEmpty) return;
    final idx = eps.indexWhere((e) => e.serialNo == entry.serialNo);
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => HjPlayerPage(
          series: series,
          episodes: eps,
          startIndex: idx < 0 ? 0 : idx,
        ),
      ),
    );
  }

  static const _tabs = <(String, IconData, IconData)>[
    ('首页', Icons.home_outlined, Icons.home_rounded),
    ('分类', Icons.grid_view_outlined, Icons.grid_view_rounded),
    ('记录', Icons.history_outlined, Icons.history_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    final m = HjMetrics.of(context);
    final wide = m.isDesktop || m.isTv || m.width >= 900;

    final body = switch (_tab) {
      0 => HjHomePage(onOpen: _openSeries),
      1 => HjCategoryPage(onOpen: _openSeries),
      _ => HjHistoryPage(onResume: _resume),
    };

    return Scaffold(
      backgroundColor: ColorScheme.of(context).surface,
      body: LayoutBuilder(
        builder: (c, cons) {
          if (wide) {
            return Row(
              children: [
                _SideNav(
                  tab: _tab,
                  metrics: m,
                  onSelect: (i) => setState(() => _tab = i),
                ),
                VerticalDivider(
                  width: 1,
                  thickness: 1,
                  color: Colors.white.withValues(alpha: 0.06),
                ),
                Expanded(child: body),
              ],
            );
          }
          return Column(
            children: [
              Expanded(child: body),
              _BottomNav(
                tab: _tab,
                metrics: m,
                onSelect: (i) => setState(() => _tab = i),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SideNav extends StatelessWidget {
  const _SideNav({
    required this.tab,
    required this.metrics,
    required this.onSelect,
  });

  final int tab;
  final HjMetrics metrics;
  final void Function(int) onSelect;

  @override
  Widget build(BuildContext context) {
    final m = metrics;
    final count = HjStore.instance.playMapCount;
    return Container(
      width: m.isTv ? m.gap(200) : m.gap(176),
      padding: EdgeInsets.symmetric(vertical: m.gap(18)),
      color: ColorScheme.of(context).surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: m.gap(16)),
            child: Row(
              children: [
                Container(
                  width: m.gap(30),
                  height: m.gap(30),
                  decoration: BoxDecoration(
                    gradient: HjTheme.brand,
                    borderRadius: BorderRadius.circular(m.gap(9)),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '韩',
                    style: TextStyle(
                      fontSize: m.sp(14),
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                ),
                SizedBox(width: m.gap(9)),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '韩小圈',
                      style: TextStyle(
                        fontSize: m.sp(14.5),
                        fontWeight: FontWeight.w800,
                        color: ColorScheme.of(context).onSurface,
                      ),
                    ),
                    Text(
                      '韩综 · TV/移动',
                      style: TextStyle(
                        fontSize: m.sp(9.5),
                        color: HjTheme.muted(context),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(height: m.gap(20)),
          for (var i = 0; i < _HjShellState._tabs.length; i++) ...[
            _NavItem(
              label: _HjShellState._tabs[i].$1,
              icon: tab == i
                  ? _HjShellState._tabs[i].$3
                  : _HjShellState._tabs[i].$2,
              selected: tab == i,
              metrics: m,
              onTap: () => onSelect(i),
            ),
            SizedBox(height: m.gap(3)),
          ],
          const Spacer(),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: m.gap(16)),
            child: Row(
              children: [
                Container(
                  width: m.gap(6),
                  height: m.gap(6),
                  decoration: const BoxDecoration(
                    color: HjTheme.accent,
                    shape: BoxShape.circle,
                  ),
                ),
                SizedBox(width: m.gap(7)),
                Text(
                  '已收录 $count 集播放源',
                  style: TextStyle(
                    fontSize: m.sp(10),
                    color: HjTheme.muted(context),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatefulWidget {
  const _NavItem({
    required this.label,
    required this.icon,
    required this.selected,
    required this.metrics,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final HjMetrics metrics;
  final VoidCallback onTap;

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool _hover = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final m = widget.metrics;
    final active = widget.selected;
    final hot = (_hover || _focused) && !active;
    return Focus(
      onFocusChange: (v) => setState(() => _focused = v),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: Container(
            margin: EdgeInsets.symmetric(horizontal: m.gap(10)),
            padding: EdgeInsets.symmetric(
              horizontal: m.gap(11),
              vertical: m.gap(9),
            ),
            decoration: BoxDecoration(
              color: active
                  ? HjTheme.accent.withValues(alpha: 0.14)
                  : (hot ? Colors.white.withValues(alpha: 0.05) : null),
              borderRadius: BorderRadius.circular(m.gap(9)),
              border: Border.all(
                color: active || _focused
                    ? HjTheme.accent.withValues(alpha: _focused ? 0.65 : 0.22)
                    : Colors.transparent,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  widget.icon,
                  size: m.sp(15),
                  color: active
                      ? HjTheme.accent
                      : HjTheme.muted(context),
                ),
                SizedBox(width: m.gap(9)),
                Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: m.sp(12.5),
                    fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                    color: active
                        ? HjTheme.accent
                        : ColorScheme.of(context).onSurface,
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

class _BottomNav extends StatelessWidget {
  const _BottomNav({
    required this.tab,
    required this.metrics,
    required this.onSelect,
  });

  final int tab;
  final HjMetrics metrics;
  final void Function(int) onSelect;

  @override
  Widget build(BuildContext context) {
    final m = metrics;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: ColorScheme.of(context).surfaceContainerLow,
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            for (var i = 0; i < _HjShellState._tabs.length; i++)
              Expanded(
                child: GestureDetector(
                  onTap: () => onSelect(i),
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: m.gap(9)),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          tab == i
                              ? _HjShellState._tabs[i].$3
                              : _HjShellState._tabs[i].$2,
                          size: m.sp(19),
                          color: tab == i
                              ? HjTheme.accent
                              : HjTheme.muted(context),
                        ),
                        SizedBox(height: m.gap(3)),
                        Text(
                          _HjShellState._tabs[i].$1,
                          style: TextStyle(
                            fontSize: m.sp(9.5),
                            fontWeight: tab == i
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: tab == i
                                ? HjTheme.accent
                                : HjTheme.muted(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}