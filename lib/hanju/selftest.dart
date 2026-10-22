import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;

import 'package:PiliPlus/hanju/api.dart';
import 'package:PiliPlus/hanju/playlist_server.dart';
import 'package:media_kit/media_kit.dart';

/// 端到端播放自检：真实 CDN → 本机并发代理 → libmpv 解码。
///
/// 只在设置了环境变量 HJ_SELFTEST=1 时由 main() 调用，
/// 结果写到 /tmp/hj_selftest.log 后直接退出进程。
Future<void> runPlaybackSelfTest() async {
  final log = StringBuffer();
  void w(String s) {
    log.writeln(s);
    stdout.writeln(s);
  }

  final logFile = File('${Directory.systemTemp.path}/hj_selftest.log');
  Future<void> flush() async {
    try {
      await logFile.writeAsString(log.toString());
      stdout.writeln('LOG=${logFile.path}');
    } catch (_) {}
  }

  Player? player;
  try {
    // 1) 取一个已知播放目录
    String dir = Platform.environment['HJ_DIR'] ?? '';
    if (dir.isEmpty) {
      final raw = await rootBundle.loadString('assets/hanju/playmap.json');
      final list = jsonDecode(raw) as List;
      dir = (list.first as Map<String, dynamic>)['dir'] as String;
    }
    w('DIR=$dir');

    // 2) 拉清单（并发分段）
    final t0 = DateTime.now();
    final playlist = await HjApi.instance.fetchPlaylist(dir);
    final ms = DateTime.now().difference(t0).inMilliseconds;
    w('MANIFEST ok bytes=${playlist.length} in ${ms}ms');

    // 3) 起本机代理（验证沙盒 network.server）
    final url = await HjPlaylistServer.instance.publish(dir, playlist);
    w('PROXY url=$url port=${HjPlaylistServer.instance.port}');

    // 4) libmpv 真实播放
    player = await Player.create(
      configuration: const PlayerConfiguration(
        title: 'HanjuTV',
        logLevel: MPVLogLevel.warn,
      ),
    );
    final errSub = player.stream.error.listen((e) => w('MPV_ERROR $e'));
    final logSub = player.stream.log.listen((e) {
      final t = e.text.trim();
      if (t.isNotEmpty &&
          (t.contains('ao') ||
              t.contains('audio') ||
              t.contains('Audio') ||
              t.contains('device') ||
              t.contains('codec'))) {
        w('MPV_LOG $t');
      }
    });
    final audioSub =
        player.stream.audioParams.listen((p) => w('AUDIO_PARAMS $p'));
    final t1 = DateTime.now();
    await player.open(Media(url.toString()), play: true);

    final deadline = DateTime.now().add(const Duration(seconds: 75));
    var lastPos = Duration.zero;
    var stalls = 0;
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      final s = player.state;
      if (s.position != lastPos) {
        lastPos = s.position;
        stalls = 0;
      } else if (s.position > Duration.zero) {
        stalls++;
      }
      if (s.position.inSeconds >= 20) break;
    }
    final s = player.state;
    final el = DateTime.now().difference(t1).inMilliseconds / 1000;
    w('PLAY pos=${s.position.inSeconds}s dur=${s.duration.inSeconds}s '
        'size=${s.width}x${s.height} buffering=${s.buffering} '
        'stallSamples=$stalls elapsed=${el.toStringAsFixed(1)}s');
    w('AUDIO state=${s.audioParams}');
    w(s.position.inSeconds >= 10
        ? 'RESULT PASS'
        : 'RESULT FAIL position too small');

    await errSub.cancel();
    await logSub.cancel();
    await audioSub.cancel();
  } catch (e, st) {
    w('RESULT FAIL $e');
    w(st.toString());
  } finally {
    try {
      await player?.dispose();
    } catch (_) {}
    HjPlaylistServer.instance.dispose();
    await flush();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    exit(0);
  }
}
