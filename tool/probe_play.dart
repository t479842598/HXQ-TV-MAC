import 'dart:io';

import 'package:PiliPlus/hanju/api.dart';
import 'package:PiliPlus/hanju/playlist_server.dart';

/// 模拟播放器连续拉 12 个分片，验证本机代理能否稳定跑赢码率（~96 KB/s）。
Future<void> main(List<String> args) async {
  final dir = args.isNotEmpty
      ? args.first
      : '0GzEGBpIQGVGQPHL_QWVZ8pigFsq_w3DdW6Zs9Mw';
  final playlist = await HjApi.instance.fetchPlaylist(dir);
  final url = await HjPlaylistServer.instance.publish(dir, playlist);
  final segs = HjPlaylistServer.instance.rewrite(dir, playlist).segments;
  print('manifest ok, segs=${segs.length}, local=$url');

  final client = HttpClient()..maxConnectionsPerHost = 4;
  var totalBytes = 0;
  final t0 = DateTime.now();
  for (var i = 0; i < 12; i++) {
    final s = DateTime.now();
    final req = await client
        .getUrl(Uri.parse('${HjPlaylistServer.instance.baseUrl}/${segs[i]}'));
    final resp = await req.close();
    var n = 0;
    await for (final c in resp) {
      n += c.length;
    }
    totalBytes += n;
    final ms = DateTime.now().difference(s).inMilliseconds;
    print('seg $i: $n B / ${ms}ms');
  }
  final el = DateTime.now().difference(t0).inMilliseconds / 1000;
  print('TOTAL $totalBytes B in ${el.toStringAsFixed(1)}s = '
      '${(totalBytes / el / 1024).toStringAsFixed(0)} KB/s (bitrate need 96 KB/s)');
  HjPlaylistServer.instance.dispose();
  client.close(force: true);
}
