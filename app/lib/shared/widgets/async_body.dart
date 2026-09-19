import 'package:flutter/material.dart';

import '../../core/theme/kugo_tokens.dart';
import '../../core/theme/kugo_theme.dart';

/// Loading / empty / error body shell used across list pages.
class AsyncBody extends StatelessWidget {
  const AsyncBody({
    super.key,
    required this.loading,
    required this.hasError,
    required this.isEmpty,
    required this.child,
    this.onRetry,
    this.emptyMessage = '暂无内容',
    this.errorMessage = '加载失败',
  });

  final bool loading;
  final bool hasError;
  final bool isEmpty;
  final Widget child;
  final VoidCallback? onRetry;
  final String emptyMessage;
  final String errorMessage;

  @override
  Widget build(BuildContext context) {
    if (loading) return const SkeletonList();
    if (hasError) {
      return _StatusView(
        icon: Icons.wifi_off_rounded,
        message: errorMessage,
        actionLabel: '重试',
        onAction: onRetry,
      );
    }
    if (isEmpty) {
      return _StatusView(
        icon: Icons.music_off_rounded,
        message: emptyMessage,
        actionLabel: onRetry == null ? null : '刷新',
        onAction: onRetry,
      );
    }
    return child;
  }
}

class SkeletonList extends StatelessWidget {
  const SkeletonList({super.key, this.itemCount = 6});

  final int itemCount;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(KugoSpacing.lg),
      itemCount: itemCount,
      itemBuilder: (_, _) => const Padding(
        padding: EdgeInsets.only(bottom: KugoSpacing.md),
        child: _SkeletonRow(),
      ),
    );
  }
}

class _SkeletonRow extends StatefulWidget {
  const _SkeletonRow();

  @override
  State<_SkeletonRow> createState() => _SkeletonRowState();
}

class _SkeletonRowState extends State<_SkeletonRow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final kugo = KugoTheme.of(context);
    return FadeTransition(
      opacity: Tween(begin: 0.35, end: 0.8).animate(_controller),
      child: Row(
        children: [
          _box(kugo, 52, 52, radius: KugoRadius.cover),
          const SizedBox(width: KugoSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _box(kugo, double.infinity, 14),
                const SizedBox(height: 8),
                _box(kugo, 120, 12),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _box(KugoTheme kugo, double w, double h, {double radius = 8}) {
    return Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: kugo.surfaceElevated,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

class _StatusView extends StatelessWidget {
  const _StatusView({
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final kugo = KugoTheme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: kugo.textTertiary),
          const SizedBox(height: KugoSpacing.md),
          Text(message, style: kugo.caption),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: KugoSpacing.lg),
            FilledButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}
