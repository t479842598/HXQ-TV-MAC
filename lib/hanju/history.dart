import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

/// 一条观看记录。key 由 sid + serialNo 决定，同一集反复观看只保留最新进度。
class HjHistoryEntry {
  final String sid;
  final String seriesName;
  final int serialNo;
  final String epTitle;
  final String dir;
  final String? poster;
  final int positionMs;
  final int durationMs;
  final int updatedAtMs;

  const HjHistoryEntry({
    required this.sid,
    required this.seriesName,
    required this.serialNo,
    required this.epTitle,
    required this.dir,
    this.poster,
    required this.positionMs,
    required this.durationMs,
    required this.updatedAtMs,
  });

  String get id => '$sid#$serialNo';

  double get progress {
    if (durationMs <= 0) return 0;
    final p = positionMs / durationMs;
    return p.isFinite ? p.clamp(0.0, 1.0) : 0.0;
  }

  String get positionText => _fmt(positionMs);
  String get durationText => _fmt(durationMs);

  static String _fmt(int ms) {
    final total = (ms / 1000).round();
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    final s = total % 60;
    String two(int v) => v.toString().padLeft(2, '0');
    return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'sid': sid,
    'seriesName': seriesName,
    'serialNo': serialNo,
    'epTitle': epTitle,
    'dir': dir,
    'poster': poster,
    'positionMs': positionMs,
    'durationMs': durationMs,
    'updatedAtMs': updatedAtMs,
  };

  factory HjHistoryEntry.fromJson(Map<String, dynamic> j) => HjHistoryEntry(
    sid: j['sid'] as String? ?? '',
    seriesName: j['seriesName'] as String? ?? '',
    serialNo: (j['serialNo'] as num?)?.toInt() ?? 0,
    epTitle: j['epTitle'] as String? ?? '',
    dir: j['dir'] as String? ?? '',
    poster: j['poster'] as String?,
    positionMs: (j['positionMs'] as num?)?.toInt() ?? 0,
    durationMs: (j['durationMs'] as num?)?.toInt() ?? 0,
    updatedAtMs: (j['updatedAtMs'] as num?)?.toInt() ?? 0,
  );
}

/// 观看历史 + 进度续播，独立于 PiliPlus 自己的 watchProgress（键空间完全不同，
/// 不能混用同一个 Hive box）。落盘 JSON，避免引入额外依赖。
class HjHistory extends ChangeNotifier {
  HjHistory._();
  static final HjHistory instance = HjHistory._();

  static const int _maxEntries = 200;

  final List<HjHistoryEntry> _entries = <HjHistoryEntry>[];
  File? _file;

  List<HjHistoryEntry> get entries => List.unmodifiable(_entries);

  /// 继续观看：每部剧只留最新一集，进度 1%~99%
  List<HjHistoryEntry> get continueWatching {
    final seen = <String>{};
    final out = <HjHistoryEntry>[];
    for (final e in _entries) {
      if (e.progress <= 0.01 || e.progress >= 0.99) continue;
      if (seen.add(e.sid)) out.add(e);
      if (out.length >= 12) break;
    }
    return out;
  }

  Future<void> init() async {
    final f = await _resolveFile();
    _file = f;
    if (!f.existsSync()) return;
    try {
      final raw = await f.readAsString();
      final list = jsonDecode(raw);
      if (list is! List) return;
      _entries
        ..clear()
        ..addAll(
          list
              .whereType<Map<String, dynamic>>()
              .map(HjHistoryEntry.fromJson),
        );
      _entries.sort((a, b) => b.updatedAtMs.compareTo(a.updatedAtMs));
      notifyListeners();
    } catch (e) {
      debugPrint('HjHistory load failed: $e');
    }
  }

  HjHistoryEntry? entry(String sid, int serialNo) {
    final key = '$sid#$serialNo';
    for (final e in _entries) {
      if (e.id == key) return e;
    }
    return null;
  }

  /// 只在已观看超过 8 秒、且距结尾超过 20 秒时才返回续播位置
  int? resumePosition(String sid, int serialNo) {
    final e = entry(sid, serialNo);
    if (e == null) return null;
    if (e.positionMs < 8000) return null;
    if (e.durationMs > 0 && e.durationMs - e.positionMs < 20000) return null;
    return e.positionMs;
  }

  void record({
    required String sid,
    required String seriesName,
    required int serialNo,
    required String epTitle,
    required String dir,
    String? poster,
    required int positionMs,
    required int durationMs,
  }) {
    final e = HjHistoryEntry(
      sid: sid,
      seriesName: seriesName,
      serialNo: serialNo,
      epTitle: epTitle,
      dir: dir,
      poster: poster,
      positionMs: positionMs,
      durationMs: durationMs,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    final idx = _entries.indexWhere((x) => x.id == e.id);
    if (idx >= 0) {
      final old = _entries[idx];
      // 进度不倒退（除非用户重新从头开始播）
      final keepOld = old.positionMs > positionMs && durationMs > 0 &&
          positionMs < durationMs - 5000 && old.progress > 0.97;
      _entries[idx] = keepOld
          ? HjHistoryEntry(
              sid: old.sid,
              seriesName: old.seriesName,
              serialNo: old.serialNo,
              epTitle: old.epTitle,
              dir: old.dir,
              poster: old.poster,
              positionMs: old.positionMs,
              durationMs: old.durationMs,
              updatedAtMs: e.updatedAtMs,
            )
          : e;
    } else {
      _entries.insert(0, e);
    }
    _entries.sort((a, b) => b.updatedAtMs.compareTo(a.updatedAtMs));
    while (_entries.length > _maxEntries) {
      _entries.removeLast();
    }
    notifyListeners();
    _persist();
  }

  void remove(String id) {
    _entries.removeWhere((e) => e.id == id);
    notifyListeners();
    _persist();
  }

  void clear() {
    _entries.clear();
    notifyListeners();
    _persist();
  }

  Future<File> _resolveFile() async {
    final home = Platform.environment['HOME'] ?? '.';
    final dir = Directory(path.join(home, 'Library', 'Application Support', 'HanjuTV'));
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return File(path.join(dir.path, 'history.json'));
  }

  void _persist() {
    final f = _file;
    if (f == null) return;
    final data = jsonEncode(_entries.map((e) => e.toJson()).toList());
    // 写盘不阻塞 UI
    Future<void>(() async {
      try {
        await f.writeAsString(data, flush: true);
      } catch (e) {
        debugPrint('HjHistory persist failed: $e');
      }
    });
  }
}
