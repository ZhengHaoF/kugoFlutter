import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api/mappers.dart';
import '../../core/cache/cover_cache.dart';
import 'cover_box.dart';

/// 打开封面大图查看器。
///
/// Hero 从调用处的封面飞入（[tag] 与页面上的 `CoverHero` 一致）。退出：
/// 点击空白处 / 拖拽下拉 / Esc / 右上角关闭钮。查看器内部先展示已缓存的
/// 原图，拉到 [coverLargeUrl] 的大图变体后交叉淡入——首帧不空、不闪。
Future<void> showCoverViewer(
  BuildContext context, {
  required String seed,
  required String tag,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '关闭',
    barrierColor: Colors.black87,
    transitionDuration: const Duration(milliseconds: 240),
    pageBuilder: (dialogContext, _, _) => CoverViewer(seed: seed, tag: tag),
    transitionBuilder: (context, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(opacity: curved, child: child);
    },
  );
}

/// 全屏封面大图：捏合/触控板缩放、拖拽下拉关闭、点击/Esc 关闭。
class CoverViewer extends StatefulWidget {
  const CoverViewer({super.key, required this.seed, required this.tag});

  /// 封面 URL（与页面 CoverHero 的 seed 一致）。
  final String seed;

  /// Hero 标签（与页面 CoverHero 的 tag 一致）。
  final String tag;

  @override
  State<CoverViewer> createState() => _CoverViewerState();
}

class _CoverViewerState extends State<CoverViewer>
    with SingleTickerProviderStateMixin {
  final TransformationController _transform = TransformationController();

  /// 下拉关闭的位移；同时决定内容透明度（下拉越多越淡）。
  double _dragY = 0;

  /// 松手回弹动画（下拉未过阈值时弹回原位）。
  late final AnimationController _spring;
  double _springFrom = 0;

  Uint8List? _bytes;
  bool _bigLoaded = false;
  bool _closing = false;

  /// 缩放态才允许 InteractiveViewer 平移；未缩放时纵拖留给「下拉关闭」。
  bool _panEnabled = false;

  double get _scale => _transform.value.entry(0, 0);

  @override
  void initState() {
    super.initState();
    // 必须 eager 建：懒初始化的话，没拖拽过就关闭查看器时 dispose() 首次
    // 访问 _spring 会在元素已卸载后 createTicker（查祖先直接抛）。
    _spring = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    )..addListener(() {
      if (!mounted) return;
      setState(() => _dragY = _springFrom * (1 - _spring.value));
    });
    _transform.addListener(_onTransformChanged);
    _load();
  }

  /// 捏合放大后要翻 `panEnabled`，否则缩放了却平移不了。
  void _onTransformChanged() {
    if (!mounted) return;
    final zoomed = _scale > 1.001;
    if (zoomed != _panEnabled) setState(() => _panEnabled = zoomed);
  }

  @override
  void dispose() {
    _transform.dispose();
    _spring.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final seed = widget.seed.trim();
    if (seed.isEmpty) return;
    // 1) 已缓存的原图先上（内存命中同步返回，首帧不空）。
    final small = CoverCache.instance.peek(seed);
    if (small != null && mounted) setState(() => _bytes = small);
    // 2) 拉大图变体；失败/无变体则保持原图。
    final bigUrl = coverLargeUrl(seed);
    final big = bigUrl == seed ? small : await CoverCache.instance.get(bigUrl);
    if (!mounted || big == null) return;
    setState(() {
      _bytes = big;
      _bigLoaded = true;
    });
  }

  void _dismiss() {
    if (_closing) return;
    _closing = true;
    Navigator.of(context).pop();
  }

  void _onDragUpdate(DragUpdateDetails d) {
    if (_scale > 1.001) return; // 缩放态下纵拖是平移，不是关闭
    _spring.stop();
    setState(() => _dragY = _dragY + d.primaryDelta!);
  }

  void _onDragEnd(DragEndDetails d) {
    final velocity = d.primaryVelocity ?? 0;
    if (_dragY.abs() > 120 || velocity.abs() > 700) {
      _dismiss();
      return;
    }
    _springFrom = _dragY;
    _spring.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.maybeOf(context);
    final decodeSide = mq == null
        ? 1080.0
        : math.max(mq.size.width, mq.size.height);
    final decodeWidth = mq == null
        ? null
        : coverDecodeWidth(decodeSide, mq.devicePixelRatio);

    final bytes = _bytes;
    // 大图到达后交叉淡入（同一张图、更清晰，布局不变所以不跳）。
    final image = AnimatedSwitcher(
      duration: const Duration(milliseconds: 240),
      child: bytes == null
          ? KeyedSubtree(
              key: const ValueKey('placeholder'),
              child: CoverBox(seed: widget.seed, size: 0, radius: 0),
            )
          : KeyedSubtree(
              key: ValueKey('bytes-$_bigLoaded'),
              child: Image.memory(
                bytes,
                fit: BoxFit.contain,
                gaplessPlayback: true,
                cacheWidth: decodeWidth,
              ),
            ),
    );

    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.escape): _DismissIntent(),
      },
      child: Actions(
        actions: {
          _DismissIntent: CallbackAction<_DismissIntent>(onInvoke: (_) {
            _dismiss();
            return null;
          }),
        },
        child: Focus(
          autofocus: true,
          child: Stack(
            children: [
              // 1) 空白处点击关闭。
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _dismiss,
                ),
              ),
              // 2) 图片本体：缩放 + 下拉关闭 + 点击关闭。
              Center(
                child: Opacity(
                  opacity: (1 - _dragY.abs() / 400).clamp(0.3, 1.0),
                  child: Transform.translate(
                    offset: Offset(0, _dragY),
                    child: SizedBox.expand(
                      child: InteractiveViewer(
                        transformationController: _transform,
                        maxScale: 4,
                        minScale: 1,
                        // 未缩放时纵拖交给外层做「下拉关闭」；缩放态才平移。
                        panEnabled: _panEnabled,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: _scale > 1.001 ? null : _dismiss,
                          onVerticalDragUpdate: _onDragUpdate,
                          onVerticalDragEnd: _onDragEnd,
                          child: Hero(
                            tag: widget.tag,
                            flightShuttleBuilder: coverHeroFlightShuttle,
                            child: image,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // 3) 关闭钮 + 操作提示。
              Positioned(
                top: 0,
                right: 0,
                child: SafeArea(
                  child: IconButton(
                    tooltip: '关闭',
                    color: Colors.white70,
                    icon: const Icon(Icons.close_rounded, size: 28),
                    onPressed: _dismiss,
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: Center(
                      child: Text(
                        '下拉关闭 · 捏合缩放',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.55),
                          fontSize: 12,
                        ),
                      ),
                    ),
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

class _DismissIntent extends Intent {
  const _DismissIntent();
}
