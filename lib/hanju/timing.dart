import 'dart:async';
import 'dart:io';

import 'package:PiliPlus/hanju/api.dart';
import 'package:PiliPlus/hanju/audio_guard.dart';
import 'package:PiliPlus/hanju/parallel_http.dart';
import 'package:PiliPlus/hanju/playlist_server.dart';
import 'package:PiliPlus/hanju/segment_auth.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// 逐段计时：找出「点了之后一直转圈」到底卡在哪一步。
Future<void> runTiming() async {
  final dir = Platform.environment['HJ_DIR'] ??
      '0GzEGBpIQGVGQPHL_QWVZ8pigFsq_w3DdW6Zs9Mw';
  final sid = Platform.environment['HJ_SID'] ?? '8P29P8kA5Z15xrOcB2GmV';

  final sw = Stopwatch()..start();
  void mark(String s) {
    stdout.writeln('[T] ${sw.elapsedMilliseconds}ms $s');
  }

  // 0) 详情接口
  try {
    final d = await HjApi.instance.fetchDetail(sid);
    mark('detail ok eps=${d.playItems.length} series=${d.series?.name}');
  } catch (e) {
    mark('detail FAIL $e');
  }

  // 1) 清单
  sw.reset();
  final uri = Uri.parse('$hjCdnHost/m3u8/$dir.m3u8?$hjSegmentAuth');
  final bytes = await HjParallel.fetch(uri);
  mark('manifest bytes=${bytes.length}');

  // 2) 清单里第一段
  final text = String.fromCharCodes(bytes);
  final lines = text.split('\n');
  final segs = lines
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty && !l.startsWith('#'))
      .toList();
  mark('segments=${segs.length} first=${segs.isEmpty ? "-" : segs.first}');

  if (segs.isNotEmpty) {
    sw.reset();
    final segUri = Uri.parse('$hjCdnHost${segs.first}?$hjSegmentAuth');
    final seg = await HjParallel.fetch(segUri);
    mark('segment0 bytes=${seg.length}');
  }

  // 3) 走本机代理 + 播放器，测首帧与首音
  sw.reset();
  final url = await HjPlaylistServer.instance.publish(dir, text);
  mark('publish $url');

  final p = await Player.create(
    configuration: const PlayerConfiguration(
      title: 'HanjuTV',
      logLevel: MPVLogLevel.warn,
    ),
  );
  // 不建 VideoController 时 mpv 的 vo=null，不解视频，video-params 永远空。
  await VideoController.create(
    p,
    configuration: const VideoControllerConfiguration(
      enableHardwareAcceleration: true,
    ),
  );
  var firstFrame = -1;
  var firstAudio = -1;
  p.stream.videoParams.listen((v) {
    final w = v.w ?? 0;
    if (w > 0 && firstFrame < 0) {
      firstFrame = sw.elapsedMilliseconds;
      stdout.writeln('[T] ${sw.elapsedMilliseconds}ms FIRST_FRAME ${w}px');
    }
  });
  p.stream.error.listen((e) => stdout.writeln('[T] ERR $e'));

  await p.open(Media(url.toString()), play: true);
  while (sw.elapsedMilliseconds < 60000) {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (firstAudio < 0 && HjAudioGuard.hasAudio(p)) {
      firstAudio = sw.elapsedMilliseconds;
      stdout.writeln('[T] ${sw.elapsedMilliseconds}ms FIRST_AUDIO');
    }
    if (firstFrame > 0 && firstAudio > 0) break;
  }
  mark('pos=${p.state.position.inSeconds}s dur=${p.state.duration.inSeconds}s '
      'playing=${p.state.playing}');

  await p.dispose();
  HjPlaylistServer.instance.dispose();
  mark('DONE');
  await Future<void>.delayed(const Duration(milliseconds: 200));
  exit(0);
}
