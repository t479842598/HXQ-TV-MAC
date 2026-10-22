import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:PiliPlus/hanju/api.dart';
import 'package:PiliPlus/hanju/playlist_server.dart';
import 'package:media_kit/media_kit.dart';

/// 复现「部分视频没有声音」：模拟用户反复进出播放页，
/// 每轮新建一个 Player（旧的不 await dispose），观察第几个开始 ao 失败。
///
/// 触发：HJ_AUDIOSTRESS=1，HJ_STRESS_N=轮数（默认 10）。
Future<void> runAudioStress() async {
  final log = StringBuffer();
  void w(String s) {
    log.writeln(s);
    stdout.writeln(s);
  }

  final n = int.tryParse(Platform.environment['HJ_STRESS_N'] ?? '') ?? 10;
  final dirs = <String>[];
  try {
    final raw = await rootBundle.loadString('assets/hanju/playmap.json');
    final list = jsonDecode(raw) as List;
    for (final e in list) {
      final m = e as Map<String, dynamic>;
      final d = m['dir'] as String? ?? '';
      if (d.isNotEmpty) dirs.add(d);
    }
  } catch (e) {
    w('playmap load failed: $e');
  }
  w('STRESS dirs=${dirs.length} rounds=$n');

  final keepAlive = <Player>[];

  for (var i = 0; i < n; i++) {
    final dir = dirs[i % dirs.length];
    final errors = <String>[];
    Player? p;
    try {
      p = await Player.create(
        configuration: const PlayerConfiguration(
          title: 'HanjuTV',
          logLevel: MPVLogLevel.warn,
        ),
      );
      final sub = p.stream.error.listen(errors.add);
      final playlist = await HjApi.instance.fetchPlaylist(dir);
      final url = await HjPlaylistServer.instance.publish(dir, playlist);
      await p.open(Media(url.toString()), play: true);

      final deadline = DateTime.now().add(const Duration(seconds: 15));
      while (DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        if (p.state.position.inSeconds >= 1) break;
      }
      await Future<void>.delayed(const Duration(seconds: 1));
      final ap = p.state.audioParams;
      w('[round $i] pos=${p.state.position.inSeconds}s '
          'audio=${ap.channelCount}ch/${ap.sampleRate}Hz '
          'err=${errors.isEmpty ? "-" : errors.first}');
      await sub.cancel();
      // 模拟用户返回上一页：dispose 但不 await（和当前 player_page 一致）
      unawaited(p.dispose());
      keepAlive.add(p);
    } catch (e) {
      w('[round $i] EXC $e');
    }
  }

  w('DONE alivePlayers=${keepAlive.length}');
  HjPlaylistServer.instance.dispose();
  final f = File('${Directory.systemTemp.path}/hj_audiostress.log');
  try {
    await f.writeAsString(log.toString());
    w('LOG=${f.path}');
  } catch (_) {}
  await Future<void>.delayed(const Duration(milliseconds: 300));
  exit(0);
}
