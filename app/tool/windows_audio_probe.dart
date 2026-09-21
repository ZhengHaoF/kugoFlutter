// Windows 桌面音频链路探针。
//
// 必须真实运行在 Windows 上（just_audio_windows 是原生插件，flutter test 跑不到）：
//
//   flutter run -t tool/windows_audio_probe.dart -d windows
//
// 分两段：
//   A. 本地生成 440Hz 正弦波 WAV，喂给 JustAudioPlayerImpl。
//      离线验证 Windows 音频后端本身，不依赖任何网络。
//      刻意模拟真实使用：进程起来后等几秒再点播放，并用同一个播放器连播两次。
//   B. 真实链路：搜索 → PlayRepository 解析地址 → 引擎，
//      对比「带 headers / 无 headers」——just_audio_windows 会静默丢弃自定义
//      请求头，用来判断酷狗 CDN 是否校验 Referer/UA。
//      B 段需要登录态（游客通道 errcode 20028 已关闭），会从 shared_preferences
//      恢复会话；未登录时会直接报告并跳过。
//
// 想复现「just_audio_windows 首个播放器实例不出声」的对照结论：临时把
// `just_audio_windows: ^0.2.3` 加回 pubspec，再调用 JustAudioPlayerImpl。
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kugo/data/repositories/play_repository.dart';
import 'package:kugo/data/repositories/search_repository.dart';
import 'package:kugo/features/auth/auth_controller.dart';
import 'package:kugo/features/player/audio_player_port.dart';
import 'package:kugo/features/player/media_kit_player.dart';
import 'package:media_kit/media_kit.dart';

/// 进程启动后等待多久才播第一首。真实使用中用户要翻页面才点播放，
/// 这里用来区分「插件启动竞态」和「播放器本身坏了」。
const _warmupDelay = Duration(seconds: 5);

/// 与 PlayerController 下发给引擎的头完全一致。
const _headers = <String, String>{
  'User-Agent':
      'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
  'Referer': 'http://www.kugou.com/',
};

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const _ProbeApp());
}

class _ProbeApp extends StatefulWidget {
  const _ProbeApp();

  @override
  State<_ProbeApp> createState() => _ProbeAppState();
}

class _ProbeAppState extends State<_ProbeApp> {
  final List<String> _log = [];

  @override
  void initState() {
    super.initState();
    // 看门狗：探针一旦卡住也要退出，否则 flutter run 会一直挂着。
    Timer(const Duration(seconds: 150), () {
      // ignore: avoid_print
      print('[probe] 看门狗触发，强制退出');
      exit(2);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_run()));
  }

  void _say(String line) {
    // ignore: avoid_print
    print('[probe] $line');
    if (mounted) setState(() => _log.add(line));
  }

  Future<void> _run() async {
    var failed = false;
    try {
      // ---- A 段：本地音频，纯验证 Windows 后端 ----
      _say('==== A 段：本地 WAV（离线） ====');
      final wav = await _writeToneWav(seconds: 20);
      final url = Uri.file(wav.path).toString();
      _say('已生成 ${wav.path}');

      _say('等待 ${_warmupDelay.inSeconds}s 模拟真实使用（进程预热）…');
      await Future<void>.delayed(_warmupDelay);

      // 关键：让 media_kit 成为进程内**第一次**播放，直接检验它有没有
      // just_audio_windows 那个「首次静默失败」的毛病。
      final mk = MediaKitPlayerImpl();
      try {
        final mk1 = await _measure(mk, url);
        _say('A1 media_kit · 进程内第 1 次: $mk1');
        if (!mk1.startsWith('OK')) failed = true;
        final mk2 = await _measure(mk, url);
        _say('A2 media_kit · 同播放器第 2 次: $mk2');
        if (!mk2.startsWith('OK')) failed = true;
      } finally {
        await mk.dispose();
      }


      // ---- B 段：真实酷狗链路 ----
      _say('==== B 段：酷狗真实地址 ====');
      final container = ProviderContainer();
      await container.read(authControllerProvider.notifier).ensureReady();
      final logged = container.read(authControllerProvider).isLogged;
      _say('登录态: $logged');

      final tracks = await searchRepository.searchSongs('周杰伦', pageSize: 10);
      final withHash = tracks.where((t) => t.hash.isNotEmpty).toList();
      _say('搜索到 ${tracks.length} 首，其中带 hash ${withHash.length} 首');
      if (withHash.isEmpty) {
        _say('没有可用曲目');
        failed = true;
      } else {
        final track = withHash.first;
        _say('曲目: ${track.name} — ${track.artist} (hash=${track.hash})');
        final resolved = await playRepository.resolveUrlWithFallback(
          track,
          qualityCandidates: const ['128'],
        );
        if (resolved == null) {
          _say('解析失败: ${playRepository.lastError}');
          _say('（游客通道已关闭，需要先登录后再跑本探针）');
          failed = true;
        } else {
          _say('URL: ${resolved.url}');
          final engine2 = MediaKitPlayerImpl();
          try {
            final withH = await _measure(engine2, resolved.allUrls.first,
                headers: _headers);
            _say('B1 带 headers: $withH');
            final withoutH =
                await _measure(engine2, resolved.allUrls.first, headers: null);
            _say('B2 无 headers: $withoutH');
            if (!withH.startsWith('OK') && !withoutH.startsWith('OK')) {
              failed = true;
            }
          } finally {
            await engine2.dispose();
          }
        }
      }
    } catch (e, st) {
      _say('异常: $e');
      _say('${st.toString().split('\n').take(4).join(' ⏎ ')}');
      failed = true;
    }
    _say(failed ? 'PROBE RESULT: FAIL' : 'PROBE RESULT: OK');
    await Future<void>.delayed(const Duration(milliseconds: 400));
    exit(failed ? 1 : 0);
  }

