import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:PiliPlus/hanju/api.dart';
import 'package:PiliPlus/hanju/parallel_http.dart';
import 'package:PiliPlus/hanju/playlist_server.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// 全量首帧体检。
///
/// 每个源独立 Player + VideoController，用完立即 dispose。
/// 教训：
///  1) 复用同一个 Player 时第 4 个源之后 videoParams 再也不发（VideoController
///     在 player.stop() 之后不再重建 vo），表现为连续 timeout —— 必须逐源重建。
///  2) 逐源重建但**不 dispose** 会泄漏原生资源，第 5 个源后进程静默退出。
///  3) 判据用新建 player 的 state.width > 0 轮询（新 player 不会有残留值）。
Future<void> runFrameScan() async {
  final from = int.tryParse(Platform.environment['HJ_SCAN_FROM'] ?? '') ?? 0;
  final limit = int.tryParse(Platform.environment['HJ_SCAN_N'] ?? '') ?? 999;
  final budget =
      int.tryParse(Platform.environment['HJ_SCAN_BUDGET'] ?? '') ?? 45000;

  final dirs = <String>[];
  final names = <String, String>{};
  try {
    final raw = await rootBundle.loadString('assets/hanju/playmap.json');
    for (final e in jsonDecode(raw) as List) {
      final m = e as Map<String, dynamic>;
      final d = m['dir'] as String? ?? '';
      if (d.isEmpty) continue;
      if (!dirs.contains(d)) {
        dirs.add(d);
        names[d] = (m['name'] ?? '') as String;
      }
    }
  } catch (e) {
    stdout.writeln('playmap load failed: $e');
  }

  final slice = dirs.skip(from).take(limit).toList();
  stdout.writeln('FRAME total=${dirs.length} from=$from n=${slice.length}');

  var ok = 0;
  var fail = 0;
  final failList = <String>[];

  for (var i = 0; i < slice.length; i++) {
    final dir = slice[i];
    final tag =
        '${from + i + 1}/${dirs.length} ${names[dir] ?? dir.substring(0, 8)}';
    final sw = Stopwatch()..start();
    var frameMs = -1;
    var w = 0;
    Player? player;
    try {
      // 换源前丢掉上一条源残留的连接池，否则复用死连接会把首帧拖到 45s+。
      HjParallel.reset();
      final playlist = await HjApi.instance.fetchPlaylist(dir);
      final url = await HjPlaylistServer.instance.publish(dir, playlist);
      player = await Player.create(
        configuration: const PlayerConfiguration(
          title: 'HanjuTV',
          logLevel: MPVLogLevel.error,
        ),
      );
      // 必须建 VideoController：mpv 默认 vo=null，不建根本不解视频。
      await VideoController.create(
        player,
        configuration: const VideoControllerConfiguration(
          enableHardwareAcceleration: true,
        ),
      );
      await player.open(Media(url.toString()), play: true);
      while (sw.elapsedMilliseconds < budget) {
        final pw = player.state.width;
        if (pw > 0) {
          frameMs = sw.elapsedMilliseconds;
          w = pw;
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 120));
      }
      if (frameMs > 0) {
        ok++;
        stdout.writeln('OK   $tag frameMs=$frameMs w=$w');
      } else {
        fail++;
        failList.add(dir);
        stdout.writeln('FAIL $tag timeout ${budget}ms');
      }
    } catch (e) {
      fail++;
      failList.add(dir);
      stdout.writeln('FAIL $tag EX $e');
    } finally {
      // PlatformVideoController 没有 dispose()（只有 Player 有），
      // 释放顺序：先 stop 再 dispose player，控制器随 player 一起释放。
      try {
        await player?.stop();
      } catch (_) {}
      try {
        await player?.dispose();
      } catch (_) {}
      player = null;
    }
  }

  stdout.writeln('FRAME DONE ok=$ok fail=$fail');
  if (failList.isNotEmpty) stdout.writeln('FAILED_DIRS ${failList.join(",")}');
  HjPlaylistServer.instance.dispose();
  await Future<void>.delayed(const Duration(milliseconds: 400));
  exit(0);
}
