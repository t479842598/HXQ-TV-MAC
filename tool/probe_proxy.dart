import 'dart:io';

import 'package:PiliPlus/hanju/api.dart';
import 'package:PiliPlus/hanju/parallel_http.dart';
import 'package:PiliPlus/hanju/playlist_server.dart';

Future<void> main(List<String> args) async {
  final dir = args.isNotEmpty
      ? args.first
      : '0GzEGBpIQGVGQPHL_QWVZ8pigFsq_w3DdW6Zs9Mw';
  final t0 = DateTime.now();
  final playlist = await HjApi.instance.fetchPlaylist(dir);
  final t1 = DateTime.now();
  print('manifest ${playlist.length}B in ${t1.difference(t0).inMilliseconds}ms');

  final url = await HjPlaylistServer.instance.publish(dir, playlist);
  print('local url: $url');
  final segs = HjPlaylistServer.instance.rewrite(dir, playlist).segments;
  print('segments: ${segs.length}, first=${segs.first}');

  final client = HttpClient();
  for (var i = 0; i < 4; i++) {
    final s = DateTime.now();
    final req = await client.getUrl(
        Uri.parse('${HjPlaylistServer.instance.baseUrl}/${segs[i]}'));
    final resp = await req.close();
    var n = 0;
    await for (final c in resp) {
      n += c.length;
    }
    final el = DateTime.now().difference(s).inMilliseconds;
    print('seg $i: $n B in ${el}ms = ${(n / (el / 1000) / 1024).toStringAsFixed(0)} KB/s');
  }
  HjPlaylistServer.instance.dispose();
  client.close(force: true);
  print('done');
}