  /// 在既有引擎上播一次并采样，返回 `OK …` 或失败原因。
  Future<String> _measure(
    AudioPlayerPort engine,
    String url, {
    Map<String, String>? headers,
    Duration window = const Duration(seconds: 6),
  }) async {
    var maxPosition = Duration.zero;
    var duration = Duration.zero;
    var buffered = Duration.zero;
    var playEvents = 0;
    var completed = 0;
    var lastError = '';
    final subs = <StreamSubscription<dynamic>>[
      engine.positionStream.listen((p) {
        if (p > maxPosition) maxPosition = p;
      }),
      engine.durationStream.listen((d) {
        if (d != null && d > duration) duration = d;
      }),
      engine.bufferedPositionStream.listen((b) {
        if (b > buffered) buffered = b;
      }),
      engine.playingStream.listen((p) {
        if (p) playEvents++;
      }),
      engine.completionStream.listen((r) {
        completed++;
        if (r == PlayerIdleReason.error) lastError = 'completion=error';
      }),
    ];
    try {
      try {
        await engine.playUrl(url, headers: headers);
      } catch (e) {
        return 'playUrl 抛错: ${e.toString().split('\n').first}';
      }
      await Future<void>.delayed(window);
      final stats = 'maxPos=${maxPosition.inMilliseconds}ms '
          'duration=${duration.inMilliseconds}ms '
          'buffered=${buffered.inMilliseconds}ms '
          'playEvents=$playEvents completed=$completed'
          '${lastError.isEmpty ? '' : ' $lastError'}';
      return maxPosition > const Duration(milliseconds: 200)
          ? 'OK 真的在放 | $stats'
          : '进度没走 | $stats';
    } finally {
      for (final s in subs) {
        await s.cancel();
      }
    }
  }

  /// 生成 [seconds] 秒 440Hz 正弦波 WAV（16bit / 44.1kHz / 单声道）。
  Future<File> _writeToneWav({int seconds = 2}) async {
    const rate = 44100;
    final total = rate * seconds;
    final data = Int16List(total);
    for (var i = 0; i < total; i++) {
      // 两端淡入淡出，避免爆音。
      final t = i / total;
      final fade = math.min(1.0, math.min(t, 1 - t) * 20);
      data[i] = (math.sin(2 * math.pi * 440 * i / rate) * 12000 * fade).round();
    }
    final dataBytes = data.buffer.asUint8List();
    final header = BytesBuilder();
    void ascii(String s) => header.add(s.codeUnits);
    void u32(int v) => header.add(
        Uint8List(4)..buffer.asByteData().setUint32(0, v, Endian.little));
    void u16(int v) => header.add(
        Uint8List(2)..buffer.asByteData().setUint16(0, v, Endian.little));

    ascii('RIFF');
    u32(36 + dataBytes.length);
    ascii('WAVE');
    ascii('fmt ');
    u32(16);
    u16(1); // PCM
    u16(1); // mono
    u32(rate);
    u32(rate * 2); // byte rate
    u16(2); // block align
    u16(16); // bits
    ascii('data');
    u32(dataBytes.length);

    final dir = await Directory.systemTemp.createTemp('kugo_probe');
    final file = File('${dir.path}${Platform.pathSeparator}tone.wav');
    await file.writeAsBytes([...header.takeBytes(), ...dataBytes]);
    return file;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF101216),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'kugo · Windows 音频探针',
                style: TextStyle(color: Colors.white, fontSize: 18),
              ),
              const SizedBox(height: 12),
              for (final line in _log)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: SelectableText(
                    line,
                    style: const TextStyle(
                      color: Color(0xFFB8C0CC),
                      fontSize: 12,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
