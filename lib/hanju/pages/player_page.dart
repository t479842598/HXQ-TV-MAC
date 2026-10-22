import 'dart:async';

import 'package:flutter/services.dart';

import 'package:PiliPlus/hanju/api.dart';
import 'package:PiliPlus/hanju/audio_guard.dart';
import 'package:PiliPlus/hanju/history.dart';
import 'package:PiliPlus/hanju/models.dart';
import 'package:PiliPlus/hanju/playlist_server.dart';
import 'package:PiliPlus/hanju/store.dart';
import 'package:PiliPlus/hanju/ui/hj_theme.dart';
import 'package:PiliPlus/hanju/ui/responsive.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:material_ui/material_ui.dart';

/// 画面比例（对齐 PiliPlus 的 VideoFitType 子集）
enum HjVideoFit {
  contain('适应', BoxFit.contain),
  cover('铺满', BoxFit.cover),
  fill('拉伸', BoxFit.fill),
  fitWidth('适应宽度', BoxFit.fitWidth),
  fitHeight('适应高度', BoxFit.fitHeight);

  const HjVideoFit(this.label, this.fit);
  final String label;
  final BoxFit fit;
}

const List<double> hjPlaySpeeds = <double>[
  0.5,
  0.75,
  1.0,
  1.25,
  1.5,
  1.75,
  2.0,
  3.0,
];

/// 播放页：全屏 media_kit 播放 + 选集/倍速/画面比例 + 历史进度续播
class HjPlayerPage extends StatefulWidget {
  const HjPlayerPage({
    super.key,
    required this.series,
    required this.episodes,
    required this.startIndex,
  });

  final HjSeries series;
  final List<HjPlayItem> episodes;
  final int startIndex;

  @override
  State<HjPlayerPage> createState() => _HjPlayerPageState();
}

class _HjPlayerPageState extends State<HjPlayerPage> {
  final _store = HjStore.instance;
  final _history = HjHistory.instance;

  Player? _player;
  VideoController? _video;

  int _index = 0;
  bool _loading = true;
  String? _error;
  bool _audioRecovering = false;
  int _audioRecoverAttempts = 0;
  Timer? _audioWatchdog;
  String? _currentUrl;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Duration _buffered = Duration.zero;
  bool _playing = false;
  bool _buffering = false;

  double _rate = 1.0;
  double _volume = 100;
  bool _muted = false;
  HjVideoFit _fit = HjVideoFit.contain;
  String _quality = '720P';

  bool _showControls = true;
  Timer? _hideTimer;
  Timer? _historyTimer;

  // 长按方向键：右键先计时 250ms 再进倍速，松开回到原速；
  // 上下键按下先跳一格音量，再每 140ms 连续加减（对齐 PiliPlus player_focus 的手感）。
  Timer? _speedHoldTimer;
  Timer? _volHoldTimer;
  bool _speedBoost = false;
  double _rateBeforeBoost = 1.0;

  /// 音量浮层：调音量时显示，停手 900ms 后隐藏
  bool _volHudVisible = false;
  Timer? _volHudTimer;
  bool _seeking = false;
  double _seekValue = 0;
  bool _panelOpen = false;

  final List<StreamSubscription<dynamic>> _subs = [];

  @override
  void initState() {
    super.initState();
    _index = widget.startIndex.clamp(0, widget.episodes.length - 1);
    _history.addListener(_onHistory);
    _boot();
  }

