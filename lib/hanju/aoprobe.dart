import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:PiliPlus/hanju/api.dart';
import 'package:PiliPlus/hanju/audio_guard.dart';
import 'package:PiliPlus/hanju/playlist_server.dart';
import 'package:media_kit/media_kit.dart';

/// 音频故障归因实验：
/// 1) 逐个 coreaudio 设备试开，找出哪个设备打不开（虚拟声卡/被独占）
/// 2) 正常起播后打断 ao，再验证 ao-reload / reopen 两级恢复
Future<void> runAoProbe() async {
  final log = StringBuffer();
  void w(String s) {
    log.writeln(s);
    stdout.writeln(s);
  }

  final dirs = <String>[];
  try {
    final raw = await rootBundle.loadString('assets/hanju/playmap.json');
    for (final e in jsonDecode(raw) as List) {
      final d = (e as Map<String, dynamic>)['dir'] as String? ?? '';
      if (d.isNotEmpty) dirs.add(d);
    }
  } catch (e) {
    w('playmap load failed: $e');
  }

  Future<String> urlOf(int i) async {
    final dir = dirs[i % dirs.length];
    final playlist = await HjApi.instance.fetchPlaylist(dir);
    return (await HjPlaylistServer.instance.publish(dir, playlist)).toString();
  }

  String apOf(Player p) {
    final s = p.getProperty('audio-params');
    return s.isEmpty ? '<empty>' : s.replaceAll('\n', ' ');
  }

  final url = await urlOf(0);
  final p = await Player.create(
    configuration: const PlayerConfiguration(
      title: 'HanjuTV',
      logLevel: MPVLogLevel.warn,
    ),
  );
  final errs = <String>[];
  p.stream.error.listen(errs.add);

  // ---------- 1) 设备清单逐个试 ----------
  final devices = p.getAudioDevices();
  w('DEVICES count=${devices.length}');
  for (final d in devices) {
    w('DEV ${d.name} :: ${d.description}');
  }

  await p.open(Media(url), play: true);
  final t0 = DateTime.now();
  var ok = false;
  for (var i = 0; i < 120; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (HjAudioGuard.hasAudio(p) && p.state.position.inSeconds >= 2) {
      ok = true;
      break;
    }
  }
  w('BASELINE ok=$ok ms=${DateTime.now().difference(t0).inMilliseconds} '
      'pos=${p.state.position.inSeconds}s errs=$errs');

  // 逐个设备切换（只切不重开媒体）
  for (final d in devices) {
    if (d.name == 'auto') continue;
    errs.clear();
    try {
      await p.setAudioDevice(d);
      await Future<void>.delayed(const Duration(milliseconds: 1800));
      w('SWITCH ${d.name} hasAudio=${HjAudioGuard.hasAudio(p)} '
          'ap=${apOf(p)} errs=${errs.isEmpty ? "-" : errs.first}');
    } catch (e) {
      w('SWITCH ${d.name} EXC $e');
    }
  }

  // 回到 auto
  errs.clear();
  await p.setAudioDevice(AudioDevice.auto());
  await p.command(['ao-reload']);
  await Future<void>.delayed(const Duration(seconds: 2));
  w('BACK_AUTO hasAudio=${HjAudioGuard.hasAudio(p)} pos=${p.state.position.inSeconds}s');

  // ---------- 2) 打断 + 两级恢复 ----------
  errs.clear();
  await p.command(['set', 'ao', 'definitely_not_a_driver']);
  await Future<void>.delayed(const Duration(seconds: 3));
  final posBefore = p.state.position;
  w('BROKEN hasAudio=${HjAudioGuard.hasAudio(p)} pos=${posBefore.inSeconds}s '
      'playing=${p.state.playing} errs=$errs');

  errs.clear();
  await p.command(['set', 'ao', 'coreaudio']);
  await p.command(['ao-reload']);
  await Future<void>.delayed(const Duration(seconds: 2));
  final afterReload = HjAudioGuard.hasAudio(p);
  w('RECOVER_A ao-reload hasAudio=$afterReload ap=${apOf(p)} '
      'pos=${p.state.position.inSeconds}s playing=${p.state.playing} errs=$errs');

  if (!afterReload) {
    errs.clear();
    await p.open(Media(url), play: true);
    for (var i = 0; i < 60; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (HjAudioGuard.hasAudio(p)) break;
    }
    await p.seek(posBefore);
    await Future<void>.delayed(const Duration(seconds: 2));
    w('RECOVER_B reopen hasAudio=${HjAudioGuard.hasAudio(p)} ap=${apOf(p)} '
        'pos=${p.state.position.inSeconds}s playing=${p.state.playing} errs=$errs');
  }

  await p.dispose();
  HjPlaylistServer.instance.dispose();
  w('DONE');
  final f = File('${Directory.systemTemp.path}/hj_aoprobe.log');
  try {
    await f.writeAsString(log.toString());
    w('LOG=${f.path}');
  } catch (_) {}
  await Future<void>.delayed(const Duration(milliseconds: 200));
  exit(0);
}
