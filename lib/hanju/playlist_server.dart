import 'dart:async';
import 'dart:io';

import 'package:PiliPlus/hanju/segment_auth.dart';

/// 本地微服务器：把 CDN 的 master m3u8 重写成「绝对地址分片 + ENDLIST」的
/// 点播清单，让播放器拿到完整时长并可拖动；分片本身仍直连 CDN，
/// 不经过本机中转（避免本地带宽成为瓶颈）。
class HjPlaylistServer {
  HjPlaylistServer._();
  static final HjPlaylistServer instance = HjPlaylistServer._();

  HttpServer? _server;
  int _port = 0;
  final Map<String, String> _routes = <String, String>{};

  int get port => _port;
  String get baseUrl => 'http://127.0.0.1:$_port';

  Future<void> ensureStarted() async {
    if (_server != null) return;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _port = server.port;
    _server = server;
    server.listen(_handle, onError: (_) {});
  }

  void _handle(HttpRequest req) {
    final key = req.uri.path.startsWith('/')
        ? req.uri.path.substring(1)
        : req.uri.path;
    final body = _routes[key];
    if (body == null) {
      req.response.statusCode = HttpStatus.notFound;
      req.response.close();
      return;
    }
    req.response.headers.contentType =
        ContentType('application', 'vnd.apple.mpegurl', charset: 'utf-8');
    req.response.headers.set('Access-Control-Allow-Origin', '*');
    req.response.write(body);
    req.response.close();
  }

  /// 注册一份清单，返回给播放器使用的本地 URL
  Future<Uri> publish(String dir, String playlist) async {
    await ensureStarted();
    final rewritten = rewrite(playlist);
    final key = 'p_${dir.substring(0, dir.length < 12 ? dir.length : 12)}_'
        '${rewritten.hashCode.toUnsigned(32).toRadixString(16)}.m3u8';
    _routes[key] = rewritten;
    return Uri.parse('$baseUrl/$key');
  }

  /// 分片改成带签名的绝对 URL，并补 ENDLIST 让播放器当点播处理
  String rewrite(String playlist) {
    final out = <String>[];
    for (final raw in playlist.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) {
        out.add(raw);
        continue;
      }
      if (line.startsWith('#EXT-X-ENDLIST')) continue;
      if (line.startsWith('/m3u8/')) {
        out.add('$hjCdnHost$line?$hjSegmentAuth');
      } else if (line.startsWith('http')) {
        out.add(line.contains('?')
            ? '$line&$hjSegmentAuth'
            : '$line?$hjSegmentAuth');
      } else {
        out.add(raw);
      }
    }
    if (!out.any((l) => l.startsWith('#EXT-X-ENDLIST'))) {
      out.add('#EXT-X-ENDLIST');
    }
    return out.join('\n');
  }
}
