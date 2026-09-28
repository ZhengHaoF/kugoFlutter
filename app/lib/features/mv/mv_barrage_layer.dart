import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/models/barrage.dart';
import '../../core/source/capabilities.dart';
import '../../core/source/music_platform.dart';
import '../../core/source/registry.dart';
import '../auth/auth_token_holder.dart';

/// MV 弹幕飞层。叠在视频上，[IgnorePointer] 穿透、不抢播控手势。
///
/// 数据按 MV 主 hash 从 [MvBarrageSource] 拉取；同屏最多 [kBarrageLanes] 条，
/// 逐条从右往左飞。自行管理「播放暂停 → 弹幕暂停 / 恢复」，与音频队列无关。
///
/// 对齐 EchoMusic `components/music/BarrageLayer.vue` 的行为：
/// 池上限、轨道数、密度间隔、飞行时长、自己弹幕回流抑制均同一套常量
/// （见 `core/models/barrage.dart`）。
class MvBarrageLayer extends StatefulWidget {
  const MvBarrageLayer({
    super.key,
    required this.hash,
    required this.enabled,
    required this.playing,
    required this.config,
    this.name = '',
    this.platform = MusicPlatform.kugou,
  });

  /// 弹幕分池用的 MV 主 hash。
  final String hash;
  final bool enabled;
  final bool playing;
  final BarrageConfig config;

  /// MV 标题（`childrenname`，发送时用）。
  final String name;
  final MusicPlatform platform;

  @override
  State<MvBarrageLayer> createState() => MvBarrageLayerState();
}

