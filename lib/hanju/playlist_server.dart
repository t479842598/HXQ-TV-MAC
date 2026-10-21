import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'package:PiliPlus/hanju/parallel_http.dart';
import 'package:PiliPlus/hanju/segment_auth.dart';

/// 本地 HLS 微服务。
///
/// 背景：CDN（火山引擎 Byte-nginx）对**单条 TCP 连接**硬限速到 ~850 B/s，
/// 但并发连接可线性叠加（实测 300 并发 ≈ 176~218 KB/s，而流码率仅 ~96 KB/s）。
/// 所以这里不再让播放器直连 CDN，而是：
///   1. 把 master m3u8 重写成指向本机的地址；
///   2. 播放器请求分片时，本机用 [HjParallel] 分段并发拉完再吐给它；
///   3. 顺带预取后两个分片，保证播放不卡。
class HjPlaylistServer {
  HjPlaylistServer._();
  static final HjPlaylistServer instance = HjPlaylistServer._();

  static const int _cacheBytes = 96 * 1024 * 1024;
  static const int _prefetch = 2;

  HttpServer? _server;
  int _port = 0;

  /// 路由：本地 path -> 远端 CDN path（不含 host）
  final Map<String, String> _routes = <String, String>{};
  final LinkedHashMap<String, Uint8List> _segCache = LinkedHashMap<String, Uint8List>();
  final Map<String, Future<Uint8List>> _inflight = <String, Future<Uint8List>>{};
  int _cacheSize = 0;

  int get port => _port;
  String get baseUrl => 'http://127.0.0.1:$_port';

  Future<void> ensureStarted() async {
    if (_server != null) return;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _port = server.port;
    _server = server;
    server.listen(_handle, onError: (_) {});
  }

  void dispose() {
    _server?.close(force: true);
    _server = null;
    _routes.clear();
    _segCache.clear();
    _inflight.clear();
    _cacheSize = 0;
  }

  Future<void> _handle(HttpRequest req) async {
    try {
      final path = req.uri.path;
      if (path.endsWith('.m3u8')) {
        await _servePlaylist(req, path);
      } else {
        await _serveSegment(req, path);
      }
    } catch (e) {
      try {
        req.response.statusCode = HttpStatus.badGateway;
        req.response.headers.contentType = ContentType.text;
        req.response.write('proxy error: $e');
        await req.response.close();
      } catch (_) {}
    }
  }

  Future<void> _servePlaylist(HttpRequest req, String path) async {
    final key = path.startsWith('/') ? path.substring(1) : path;
    final body = _routes[key];
    if (body == null) {
      req.response.statusCode = HttpStatus.notFound;
      await req.response.close();
      return;
    }
    req.response.headers.contentType =
        ContentType('application', 'vnd.apple.mpegurl', charset: 'utf-8');
    req.response.headers.set('Access-Control-Allow-Origin', '*');
    req.response.headers.set('Cache-Control', 'no-store');
    req.response.write(body);
    await req.response.close();
  }

  Future<void> _serveSegment(HttpRequest req, String path) async {
    final key = path.startsWith('/') ? path.substring(1) : path;
    final remotePath = _routes[key];
    if (remotePath == null) {
      req.response.statusCode = HttpStatus.notFound;
      await req.response.close();
      return;
    }
    Uint8List data;
    try {
      data = await _loadSegment(key, remotePath);
    } catch (e) {
      req.response.statusCode = HttpStatus.badGateway;
      await req.response.close();
      return;
    }

    final range = req.headers.value(HttpHeaders.rangeHeader);
    if (range != null && range.startsWith('bytes=')) {
      final spec = range.substring(6).split(',').first.trim();
      final dash = spec.indexOf('-');
      var start = dash <= 0 ? 0 : (int.tryParse(spec.substring(0, dash)) ?? 0);
      var end = dash < 0 || dash == spec.length - 1
          ? data.length - 1
          : (int.tryParse(spec.substring(dash + 1)) ?? data.length - 1);
      if (start >= data.length) {
        req.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        await req.response.close();
        return;
      }
      if (end >= data.length) end = data.length - 1;
      req.response.statusCode = HttpStatus.partialContent;
      req.response.headers.set(
          HttpHeaders.contentRangeHeader, 'bytes $start-$end/${data.length}');
      req.response.headers.contentLength = end - start + 1;
      req.response.add(data.sublist(start, end + 1));
      await req.response.close();
      return;
    }

    req.response.headers.contentType = ContentType('video', 'mp2t');
    req.response.headers.set('Access-Control-Allow-Origin', '*');
    req.response.headers.set('Cache-Control', 'no-store');
    req.response.headers.contentLength = data.length;
    req.response.add(data);
    await req.response.close();
  }

