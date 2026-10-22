import 'dart:async';
import 'dart:io';

import 'package:PiliPlus/hanju/api.dart';
import 'package:PiliPlus/hanju/playlist_server.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// 逐源体检：看每个源到底有没有视频帧、什么编码、多大分辨率。
///
/// 用途：定位「点了之后一直转圈」——如果 `video-params` 一直是空、
/// 或者编码本机解不了，播放器就永远停在加载态。
Future<void> runCodecProbe() async {
  final dirs = <String>[];
  final env = Platform.environment['HJ_DIRS'];
  if (env != null && env.isNotEmpty) {
    dirs.addAll(env.split(','));
  } else {
    dirs.add(Platform.environment['HJ_DIR'] ??
        '0GzEGBpIQGVGQPHL_QWVZ8pigFsq_w3DdW6Zs9Mw');
  }

  final p = await Player.create(
    configuration: const PlayerConfiguration(
      title: 'HanjuTV',
      logLevel: MPVLogLevel.warn,
    ),
  );
  // 必须建 VideoController：mpv 默认 vo=null，不建的话根本不解视频，
  // video-params 永远为空（这一点误导过一次排查）。
  await VideoController.create(
    p,
    configuration: const VideoControllerConfiguration(
      enableHardwareAcceleration: true,
    ),
  );
  p.stream.log.listen((l) {
    final t = l.text;
    if (t.contains('error') || t.contains('Error') || t.contains('fail')) {
      stdout.writeln('[LOG] ${l.prefix}/${l.level}: $t');
    }
  });
  p.stream.error.listen((e) => stdout.writeln('[ERR] $e'));

  for (final dir in dirs) {
    final sw = Stopwatch()..start();
    stdout.writeln('=== ${dir.substring(0, 10)} ===');
    try {
      final playlist = await HjApi.instance.fetchPlaylist(dir);
      final url = await HjPlaylistServer.instance.publish(dir, playlist);
      await p.open(Media(url.toString()), play: true);

      var vp = '';
      var codec = '';
      var frameMs = -1;
      while (sw.elapsedMilliseconds < 40000) {
        await Future<void>.delayed(const Duration(milliseconds: 300));
        vp = p.getProperty('video-params');
        codec = p.getProperty('video-codec');
        final w = p.state.width;
        if (w > 0 && frameMs < 0) {
          frameMs = sw.elapsedMilliseconds;
        }
        if (frameMs > 0 && vp.isNotEmpty) break;
      }
      stdout.writeln('RESULT ${dir.substring(0, 10)} frameMs=$frameMs '
          'w=${p.state.width} h=${p.state.height} '
          'codec=${codec.isEmpty ? "-" : codec} '
          'pos=${p.state.position.inSeconds}s '
          'vp=${vp.length > 160 ? vp.substring(0, 160) : vp}');
    } catch (e) {
      stdout.writeln('RESULT ${dir.substring(0, 10)} EXC $e');
    }
  }

  await p.dispose();
  HjPlaylistServer.instance.dispose();
  stdout.writeln('DONE');
  await Future<void>.delayed(const Duration(milliseconds: 200));
  exit(0);
}