  void _onHistory() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _historyTimer?.cancel();
    _audioWatchdog?.cancel();
    _speedHoldTimer?.cancel();
    _volHoldTimer?.cancel();
    _volHudTimer?.cancel();
    _history.removeListener(_onHistory);
    for (final s in _subs) {
      s.cancel();
    }
    _player?.dispose();
    super.dispose();
  }

  Future<void> _boot() async {
    try {
      final player = await Player.create(
        configuration: const PlayerConfiguration(
          title: 'HanjuTV',
          logLevel: MPVLogLevel.error,
        ),
      );
      final video = await VideoController.create(
        player,
        configuration: const VideoControllerConfiguration(
          enableHardwareAcceleration: true,
        ),
      );
      _player = player;
      _video = video;
      await player.setVolume(_volume);

      _subs.add(player.stream.position.listen((v) {
        if (!_seeking && mounted) setState(() => _position = v);
      }));
      _subs.add(player.stream.duration.listen((v) {
        if (mounted) setState(() => _duration = v);
      }));
      _subs.add(player.stream.buffer.listen((v) {
        if (mounted) setState(() => _buffered = v);
      }));
      _subs.add(player.stream.playing.listen((v) {
        if (mounted) setState(() => _playing = v);
      }));
      _subs.add(player.stream.buffering.listen((v) {
        if (mounted) setState(() => _buffering = v);
      }));
      _subs.add(player.stream.completed.listen((v) {
        if (v && mounted) _next();
      }));
      _subs.add(player.stream.error.listen((v) {
        if (!mounted) return;
        // 音频输出故障不该让整页变成错误页：视频照常播，后台自愈。
        if (HjAudioGuard.isAudioFailure(v)) {
          unawaited(_recoverAudio());
          return;
        }
        setState(() => _error = v);
      }));
      _subs.add(player.stream.videoParams.listen((v) {
        final h = v.h;
        if (h != null && h > 0 && mounted) {
          setState(() {
            _quality = h >= 1000
                ? '1080P'
                : (h >= 700 ? '720P' : (h >= 460 ? '480P' : '360P'));
          });
        }
      }));

      await _load(_index);
      _startHistoryTimer();
      _scheduleHide();
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '播放器初始化失败: $e';
        });
      }
    }
  }

  /// 音频自愈：不让 `Could not open/initialize audio device` 变成播放失败。
  ///
  /// mpv 在 ao 打不开时会直接丢掉音轨，只发 `ao-reload` 救不回来，
  /// 必须重开媒体再 seek 回原位置 —— 见 [HjAudioGuard.recover] 的 reopen 回调。
  Future<void> _recoverAudio() async {
    final player = _player;
    final url = _currentUrl;
    if (player == null || url == null || _audioRecovering) return;
    _audioRecovering = true;
    _audioRecoverAttempts++;
    try {
      final at = _position;
      final ok = await HjAudioGuard.recover(
        player,
        reopen: () async {
          await player.open(Media(url), play: true);
          if (at > const Duration(seconds: 1)) {
            await Future<void>.delayed(const Duration(milliseconds: 500));
            await player.seek(at);
          }
          await player.setRate(_rate);
          await player.setVolume(_volume);
          if (_muted) await player.setVolume(0);
        },
      );
      HjAudioGuard.note(
        'recover attempt=$_audioRecoverAttempts ok=$ok '
        'ep=${_episodeAt(_index)?.serialNo}',
      );
      if (!ok && mounted) {
        // 三级恢复都没救回来：提示一次，但不锁死播放。
        setState(() => _error = '音频设备打不开，可以继续看画面或点重试');
      }
    } finally {
      _audioRecovering = false;
    }
  }

  /// 起播后 3 秒体检一次：有视频没声音 → 直接自愈。
  void _armAudioWatchdog() {
    _audioWatchdog?.cancel();
    _audioWatchdog = Timer(const Duration(seconds: 12), () {
      final p = _player;
      if (p == null || !mounted) return;
      if (p.state.playing && !HjAudioGuard.hasAudio(p)) {
        HjAudioGuard.note('watchdog no-audio ep=${_episodeAt(_index)?.serialNo}');
        unawaited(_recoverAudio());
      }
    });
  }

  void _startHistoryTimer() {
    _historyTimer?.cancel();
    _historyTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _recordHistory();
    });
  }

  void _recordHistory() {
    final p = _player;
    if (p == null) return;
    if (_duration.inMilliseconds <= 0) return;
    final ep = _episodeAt(_index);
    if (ep == null) return;
    _history.record(
      sid: widget.series.sid,
      seriesName: widget.series.name,
      serialNo: ep.serialNo,
      epTitle: ep.title,
      dir: _dirOf(ep) ?? '',
      poster: widget.series.thumb ?? widget.series.poster,
      positionMs: _position.inMilliseconds,
      durationMs: _duration.inMilliseconds,
    );
  }

  HjPlayItem? _episodeAt(int i) {
    if (i < 0 || i >= widget.episodes.length) return null;
    return widget.episodes[i];
  }

  String? _dirOf(HjPlayItem ep) =>
      _store.playDir(widget.series.sid, ep.serialNo);

  Future<void> _load(int i, {bool resume = true}) async {
    i = i.clamp(0, widget.episodes.length - 1);
    final player = _player;
    if (player == null) return;
    final ep = _episodeAt(i);
    if (ep == null) return;
    setState(() {
      _index = i;
      _loading = true;
      _error = null;
      _position = Duration.zero;
      _duration = Duration.zero;
      _buffered = Duration.zero;
    });
    try {
      _recordHistory();
      final dir = _dirOf(ep);
      if (dir == null) {
        setState(() {
          _loading = false;
          _error = '第 ${ep.serialNo} 期还没有本地播放源';
        });
        return;
      }
      final playlist = await HjApi.instance.fetchPlaylist(dir);
      final url = await HjPlaylistServer.instance.publish(dir, playlist);
      var start = Duration.zero;
      if (resume) {
        final ms = _history.resumePosition(widget.series.sid, ep.serialNo);
        if (ms != null && ms > 0) start = Duration(milliseconds: ms);
      }
      await player.setRate(_rate);
      _audioRecoverAttempts = 0;
      _currentUrl = url.toString();
      await player.open(Media(url.toString()), play: true);
      if (start > Duration.zero) {
        await Future<void>.delayed(const Duration(milliseconds: 400));
        await player.seek(start);
      }
      if (mounted) setState(() => _loading = false);
      _armAudioWatchdog();
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '播放失败: $e';
        });
      }
    }
  }

  /// 重试：先原地重载；连续失败则重建整个 Player（核心资源全换）。
  Future<void> _retry() async {
    setState(() {
      _error = null;
      _loading = true;
    });
    if (_audioRecoverAttempts < 2) {
      await _load(_index, resume: false);
      return;
    }
    await _rebuildPlayer();
  }

  Future<void> _rebuildPlayer() async {
    final old = _player;
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    _video = null;
    _player = null;
    _audioRecoverAttempts = 0;
    if (old != null) unawaited(old.dispose());
    await _boot();
  }

  void _prev() {
    if (_index > 0) _load(_index - 1);
  }

  void _next() {
    if (_index < widget.episodes.length - 1) _load(_index + 1);
  }

  void _togglePlay() {
    final p = _player;
    if (p == null) return;
    if (p.state.playing) {
      p.pause();
    } else {
      p.play();
    }
    _scheduleHide();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _playing && !_panelOpen) {
        setState(() => _showControls = false);
      }
    });
  }

  void _wake() {
    if (!_showControls) setState(() => _showControls = true);
    _scheduleHide();
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    final mm = m.toString().padLeft(h > 0 ? 2 : 1, '0');
    final ss = s.toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    final m = HjMetrics.of(context);
    final ep = _episodeAt(_index);
    return Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        autofocus: true,
        onKeyEvent: _onKey,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            // 点画面 = 播放/暂停（PiliPlus 同款），同时把控制条亮出来。
            _togglePlay();
            _wake();
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (_video != null)
                Video(
                  controller: _video!,
                  fit: _fit.fit,
                  controls: NoVideoControls,
                  fill: Colors.black,
                )
              else
                const Center(
                  child: CircularProgressIndicator(color: HjTheme.accent),
                ),
              if (_loading || _buffering)
                const Center(
                  child: CircularProgressIndicator(color: HjTheme.accent),
                ),
              if (_error != null) _errorView(m),
              if (_speedBoost) _speedHud(m),
              _volumeHud(m),
              if (_showControls) ...[
                _topBar(m, ep),
                _bottomBar(m),
                if (_panelOpen) _episodePanel(m),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// 长按右键的倍速角标
  Widget _speedHud(HjMetrics m) {
    return Positioned(
      top: m.gap(18),
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: Center(
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: m.gap(14),
              vertical: m.gap(7),
            ),
            decoration: BoxDecoration(
              gradient: HjTheme.brand,
              borderRadius: BorderRadius.circular(m.gap(16)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.fast_forward_rounded,
                    size: m.sp(14), color: Colors.white),
                SizedBox(width: m.gap(6)),
                Text(
                  '2X 倍速',
                  style: TextStyle(
                    fontSize: m.sp(12),
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 音量浮层：长按上下键时出现，停手 900ms 后淡出
  Widget _volumeHud(HjMetrics m) {
    if (!_volHudVisible) return const SizedBox.shrink();
    final v = _volume.round();
    return Positioned(
      right: m.gap(24),
      top: 0,
      bottom: 0,
      child: IgnorePointer(
        child: Center(
          child: Container(
            width: m.gap(38),
            height: m.gap(190),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.62),
              borderRadius: BorderRadius.circular(m.gap(19)),
            ),
            child: Column(
              children: [
                SizedBox(height: m.gap(10)),
                Icon(
                  _muted || v <= 0
                      ? Icons.volume_off_rounded
                      : (v >= 60
                          ? Icons.volume_up_rounded
                          : Icons.volume_down_rounded),
                  size: m.sp(15),
                  color: Colors.white70,
                ),
                SizedBox(height: m.gap(8)),
                Expanded(
                  child: RotatedBox(
                    quarterTurns: 3,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(m.gap(4)),
                      child: LinearProgressIndicator(
                        value: v / 100,
                        minHeight: m.gap(6),
                        backgroundColor: Colors.white.withValues(alpha: 0.14),
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          HjTheme.accent,
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(height: m.gap(8)),
                Text(
                  '$v',
                  style: TextStyle(
                    fontSize: m.sp(10.5),
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: m.gap(10)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _errorView(HjMetrics m) {
    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.72),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline,
                size: m.gap(34), color: Colors.white70),
            SizedBox(height: m.gap(12)),
            Text(
              _error ?? '播放失败',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: m.sp(12.5), color: Colors.white70),
            ),
            SizedBox(height: m.gap(16)),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: HjTheme.accent),
              onPressed: _retry,
              child: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _topBar(HjMetrics m, HjPlayItem? ep) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.fromLTRB(
          m.gap(14),
          m.gap(14),
          m.gap(16),
          m.gap(30),
        ),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xCC000000), Color(0x00000000)],
          ),
        ),
        child: Row(
          children: [
            _circleBtn(
              icon: Icons.arrow_back_ios_new_rounded,
              m: m,
              onTap: () => Navigator.of(context).maybePop(),
            ),
            SizedBox(width: m.gap(10)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.series.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: m.sp(13.5),
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  if (ep != null)
                    Text(
                      ep.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: m.sp(11),
                        color: Colors.white60,
                      ),
                    ),
                ],
              ),
            ),
            SizedBox(width: m.gap(10)),
            Text(
              '第 ${_index + 1} / ${widget.episodes.length} 集',
              style: TextStyle(
                fontSize: m.sp(11.5),
                fontWeight: FontWeight.w600,
                color: Colors.white70,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bottomBar(HjMetrics m) {
    final total = _duration.inMilliseconds;
    final pos = _position.inMilliseconds;
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        padding: EdgeInsets.fromLTRB(
          m.gap(16),
          m.gap(26),
          m.gap(16),
          m.gap(14),
        ),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [Color(0xE6000000), Color(0x00000000)],
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text(
                  _fmt(_position),
                  style: TextStyle(
                    fontSize: m.sp(11),
                    color: Colors.white,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                SizedBox(width: m.gap(10)),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3.5,
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 7,
                      ),
                      overlayShape: const RoundSliderOverlayShape(
                        overlayRadius: 16,
                      ),
                      activeTrackColor: HjTheme.accent,
                      thumbColor: HjTheme.accent,
                      inactiveTrackColor: Colors.white.withValues(alpha: 0.20),
                      secondaryActiveTrackColor:
                          Colors.white.withValues(alpha: 0.34),
                    ),
                    child: Slider(
                    min: 0,
                    max: total > 0 ? total.toDouble() : 1,
                    value: (_seeking
                            ? _seekValue
                            : pos.toDouble())
                        .clamp(0, total > 0 ? total.toDouble() : 1),
                    secondaryTrackValue: _buffered.inMilliseconds
                        .toDouble()
                        .clamp(0, total > 0 ? total.toDouble() : 1),
                    onChangeStart: (v) {
                      setState(() {
                        _seeking = true;
                        _seekValue = v;
                      });
                    },
                    onChanged: (v) => setState(() => _seekValue = v),
                    onChangeEnd: (v) async {
                      await _player?.seek(Duration(milliseconds: v.round()));
                      if (mounted) setState(() => _seeking = false);
                      _scheduleHide();
                    },
                    ),
                  ),
                ),
                SizedBox(width: m.gap(10)),
                Text(
                  _fmt(_duration),
                  style: TextStyle(
                    fontSize: m.sp(11),
                    color: Colors.white70,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            SizedBox(height: m.gap(4)),
            Row(
              children: [
                _iconBtn(
                  icon: _playing
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  m: m,
                  size: 24,
                  onTap: _togglePlay,
                ),
                SizedBox(width: m.gap(6)),
                _iconBtn(
                  icon: Icons.skip_previous_rounded,
                  m: m,
                  size: 20,
                  enabled: _index > 0,
                  onTap: _prev,
                ),
                SizedBox(width: m.gap(2)),
                _iconBtn(
                  icon: Icons.skip_next_rounded,
                  m: m,
                  size: 20,
                  enabled: _index < widget.episodes.length - 1,
                  onTap: _next,
                ),
                SizedBox(width: m.gap(10)),
                _iconBtn(
                  icon: _muted || _volume <= 0
                      ? Icons.volume_off_rounded
                      : Icons.volume_up_rounded,
                  m: m,
                  size: 20,
                  onTap: () async {
                    final nm = !(_muted || _volume <= 0);
                    setState(() => _muted = nm);
                    await _player?.setVolume(nm ? 0 : _volume);
                  },
                ),
                const Spacer(),
                _episodeBtn(m),
                SizedBox(width: m.gap(6)),
                _menuBtn(
                  label: '${_rate.toString().replaceAll('.0', '')}X',
                  m: m,
                  items: [
                    for (final s in hjPlaySpeeds)
                      PopupMenuItem<double>(
                        value: s,
                        height: 34,
                        child: Text(
                          '${s.toString().replaceAll('.0', '')}X',
                          style: TextStyle(
                            fontSize: m.sp(12),
                            color: s == _rate
                                ? HjTheme.accent
                                : Colors.white,
                          ),
                        ),
                      ),
                  ],
                  onSelect: (v) async {
                    setState(() => _rate = v);
                    await _player?.setRate(v);
                  },
                ),
                SizedBox(width: m.gap(6)),
                _menuBtn(
                  label: _fit.label,
                  m: m,
                  items: [
                    for (final f in HjVideoFit.values)
                      PopupMenuItem<HjVideoFit>(
                        value: f,
                        height: 34,
                        child: Text(
                          f.label,
                          style: TextStyle(
                            fontSize: m.sp(12),
                            color: f == _fit ? HjTheme.accent : Colors.white,
                          ),
                        ),
                      ),
                  ],
                  onSelect: (v) => setState(() => _fit = v),
                ),
                SizedBox(width: m.gap(6)),
                _menuBtn(
                  label: _quality,
                  m: m,
                  items: [
                    PopupMenuItem<String>(
                      value: _quality,
                      height: 34,
                      child: Text(
                        '$_quality（当前源）',
                        style: TextStyle(
                          fontSize: m.sp(12),
                          color: HjTheme.accent,
                        ),
                      ),
                    ),
                  ],
                  onSelect: (_) {},
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _episodeBtn(HjMetrics m) {
    return _chipBtn(
      icon: Icons.video_library_outlined,
      label: '选集',
      m: m,
      active: _panelOpen,
      onTap: () {
        setState(() {
          _panelOpen = !_panelOpen;
          _showControls = true;
        });
      },
    );
  }

  Widget _menuBtn<T>({
    required String label,
    required HjMetrics m,
    required List<PopupMenuEntry<T>> items,
    required void Function(T) onSelect,
  }) {
    return PopupMenuButton<T>(
      tooltip: '',
      color: Colors.black.withValues(alpha: 0.88),
      initialValue: null,
      onSelected: onSelect,
      itemBuilder: (c) => items,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: m.gap(8),
          vertical: m.gap(5),
        ),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(m.gap(7)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: m.sp(11),
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _chipBtn({
    required IconData icon,
    required String label,
    required HjMetrics m,
    required VoidCallback onTap,
    bool active = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: m.gap(9),
          vertical: m.gap(5),
        ),
        decoration: BoxDecoration(
          gradient: active ? HjTheme.brand : null,
          color: active ? null : Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(m.gap(7)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: m.sp(13), color: Colors.white),
            SizedBox(width: m.gap(4)),
            Text(
              label,
              style: TextStyle(
                fontSize: m.sp(11),
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _iconBtn({
    required IconData icon,
    required HjMetrics m,
    required VoidCallback onTap,
    double size = 20,
    bool enabled = true,
  }) {
    return Opacity(
      opacity: enabled ? 1 : 0.35,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: EdgeInsets.all(m.gap(5)),
          child: Icon(icon, size: m.sp(size), color: Colors.white),
        ),
      ),
    );
  }

  Widget _circleBtn({
    required IconData icon,
    required HjMetrics m,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: m.gap(30),
        height: m.gap(30),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.14),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: m.sp(14), color: Colors.white),
      ),
    );
  }

  Widget _episodePanel(HjMetrics m) {
    return Positioned(
      right: 0,
      top: 0,
      bottom: 0,
      child: Container(
        width: m.isTv ? m.gap(360) : m.gap(280),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.94),
          border: Border(
            left: BorderSide(color: Colors.white.withValues(alpha: 0.07)),
          ),
        ),
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                m.gap(14),
                m.gap(52),
                m.gap(14),
                m.gap(10),
              ),
              child: Row(
                children: [
                  Text(
                    '选集',
                    style: TextStyle(
                      fontSize: m.sp(14),
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(width: m.gap(8)),
                  Text(
                    '${widget.episodes.length} 期',
                    style: TextStyle(
                      fontSize: m.sp(11),
                      color: Colors.white54,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => setState(() => _panelOpen = false),
                    child: Icon(Icons.close_rounded,
                        size: m.sp(16), color: Colors.white70),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: EdgeInsets.symmetric(horizontal: m.gap(10)),
                itemCount: widget.episodes.length,
                itemBuilder: (c, i) {
                  final ep = widget.episodes[i];
                  final has = _dirOf(ep) != null;
                  final sel = i == _index;
                  return Padding(
                    padding: EdgeInsets.only(bottom: m.gap(6)),
                    child: GestureDetector(
                      onTap: has
                          ? () {
                              setState(() => _panelOpen = false);
                              _load(i);
                            }
                          : null,
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: m.gap(10),
                          vertical: m.gap(9),
                        ),
                        decoration: BoxDecoration(
                          gradient: sel ? HjTheme.brand : null,
                          color: sel
                              ? null
                              : Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(m.gap(8)),
                        ),
                        child: Row(
                          children: [
                            Text(
                              '${ep.serialNo}',
                              style: TextStyle(
                                fontSize: m.sp(11),
                                fontWeight: FontWeight.w800,
                                color: sel ? Colors.white : Colors.white60,
                              ),
                            ),
                            SizedBox(width: m.gap(10)),
                            Expanded(
                              child: Text(
                                ep.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: m.sp(11.5),
                                  color: has
                                      ? Colors.white
                                      : Colors.white38,
                                ),
                              ),
                            ),
                            if (!has)
                              Icon(Icons.inbox_outlined,
                                  size: m.sp(12), color: Colors.white30),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------- 长按方向键 ----------

  /// 长按右键：250ms 后进 2 倍速，松开还原。
  ///
  /// 短按（<250ms）走 [_seekBy]，长按期间不 seek，避免「先跳 15 秒再加速」的错手感。
  void _holdSpeedStart() {
    if (_speedBoost || _player == null) return;
    _speedHoldTimer?.cancel();
    _speedHoldTimer = Timer(const Duration(milliseconds: 250), () {
      if (!mounted || _player == null) return;
      _rateBeforeBoost = _rate;
      setState(() => _speedBoost = true);
      unawaited(_player!.setRate(2.0));
    });
  }

  /// 松开右键：进过倍速就还原（不 seek），没进过就当成短按跳 15 秒
  void _holdSpeedEnd() {
    final timer = _speedHoldTimer;
    _speedHoldTimer = null;
    timer?.cancel();
    if (_speedBoost) {
      setState(() => _speedBoost = false);
      unawaited(_player?.setRate(_rateBeforeBoost) ?? Future<void>.value());
      _wake();
      return;
    }
    _seekBy(15);
  }

  /// 音量步进：每次 5%，长按期间每 140ms 一次
  void _stepVolume(int delta) {
    setState(() {
      _volume = (_volume + delta).clamp(0, 100);
      if (_muted && _volume > 0) _muted = false;
      _volHudVisible = true;
    });
    unawaited(_player?.setVolume(_volume) ?? Future<void>.value());
    _volHudTimer?.cancel();
    _volHudTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _volHudVisible = false);
    });
    _wake();
  }

  void _holdVolumeStart(int delta) {
    _stepVolume(delta);
    _volHoldTimer?.cancel();
    _volHoldTimer = Timer.periodic(const Duration(milliseconds: 140), (_) {
      if (!mounted) return;
      _stepVolume(delta);
    });
  }

  void _holdVolumeEnd() {
    _volHoldTimer?.cancel();
    _volHoldTimer = null;
  }

  void _seekBy(int seconds) {
    _player?.seek(_position + Duration(seconds: seconds));
    _wake();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final k = event.logicalKey;

    // 松开：结束长按态
    if (event is KeyUpEvent) {
      if (k == LogicalKeyboardKey.arrowRight) {
        _holdSpeedEnd();
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.arrowUp ||
          k == LogicalKeyboardKey.arrowDown) {
        _holdVolumeEnd();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    // 重复的 KeyDown（系统自动重复）不重复起计时器
    if (event is KeyRepeatEvent) {
      if (k == LogicalKeyboardKey.arrowRight ||
          k == LogicalKeyboardKey.arrowUp ||
          k == LogicalKeyboardKey.arrowDown) {
        return KeyEventResult.handled;
      }
    }

    if (k == LogicalKeyboardKey.escape) {
      if (_panelOpen) {
        setState(() => _panelOpen = false);
      } else {
        Navigator.of(context).maybePop();
      }
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.space || k == LogicalKeyboardKey.enter) {
      _togglePlay();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowLeft) {
      _seekBy(-15);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowRight) {
      _holdSpeedStart();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowUp) {
      _holdVolumeStart(5);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowDown) {
      _holdVolumeStart(-5);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.keyF) {
      setState(() {
        _fit = _fit == HjVideoFit.contain
            ? HjVideoFit.cover
            : HjVideoFit.contain;
      });
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }
}
