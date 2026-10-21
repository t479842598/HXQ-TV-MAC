import 'dart:convert';
import 'dart:io';

import 'package:PiliPlus/hanju/models.dart';
import 'package:PiliPlus/hanju/parallel_http.dart';
import 'package:PiliPlus/hanju/segment_auth.dart';

class HjApiError implements Exception {
  final String message;
  final int? status;
  const HjApiError(this.message, {this.status});
  @override
  String toString() => 'HjApiError($message, status: $status)';
}

/// 韩小圈接口客户端，只访问明文端点：
///   GET https://hxqapi.hiyun.tv/api/series/detail?sid=SID
///   GET https://voldn-ser01.51touxiang.com/m3u8/DIR.m3u8
///
/// 请求头是安卓端抓包拿到的稳定组合，服务端不校验 sign 时效。
class HjApi {
  HjApi._();
  static final HjApi instance = HjApi._();

  static const String _host = 'https://hxqapi.hiyun.tv';
  static const String _ua = 'HanjuTV/6.9.1 (Macintosh; macOS)';

  static const Map<String, String> _baseHeaders = <String, String>{
    'sign': 'o1BehZh0B9FV93plMNvkWGpAQvoE+AcFneUWRPRcFjuZ2xvwtGyf6RLlkOQT6EcpRR6mi3vOvCI4wOAhs39ew1jUK1zMtCcVd2bU4fwVynKT9MpqQiIbYAvv/0io9/gMluW7sSShOoTewofcGUd4lR1wjD0txyHFWU23e5HZiBjOWJHv4zp+ngRCZoY4Y9UVIYU/w8OB2sdc6wNSyENq8ryhPXPTnWhqKSbDEwCM+YFScsgyEjz3I/J3phnpgeWrvTlo4HTQGpGA8zQwtNKKoAk0i3yNnCfnfOmkYBxj/2YPI3EyiTfplO5PATgC7D1nUjlE/ugRMmDhJ9f3Aw4MTkNGFBg2R3DonH920v6J7GOjZM03wUNy2NNNcZNV1kRDtZX0jF2C2HlszyhnH81AcdPP0e37cwEkPOewtJvhpJNu7dhWypnFaJR3MsyeRjGNQ9NrASqoeuLO3RoFAmwcsyRhhlv68lI2pgiwLg0pGgvQd+n1fMl9FNWCnDTxPh0yk0ItUEUB4wYm8nknPEYbKjyDIHdx4fD+ByzAcDxIii+5YblBLFV71qZNruesbkzTWezKTVj9FjXffHH41rsvB4XJ4fO32KeiivsRbJeC0Eo=',
    'vc': 'a_8360',
    'vn': '6.9.1',
    'ch': 'bbc',
    'app': 'hj',
    'User-Agent': _ua,
    'said': '2bf796cf4af725a0',
    'uk': 'vEhlSUmg42HS6lP0EIYNnXg0eFl59dgAaoiGd74khag=',
    'auth-token': '',
    'auth-uid': '',
  };

  HttpClient? _client;

  HttpClient get _http {
    final c = _client;
    if (c != null) return c;
    final n = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20)
      ..idleTimeout = const Duration(seconds: 30);
    _client = n;
    return n;
  }

  Future<Map<String, dynamic>> _getJson(Uri uri) async {
    final req = await _http.getUrl(uri);
    _baseHeaders.forEach(req.headers.set);
    final resp = await req.close();
    final body = await resp.transform(utf8.decoder).join();
    if (resp.statusCode != 200) {
      throw HjApiError('HTTP $body', status: resp.statusCode);
    }
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw const HjApiError('响应格式异常');
    }
    return decoded;
  }

  /// 拉剧集详情 + 选集列表
  Future<HjDetailResponse> fetchDetail(String sid) async {
    final uri = Uri.parse('$_host/api/series/detail?sid=$sid');
    final json = await _getJson(uri);
    final res = HjDetailResponse.fromJson(json);
    if (res.rescode != 0) {
      throw HjApiError('服务端返回 rescode=${res.rescode}');
    }
    return res;
  }

  /// 拉 master m3u8 原始文本。
  /// CDN 对单连接限速 ~850 B/s（42 KB 清单要 42 秒），所以清单也走并发分段拉。
  Future<String> fetchPlaylist(String dir) async {
    final uri = Uri.parse('$hjCdnHost/m3u8/$dir.m3u8?$hjSegmentAuth');
    final bytes = await HjParallel.fetch(uri);
    return utf8.decode(bytes, allowMalformed: true);
  }

  /// 图片带时效签名，只能下载 detail 里给出的新 URL
  Future<List<int>> fetchImage(String url) async {
    final req = await _http.getUrl(Uri.parse(url));
    req.headers.set('User-Agent', _ua);
    final resp = await req.close();
    if (resp.statusCode != 200) {
      throw HjApiError('图片 HTTP ${resp.statusCode}');
    }
    final chunks = <int>[];
    await for (final chunk in resp) {
      chunks.addAll(chunk);
    }
    return chunks;
  }

  void dispose() {
    _client?.close(force: true);
    _client = null;
  }
}
