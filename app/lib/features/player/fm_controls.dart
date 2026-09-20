import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/fm_mode.dart';
import '../../core/models/track.dart';
import '../../core/theme/cover_palette.dart';
import '../../core/theme/kugo_theme.dart';
import '../../core/theme/kugo_tokens.dart';
import '../../shared/widgets/cover_box.dart';
import '../fm/fm_controller.dart';
import '../player/player_controller.dart';

/// 播放页上的 FM 紧凑入口：一行药丸，点开 [showFmSheet]。
///
/// 独立「私人 FM」页面撤掉后，这是 FM 在播放页的唯一常驻痕迹：
/// 高度约 36px，不挡歌词、不抢封面。
class FmEntryPill extends ConsumerWidget {
  const FmEntryPill({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kugo = KugoTheme.of(context);
    final fm = ref.watch(fmControllerProvider);
    final player = ref.watch(playerControllerProvider);
    final accent = CoverPalette.accentFromSeed(
      player.current?.coverUrl ?? 'fm',
      kugo.palette,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        KugoSpacing.lg,
        0,
        KugoSpacing.lg,
        KugoSpacing.sm,
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Semantics(
          button: true,
          label:
              '私人 FM 电台：${fm.pendingMode.stationTitle} · ${fm.pendingPool.label}',
          child: InkWell(
            borderRadius: BorderRadius.circular(KugoRadius.chip),
            onTap: () => showFmSheet(context),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: kugo.surface.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(KugoRadius.chip),
                border: Border.all(color: accent.withValues(alpha: 0.45)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.radio_rounded, size: 14, color: accent),
                  const SizedBox(width: 6),
                  Text(
                    '${fm.pendingMode.stationTitle} · ${fm.pendingPool.label}',
                    style: kugo.caption.copyWith(
                      color: kugo.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  // 有待生效的轴时给个小圆点，否则用户不知道切了没生效。
                  if (fm.hasPendingChange) ...[
                    const SizedBox(width: 6),
                    Container(
                      key: const ValueKey('fm_pending_dot'),
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                  const SizedBox(width: 4),
                  Icon(
                    Icons.keyboard_arrow_up_rounded,
                    size: 16,
                    color: kugo.textSecondary,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// FM 控制面板：自定义转场（上滑 + 淡入）+ 可拖拽展开。
///
/// 用 `showGeneralDialog` 而不是 `showModalBottomSheet`，才能自己控制转场曲线；
/// 里面套 `DraggableScrollableSheet`，可以下拉收回、上拉接近全屏，
/// 把原来 FM 页里唱片堆预告那部分容量补回来。
Future<void> showFmSheet(BuildContext context) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '关闭私人 FM 面板',
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (_, _, _) => const _FmSheet(),
    transitionBuilder: (context, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.12),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class _FmSheet extends ConsumerWidget {
  const _FmSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kugo = KugoTheme.of(context);
    final fm = ref.watch(fmControllerProvider);
    final player = ref.watch(playerControllerProvider);
    final fmCtl = ref.read(fmControllerProvider.notifier);
    final playerCtl = ref.read(playerControllerProvider.notifier);
    final accent = CoverPalette.accentFromSeed(
      player.current?.coverUrl ?? 'fm',
      kugo.palette,
    );
    final current = player.current;

    return Align(
      alignment: Alignment.bottomCenter,
      child: DraggableScrollableSheet(
        initialChildSize: 0.66,
        minChildSize: 0.32,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) {
          // 面板底色交给 Material 而不是 Container 的 decoration：
          // 里面是 ListTile，中间夹一层带背景的 DecoratedBox 会让它
          // 自己的背景和水波纹被盖住（框架会直接断言报错）。
          return Material(
            color: kugo.bg.withValues(alpha: 0.98),
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
              side: BorderSide(color: kugo.divider),
            ),
            child: CustomScrollView(
              controller: scrollController,
              slivers: [
                SliverToBoxAdapter(child: _grabber(kugo)),
                SliverToBoxAdapter(child: _header(context, kugo, fm, current)),
                SliverToBoxAdapter(child: _axisMode(kugo, fm, fmCtl)),
                SliverToBoxAdapter(child: _axisPool(kugo, fm, fmCtl)),
                SliverToBoxAdapter(
                  child: _transport(kugo, accent, player, fmCtl, playerCtl),
                ),
                SliverToBoxAdapter(child: _sourceBadge(kugo, fm)),
                const SliverToBoxAdapter(
                  child: SizedBox(height: KugoSpacing.md),
                ),
                SliverToBoxAdapter(child: _upcomingHeader(kugo, player)),
                _upcomingList(kugo, player, playerCtl),
                const SliverToBoxAdapter(
                  child: SizedBox(height: KugoSpacing.xxl),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _grabber(KugoTheme kugo) => Center(
    child: Container(
      margin: const EdgeInsets.only(
        top: KugoSpacing.sm,
        bottom: KugoSpacing.xs,
      ),
      width: 36,
      height: 4,
      decoration: BoxDecoration(
        color: kugo.textTertiary.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(2),
      ),
    ),
  );

  Widget _header(
    BuildContext context,
    KugoTheme kugo,
    FmSession fm,
    Track? current,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        KugoSpacing.lg,
        KugoSpacing.xs,
        KugoSpacing.sm,
        KugoSpacing.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  current?.name ?? fm.pendingMode.stationTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: kugo.title,
                ),
                const SizedBox(height: 2),
                Text(
                  '${fm.pendingMode.stationTitle} · ${fm.pendingMode.subtitle}'
                  '${current == null ? '' : ' · ${current.artist}'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: kugo.caption,
                ),
              ],
            ),
          ),
          if (current != null)
            ClipOval(
              child: SizedBox(
                width: 44,
                height: 44,
                child: CoverBox(seed: current.coverUrl, size: 44, radius: 999),
              ),
            ),
          IconButton(
            tooltip: '关闭',
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }

  Widget _axisMode(KugoTheme kugo, FmSession fm, FmController fmCtl) {
    return _AxisRow(
      kugo: kugo,
      label: '档位',
      hint: '下一首生效',
      pending: fm.hasPendingChange,
      child: _CapsuleSwitch<FmMode>(
        kugo: kugo,
        values: FmMode.values,
        labelOf: (m) => m.label,
        selected: fm.pendingMode,
        onChanged: fmCtl.setPendingMode,
      ),
    );
  }

  Widget _axisPool(KugoTheme kugo, FmSession fm, FmController fmCtl) {
    return _AxisRow(
      kugo: kugo,
      label: '歌池',
      hint: fm.hasPendingChange ? '待生效' : '下一首生效',
      pending: fm.hasPendingChange,
      trailing: fm.hasPendingChange
          ? TextButton(
              onPressed: fmCtl.applyPendingNow,
              child: const Text('立即生效'),
            )
          : null,
      child: _CapsuleSwitch<FmSongPool>(
        kugo: kugo,
        values: FmSongPool.values,
        labelOf: (p) => p.label,
        selected: fm.pendingPool,
        onChanged: fmCtl.setPendingPool,
      ),
    );
  }

  Widget _transport(
    KugoTheme kugo,
    Color accent,
    PlayerState player,
    FmController fmCtl,
    PlayerController playerCtl,
  ) {
    final track = player.current;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: KugoSpacing.lg,
        vertical: KugoSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: KugoSpacing.sm,
            runSpacing: KugoSpacing.xs,
            children: [
              if (track != null && track.durationMs > 0)
                _chip(kugo, track.durationLabel),
              if (track != null && track.quality.isNotEmpty)
                _chip(kugo, track.quality),
              if (track != null && track.language.isNotEmpty)
                _chip(kugo, track.language),
            ],
          ),
          const SizedBox(height: KugoSpacing.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _RoundAction(
                kugo: kugo,
                icon: Icons.thumb_down_alt_rounded,
                label: '不喜欢',
                onTap: fmCtl.dislike,
              ),
              _RoundAction(
                kugo: kugo,
                icon: player.isPlaying
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
                large: true,
                accent: accent,
                onTap: playerCtl.togglePlay,
              ),
              _RoundAction(
                kugo: kugo,
                icon: Icons.thumb_up_alt_rounded,
                label: '红心',
                onTap: () async {
                  await fmCtl.like();
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(KugoTheme kugo, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: kugo.surface.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(KugoRadius.chip),
        border: Border.all(color: kugo.divider),
      ),
      child: Text(text, style: kugo.caption),
    );
  }

  Widget _sourceBadge(KugoTheme kugo, FmSession fm) {
    final semantic = fm.pool.semantic.isEmpty ? '' : ' · ${fm.pool.semantic}';
    final text = fm.fromServer
        ? '来源：酷狗私人 FM · ${fm.pool.label}$semantic'
        : '来源：关键词检索 · ${fm.pool.reasonLabel}'
              '${fm.gatewayError.isEmpty ? '' : '（${fm.gatewayError}）'}';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KugoSpacing.lg),
      child: Text(
        text,
        style: kugo.caption.copyWith(color: kugo.textTertiary, fontSize: 11),
      ),
    );
  }

  Widget _upcomingHeader(KugoTheme kugo, PlayerState player) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        KugoSpacing.lg,
        KugoSpacing.sm,
        KugoSpacing.lg,
        KugoSpacing.xs,
      ),
      child: Row(
        children: [
          Text('接下来', style: kugo.section),
          const SizedBox(width: KugoSpacing.sm),
          Expanded(
            child: Text(
              '${player.queue.isEmpty ? 0 : player.queue.length - player.currentIndex - 1}'
              ' 首待播',
              style: kugo.caption,
            ),
          ),
        ],
      ),
    );
  }

  Widget _upcomingList(
    KugoTheme kugo,
    PlayerState player,
    PlayerController playerCtl,
  ) {
    final from = player.currentIndex + 1;
    final upcoming = player.queue.length > from
        ? player.queue.sublist(from, (from + 20).clamp(0, player.queue.length))
        : const <Track>[];
    if (upcoming.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(KugoSpacing.lg),
          child: Text('歌池正在续接…', style: kugo.caption),
        ),
      );
    }
    return SliverList.separated(
      itemCount: upcoming.length,
      separatorBuilder: (_, _) => Divider(color: kugo.divider, height: 1),
      itemBuilder: (context, i) {
        final t = upcoming[i];
        return ListTile(
          dense: true,
          leading: ClipOval(
            child: SizedBox(
              width: 36,
              height: 36,
              child: CoverBox(seed: t.coverUrl, size: 36, radius: 999),
            ),
          ),
          title: Text(t.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(t.artist, maxLines: 1),
          trailing: t.durationMs > 0
              ? Text(t.durationLabel, style: kugo.caption)
              : null,
          onTap: () {
            // 直接跳到待播列表里的某一首（原先侧立唱片堆的能力）。
            playerCtl.playAtIndex(from + i);
          },
        );
      },
    );
  }
}

class _AxisRow extends StatelessWidget {
  const _AxisRow({
    required this.kugo,
    required this.label,
    required this.hint,
    required this.pending,
    required this.child,
    this.trailing,
  });

  final KugoTheme kugo;
  final String label;
  final String hint;
  final bool pending;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        KugoSpacing.lg,
        KugoSpacing.sm,
        KugoSpacing.sm,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(label, style: kugo.caption),
              const SizedBox(width: KugoSpacing.sm),
              Text(
                hint,
                style: kugo.caption.copyWith(
                  color: pending ? kugo.primary : kugo.textTertiary,
                  fontSize: 11,
                ),
              ),
              const Spacer(),
              ?trailing,
            ],
          ),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }
}

class _RoundAction extends StatelessWidget {
  const _RoundAction({
    required this.kugo,
    required this.icon,
    required this.onTap,
    this.label,
    this.large = false,
    this.accent,
  });

  final KugoTheme kugo;
  final IconData icon;
  final VoidCallback onTap;
  final String? label;
  final bool large;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final size = large ? 64.0 : 48.0;
    final tone = accent ?? kugo.primary;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: large
                  ? LinearGradient(colors: [tone, tone.withValues(alpha: 0.7)])
                  : null,
              color: large ? null : kugo.surface.withValues(alpha: 0.75),
            ),
            child: Icon(
              icon,
              size: large ? 30 : 22,
              color: large ? kugo.onAccent : kugo.textPrimary,
            ),
          ),
        ),
        if (label != null) ...[
          const SizedBox(height: 6),
          Text(label!, style: kugo.caption),
        ],
      ],
    );
  }
}

/// 胶囊分段开关：档位轴 / 歌池轴共用。
class _CapsuleSwitch<T> extends StatelessWidget {
  const _CapsuleSwitch({
    required this.kugo,
    required this.values,
    required this.labelOf,
    required this.selected,
    required this.onChanged,
  });

  final KugoTheme kugo;
  final List<T> values;
  final String Function(T) labelOf;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: kugo.surface.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(KugoRadius.chip),
        border: Border.all(color: kugo.divider),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final value in values)
            GestureDetector(
              onTap: () => onChanged(value),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: value == selected
                      ? kugo.primary.withValues(alpha: 0.30)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(KugoRadius.chip),
                ),
                child: Text(
                  labelOf(value),
                  style: kugo.caption.copyWith(
                    color: value == selected
                        ? kugo.textPrimary
                        : kugo.textSecondary,
                    fontWeight: value == selected
                        ? FontWeight.w700
                        : FontWeight.w500,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
