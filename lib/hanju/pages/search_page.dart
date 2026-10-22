import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:PiliPlus/hanju/models.dart';
import 'package:PiliPlus/hanju/store.dart';
import 'package:PiliPlus/hanju/ui/hj_theme.dart';
import 'package:PiliPlus/hanju/ui/responsive.dart';
import 'package:PiliPlus/hanju/widgets/poster_card.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as path;

/// 搜索页：全库检索 + 最近搜索 + 热门推荐。
///
/// 服务端 /api/search 系列端点（/api/search、/api/search/v2、/api/search/series…）
/// 全部返回 200 + 0 字节的空 body，唯一有内容的 /api/search/placeholder 又是
/// AES 密文的 data 字段。所以搜索走本地全库匹配：catalog.json 里 171 部综艺的
/// 名称 / 简介 / 主演 / 板块名全部参与打分，不需要任何网络请求。
class HjSearchPage extends StatefulWidget {
  const HjSearchPage({super.key, required this.onOpen});

  final void Function(HjSeries series) onOpen;

  @override
  State<HjSearchPage> createState() => _HjSearchPageState();
}

class _HjSearchPageState extends State<HjSearchPage> {
  static const int _maxRecent = 12;

  final _store = HjStore.instance;
  final _ctl = TextEditingController();
  final _focus = FocusNode();

  String _q = '';
  List<HjSeries> _results = const <HjSeries>[];
  final List<String> _recent = <String>[];

  /// sid -> 板块名，用于「恋爱」「推理」这类按板块搜
  final Map<String, String> _blockOf = <String, String>{};

  @override
  void initState() {
    super.initState();
    for (final b in _store.blocks) {
      for (final s in b.items) {
        _blockOf[s.sid] = b.cleanTitle;
      }
    }
    _store.addListener(_onStore);
    unawaited(_loadRecent());
  }

  void _onStore() {
    if (!mounted) return;
    setState(() {
      if (_q.trim().isNotEmpty) _results = _compute(_q);
    });
  }

  @override
  void dispose() {
    _store.removeListener(_onStore);
    _ctl.dispose();
    _focus.dispose();
    super.dispose();
  }

  // ---------- 检索 ----------

  int _score(HjSeries s, String q) {
    final name = s.name.toLowerCase();
    if (name == q) return 120;
    if (name.startsWith(q)) return 100;
    if (name.contains(q)) return 90;
    if ((s.shorthand ?? '').toLowerCase().contains(q)) return 60;
    if ((s.crew ?? '').toLowerCase().contains(q)) return 50;
    if ((_blockOf[s.sid] ?? '').toLowerCase().contains(q)) return 40;
    if (_fuzzy(name, q)) return 20;
    return 0;
  }

  /// 逐字模糊：q 的每个字符按顺序出现在 name 里即可（「宇宙店」能命中「宇宙年糕店」）
  bool _fuzzy(String text, String q) {
    if (q.length < 2) return false;
    var i = 0;
    for (var j = 0; j < text.length && i < q.length; j++) {
      if (text[j] == q[i]) i++;
    }
    return i == q.length;
  }

  List<HjSeries> _compute(String raw) {
    final q = raw.trim().toLowerCase();
    if (q.isEmpty) return const <HjSeries>[];
    final scored = <(int, HjSeries)>[];
    for (final s in _store.allItems) {
      final sc = _score(s, q);
      if (sc > 0) scored.add((sc, s));
    }
    scored.sort((a, b) {
      final c = b.$1.compareTo(a.$1);
      if (c != 0) return c;
      return (b.$2.rank ?? 0).compareTo(a.$2.rank ?? 0);
    });
    return scored.map((e) => e.$2).toList(growable: false);
  }

  void _onChanged(String v) {
    setState(() {
      _q = v;
      _results = _compute(v);
    });
  }

  void _submit(String v) {
    final q = v.trim();
    if (q.isEmpty) return;
    setState(() {
      _recent
        ..remove(q)
        ..insert(0, q);
      while (_recent.length > _maxRecent) {
        _recent.removeLast();
      }
      _q = q;
      _ctl.text = q;
      _results = _compute(q);
    });
    unawaited(_saveRecent());
  }

  void _clear() {
    setState(() {
      _q = '';
      _ctl.clear();
      _results = const <HjSeries>[];
    });
    _focus.requestFocus();
  }

  // ---------- 最近搜索落盘 ----------

  Future<File> _recentFile() async {
    final home = Platform.environment['HOME'] ?? '.';
    final dir = Directory(
      path.join(home, 'Library', 'Application Support', 'HanjuTV'),
    );
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return File(path.join(dir.path, 'search_recent.json'));
  }

  Future<void> _loadRecent() async {
    try {
      final f = await _recentFile();
      if (!f.existsSync()) return;
      final list = jsonDecode(await f.readAsString());
      if (list is! List || !mounted) return;
      setState(() {
        _recent
          ..clear()
          ..addAll(list.whereType<String>().take(_maxRecent));
      });
    } catch (_) {
      // 最近搜索只是便利功能，读失败直接当空
    }
  }

