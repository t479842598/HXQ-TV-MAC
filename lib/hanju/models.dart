/// 韩小圈数据模型：对应服务端 /api/series/detail 与本地 catalog/playmap 资源。
library;

class HjCatalog {
  final List<HjBlock> blocks;
  const HjCatalog(this.blocks);

  factory HjCatalog.fromJson(Map<String, dynamic> json) => HjCatalog(
    (json['blocks'] as List? ?? const [])
        .map((e) => HjBlock.fromJson(e as Map<String, dynamic>))
        .toList(),
  );

  List<HjSeries> get allItems =>
      blocks.expand((b) => b.items).toList(growable: false);
}

class HjBlock {
  final int mid;
  final String title;
  final List<HjSeries> items;
  const HjBlock({required this.mid, required this.title, required this.items});

  /// 去掉变体选择符（▶️ 🤔 之类）后用于展示
  String get cleanTitle => title.replaceAll(String.fromCharCode(0xFE0F), '').trim();

  factory HjBlock.fromJson(Map<String, dynamic> json) => HjBlock(
    mid: (json['mid'] as num?)?.toInt() ?? 0,
    title: json['title'] as String? ?? '',
    items: (json['items'] as List? ?? const [])
        .map((e) => HjSeries.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}

class HjSeries {
  final String sid;
  final String name;
  final int? category;
  final String? shorthand;
  final String? crew;
  final int? lastSerialNo;
  final int? finished;
  final int? rank;
  final String? thumb;
  final String? poster;

  const HjSeries({
    required this.sid,
    required this.name,
    this.category,
    this.shorthand,
    this.crew,
    this.lastSerialNo,
    this.finished,
    this.rank,
    this.thumb,
    this.poster,
  });

  factory HjSeries.fromJson(Map<String, dynamic> json) => HjSeries(
    sid: json['sid'] as String? ?? '',
    name: json['name'] as String? ?? '',
    category: (json['category'] as num?)?.toInt(),
    shorthand: json['shorthand'] as String?,
    crew: json['crew'] as String?,
    lastSerialNo: (json['lastSerialNo'] as num?)?.toInt(),
    finished: (json['finished'] as num?)?.toInt(),
    rank: (json['rank'] as num?)?.toInt(),
    thumb: json['thumb'] as String?,
    poster: json['poster'] as String?,
  );

  /// 服务端 rank 是 91，展示成 9.1
  String? get rankText {
    final r = rank;
    if (r == null || r <= 0) return null;
    return '${r ~/ 10}.${r % 10}';
  }

  String get statusText {
    if (finished == 1) return '全${lastSerialNo ?? 0}期';
    final n = lastSerialNo;
    if (n != null && n > 0) return '更新至第$n期';
    return '连载中';
  }

  HjSeries copyWith({
    String? name,
    int? lastSerialNo,
    int? finished,
    int? rank,
    String? thumb,
    String? poster,
    String? crew,
    String? shorthand,
  }) => HjSeries(
    sid: sid,
    name: name ?? this.name,
    category: category,
    shorthand: shorthand ?? this.shorthand,
    crew: crew ?? this.crew,
    lastSerialNo: lastSerialNo ?? this.lastSerialNo,
    finished: finished ?? this.finished,
    rank: rank ?? this.rank,
    thumb: thumb ?? this.thumb,
    poster: poster ?? this.poster,
  );
}

class HjDetailResponse {
  final int rescode;
  final int? ts;
  final HjSeriesInfo? series;
  final List<HjPlayItem> playItems;

  const HjDetailResponse({
    required this.rescode,
    this.ts,
    this.series,
    this.playItems = const [],
  });

  factory HjDetailResponse.fromJson(Map<String, dynamic> json) =>
      HjDetailResponse(
        rescode: (json['rescode'] as num?)?.toInt() ?? -1,
        ts: (json['ts'] as num?)?.toInt(),
        series: json['series'] == null
            ? null
            : HjSeriesInfo.fromJson(json['series'] as Map<String, dynamic>),
        playItems: (json['playItems'] as List? ?? const [])
            .map((e) => HjPlayItem.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class HjSeriesInfo {
  final String sid;
  final String name;
  final int? rank;
  final bool? isFinished;
  final int? publishTime;
  final String? intro;
  final String? thumb;
  final String? poster;
  final String? posterThumb;
  final int? count;
  final String? source;
  final int? category;
  final bool? isPreview;
  final String? shorthand;
  final String? crew;
  final List<HjQuality> scopeQualities;

  const HjSeriesInfo({
    required this.sid,
    required this.name,
    this.rank,
    this.isFinished,
    this.publishTime,
    this.intro,
    this.thumb,
    this.poster,
    this.posterThumb,
    this.count,
    this.source,
    this.category,
    this.isPreview,
    this.shorthand,
    this.crew,
    this.scopeQualities = const [],
  });

  factory HjSeriesInfo.fromJson(Map<String, dynamic> json) => HjSeriesInfo(
    sid: json['sid'] as String? ?? '',
    name: json['name'] as String? ?? '',
    rank: (json['rank'] as num?)?.toInt(),
    isFinished: json['isFinished'] as bool?,
    publishTime: (json['publishTime'] as num?)?.toInt(),
    intro: json['intro'] as String?,
    thumb: json['thumb'] as String?,
    poster: json['poster'] as String?,
    posterThumb: json['posterThumb'] as String?,
    count: (json['count'] as num?)?.toInt(),
    source: json['source'] as String?,
    category: (json['category'] as num?)?.toInt(),
    isPreview: json['isPreview'] as bool?,
    shorthand: json['shorthand'] as String?,
    crew: json['crew'] as String?,
    scopeQualities: (json['scopeQualities'] as List? ?? const [])
        .map((e) => HjQuality.fromJson(e as Map<String, dynamic>))
        .toList(),
  );

  /// intro 是 HTML，去掉标签后给简介区用
  String get plainIntro {
    final raw = intro;
    if (raw == null || raw.isEmpty) return '';
    var s = raw
        .replaceAll('<br />', '\n')
        .replaceAll('<br/>', '\n')
        .replaceAll('<br>', '\n')
        .replaceAll('<p>', '')
        .replaceAll('</p>', '\n');
    s = s.replaceAll(RegExp(r'<[^>]+>'), '');
    return s.trim();
  }
}

class HjQuality {
  final String? name;
  final String? resolution;
  final int? value;
  const HjQuality({this.name, this.resolution, this.value});

  factory HjQuality.fromJson(Map<String, dynamic> json) => HjQuality(
    name: json['name'] as String?,
    resolution: json['resolution'] as String?,
    value: (json['value'] as num?)?.toInt(),
  );
}

class HjPlayItem {
  final String pid;
  final int serialNo;
  final int? publishTime;
  final String title;
  final String? srcUrl;
  final String? srcSite;
  final int? cache;
  final int? playTrial;
  final int? duration;

  const HjPlayItem({
    required this.pid,
    required this.serialNo,
    this.publishTime,
    required this.title,
    this.srcUrl,
    this.srcSite,
    this.cache,
    this.playTrial,
    this.duration,
  });

  factory HjPlayItem.fromJson(Map<String, dynamic> json) => HjPlayItem(
    pid: json['pid'] as String? ?? '',
    serialNo: (json['serialNo'] as num?)?.toInt() ?? 0,
    publishTime: (json['publishTime'] as num?)?.toInt(),
    title: json['title'] as String? ?? '',
    srcUrl: json['srcUrl'] as String?,
    srcSite: json['srcSite'] as String?,
    cache: (json['cache'] as num?)?.toInt(),
    playTrial: (json['playTrial'] as num?)?.toInt(),
    duration: (json['duration'] as num?)?.toInt(),
  );
}

class HjPlayMapEntry {
  final String sid;
  final String? name;
  final int serialNo;
  final String dir;
  const HjPlayMapEntry({
    required this.sid,
    this.name,
    required this.serialNo,
    required this.dir,
  });

  factory HjPlayMapEntry.fromJson(Map<String, dynamic> json) => HjPlayMapEntry(
    sid: json['sid'] as String? ?? '',
    name: json['name'] as String?,
    serialNo: (json['serialNo'] as num?)?.toInt() ?? 0,
    dir: json['dir'] as String? ?? '',
  );
}

/// 加载状态（详情、播放源共用）
enum HjLoadState { idle, loading, loaded, failed }
