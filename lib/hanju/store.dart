import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:PiliPlus/hanju/api.dart';
import 'package:PiliPlus/hanju/models.dart';

/// 全部内容状态：离线目录 + 播放源索引 + 实时详情缓存。
///
/// 目录（catalog.json）与播放源索引（playmap.json）随包内置，
/// 详情必须实时拉，因为海报/缩略图签名有时效。
class HjStore extends ChangeNotifier {
  HjStore._();
  static final HjStore instance = HjStore._();

  HjCatalog? _catalog;
  final Map<String, String> _playMap = <String, String>{}; // 'sid#serialNo' -> dir
  final Map<String, List<String>> _playMapBySid = <String, List<String>>{};
  final Map<String, HjDetailResponse> _details = <String, HjDetailResponse>{};
  final Map<String, HjLoadState> _detailState = <String, HjLoadState>{};

  bool _booted = false;
  bool _refreshing = false;
  int _refreshed = 0;

  HjCatalog? get catalog => _catalog;
  List<HjBlock> get blocks => _catalog?.blocks ?? const <HjBlock>[];
  bool get booted => _booted;
  bool get refreshing => _refreshing;
  int get refreshedCount => _refreshed;
  int get playMapCount => _playMap.length;

  List<HjSeries> get allItems => _catalog?.allItems ?? const <HjSeries>[];

  HjDetailResponse? detail(String sid) => _details[sid];
  HjLoadState state(String sid) =>
      _detailState[sid] ?? HjLoadState.idle;

  /// 本地播放源数量（用于详情页「本地已收录 N 集」）
  int playCount(String sid) => _playMapBySid[sid]?.length ?? 0;

  /// 精确取某集的播放目录，取不到退回同剧任意一集
  String? playDir(String sid, int serialNo) {
    final exact = _playMap['$sid#$serialNo'];
    if (exact != null) return exact;
    final list = _playMapBySid[sid];
    if (list == null || list.isEmpty) return null;
    return list.first;
  }

  Future<void> bootstrap() async {
    if (_booted) return;
    await _loadCatalog();
    await _loadPlayMap();
    _booted = true;
    notifyListeners();
    unawaited(refreshAll());
  }

  Future<void> _loadCatalog() async {
    try {
      final raw = await rootBundle.loadString('assets/hanju/catalog.json');
      final json = jsonDecode(raw) as Map<String, dynamic>;
      _catalog = HjCatalog.fromJson(json);
    } catch (e) {
      debugPrint('HjStore catalog load failed: $e');
      _catalog = const HjCatalog(<HjBlock>[]);
    }
  }

  Future<void> _loadPlayMap() async {
    try {
      final raw = await rootBundle.loadString('assets/hanju/playmap.json');
      final list = jsonDecode(raw) as List;
      _playMap.clear();
      _playMapBySid.clear();
      for (final e in list) {
        final entry = HjPlayMapEntry.fromJson(e as Map<String, dynamic>);
        if (entry.dir.isEmpty) continue;
        _playMap['${entry.sid}#${entry.serialNo}'] = entry.dir;
        _playMapBySid.putIfAbsent(entry.sid, () => <String>[]).add(entry.dir);
      }
    } catch (e) {
      debugPrint('HjStore playmap load failed: $e');
    }
  }

  /// 并发刷新全部详情（窗口 8，块间串行，避免一次性打满连接）
  Future<void> refreshAll() async {
    if (_refreshing) return;
    final items = allItems;
    if (items.isEmpty) return;
    _refreshing = true;
    _refreshed = 0;
    notifyListeners();
    const window = 8;
    var i = 0;
    while (i < items.length) {
      final end = (i + window) < items.length ? i + window : items.length;
      final chunk = items.sublist(i, end);
      await Future.wait(chunk.map((s) async {
        try {
          await loadDetail(s.sid);
          _refreshed++;
        } catch (_) {
          // 单条失败不影响整批
        }
      }));
      i = end;
      notifyListeners();
    }
    _refreshing = false;
    notifyListeners();
  }

  Future<HjDetailResponse?> loadDetail(String sid, {bool force = false}) async {
    final cached = _details[sid];
    if (cached != null && !force) return cached;
    if (_detailState[sid] == HjLoadState.loading) return null;
    _detailState[sid] = HjLoadState.loading;
    notifyListeners();
    try {
      final res = await HjApi.instance.fetchDetail(sid);
      _details[sid] = res;
      _detailState[sid] = HjLoadState.loaded;
      notifyListeners();
      return res;
    } catch (e) {
      debugPrint('HjStore detail $sid failed: $e');
      _detailState[sid] = HjLoadState.failed;
      notifyListeners();
      return null;
    }
  }

  /// 合并目录静态字段与详情实时字段（封面换新签名、期数、评分）
  HjSeries display(HjSeries item) {
    final info = _details[item.sid]?.series;
    if (info == null) return item;
    return item.copyWith(
      name: info.name.isEmpty ? null : info.name,
      rank: info.rank,
      thumb: info.thumb,
      poster: info.poster,
      crew: info.crew,
      shorthand: info.shorthand,
    );
  }

}

void unawaited(Future<void> future) {
  future.catchError((Object e) {
    debugPrint('HjStore unawaited error: $e');
  });
}