  Future<void> _saveRecent() async {
    try {
      final f = await _recentFile();
      await f.writeAsString(jsonEncode(_recent), flush: true);
    } catch (_) {
      // 同上，写失败不影响搜索
    }
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    final m = HjMetrics.of(context);
    final q = _q.trim();

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
                m.gap(8),
              ),
              child: Row(
                children: [
                  Text(
                    '搜索',
                    style: TextStyle(
                      fontSize: m.sp(17),
                      fontWeight: FontWeight.w900,
                      color: ColorScheme.of(context).onSurface,
                    ),
                  ),
                  SizedBox(width: m.gap(9)),
                  Text(
                    q.isEmpty
                        ? '全库 ${_store.allItems.length} 部'
                        : '${_results.length} 个结果',
                    style: TextStyle(
                      fontSize: m.sp(10.5),
                      color: HjTheme.muted(context),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: m.pagePadding.horizontal,
              ),
              child: SizedBox(
                height: m.gap(34),
                child: TextField(
                  controller: _ctl,
                  focusNode: _focus,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  onChanged: _onChanged,
                  onSubmitted: _submit,
                  style: TextStyle(
                    fontSize: m.sp(12),
                    color: ColorScheme.of(context).onSurface,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: '搜综艺名 / 嘉宾 / 简介，回车记录',
                    hintStyle: TextStyle(
                      fontSize: m.sp(11),
                      color: HjTheme.muted(context),
                    ),
                    prefixIcon: Icon(
                      Icons.search_rounded,
                      size: m.sp(15),
                      color: HjTheme.muted(context),
                    ),
                    suffixIcon: q.isEmpty
                        ? null
                        : GestureDetector(
                            onTap: _clear,
                            child: Icon(
                              Icons.close_rounded,
                              size: m.sp(14),
                              color: HjTheme.muted(context),
                            ),
                          ),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: m.gap(10),
                      vertical: m.gap(9),
                    ),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.05),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(m.gap(10)),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(height: m.gap(10)),
            if (q.isEmpty) ...[
              if (_recent.isNotEmpty) ...[
                _sectionLabel(m, '最近搜索'),
                SizedBox(height: m.gap(7)),
                _chips(m, _recent, _submit),
                SizedBox(height: m.gap(14)),
              ],
              _sectionLabel(m, '热门'),
              SizedBox(height: m.gap(7)),
              _chips(
                m,
                _hot().map((s) => s.name).toList(growable: false),
                _submit,
              ),
              SizedBox(height: m.gap(14)),
              _sectionLabel(m, '按嘉宾搜'),
              SizedBox(height: m.gap(7)),
              _chips(m, _crews(), _submit),
            ],
            SizedBox(height: m.gap(10)),
            Expanded(
              child: q.isEmpty
                  ? _empty(m)
                  : (_results.isEmpty
                        ? Center(
                            child: Text(
                              '没有找到「$q」',
                              style: TextStyle(
                                fontSize: m.sp(11.5),
                                color: HjTheme.muted(context),
                              ),
                            ),
                          )
                        : _grid(m, _results)),
            ),
          ],
        ),
      ),
    );
  }

  List<HjSeries> _hot() {
    final all = <HjSeries>[..._store.allItems]
      ..sort((a, b) => (b.rank ?? 0).compareTo(a.rank ?? 0));
    return all.take(10).toList(growable: false);
  }

  /// 从 crew 字段里抽出高频嘉宾名（"主演: 金美贤、安宥真、李恩智" → 三个人名）
  List<String> _crews() {
    final count = <String, int>{};
    for (final s in _store.allItems) {
      final crew = s.crew ?? '';
      if (crew.isEmpty) continue;
      final body = crew.replaceAll(RegExp(r'^[^:：]*[:：]'), '');
      for (final raw in body.split(RegExp(r'[、,，/]'))) {
        final n = raw.trim();
        if (n.length < 2 || n.length > 6) continue;
        count[n] = (count[n] ?? 0) + 1;
      }
    }
    final list = count.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return list.take(12).map((e) => e.key).toList(growable: false);
  }

  Widget _sectionLabel(HjMetrics m, String text) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: m.pagePadding.horizontal),
      child: Text(
        text,
        style: TextStyle(
          fontSize: m.sp(11.5),
          fontWeight: FontWeight.w800,
          color: ColorScheme.of(context).onSurface,
        ),
      ),
    );
  }

  Widget _chips(HjMetrics m, List<String> items, void Function(String) onTap) {
    return SizedBox(
      height: m.gap(26),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: m.pagePadding.horizontal),
        itemCount: items.length,
        separatorBuilder: (c, i) => SizedBox(width: m.gap(6)),
        itemBuilder: (c, i) {
          final label = items[i];
          return GestureDetector(
            onTap: () => onTap(label),
            child: Container(
              alignment: Alignment.center,
              padding: EdgeInsets.symmetric(horizontal: m.gap(12)),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(m.gap(13)),
                border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: m.sp(10.5),
                  fontWeight: FontWeight.w600,
                  color: ColorScheme.of(context).onSurface,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _empty(HjMetrics m) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.search_rounded,
            size: m.gap(30),
            color: Colors.white.withValues(alpha: 0.12),
          ),
          SizedBox(height: m.gap(9)),
          Text(
            '输入关键词开始搜索',
            style: TextStyle(
              fontSize: m.sp(11.5),
              color: HjTheme.muted(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _grid(HjMetrics m, List<HjSeries> items) {
    return LayoutBuilder(
      builder: (c, cons) {
        final maxW = cons.maxWidth - m.pagePadding.horizontal * 2;
        final cols = (maxW / m.gridCellMin).floor().clamp(2, m.isTv ? 11 : 12);
        return GridView.builder(
          padding: EdgeInsets.fromLTRB(
            m.pagePadding.horizontal,
            m.gap(4),
            m.pagePadding.horizontal,
            m.gap(26),
          ),
          itemCount: items.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            mainAxisSpacing: m.gap(13),
            crossAxisSpacing: m.gap(9),
            childAspectRatio: HjTheme.posterAspect / 1.28,
          ),
          itemBuilder: (c, i) {
            final s = items[i];
            return HjPosterCard(
              series: _store.display(s),
              metrics: m,
              onTap: () => widget.onOpen(s),
            );
          },
        );
      },
    );
  }
}
