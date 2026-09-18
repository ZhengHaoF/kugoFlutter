import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/cache/cover_cache.dart';
import '../../core/theme/cover_palette.dart';
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
    final bytes = await CoverCache.instance.get(url);
    if (!mounted || _resolvedFor != url) return;
    setState(() => _bytes = bytes);
  }

  @override
  Widget build(BuildContext context) {
    final colors = CoverPalette.fromSeed(widget.seed);
    final fallback = BoxDecoration(
      borderRadius: BorderRadius.circular(widget.radius),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: colors,
        stops: const [0.0, 0.55, 1.0],
      ),
    );

    Widget placeholder() {
      if (widget._fillsParent) {
        return SizedBox.expand(
          child: DecoratedBox(
            decoration: fallback,
            child: widget.child == null ? null : Center(child: widget.child),
          ),
        );
      }
      final box = DecoratedBox(
        decoration: fallback,
        child: widget.child == null ? null : Center(child: widget.child),
      );
      return SizedBox(width: widget.size, height: widget.size, child: box);
    }

    if (!widget._isNetwork) return placeholder();

    final bytes = _bytes;
    if (bytes == null) return placeholder();

    final image = Image.memory(
      bytes,
      key: ValueKey(widget.seed),
      fit: BoxFit.cover,
      gaplessPlayback: true,
      width: widget._fillsParent ? null : widget.size,
      height: widget._fillsParent ? null : widget.size,
      errorBuilder: (context, error, stackTrace) => placeholder(),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.radius),
      child: image,
    );
  }
}
