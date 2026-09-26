import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/cache/cover_cache.dart';
import '../../core/theme/cover_palette.dart';
import '../../core/theme/kugo_theme.dart';
import '../../core/theme/kugo_tokens.dart';

/// Album/playlist cover. Network art is cached on disk via [CoverCache];
/// falls back to a seed gradient while loading or on error.
class CoverBox extends StatefulWidget {
  const CoverBox({
    super.key,
    required this.seed,
    this.size = 56,
    this.radius = KugoRadius.cover,
    this.child,
  });

  /// Image URL, or any string used as a color-seed fallback.
  final String seed;

  /// Edge length. Use `0` or `double.infinity` to fill the parent box.
  final double size;
  final double radius;
  final Widget? child;

  /// Infinite/NaN/<=0 all mean "size to parent".
  bool get _fillsParent => size <= 0 || size.isInfinite || size.isNaN;

  bool get _isNetwork {
    final s = seed.trim();
    return s.startsWith('http://') || s.startsWith('https://');
  }

  @override
  State<CoverBox> createState() => _CoverBoxState();
}

class _CoverBoxState extends State<CoverBox> {
  Uint8List? _bytes;
  String? _resolvedFor;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant CoverBox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.seed != widget.seed) {
      _bytes = null;
      _resolve();
    }
  }

  Future<void> _resolve() async {
    final url = widget.seed.trim();
    if (!widget._isNetwork) {
      _resolvedFor = url;
      if (mounted) setState(() => _bytes = null);
      return;
    }
    // Already showing this URL — skip (cache hits would be free, but avoid setState).
    if (_resolvedFor == url && _bytes != null) return;

    _resolvedFor = url;
    // Sync memory hit first so the first frame after Hero landing is real art.
    final peeked = CoverCache.instance.peek(url);
    if (peeked != null) {
      _bytes = peeked;
      return;
    }
    final bytes = await CoverCache.instance.get(url);
    if (!mounted || _resolvedFor != url) return;
    setState(() => _bytes = bytes);
  }

  @override
  Widget build(BuildContext context) {
    // 封面出来（或 seed 换了退回占位）时做交叉淡入——直接硬切会出现
    // 「一片渐变占位 → 图片齐刷刷蹦出来」，列表尤其明显。
    if (widget._fillsParent) {
      return SizedBox.expand(
        child: AnimatedSwitcher(
          duration: _kCoverFade,
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          child: _content(fill: true),
        ),
      );
    }
    return AnimatedSwitcher(
      duration: _kCoverFade,
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      child: _content(fill: false),
    );
  }

  /// 占位 → 图片（或反向）。两个分支带不同的 key，AnimatedSwitcher 才知道要过渡。
  Widget _content({required bool fill}) {
    final bytes = _bytes;
    if (!widget._isNetwork || bytes == null) {
      return KeyedSubtree(
        key: ValueKey('cover-placeholder-${widget.seed}'),
        child: _placeholder(fill: fill),
      );
    }
    return ClipRRect(
      key: ValueKey('cover-image-${widget.seed}'),
      borderRadius: BorderRadius.circular(widget.radius),
      child: Image.memory(
        bytes,
        key: ValueKey(widget.seed),
        fit: BoxFit.cover,
        gaplessPlayback: true,
        width: fill ? null : widget.size,
        height: fill ? null : widget.size,
        // 解码出第一帧之前保持透明，否则会先闪一帧空白再淡入。
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          if (wasSynchronouslyLoaded) return child;
          return AnimatedOpacity(
            opacity: frame == null ? 0 : 1,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            child: child,
          );
        },
        errorBuilder: (context, error, stackTrace) => _placeholder(fill: fill),
      ),
    );
  }

  Widget _placeholder({required bool fill}) {
    final kugo = KugoTheme.of(context);
    final colors = CoverPalette.fromSeed(widget.seed, kugo.palette);
    final box = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(widget.radius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
          stops: const [0.0, 0.55, 1.0],
        ),
      ),
      child: widget.child == null ? null : Center(child: widget.child),
    );
    if (fill) return box;
    return SizedBox(width: widget.size, height: widget.size, child: box);
  }
}

/// 交叉淡入时长。与 mini_player_bar / common 的 220ms 靠拢，别再开新档。
const Duration _kCoverFade = Duration(milliseconds: 240);

CoverBox? _coverFromHeroContext(BuildContext context) {
  final w = context.widget;
  if (w is Hero) {
    final child = w.child;
    if (child is CoverBox) return child;
    if (child is ClipRRect && child.child is CoverBox) return child.child as CoverBox;
    if (child is Material && child.child is CoverBox) return child.child as CoverBox;
  }
  return null;
}

/// Keep the Hero flight on real cover bytes (not the async CoverBox
/// placeholder) so the last frame of the player transition doesn't flash.
Widget coverHeroFlightShuttle(
  BuildContext context,
  Animation<double> animation,
  HeroFlightDirection flightDirection,
  BuildContext fromHeroContext,
  BuildContext toHeroContext,
) {
  final from = _coverFromHeroContext(fromHeroContext);
  final to = _coverFromHeroContext(toHeroContext);
  final seed = to?.seed ?? from?.seed ?? '';
  final fromRadius = from?.radius ?? KugoRadius.cover;
  final toRadius = to?.radius ?? KugoRadius.cover;
  final bytes = seed.isEmpty ? null : CoverCache.instance.peek(seed);

  final isPush = flightDirection == HeroFlightDirection.push;

  return AnimatedBuilder(
    animation: animation,
    builder: (context, _) {
      final progress = isPush ? animation.value : (1.0 - animation.value);
      final t = Curves.easeInOutCubic.transform(progress);
      // Push: source → dest; Pop: from/to contexts are swapped by HeroController,
      // and progress normalized so 0.0 is flight start and 1.0 is landing.
      final radius = fromRadius + (toRadius - fromRadius) * t;

      final Widget child;
      if (bytes != null) {
        child = Image.memory(
          bytes,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          width: double.infinity,
          height: double.infinity,
        );
      } else {
        child = CoverBox(seed: seed, size: 0, radius: radius);
      }

      return ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: child,
      );
    },
  );
}

/// Shared cover hero for list/grid → detail (and mini-player ↔ full-player).
class CoverHero extends StatelessWidget {
  const CoverHero({
    super.key,
    required this.tag,
    required this.seed,
    this.size = 56,
    this.radius = KugoRadius.cover,
    this.child,
  });

  final String tag;
  final String seed;
  final double size;
  final double radius;

  /// Placeholder overlay when the seed has no network art (e.g. person icon).
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Hero(
      tag: tag,
      flightShuttleBuilder: coverHeroFlightShuttle,
      child: CoverBox(seed: seed, size: size, radius: radius, child: child),
    );
  }
}
