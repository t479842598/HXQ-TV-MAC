import 'dart:async';

import 'package:media_kit/media_kit.dart';

/// 音频链路健康检查与自愈。
///
/// 实测结论（macOS / mpv 0.36 / coreaudio）：
/// * mpv 的 ao 打不开时日志是
///   `[ao/error] Failed to initialize audio driver ...` +
///   `[cplayer/error] Could not open/initialize audio device -> no sound.`
///   并以 **cplayer** 前缀进 media_kit 的 error 流 —— 于是播放页整页被错误浮层盖住。
/// * 此时 mpv 已经把音轨丢掉（日志 `Audio: no audio`），
///   **只发 `ao-reload` 救不回来**（实测 hasAudio 仍为 false、playing 变 false）。
/// * 必须**重新 open 同一 URL** 才会重建音轨；重新 open 后再 seek 回原位置，
///   声音与进度都能恢复（实测 pos 连续、playing=true）。
///
/// 因此这里做三级恢复：ao-reload → 换设备 → 重开媒体。
class HjAudioGuard {
  HjAudioGuard._();

  /// 最近若干条自愈记录，供排查。
  static final List<String> events = <String>[];

  static void note(String line) {
    events.add(line);
    if (events.length > 40) events.removeAt(0);
    // ignore: avoid_print
    print('[HjAudio] $line');
  }

  /// 这条 error 是否属于「音频输出打不开」而非真正的播放失败。
  static bool isAudioFailure(String message) {
    final s = message.toLowerCase();
    return s.contains('audio device') ||
        s.contains('audio output') ||
        s.contains('no sound') ||
        s.contains('failed to initialize audio driver') ||
        s.contains('could not open/initialize audio');
  }

  /// 当前是否真的在出声：audio-params 里有有效声道。
  static bool hasAudio(Player player) {
    try {
      final raw = player.getProperty('audio-params');
      if (raw.isEmpty) return false;
      if (raw.contains('"channel-count":0')) return false;
      if (raw.contains('"channels":"unknown"')) return false;
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 依次尝试恢复音频输出。返回是否恢复成功。
  ///
  /// [reopen] 是「重新打开当前媒体并 seek 回原位置」的回调 ——
  /// 没有它就只能做前两级，而前两级在实测里救不回已丢掉的音轨。
  static Future<bool> recover(
    Player player, {
    Future<void> Function()? reopen,
    Duration settle = const Duration(milliseconds: 1500),
  }) async {
    // 1) 复位 ao 并让 mpv 重载音频输出
    try {
      await player.command(['set', 'ao', 'coreaudio']);
      await player.command(['ao-reload']);
    } catch (_) {}
    await Future<void>.delayed(settle);
    if (hasAudio(player)) {
      note('recover ok=ao-reload');
      return true;
    }

    // 2) 逐个真实设备试（跳过 auto）
    List<AudioDevice> devices = const <AudioDevice>[];
    try {
      devices = player
          .getAudioDevices()
          .where((d) => d.name != 'auto')
          .toList(growable: false);
    } catch (_) {}
    for (final d in devices) {
      try {
        await player.setAudioDevice(d);
        await Future<void>.delayed(settle);
        if (hasAudio(player)) {
          note('recover ok=device ${d.name}');
          return true;
        }
      } catch (_) {}
    }
    try {
      await player.setAudioDevice(AudioDevice.auto());
      await Future<void>.delayed(const Duration(milliseconds: 600));
    } catch (_) {}

    // 3) 重开媒体 —— 唯一能救回已丢弃音轨的路径
    if (reopen != null) {
      try {
        await reopen();
        for (var i = 0; i < 40; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 250));
          if (hasAudio(player)) {
            note('recover ok=reopen');
            return true;
          }
        }
      } catch (e) {
        note('recover reopen EXC $e');
      }
    }

    note('recover failed');
    return false;
  }
}
