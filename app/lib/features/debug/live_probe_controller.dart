import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/api/endpoints.dart';
import '../../core/api/kugo_client.dart';
import '../../data/repositories/search_repository.dart';

enum ProbeStatus { idle, ok, fail, filtered, probing }

class LiveProbeTarget {
  LiveProbeTarget({
    required this.id,
    required this.label,
    required this.run,
  });

  final String id;
  final String label;
  final Future<void> Function() run;

  ProbeStatus status = ProbeStatus.idle;
  int latencyMs = -1;
  String message = '';
  DateTime? lastAt;
}

/// Continuous background probes for the network debug screen.
class LiveProbeController extends ChangeNotifier {
  LiveProbeController({KugoClient? client, SearchRepository? search})
      : _client = client ?? kugoClient,
        _search = search ?? searchRepository {
    targets = [
      LiveProbeTarget(
        id: 'search',
        label: '搜索',
        run: () async {
          final list = await _search.searchSongs('晴天', pageSize: 1);
          if (list.isEmpty) throw Exception('空结果');
        },
      ),
      LiveProbeTarget(
        id: 'hot',
        label: '热搜',
        run: () async {
          final hot = await _search.hotKeywords();
          if (hot.isEmpty) throw Exception('空结果');
        },
      ),
      LiveProbeTarget(
        id: 'lyric',
        label: '歌词',
        run: () async {
          final url = buildUrl(
            KugoEndpoints.lyrics,
            KugoEndpoints.lyricSearch,
            {
              'ver': 1,
              'man': 'yes',
              'client': 'pc',
              'keyword': '周杰伦',
              'hash': '',
              'timelength': 0,
            },
          );
          final text = await _client.getText(url);
          if (!text.contains('candidates') && !text.contains('id')) {
            throw Exception('响应异常');
          }
        },
      ),
      LiveProbeTarget(
        id: 'play',
        label: '播放域',
        run: () async {
          final url = buildUrl(
            KugoEndpoints.wwwApi,
            KugoEndpoints.playData,
            {
              'r': 'play/getdata',
              'hash': 'b3a52a7a958bf0aed0ebfba2e9a818b7',
              'mid': 'kugo_mid',
              'guid': 'kugo_guid',
              'platid': 4,
              'appid': 1014,
            },
          );
          final data = await _client.getJson(url);
          final s = data.toString();
          if (s.contains('URL过滤') || s.contains('disable.htm')) {
            throw Exception('内容过滤');
          }
        },
      ),
      LiveProbeTarget(
        id: 'https',
        label: 'HTTPS',
        run: () async {
          final url = 'https://mobilecdn.kugou.com${KugoEndpoints.searchSong}';
          await _client.getJson(url, query: {
            'format': 'json',
            'keyword': '晴天',
            'page': 1,
            'pagesize': 1,
            'showtype': 1,
          });
        },
      ),
    ];
  }

  final KugoClient _client;
  final SearchRepository _search;

  late final List<LiveProbeTarget> targets;
  Timer? _timer;
  bool _enabled = false;
  int _intervalSec = 5;
  int _round = 0;

  bool get enabled => _enabled;
  int get intervalSec => _intervalSec;
  int get round => _round;

  void setInterval(int seconds) {
    _intervalSec = seconds.clamp(2, 60);
    notifyListeners();
    if (_enabled) {
      _timer?.cancel();
      _timer = Timer.periodic(
        Duration(seconds: _intervalSec),
        (_) => unawaited(tick()),
      );
    }
  }

  void setEnabled(bool value) {
    _enabled = value;
    notifyListeners();
    _timer?.cancel();
    _timer = null;
    if (value) {
      unawaited(tick());
      _timer = Timer.periodic(
        Duration(seconds: _intervalSec),
        (_) => unawaited(tick()),
      );
    } else {
      for (final t in targets) {
        if (t.status == ProbeStatus.probing) {
          t.status = ProbeStatus.idle;
        }
      }
      notifyListeners();
    }
  }

  Future<void> tick() async {
    _round += 1;
    notifyListeners();
    // Sequential to avoid stampeding filtered hosts.
    for (final t in targets) {
      t.status = ProbeStatus.probing;
      notifyListeners();
      final sw = Stopwatch()..start();
      try {
        await t.run();
        t
          ..status = ProbeStatus.ok
          ..latencyMs = sw.elapsedMilliseconds
          ..message = 'OK'
          ..lastAt = DateTime.now();
      } catch (e) {
        final msg = e.toString().split('\n').first;
        final filtered = msg.contains('URL过滤') ||
            msg.contains('内容过滤') ||
            msg.contains('disable.htm') ||
            msg.contains('Connection terminated') ||
            msg.contains('Handshake');
        t
          ..status = filtered ? ProbeStatus.filtered : ProbeStatus.fail
          ..latencyMs = sw.elapsedMilliseconds
          ..message = filtered ? '被过滤/不可达' : msg
          ..lastAt = DateTime.now();
      }
      notifyListeners();
    }
  }

  String buildLiveReport() {
    final buf = StringBuffer()
      ..writeln('== 实时探测 round=$_round interval=${_intervalSec}s ==');
    for (final t in targets) {
      final st = switch (t.status) {
        ProbeStatus.ok => 'OK',
        ProbeStatus.fail => 'FAIL',
        ProbeStatus.filtered => 'FILTERED',
        ProbeStatus.probing => 'PROBING',
        ProbeStatus.idle => 'IDLE',
      };
      buf.writeln(
        '${t.label}: $st'
        '${t.latencyMs >= 0 ? ' ${t.latencyMs}ms' : ''}'
        '${t.message.isEmpty ? '' : '  ${t.message}'}',
      );
    }
    return buf.toString();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
