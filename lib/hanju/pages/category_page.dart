import 'package:PiliPlus/hanju/models.dart';
import 'package:PiliPlus/hanju/store.dart';
import 'package:PiliPlus/hanju/ui/hj_theme.dart';
import 'package:PiliPlus/hanju/ui/responsive.dart';
import 'package:PiliPlus/hanju/widgets/poster_card.dart';
import 'package:material_ui/material_ui.dart';

/// 分类页：按板块浏览全部条目，支持板块切换 + 搜索 + 合并同系列显示。
class HjCategoryPage extends StatefulWidget {
  const HjCategoryPage({super.key, required this.onOpen});

  final void Function(HjSeries series) onOpen;

  @override
  State<HjCategoryPage> createState() => _HjCategoryPageState();
}

class _HjCategoryPageState extends State<HjCategoryPage> {
  final _store = HjStore.instance;
  final _search = TextEditingController();
  int _mid = -1;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _store.addListener(_onStore);
  }

  void _onStore() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _store.removeListener(_onStore);
    _search.dispose();
    super.dispose();
  }

  List<HjSeries> get _items {
    final blocks = _store.blocks;
    List<HjSeries> src;
    if (_mid < 0) {
      src = _store.allItems;
    } else {
      src = blocks
          .where((b) => b.mid == _mid)
          .expand((b) => b.items)
          .toList();
    }
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return src;
    return src
        .where((s) =>
            s.name.toLowerCase().contains(q) ||
            (s.crew ?? '').toLowerCase().contains(q) ||
            (s.shorthand ?? '').toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final m = HjMetrics.of(context);
    final blocks = _store.blocks;
    final items = _items;

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: m.contentMaxWidth),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                m.pagePadding.horizontal,
                m.gap(9),
                m.pagePadding.horizontal,
                m.gap(6),
              ),
              child: Row(
                children: [
                  Text(
                    '分类',
                    style: TextStyle(
                      fontSize: m.sp(17),
                      fontWeight: FontWeight.w900,
                      color: ColorScheme.of(context).onSurface,
                    ),
                  ),
                  SizedBox(width: m.gap(9)),
                  Text(
                    '${items.length} 部',
                    style: TextStyle(
                      fontSize: m.sp(10.5),
                      color: HjTheme.muted(context),
                    ),
                  ),
                  const Spacer(),
                  SizedBox(
                    width: m.isTv ? m.gap(210) : m.gap(158),
                    height: m.gap(30),
                    child: TextField(
                      controller: _search,
                      onChanged: (v) => setState(() => _query = v),
                      style: TextStyle(
                        fontSize: m.sp(11),
                        color: ColorScheme.of(context).onSurface,
                      ),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: '搜索综艺 / 嘉宾',
                        hintStyle: TextStyle(
                          fontSize: m.sp(10.5),
                          color: HjTheme.muted(context),
                        ),
                        prefixIcon: Icon(
                          Icons.search_rounded,
                          size: m.sp(13),
                          color: HjTheme.muted(context),
                        ),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: m.gap(9),
                          vertical: m.gap(7),
                        ),
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.05),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(m.gap(9)),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: m.gap(28),
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.symmetric(
                  horizontal: m.pagePadding.horizontal,
                ),
                children: [
                  _chip('全部', -1, m),
                  for (final b in blocks) ...[
                    SizedBox(width: m.gap(6)),
                    _chip(b.cleanTitle, b.mid, m),
                  ],
                ],
              ),
            ),
            SizedBox(height: m.gap(8)),
            Expanded(
              child: items.isEmpty
                  ? Center(
                      child: Text(
                        _store.booted ? '没有匹配的内容' : '正在载入目录…',
                        style: TextStyle(
                          fontSize: m.sp(11),
                          color: HjTheme.muted(context),
                        ),
                      ),
                    )
                  : LayoutBuilder(
                      builder: (c, cons) {
                        final maxW =
                            cons.maxWidth - m.pagePadding.horizontal * 2;
                        final cols = (maxW / m.gridCellMin)
                            .floor()
                            .clamp(2, m.isTv ? 11 : 12);
                        return GridView.builder(
                          padding: EdgeInsets.fromLTRB(
                            m.pagePadding.horizontal,
                            m.gap(4),
                            m.pagePadding.horizontal,
                            m.gap(26),
                          ),
                          itemCount: items.length,
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: cols,
                            mainAxisSpacing: m.gap(13),
                            crossAxisSpacing: m.gap(9),
                            childAspectRatio: HjTheme.posterAspect / 1.28,
                          ),
                          itemBuilder: (c, i) {
                            final s = items[i];
                            final display = _store.display(s);
                            return HjPosterCard(
                              series: display,
                              metrics: m,
                              onTap: () => widget.onOpen(s),
                            );
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, int mid, HjMetrics m) {
    final sel = _mid == mid;
    return GestureDetector(
      onTap: () => setState(() => _mid = mid),
      child: Container(
        alignment: Alignment.center,
        padding: EdgeInsets.symmetric(horizontal: m.gap(12)),
        decoration: BoxDecoration(
          gradient: sel ? HjTheme.brand : null,
          color: sel ? null : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(m.gap(14)),
          border: Border.all(
            color: sel
                ? Colors.transparent
                : Colors.white.withValues(alpha: 0.07),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: m.sp(10.5),
            fontWeight: FontWeight.w700,
            color: sel ? Colors.white : ColorScheme.of(context).onSurface,
          ),
        ),
      ),
    );
  }
}
