import 'package:flutter/material.dart';

import '../../core/theme/cover_palette.dart';
import '../../core/theme/kugo_tokens.dart';

/// Album/playlist cover. Loads network images; falls back to seed gradient.
class CoverBox extends StatelessWidget {
  const CoverBox({
    super.key,
    required this.seed,
    this.size = 56,
    this.radius = KugoRadius.cover,
    this.child,
  });

  /// Image URL, or any string used as a color-seed fallback.
  final String seed;
  final double size;
  final double radius;
  final Widget? child;

  bool get _fillsParent => size <= 0;

  bool get _isNetwork {
    final s = seed.trim();
    return s.startsWith('http://') || s.startsWith('https://');
  }

  @override
  Widget build(BuildContext context) {
    final colors = CoverPalette.fromSeed(seed);
    final fallback = BoxDecoration(
      borderRadius: BorderRadius.circular(radius),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: colors,
        stops: const [0.0, 0.55, 1.0],
      ),
    );

    Widget placeholder() {
      final box = DecoratedBox(
        decoration: fallback,
        child: child == null ? null : Center(child: child),
      );
      if (_fillsParent) return box;
      return SizedBox(width: size, height: size, child: box);
    }

    if (!_isNetwork) return placeholder();

    final image = Image.network(
      seed,
      fit: BoxFit.cover,
      width: _fillsParent ? null : size,
      height: _fillsParent ? null : size,
      errorBuilder: (context, error, stackTrace) => placeholder(),
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return placeholder();
      },
      headers: const {
        'Referer': 'http://www.kugou.com/',
        'User-Agent':
            'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
      },
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: image,
    );
  }
}
