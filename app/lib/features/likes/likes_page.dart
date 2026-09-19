import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/kugo_tokens.dart';
import '../../features/player/player_controller.dart';
import '../../shared/widgets/async_body.dart';
import '../../shared/widgets/common.dart';
import '../../core/theme/kugo_theme.dart';
import 'likes_controller.dart';

class LikesPage extends ConsumerWidget {
  const LikesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kugo = KugoTheme.of(context);
    final likes = ref.watch(likesProvider);
    final player = ref.watch(playerControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('我喜欢')),
      body: likes.isEmpty
          ? AsyncBody(
              loading: false,
              hasError: false,
              isEmpty: true,
              emptyMessage: '还没有红心歌曲\n播放时点 ♥ 即可收藏',
              onRetry: () {},
              child: const SizedBox.shrink(),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    KugoSpacing.lg,
                    KugoSpacing.md,
                    KugoSpacing.lg,
                    KugoSpacing.sm,
                  ),
                  child: Row(
                    children: [
                      Text(
                        '${likes.length} 首',
                        style: kugo.caption,
                      ),
                      const Spacer(),
                      FilledButton.icon(
                        onPressed: likes.isEmpty
                            ? null
                            : () {
                                ref
                                    .read(playerControllerProvider.notifier)
                                    .playQueue(likes, startIndex: 0);
                                context.push('/player');
                              },
                        icon: const Icon(Icons.play_arrow_rounded, size: 18),
                        label: const Text('播放全部'),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: likes.length,
                    itemBuilder: (context, index) {
                      final track = likes[index];
                      return TrackTile(
                        track: track,
                        isPlaying: player.current?.id == track.id &&
                            player.isPlaying,
                        trailing: IconButton(
                          icon: const Icon(
                            Icons.favorite_rounded,
                            color: Color(0xFFE87A90),
                            size: 20,
                          ),
                          onPressed: () =>
                              ref.read(likesProvider.notifier).remove(track.id),
                        ),
                        onArtistTap: artistTapFor(context, track),
                        onTap: () {
                          ref
                              .read(playerControllerProvider.notifier)
                              .playQueue(likes, startIndex: index);
                          context.push('/player');
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}
