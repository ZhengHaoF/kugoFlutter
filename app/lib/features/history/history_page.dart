import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/track.dart';
import '../../data/storage/queue_store.dart';
import '../../features/player/player_controller.dart';
import '../../shared/widgets/async_body.dart';
import '../../shared/widgets/common.dart';

class HistoryPage extends ConsumerStatefulWidget {
  const HistoryPage({super.key});

  @override
  ConsumerState<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends ConsumerState<HistoryPage> {
  List<Track> _history = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final store = await QueueStore.open();
      final list = await store.loadHistoryAsync();
      if (!mounted) return;
      setState(() {
        _history = list;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _history = const [];
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final player = ref.watch(playerControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('播放历史')),
      body: _loading
          ? const SkeletonList()
          : _history.isEmpty
              ? AsyncBody(
                  loading: false,
                  hasError: false,
                  isEmpty: true,
                  emptyMessage: '还没有播放记录\n去搜索听一首吧',
                  onRetry: _load,
                  child: const SizedBox.shrink(),
                )
              : ListView.builder(
                  itemCount: _history.length,
                  itemBuilder: (context, index) {
                    final track = _history[index];
                    return TrackTile(
                      track: track,
                      isPlaying:
                          player.current?.id == track.id && player.isPlaying,
                      onTap: () {
                        ref
                            .read(playerControllerProvider.notifier)
                            .playQueue(_history, startIndex: index);
                        context.push('/player');
                      },
                    );
                  },
                ),
    );
  }
}