  Future<Uint8List> _loadSegment(String key, String remotePath) {
    final cached = _segCache.remove(key);
    if (cached != null) {
      _segCache[key] = cached;
      return Future<Uint8List>.value(cached);
    }
    final running = _inflight[key];
    if (running != null) return running;

    final future = HjParallel.fetch(
      Uri.parse('$hjCdnHost$remotePath?$hjSegmentAuth'),
      ua: 'tdc.8360',
    ).then((bytes) {
      _remember(key, bytes);
      return bytes;
    }).whenComplete(() {
      _inflight.remove(key);
    });
    _inflight[key] = future;
    return future;
  }

  void _remember(String key, Uint8List bytes) {
    if (bytes.length > _cacheBytes) return;
    _segCache[key] = bytes;
    _cacheSize += bytes.length;
    while (_cacheSize > _cacheBytes && _segCache.isNotEmpty) {
      final oldest = _segCache.keys.first;
      final v = _segCache.remove(oldest);
      if (v != null) _cacheSize -= v.length;
    }
  }

  /// 预取后 [n] 个分片（不阻塞，失败静默）
  void _warm(List<String> keys, int from) {
    for (var i = from; i < from + _prefetch && i < keys.length; i++) {
      final k = keys[i];
      final remote = _routes[k];
      if (remote == null) continue;
      if (_segCache.containsKey(k) || _inflight.containsKey(k)) continue;
      unawaited(_loadSegment(k, remote).catchError((_) => Uint8List(0)));
    }
  }

  /// 注册一份清单，返回给播放器使用的本地 URL
  Future<Uri> publish(String dir, String playlist) async {
    await ensureStarted();
    final key = 'p_${_slug(dir)}.m3u8';
    final result = rewrite(dir, playlist);
    _routes[key] = result.playlist;
    _warm(result.segments, 0);
    return Uri.parse('$baseUrl/$key');
  }

  String _slug(String dir) {
    final safe = dir.replaceAll(RegExp(r'[^A-Za-z0-9_]'), '_');
    return safe.length <= 40 ? safe : safe.substring(0, 40);
  }

  /// 把分片改成指向本机代理，并补 ENDLIST 当点播处理。
  /// 返回重写后的清单与分片本地 key 列表。
  HjRewritten rewrite(String dir, String playlist) {
    final slug = _slug(dir);
    final out = <String>[];
    final keys = <String>[];
    var seq = 0;
    for (final raw in playlist.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) {
        out.add(raw);
        continue;
      }
      if (line.startsWith('#EXT-X-ENDLIST')) continue;
      if (line.startsWith('/m3u8/')) {
        final name = line.substring(line.lastIndexOf('/') + 1);
        final key = 's_${slug}_${name.replaceAll(RegExp(r'[^A-Za-z0-9_.]'), '_')}';
        _routes[key] = line;
        keys.add(key);
        out.add('$baseUrl/$key');
        seq++;
      } else if (line.startsWith('http')) {
        final name = line.split('/').last.split('?').first;
        final key = 's_${slug}_${seq}_${name.replaceAll(RegExp(r'[^A-Za-z0-9_.]'), '_')}';
        _routes[key] = line;
        keys.add(key);
        out.add('$baseUrl/$key');
        seq++;
      } else {
        out.add(raw);
      }
    }
    if (!out.any((l) => l.startsWith('#EXT-X-ENDLIST'))) {
      out.add('#EXT-X-ENDLIST');
    }
    return HjRewritten(out.join('\n'), keys);
  }
}

class HjRewritten {
  HjRewritten(this.playlist, this.segments);
  final String playlist;
  final List<String> segments;
}
