import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../core/app_navigator.dart';
import 'mv_player_host.dart';

/// MV 应用内浮动小窗（P2-3）：由 [mvPlayerHostProvider] 的 `mini` 位驱动，
/// 叠在 `MaterialApp.builder` 的所有路由之上；引擎不活时自身零尺寸。
///
/// 交互：整卡拖动、点卡片回全页、底部播放/暂停 + 关闭；贴右下角默认位，
/// 避开底部播放条。
class MvMiniWindow extends ConsumerStatefulWidget {
  const MvMiniWindow({super.key});

  @override
  ConsumerState<MvMiniWindow> createState() => _MvMiniWindowState();
}

class _MvMiniWindowState extends ConsumerState<MvMiniWindow> {
  static const _windowWidth = 200.0;

  /// 默认贴底时抬高的安全距（避开 MiniPlayerBar / DesktopPlayerBar）。
  static const _bottomInset = 112.0;

  /// 拖动后的位置；null = 默认右下角。
  Offset? _offset;

  void _openFull() {
    final host = ref.read(mvPlayerHostProvider.notifier);
    final brief = ref.read(mvPlayerHostProvider).brief;
    host.exitMini();
    // builder 的 context 在 Navigator 之上，走根 navigator key push。
    final navContext = kugoNavigatorKey.currentContext;
    if (brief == null || navContext == null) return;
    final query = Uri(
      queryParameters: {
        'id': brief.id,
        'hash': brief.hash,
        'name': brief.name,
        'artist': brief.artist,
        'cover': brief.coverUrl,
        'mixSongId': brief.mixSongId,
      },
    ).toString();
    navContext.push('/mv$query');
  }

  @override
  Widget build(BuildContext context) {
    final hostState = ref.watch(mvPlayerHostProvider);
    final host = ref.read(mvPlayerHostProvider.notifier);
    final controller = host.videoController;
    if (!hostState.mini || controller == null) {
      return const SizedBox.shrink();
    }
    final aspect = hostState.videoAspect <= 0 ? 16 / 9 : hostState.videoAspect;
    final height = _windowWidth / aspect;

    return LayoutBuilder(
      builder: (context, constraints) {
        final screen = constraints.biggest;
        final defaultOffset = Offset(
          screen.width - _windowWidth - 12,
          (screen.height - height - _bottomInset).clamp(0, screen.height),
        );
        final raw = _offset ?? defaultOffset;
        final clamped = Offset(
          raw.dx.clamp(0, (screen.width - _windowWidth).clamp(0, screen.width)),
          raw.dy.clamp(0, (screen.height - height).clamp(0, screen.height)),
        );
        return Stack(
          // 只有 Positioned 子节点：Stack 自身铺满但仍透传空白区点击。
          children: [
            Positioned(
              left: clamped.dx,
              top: clamped.dy,
              child: SizedBox(
                width: _windowWidth,
                height: height,
                child: _MvMiniCard(
                  controller: controller,
                  playing: host.playing,
                  position: host.position,
                  duration: host.duration,
                  // 以未夹取的原始位置累加：越界后拖回来不会「粘」在边上。
                  onPan: (delta) => setState(() {
                    _offset = raw + delta;
                  }),
                  onOpenFull: _openFull,
                  onClose: () => host.shutdown(),
                  onTogglePlay: host.togglePlay,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _MvMiniCard extends StatelessWidget {
  const _MvMiniCard({
    required this.controller,
    required this.playing,
    required this.position,
    required this.duration,
    required this.onPan,
    required this.onOpenFull,
    required this.onClose,
    required this.onTogglePlay,
  });

  final VideoController controller;
  final ValueListenable<bool> playing;
  final ValueListenable<int> position;
  final ValueListenable<int> duration;
  final ValueChanged<Offset> onPan;
  final VoidCallback onOpenFull;
  final VoidCallback onClose;
  final VoidCallback onTogglePlay;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // 整卡拖动；点按（非拖动）回全页。
      onPanUpdate: (d) => onPan(d.delta),
      onTap: onOpenFull,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.45),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          // 小窗挂在 MaterialApp.builder 上、处于 Navigator 之外——那里没有
          // Material 祖先，InkWell 会直接抛「No Material widget found」。
          child: Material(
            color: Colors.black,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(
                  color: Colors.black,
                  child: Video(
                    controller: controller,
                    controls: NoVideoControls,
                    fit: BoxFit.contain,
                  ),
                ),
                // 底部控件条（渐隐底 + 播放/暂停、回全页、关闭）
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 2,
                    ),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [Colors.black87, Colors.transparent],
                      ),
                    ),
                    child: Row(
                      children: [
                        _MiniButton(
                          onTap: onTogglePlay,
                          child: ValueListenableBuilder<bool>(
                            valueListenable: playing,
                            builder: (context, playing, _) => Icon(
                              playing
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                              color: Colors.white,
                              size: 18,
                            ),
                          ),
                        ),
                        const Spacer(),
                        _MiniButton(
                          onTap: onOpenFull,
                          child: const Icon(
                            Icons.open_in_full,
                            color: Colors.white,
                            size: 14,
                          ),
                        ),
                        _MiniButton(
                          onTap: onClose,
                          child: const Icon(
                            Icons.close,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // 细进度线
                Align(
                  alignment: Alignment.bottomCenter,
                  child: ValueListenableBuilder<int>(
                    valueListenable: duration,
                    builder: (context, durationMs, _) {
                      final dur = durationMs <= 0 ? 1 : durationMs;
                      return ValueListenableBuilder<int>(
                        valueListenable: position,
                        builder: (context, positionMs, _) {
                          final v = (positionMs.clamp(0, dur) / dur).clamp(
                            0.0,
                            1.0,
                          );
                          return SizedBox(
                            height: 2,
                            child: Stack(
                              alignment: Alignment.centerLeft,
                              children: [
                                Container(height: 2, color: Colors.white24),
                                FractionallySizedBox(
                                  widthFactor: v,
                                  child: Container(
                                    height: 2,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniButton extends StatelessWidget {
  const _MiniButton({required this.onTap, required this.child});

  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(padding: const EdgeInsets.all(5), child: child),
    );
  }
}
