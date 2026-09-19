import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/track.dart';
import '../../core/theme/kugo_tokens.dart';
import '../../data/repositories/search_repository.dart';
import '../../features/player/player_controller.dart';
import '../../shared/widgets/async_body.dart';
import '../../shared/widgets/common.dart';
import '../../core/theme/kugo_theme.dart';

class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final _repo = searchRepository;
  final _controller = TextEditingController();
  final _focus = FocusNode();

  bool _loading = false;
  bool _searched = false;
  String _error = '';
  List<Track> _results = const [];
  List<String> _hot = const [];

  @override
  void initState() {
    super.initState();
    _loadHot();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final q = GoRouterState.of(context).uri.queryParameters['q'];
      if (q == null || q.trim().isEmpty) return;
      _controller.text = q.trim();
      _search(q.trim());
    });
  }

  Future<void> _loadHot() async {
    final hot = await _repo.hotKeywords();
    if (!mounted) return;
    setState(() => _hot = hot);
  }

  Future<void> _search([String? keyword]) async {
    final kw = (keyword ?? _controller.text).trim();
    if (kw.isEmpty) return;
    _focus.unfocus();
    setState(() {
      _loading = true;
      _searched = true;
      _error = '';
    });
    try {
      final list = await _repo.searchSongs(kw);
      if (!mounted) return;
      setState(() {
        _results = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString();
      final filtered = msg.contains('Handshake') ||
          msg.contains('URL过滤') ||
          msg.contains('Connection terminated') ||
          msg.contains('timeout') ||
          msg.contains('SocketException');
      setState(() {
        _error = filtered ? '网络不可达或被网关拦截，请检查网络后重试' : '搜索失败，请重试';
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final kugo = KugoTheme.of(context);
    final player = ref.watch(playerControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('搜索')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              KugoSpacing.lg,
              0,
              KugoSpacing.lg,
              KugoSpacing.md,
            ),
            child: TextField(
              controller: _controller,
              focusNode: _focus,
              autofocus: false,
              textInputAction: TextInputAction.search,
              onSubmitted: _search,
              style: kugo.body,
              decoration: InputDecoration(
                hintText: '搜索歌曲、歌手、专辑',
                hintStyle: kugo.caption,
                filled: true,
                fillColor: kugo.surface,
                prefixIcon: Icon(
                  Icons.search_rounded,
                  color: kugo.textSecondary,
                ),
                suffixIcon: IconButton(
                  onPressed: () {
                    _controller.clear();
                    setState(() {
                      _searched = false;
                      _results = const [];
                    });
                  },
                  icon: const Icon(Icons.clear_rounded, size: 18),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(KugoRadius.chip),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(
            child: !_searched
                ? _HotKeywords(
                    hot: _hot,
                    onTap: (kw) {
                      _controller.text = kw;
                      _search(kw);
                    },
                  )
                : AsyncBody(
                    loading: _loading,
                    hasError: _error.isNotEmpty,
                    isEmpty: !_loading && _results.isEmpty,
                    errorMessage: '搜索失败，请重试',
                    emptyMessage: '没有找到相关歌曲',
                    onRetry: () => _search(),
                    child: ListView.builder(
                      itemCount: _results.length,
                      itemBuilder: (context, index) {
                        final track = _results[index];
                        return TrackTile(
                          track: track,
                          isPlaying: player.current?.id == track.id &&
                              player.isPlaying,
                          onArtistTap: () => context.push(
                            '/artist/${Uri.encodeComponent(track.artist)}',
                          ),
                          onTap: () async {
                            await ref
                                .read(playerControllerProvider.notifier)
                                .playQueue(_results, startIndex: index);
                            if (context.mounted) context.push('/player');
                          },
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _HotKeywords extends StatelessWidget {
  const _HotKeywords({required this.hot, required this.onTap});

  final List<String> hot;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final kugo = KugoTheme.of(context);
    final items = hot.isEmpty
        ? const ['周杰伦', '林俊杰', '陈奕迅', '民谣', '说唱', '粤语']
        : hot;
    return ListView(
      padding: const EdgeInsets.all(KugoSpacing.lg),
      children: [
        Text(
          '热门搜索',
          style: kugo.section.copyWith(fontSize: 16),
        ),
        const SizedBox(height: KugoSpacing.md),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final kw in items)
              ActionChip(
                label: Text(kw),
                backgroundColor: kugo.surface,
                labelStyle: kugo.caption.copyWith(fontSize: 13),
                side: BorderSide.none,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(KugoRadius.chip),
                ),
                onPressed: () => onTap(kw),
              ),
          ],
        ),
      ],
    );
  }
}