class MvBarrageLayerState extends State<MvBarrageLayer>
    with TickerProviderStateMixin {
  final List<_Flight> _flights = [];
  final List<BarrageItem> _pendingOwn = [];

  /// 自己刚发的弹幕 → 抑制到期的毫秒时间戳（避免接口回流后紧接着重复）。
  final Map<String, int> _recentOwn = {};

  List<BarrageItem> _items = const [];
  int _cursor = 0;
  int _seq = 0;
  int _generation = 0;
  Timer? _timer;
  bool _loading = false;
  String _error = '';
  double _width = 0;

  MvBarrageSource? get _source =>
      musicSourceRegistry?.capability<MvBarrageSource>(widget.platform);

  bool get _hasHash => widget.hash.trim().isNotEmpty;
  bool get _running => widget.enabled && widget.playing && _hasHash;

  @override
  void initState() {
    super.initState();
    if (widget.enabled) _load();
    _refreshTimer();
  }

  @override
  void didUpdateWidget(covariant MvBarrageLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    final old = oldWidget;
    final hashChanged = old.hash != widget.hash;
    final enabledNow = widget.enabled && !old.enabled;

    if (hashChanged) {
      _generation++;
      _reset();
    }
    // 几何 / 速度变化会让飞行轨迹跳位，重建（对齐 EchoMusic 的 watch）。
    if (old.config.fontSize != widget.config.fontSize ||
        old.config.speed != widget.config.speed ||
        old.config.area != widget.config.area) {
      _clearFlights();
    }
    if (!widget.enabled && old.enabled) {
      _clearFlights();
      _pendingOwn.clear();
    }
    if ((hashChanged || enabledNow) && widget.enabled) _load();

    if (old.playing != widget.playing) {
      for (final f in _flights) {
        if (widget.playing) {
          f.controller.forward();
        } else {
          f.controller.stop(canceled: false);
        }
      }
    }
    _refreshTimer();
  }

  @override
  void dispose() {
    _generation++;
    _timer?.cancel();
    _timer = null;
    _clearFlights();
    super.dispose();
  }

  /// 外部（发送成功后）调用：把自己发的弹幕立即放出来，并静默刷新池。
  void showOwn(String text) {
    final trimmed = text.trim();
    if (!widget.enabled || !_hasHash || trimmed.isEmpty) return;
    _pendingOwn.add(
      BarrageItem(
        text: trimmed,
        userId: normalizeBarrageUserId(AuthTokenHolder.instance.userId),
      ),
    );
    _launch(onlyOwn: true);
    unawaited(_load(preserve: true));
  }

  // ── 拉取 ────────────────────────────────────────────────

  Future<void> _load({bool preserve = false}) async {
    final generation = ++_generation;
    _error = '';
    if (!widget.enabled || !_hasHash) return;
    final src = _source;
    if (src == null) return;

    if (!preserve) {
      _items = const [];
      _cursor = 0;
      _clearFlights();
      _pendingOwn.clear();
      _recentOwn.clear();
    }
    _loading = true;
    if (mounted) setState(() {});

    final list = await src.fetchMvBarrage(
      widget.hash,
      page: 1,
      pageSize: kBarrageLimit,
    );
    if (!mounted || generation != _generation) return;
    // 审核中暂时返回空列表时保留当前播放池（对齐 EchoMusic preservePlayback）。
    if (preserve && list.isEmpty && _items.isNotEmpty) {
      _loading = false;
      setState(() {});
      return;
    }
    _items = list;
    _loading = false;
    _error = list.isEmpty ? src.barrageError : '';
    setState(() {});
    _refreshTimer();
  }

  // ── 发射 ────────────────────────────────────────────────

  void _refreshTimer() {
    _timer?.cancel();
    _timer = null;
    if (!_running) return;
    _timer = Timer.periodic(
      Duration(milliseconds: barrageIntervalMs(widget.config.density)),
      (_) => _launch(),
    );
  }

  void _launch({bool onlyOwn = false}) {
    if (!_running || _width <= 0) return;
    final lane = firstFreeBarrageLane(_flights.map((f) => f.lane));
    if (lane < 0) return;

    BarrageItem? item;
    if (_pendingOwn.isNotEmpty) {
      item = _pendingOwn.removeAt(0);
      _recentOwn[item.identity] = DateTime.now().millisecondsSinceEpoch +
          _ownSuppressMs();
    } else if (!onlyOwn) {
      final now = DateTime.now().millisecondsSinceEpoch;
      // 长弹幕仍在屏幕上时，继续抑制它的接口回流副本。
      for (final f in _flights) {
        if (_recentOwn.containsKey(f.item.identity)) {
          _recentOwn[f.item.identity] = now + 5000;
        }
      }
      item = _nextItem(now);
    }
    if (item == null) return;
    _pushFlight(item, lane);
  }

  BarrageItem? _nextItem(int now) {
    if (_items.isEmpty) return null;
    _recentOwn.removeWhere((_, expiry) => expiry <= now);
    for (var n = 0; n < _items.length; n++) {
      final item = _items[_cursor++ % _items.length];
      if (!_recentOwn.containsKey(item.identity)) return item;
    }
    return null;
  }

  void _pushFlight(BarrageItem item, int lane) {
    final textWidth = _measure(item.text);
    final controller = AnimationController(
      vsync: this,
      duration: Duration(
        milliseconds: barrageTravelMs(
          containerWidth: _width,
          textWidth: textWidth,
          speed: widget.config.speed,
        ),
      ),
    );
    final flight = _Flight(
      item: item,
      lane: lane,
      id: ++_seq,
      controller: controller,
      textWidth: textWidth,
    );
    controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) _removeFlight(flight.id);
    });
    _flights.add(flight);
    controller.forward();
    if (mounted) setState(() {});
  }

  void _removeFlight(int id) {
    final index = _flights.indexWhere((f) => f.id == id);
    if (index < 0) return;
    final flight = _flights.removeAt(index);
    flight.controller.dispose();
    if (mounted) setState(() {});
    // 刚飞完一条，继续把队列里剩下的自己弹幕放出去。
    _launch(onlyOwn: true);
  }

  void _reset() {
    _items = const [];
    _cursor = 0;
    _pendingOwn.clear();
    _recentOwn.clear();
    _error = '';
    _clearFlights();
  }

  void _clearFlights() {
    for (final f in _flights) {
      f.controller.dispose();
    }
    _flights.clear();
  }

  int _ownSuppressMs() {
    final speed = widget.config.speed <= 0 ? 1.0 : widget.config.speed;
    final ms = (10000 / speed + 5000).round();
    return ms < 20000 ? 20000 : ms;
  }

  double _measure(String text) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: _textStyle(widget.config)),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }

  static TextStyle _textStyle(BarrageConfig config) => TextStyle(
        fontSize: config.fontSize,
        fontWeight: FontWeight.w600,
        height: 1.4,
        color: Colors.white,
        shadows: const [
          Shadow(offset: Offset(0, 1), blurRadius: 3, color: Colors.black),
          Shadow(offset: Offset(1, 0), blurRadius: 2, color: Colors.black),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final config = widget.config;
    return IgnorePointer(
      child: ClipRect(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            if (width != _width) _width = width;
            final areaHeight = (constraints.maxHeight * config.area / 100)
                .clamp(0.0, constraints.maxHeight);
            final laneHeight = areaHeight / kBarrageLanes;
            return Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                if (widget.enabled)
                  for (final flight in _flights)
                    Positioned(
                      top: flight.lane * laneHeight + 2,
                      left: 0,
                      child: Opacity(
                        opacity: config.opacity / 100,
                        child: AnimatedBuilder(
                          animation: flight.controller,
                          builder: (context, child) => Transform.translate(
                            offset: Offset(
                              width -
                                  flight.controller.value *
                                      (width + flight.textWidth),
                              0,
                            ),
                            child: child,
                          ),
                          child: Text(
                            flight.item.text,
                            maxLines: 1,
                            softWrap: false,
                            style: _textStyle(config),
                          ),
                        ),
                      ),
                    ),
                if (widget.enabled &&
                    _flights.isEmpty &&
                    _pendingOwn.isEmpty &&
                    (_loading || _error.isNotEmpty || _items.isEmpty))
                  Positioned(
                    right: 16,
                    top: 12,
                    child: _BarrageStatus(loading: _loading, error: _error),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Flight {
  _Flight({
    required this.item,
    required this.lane,
    required this.id,
    required this.controller,
    required this.textWidth,
  });

  final BarrageItem item;
  final int lane;
  final int id;
  final AnimationController controller;
  final double textWidth;
}

class _BarrageStatus extends StatelessWidget {
  const _BarrageStatus({required this.loading, required this.error});

  final bool loading;
  final String error;

  @override
  Widget build(BuildContext context) {
    final text = loading
        ? '弹幕加载中…'
        : (error.isNotEmpty ? '弹幕加载失败，请关闭后重开' : '暂无弹幕');
    return Text(
      text,
      style: const TextStyle(
        color: Colors.white70,
        fontSize: 12,
        shadows: [Shadow(offset: Offset(0, 1), blurRadius: 3, color: Colors.black)],
      ),
    );
  }
}