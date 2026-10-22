import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

/// CDN（火山引擎 Byte-nginx）对**单条 TCP 连接**硬限速到 ~850 B/s，
/// 但对同一 IP 的并发连接不封顶（实测 250~300 并发可叠加到 ~200 KB/s）。
/// 所以这里用「一条资源切成 N 段 Range 并发拉，再按序拼回」来突破单连接限速。
///
/// 实测（912,176 B 分片）：100 并发 9.6s / 93 KB/s；300 并发 4.2~11s / 176~218 KB/s，
/// 且拼接结果与响应头 Content-Md5 完全一致（字节级无损）。
class HjParallel {
  HjParallel._();

  static const String defaultUa = 'tdc.8360';

  /// 总并发上限。默认 300（实测 CDN 在 400 以上开始 reset）。
  /// 体检脚本多进程并行时用 HJ_MAXCONC 下调，避免多进程叠加超过阈值。
  static final int _maxConcurrency = _readMaxConc();

  static int _readMaxConc() {
    final raw = Platform.environment['HJ_MAXCONC'];
    final n = raw == null ? 0 : (int.tryParse(raw) ?? 0);
    if (n >= 8 && n <= 300) return n;
    return 300;
  }

  static const int _minChunk = 1024;

  static HttpClient _client = _newClient();

  static HttpClient _newClient() => HttpClient()
    ..maxConnectionsPerHost = _maxConcurrency
    ..idleTimeout = const Duration(seconds: 20)
    ..connectionTimeout = const Duration(seconds: 12)
    ..autoUncompress = false;

  /// 丢弃连接池。
  ///
  /// CDN 侧会在响应结束后很快回收连接，池里残留的 300 条死连接会被下一次
  /// 复用尝试命中，触发 connect 失败 → 重试，表现为「换源后首帧从 15s 变成
  /// 45s+」。换源前调一次即可，代价只是重建客户端对象。
  static void reset() {
    try {
      _client.close(force: true);
    } catch (_) {}
    _client = _newClient();
  }

  static int concurrencyFor(int bytes) {
    final n = (bytes / _minChunk).floor();
    if (n < 8) return 8;
    if (n > _maxConcurrency) return _maxConcurrency;
    return n;
  }

  /// HEAD 拿长度；服务端不支持 HEAD 时退回 Range 0-0 解析 Content-Range。
  static Future<int> contentLength(Uri url, {String ua = defaultUa}) async {
    try {
      final req = await _client.openUrl('HEAD', url);
      req.headers.set(HttpHeaders.userAgentHeader, ua);
      final resp = await req.close();
      await resp.drain<void>();
      if (resp.statusCode == 200) {
        final n = resp.contentLength;
        if (n > 0) return n;
      }
    } catch (_) {}
    final probe = await _range(url, 0, 0, ua);
    final cr = probe.headers.value('content-range');
    if (cr != null) {
      final slash = cr.lastIndexOf('/');
      if (slash > 0) {
        final total = int.tryParse(cr.substring(slash + 1).trim());
        if (total != null && total > 0) return total;
      }
    }
    return probe.bytes.length;
  }

  static Future<_Chunk> _range(Uri url, int start, int end, String ua) async {
    Object? last;
    for (var attempt = 0; attempt < 4; attempt++) {
      try {
        final req = await _client.getUrl(url);
        req.headers.set(HttpHeaders.userAgentHeader, ua);
        req.headers.set(HttpHeaders.rangeHeader, 'bytes=$start-$end');
        final resp = await req.close();
        if (resp.statusCode != 200 && resp.statusCode != 206) {
          await resp.drain<void>();
          throw HjFetchError('HTTP ${resp.statusCode}');
        }
        final b = await resp.fold<BytesBuilder>(
          BytesBuilder(copy: false),
          (acc, d) => acc..add(d),
        );
        return _Chunk(b.takeBytes(), resp.headers);
      } catch (e) {
        last = e;
        await Future<void>.delayed(Duration(milliseconds: 150 * (attempt + 1)));
      }
    }
    throw HjFetchError('分段 $start-$end 失败: $last');
  }

  /// 边下边吐：按顺序把分好的段一段段交出去，**第一段到就立刻可用**。
  ///
  /// 关键：本地代理必须流式转发。整段下完再吐会让 ffmpeg 等超过
  /// keepalive 超时（实测 `hls: keepalive request failed ... Operation timed out`），
  /// 表现为「一直转圈、位置在走但一帧都不出」。
  static Future<HjStreamSource> open(
    Uri url, {
    String ua = defaultUa,
    int? concurrency,
  }) async {
    final total = await contentLength(url, ua: ua);
    if (total <= 0) throw const HjFetchError('无法获取资源长度');
    final n = concurrency ?? concurrencyFor(total);
    final chunk = (total / n).ceil();
    final futures = <Future<_Chunk>>[];
    for (var i = 0; i < n; i++) {
      final s = i * chunk;
      if (s >= total) break;
      final e = (s + chunk - 1).clamp(0, total - 1);
      futures.add(_range(url, s, e, ua));
    }
    Stream<Uint8List> ordered() async* {
      for (final f in futures) {
        final c = await f;
        yield c.bytes;
      }
    }

    return HjStreamSource(total, ordered());
  }

  /// 整资源并发拉取，返回完整字节（顺序正确）。
  static Future<Uint8List> fetch(
    Uri url, {
    String ua = defaultUa,
    int? concurrency,
    void Function(int done, int total)? onProgress,
  }) async {
    final total = await contentLength(url, ua: ua);
    if (total <= 0) throw const HjFetchError('无法获取资源长度');
    final n = concurrency ?? concurrencyFor(total);
    final chunk = (total / n).ceil();
    final futures = <Future<_Chunk>>[];
    for (var i = 0; i < n; i++) {
      final s = i * chunk;
      if (s >= total) break;
      final e = (s + chunk - 1).clamp(0, total - 1);
      futures.add(_range(url, s, e, ua));
    }
    final out = Uint8List(total);
    var done = 0;
    final results = await Future.wait(futures);
    var off = 0;
    for (final c in results) {
      final len = c.bytes.length;
      if (off + len > total) {
        out.setRange(off, total, c.bytes.sublist(0, total - off));
      } else {
        out.setRange(off, off + len, c.bytes);
      }
      off += len;
      done += len;
      onProgress?.call(done, total);
    }
    if (off != total) throw HjFetchError('长度不符: $off != $total');
    return out;
  }
}

/// 流式资源：`total` 是完整长度，`bytes` 按顺序吐出各段。
class HjStreamSource {
  const HjStreamSource(this.total, this.bytes);
  final int total;
  final Stream<Uint8List> bytes;
}

class _Chunk {
  _Chunk(this.bytes, this.headers);
  final Uint8List bytes;
  final HttpHeaders headers;
}

class HjFetchError implements Exception {
  const HjFetchError(this.message);
  final String message;
  @override
  String toString() => 'HjFetchError: $message';
}
