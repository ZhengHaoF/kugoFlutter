import 'package:flutter_test/flutter_test.dart';
import 'package:kugo/core/models/comment.dart';
import 'package:kugo/core/models/track.dart';
import 'package:kugo/data/repositories/comment_repository.dart';
import 'package:kugo/data/repositories/search_repository.dart';
import 'package:kugo/data/sources/kugou/kugou_source.dart';

/// 只实现解析 mixsongid 用到的 `searchSongs`，其余交给 noSuchMethod。
class _FakeSearch implements SearchRepository {
  _FakeSearch(this.hits);

  final List<Track> hits;
  final List<String> keywords = [];

  @override
  Future<List<Track>> searchSongs(
    String keyword, {
    int page = 1,
    int pageSize = 30,
  }) async {
    keywords.add(keyword);
    return hits;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 记录每次调用的参数，并按 mixsongid 吐预置结果。
class _FakeComments implements CommentRepository {
  _FakeComments({this.responses = const {}, this.failingIds = const {}});

  /// mixsongid → 该 id 的结果。
  final Map<String, CommentPage> responses;

  /// 这些 id 视作「接口报错」（lastError 有值）。
  final Set<String> failingIds;

  final List<String> askedMixSongIds = [];
  final List<({String childrenId, String mixSongId})> floorCalls = [];
  final List<({String childrenId, String songName, String mixSongId})>
  commentCalls = [];
  final List<
    ({String childrenId, String songName, String mixSongId, String tid})
  >
  replyCalls = [];
  final List<String> countedHashes = [];

  @override
  String lastError = '';

  @override
  String lastSsaCode = '';

  @override
  Future<CommentPage> fetchSongComments({
    required String mixSongId,
    int page = 1,
    int pageSize = 20,
    CommentSort sort = CommentSort.all,
  }) async {
    askedMixSongIds.add(mixSongId);
    if (failingIds.contains(mixSongId)) {
      lastError = '评论参数无效';
      return CommentPage.empty;
    }
    lastError = '';
    return responses[mixSongId] ?? CommentPage.empty;
  }

  @override
  Future<List<Comment>> fetchFloorReplies({
    required String childrenId,
    required String rootCommentId,
    String mixSongId = '',
    int page = 1,
    int pageSize = 20,
  }) async {
    floorCalls.add((childrenId: childrenId, mixSongId: mixSongId));
    return const [];
  }

  @override
  Future<int?> fetchCommentCount({required String hash}) async {
    countedHashes.add(hash);
    return 7;
  }

  @override
  Future<void> sendSongComment({
    required String childrenId,
    required String content,
    String songName = '',
    String mixSongId = '',
  }) async {
    commentCalls.add((
      childrenId: childrenId,
      songName: songName,
      mixSongId: mixSongId,
    ));
  }

  @override
  Future<void> sendFloorReply({
    required String childrenId,
    required String rootCommentId,
    required String content,
    String replyToUser = '',
    String replyToContent = '',
    String songName = '',
    String mixSongId = '',
  }) async {
    replyCalls.add((
      childrenId: childrenId,
      songName: songName,
      mixSongId: mixSongId,
      tid: rootCommentId,
    ));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _hit = Comment(id: '1', user: 'u', content: '好听');

CommentPage _page(String childrenId, {bool withItem = false}) => CommentPage(
  items: withItem ? const [_hit] : const [],
  total: withItem ? 1 : 0,
  childrenId: childrenId,
);

Track _track({
  String id = '999',
  String name = '晴天',
  String artist = '周杰伦',
  String hash = '',
  String mixSongId = '',
}) => Track(
  id: id,
  name: name,
  artist: artist,
  album: '',
  coverUrl: '',
  durationMs: 0,
  hash: hash,
  mixSongId: mixSongId,
);

void main() {
  test('解析出的 mixsongid 会被缓存：翻页不再重搜', () async {
    final search = _FakeSearch([
      _track(id: 'aa', name: '晴天', mixSongId: '111'),
    ]);
    final comments = _FakeComments(
      responses: {'111': _page('20505418', withItem: true)},
    );
    final source = KugouSource(
      searchRepository: search,
      commentRepository: comments,
    );

    final first = await source.songComments(_track());
    expect(first.items, hasLength(1));
    expect(comments.askedMixSongIds, ['111']);
    expect(search.keywords, hasLength(1));

    // 第二页：直接用缓存 id，不再搜索、也不再试候选。
    await source.songComments(_track(), page: 2);
    expect(comments.askedMixSongIds, ['111', '111']);
    expect(search.keywords, hasLength(1));
  });

  test('首个候选没有评论时继续试下一个候选（同名其他版本）', () async {
    final search = _FakeSearch([
      _track(id: 'aa', name: '晴天', mixSongId: '111'),
      _track(id: 'bb', name: '晴天 (Live)', mixSongId: '222'),
    ]);
    final comments = _FakeComments(
      responses: {'111': _page('1'), '222': _page('2', withItem: true)},
    );
    final source = KugouSource(
      searchRepository: search,
      commentRepository: comments,
    );

    final page = await source.songComments(_track());

    expect(page.items, hasLength(1));
    expect(comments.askedMixSongIds, ['111', '222']);
  });

  test('候选全部为空：记住第一个「可用」的 id，下次不再重搜', () async {
    final search = _FakeSearch([
      _track(id: 'aa', name: '晴天', mixSongId: '111'),
    ]);
    final comments = _FakeComments(responses: {'111': _page('20505418')});
    final source = KugouSource(
      searchRepository: search,
      commentRepository: comments,
    );

    final page = await source.songComments(_track());
    expect(page.items, isEmpty);
    expect(source.lastError, isEmpty); // 空 = 这首歌确实没评论，不是失败
    expect(search.keywords, hasLength(1));
    // 候选 = [搜索命中的 111, track.id 兜底 999]。
    expect(comments.askedMixSongIds, ['111', '999']);

    await source.songComments(_track());
    // 缓存了「第一个可用」的 111，第二次只打一个请求。
    expect(comments.askedMixSongIds, ['111', '999', '111']);
    expect(search.keywords, hasLength(1)); // 缓存生效，没再搜
  });

  test('候选全部报错：不缓存，且把失败原因透出来', () async {
    final search = _FakeSearch([
      _track(id: 'aa', name: '晴天', mixSongId: '111'),
    ]);
    // 连 track.id 兜底候选也一起失败，才算「全军覆没」。
    final comments = _FakeComments(failingIds: {'111', '999'});
    final source = KugouSource(
      searchRepository: search,
      commentRepository: comments,
    );

    final page = await source.songComments(_track());
    expect(page.items, isEmpty);
    expect(source.lastError, '评论参数无效');

    // 没缓存 → 第二次仍会重新搜索、重新试候选。
    await source.songComments(_track());
    expect(search.keywords, hasLength(2));
  });

  test('连候选都凑不出来：给可读文案，不发请求', () async {
    final search = _FakeSearch(const []);
    final comments = _FakeComments();
    final source = KugouSource(
      searchRepository: search,
      commentRepository: comments,
    );

    final page = await source.songComments(
      _track(id: '', name: '', artist: '', hash: ''),
    );

    expect(page.items, isEmpty);
    expect(source.lastError, contains('无法定位该歌曲'));
    expect(comments.askedMixSongIds, isEmpty);
  });

  test('hash 形态的值不会被当成 mixsongid', () async {
    const hash = '2b7d1a0ea1c1dc0e9d4b3d26c2f0f1cd';
    // 搜索无命中，track 只给了 hash 与 id。
    final search = _FakeSearch(const []);
    final comments = _FakeComments(responses: {'1234': _page('1')});
    final source = KugouSource(
      searchRepository: search,
      commentRepository: comments,
    );

    await source.songComments(_track(id: '1234', name: '', hash: hash));

    expect(comments.askedMixSongIds, ['1234']);
    expect(comments.askedMixSongIds, isNot(contains(hash)));
  });

  test('commentCount 用 track.hash，不用 mixsongid', () async {
    final comments = _FakeComments();
    final source = KugouSource(
      searchRepository: _FakeSearch(const []),
      commentRepository: comments,
    );

    final count = await source.commentCount(_track(hash: 'abc123'));

    expect(count, 7);
    expect(comments.countedHashes, ['abc123']);
  });

  test('写侧从 track 取歌名与已解析的 mixsongid', () async {
    final search = _FakeSearch([
      _track(id: 'aa', name: '晴天', mixSongId: '111'),
    ]);
    final comments = _FakeComments(
      responses: {'111': _page('20505418', withItem: true)},
    );
    final source = KugouSource(
      searchRepository: search,
      commentRepository: comments,
    );

    final track = _track();
    await source.songComments(track);
    await source.sendSongComment(
      track: track,
      childrenId: '20505418',
      content: '你好',
    );

    expect(comments.commentCalls, hasLength(1));
    expect(comments.commentCalls.first.songName, '晴天');
    expect(comments.commentCalls.first.mixSongId, '111');
  });

  test('楼层取源：有缓存用缓存，没有就退回 track 自带的 mixSongId', () async {
    final search = _FakeSearch(const []);
    final comments = _FakeComments();
    final source = KugouSource(
      searchRepository: search,
      commentRepository: comments,
    );

    await source.floorReplies(
      track: _track(id: '', name: '', mixSongId: '777'),
      childrenId: '20505418',
      rootCommentId: '42',
    );

    expect(comments.floorCalls, hasLength(1));
    expect(comments.floorCalls.first.mixSongId, '777');
    expect(comments.floorCalls.first.childrenId, '20505418');
  });
}
