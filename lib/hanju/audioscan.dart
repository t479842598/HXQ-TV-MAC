import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:PiliPlus/hanju/api.dart';
import 'package:PiliPlus/hanju/audio_guard.dart';
import 'package:PiliPlus/hanju/playlist_server.dart';
import 'package:media_kit/media_kit.dart';

/// 全量体检：逐个源检查多久能真正出声，找出一律不出声的片源。
///
/// 判据只用 mpv 的 `audio-params`（`track-list` 在本播放器里始终为空，不可用）。
/// 每行输出 `[i/total] VERDICT dir10 ms=N codec=X err=...`。
Future<void> runAudioScan() async {
  final log = StringBuffer();
  void w(String s) {
    log.writeln(s);
    stdout.writeln(s);
  }

  final dirs = <String>[];
  try {
    final raw = await rootBundle.loadString('assets/hanju/playmap.json');
    for (final e in jsonDecode(raw) as List) {
      final d = (e as Map<String, dynamic>)['dir'] as String? ?? '';
      if (d.isNotEmpty) dirs.add(d);
    }
  } catch (e) {
    w('playmap load failed: $e');
  }

  final limit = int.tryParse(Platform.environment['HJ_SCAN_N'] ?? '') ?? 20;
  final total = dirs.length < limit ? dirs.length : limit;
  w('SCAN total=$total of ${dirs.length}');

  final p = await Player.create(
    configuration: const PlayerConfiguration(
      title: 'HanjuTV',
      logLevel: MPVLogLevel.warn,
    ),
  );
  final errs = <String>[];
  p.stream.error.listen(errs.add);

  var bad = 0;
  for (var i = 0; i < total; i++) {
    final dir = dirs[i];
    errs.clear();
    var verdict = 'OK';
    var ms = -1;
    var codec = '-';
    var err = '-';
    final t0 = DateTime.now();
    try {
      final playlist = await HjApi.instance.fetchPlaylist(dir);
      final url = await HjPlaylistServer.instance.publish(dir, playlist);
      await p.open(Media(url.toString()), play: true);

      while (DateTime.now().difference(t0).inMilliseconds < 45000) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
        if (HjAudioGuard.hasAudio(p)) {
          ms = DateTime.now().difference(t0).inMilliseconds;
          break;
        }
      }
      codec = p.getProperty('audio-codec-name');
      if (codec.isEmpty) codec = '-';
      if (ms < 0) {
        verdict = 'NO_AUDIO';
        bad++;
      }
      if (errs.isNotEmpty) err = errs.first;
    } catch (e) {
      verdict = 'ERR';
      bad++;
      err = '$e';
    }
    w('[${i + 1}/$total] $verdict ${dir.substring(0, 10)} '
        'ms=$ms codec=$codec err=$err');
  }

  await p.dispose();
  HjPlaylistServer.instance.dispose();
  w('DONE bad=$bad total=$total');
  final f = File('${Directory.systemTemp.path}/hj_audioscan.log');
  try {
    await f.writeAsString(log.toString());
    w('LOG=${f.path}');
  } catch (_) {}
  await Future<void>.delayed(const Duration(milliseconds: 200));
  exit(0);
}
