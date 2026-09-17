import 'package:flutter/material.dart';

import '../../core/models/track.dart';
import '../../core/theme/kugo_tokens.dart';

class LyricsView extends StatelessWidget {
  const LyricsView({
    super.key,
    required this.lines,
    required this.positionMs,
    this.onTapLine,
    this.compact = false,
  });

  final List<LyricLine> lines;
  final int positionMs;
  final ValueChanged<int>? onTapLine;

  /// When true, only shows current ± 1 lines (player bottom preview).
  final bool compact;

  int get activeIndex {
    var active = 0;
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].timeMs <= positionMs) active = i;
    }
    return active;
  }

  @override
  Widget build(BuildContext context) {
    if (lines.isEmpty) {
      return Center(
        child: Text('暂无歌词', style: KugoTypography.caption),
      );
    }

    if (compact) {
      final start = (activeIndex - 1).clamp(0, lines.length - 1);
      final visible = lines.skip(start).take(3).toList();
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < visible.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                visible[i].text,
                textAlign: TextAlign.center,
                style: _lineStyle(start + i == activeIndex),
              ),
            ),
        ],
      );
    }

    return ListView.builder(
      controller: ScrollController(),
      padding: const EdgeInsets.symmetric(horizontal: KugoSpacing.xl, vertical: 12),
      itemCount: lines.length,
      itemBuilder: (context, index) {
        final isActive = index == activeIndex;
        return GestureDetector(
          onTap: onTapLine == null ? null : () => onTapLine!(lines[index].timeMs),
          behavior: HitTestBehavior.opaque,
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 180),
            style: _lineStyle(isActive),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                lines[index].text,
                textAlign: TextAlign.center,
              ),
            ),
          ),
        );
      },
    );
  }

  TextStyle _lineStyle(bool active) {
    return KugoTypography.body.copyWith(
      fontSize: active ? 18 : 15,
      height: 1.55,
      color: active ? KugoColors.textPrimary : KugoColors.textTertiary,
      fontWeight: active ? FontWeight.w600 : FontWeight.w400,
    );
  }
}
