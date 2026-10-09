import 'package:flutter_test/flutter_test.dart';
import 'package:kugo/core/api/netease/netease_client.dart';
import 'package:kugo/core/api/netease/netease_mappers.dart';
import 'package:kugo/core/models/cloud_models.dart';
import 'package:kugo/core/models/track.dart';
import 'package:kugo/core/source/capabilities.dart';
import 'package:kugo/core/source/music_platform.dart';
import 'package:kugo/core/source/music_source.dart';
import 'package:kugo/data/sources/netease/netease_source.dart';

/// J 组音乐云盘。fixture 取自 2026-10-09 真机探针输出
/// （`--suite cloud --qr`，uid 1593114455：460 个文件 / 19.3G of 60G），
/// 不是编的——字段名（`data[]` 是 simpleSong、容量在顶层 `size`/`maxSize`、
/// 取流平铺 `url`、歌词顶层 `lrc`/`krc` 字符串）全部来自那一轮。
void main() {
  // ── fixture ────────────────────────────────────────────────

  /// 列表：**`data[]` 是 `{simpleSong:{…}}` 包裹**（2026-10-09 实测，与详情口同形）。
  /// 两条：一条未匹配曲库（`ar`/`al` 为空，只有文件名，真机首条形态），
  /// 一条已匹配（有歌手/专辑/封面），覆盖两种展示路径。
  const listRaw = r'''
{"code":200,"count":460,"size":20795339420,"maxSize":64424509440,
 "hasMore":false,"cursor":0,"upgradeSign":0,"updateTime":1791517800000,
 "data":[
  {"simpleSong":{"name":"独庄子（3）","mainTitle":null,"additionalTitle":null,
   "id":2165810543,"pst":0,"t":1,
   "ar":[{"id":0,"name":null,"tns":[],"alias":[]}],"alia":[],
   "pop":0.0,"st":0,"rt":null,"fee":0,"v":37,"crbt":null,"cf":null,
   "al":{"id":0,"name":null,"picUrl":"http://p3.music.126.net/C6Vro2l0BH59Wka9gOaC6w==/109951171180358170.jpg","tns":[],"pic":0},
   "dt":1370196,"h":null,"m":null,
   "l":{"br":48004,"fid":0,"size":8223366,"vd":0.0,"sr":16000},
   "sq":null,"hr":null,"a":null,"cd":null,"no":0}},
  {"simpleSong":{"name":"晴天","mainTitle":null,"additionalTitle":null,
   "id":186016,"pst":0,"t":1,
   "ar":[{"id":6452,"name":"周杰伦","tns":[],"alias":[]}],"alia":[],
   "pop":100.0,"st":0,"rt":null,"fee":8,"v":38,"crbt":null,"cf":null,
   "al":{"id":37470,"name":"叶惠美","picUrl":"http://p4.music.126.net/abc==/109951163089626203.jpg","tns":[],"pic":109951163089626203},
   "dt":269314,"h":{"br":320000,"fid":0,"size":10779460,"vd":-2.0},
   "m":{"br":192000,"fid":0,"size":6467763,"vd":-2.0},
   "l":{"br":128000,"fid":0,"size":4311915,"vd":-2.0},
   "sq":null,"hr":null,"a":null,"cd":"1","no":3}}
 ]}''';

  /// 不包裹形态（`data[]` 直接是 simpleSong）：mapper 两种都要认，
  /// 免得上游换个包法又静默出空列表。
  const listRawFlat = r'''
{"code":200,"count":1,"size":8223366,"maxSize":64424509440,"hasMore":false,
 "data":[{"name":"独庄子（3）","id":2165810543,"pst":0,
   "ar":[{"id":0,"name":null,"tns":[],"alias":[]}],
   "al":{"id":0,"name":null,"picUrl":"http://p3.music.126.net/x.jpg"},
   "dt":1370196,"fee":0}]}''';

  /// 取流：**平铺**响应（`{code,size,name,url}` 全在顶层，不在 `data` 里）。
  const downloadRaw = r'''
{"code":200,"size":8223366,"name":"04.独庄子（3）.mp3",
 "url":"http://m803.music.126.net/20261009121505/1396c418ae512fab8e5ea7f627eeb809/jd-musicrep-privatecloud-audio-public/obj/woHCgMKXw6XCmDjDj8Oj/36615201771/93a7/ac23/3456/a110c49dee5bded0a4f19453eae2939c.mp3?vuutv=BO/wezHMMIn1TYjDqbePHlhHJgpNacU5Uinvrj8Yyh1NJIUW1Q9fVfN+bz8dDn3R2CWLTw/T76ZGZEwQWIPRdTfnFSu9zUrB70bInsNrGHk="}''';

  /// 歌词：顶层**字符串**（不是曲库那套 `lrc:{version,lyric}` 对象）。
  const lyricLrcRaw = r'''
{"lrc":"[00:00.00]独庄子 - 3\n[00:12.34]北冥有鱼\n","krc":"","code":200}''';

  const lyricEmptyRaw = r'''
{"lrc":"","krc":"","code":200}''';

  /// 歌词带 `krc`（YRC 逐字）：格式未实测，mapper 应先按 YRC 解。
  const lyricKrcRaw = r'''
{"lrc":"[00:00.00]北冥有鱼\n","krc":"[0,1500](0,500,0)北(500,500,0)冥(1000,500,0)有(1500,0,0)鱼\n","code":200}''';

  /// 详情：云盘文件自己的字段只在这一口。
  const detailRaw = r'''
{"code":200,"data":[
 {"simpleSong":{"name":"独庄子（3）","id":2165810543,
   "ar":[{"id":0,"name":null,"tns":[],"alias":[]}],"alia":[],
   "al":{"id":0,"name":null,"picUrl":"http://p3.music.126.net/cover==/109951171180358170.jpg","tns":[],"pic":0},
   "dt":1370196,"fee":0,"l":{"br":48004,"fid":0,"size":8223366,"vd":0.0,"sr":16000}},
  "bitrate":48004,"album":"未知专辑","artist":"未知艺术家",
  "songId":2165810543,"pcId":0,"songName":"独庄子（3）",
  "addTime":1697000000000,"cover":2165810543,"coverId":"109951171180358170",
  "lyricId":"","matchType":0,"version":1,"fileSize":8223366,
  "fileName":"04.独庄子（3）.mp3"}]}''';

  // ── J1 列表 mapper ─────────────────────────────────────────

  group('J1 mapNeteaseCloudPage', () {
    test('data[] 是 simpleSong：直接出正规歌曲元数据', () {
      final page = mapNeteaseCloudPage(listRaw);
      expect(page.tracks, hasLength(2));

      final first = page.tracks.first;
      expect(first.name, '独庄子（3）');
      expect(first.id, '2165810543');
      expect(first.durationMs, 1370196);
      expect(first.platform, MusicPlatform.netease);

      // 已匹配曲库的那条：歌手/专辑/封面都该有。
      final second = page.tracks[1];
      expect(second.name, '晴天');
      expect(second.artist, '周杰伦');
      expect(second.album, '叶惠美');
      expect(second.coverUrl, contains('109951163089626203'));
    });

    test('cloudFileId 记 songId —— isCloudTrack 是播放/歌词分支的判据', () {
      final page = mapNeteaseCloudPage(listRaw);
      for (final t in page.tracks) {
        expect(t.isCloudTrack, isTrue, reason: t.name);
        expect(t.cloudFileId, t.id);
      }
    });

    test('容量与总数取自顶层 size/maxSize/count', () {
      final page = mapNeteaseCloudPage(listRaw);
      expect(page.total, 460);
      expect(page.capacity.totalBytes, 64424509440);
      expect(page.capacity.usedBytes, 20795339420);
      expect(page.capacity.usedRatio, closeTo(0.3228, 0.001));
    });

    test('hasMore 以响应自带字段为准（limit 被忽略时首屏即全量）', () {
      expect(mapNeteaseCloudPage(listRaw).hasMore, isFalse);
      expect(
        mapNeteaseCloudPage(listRaw.replaceFirst('"hasMore":false', '"hasMore":true'))
            .hasMore,
        isTrue,
      );
    });

    test('301 需登录 → LoginRequired', () {
      expect(
        () => mapNeteaseCloudPage('{"code":301,"message":"需要登录"}'),
        throwsA(isA<LoginRequired>()),
      );
    });

    test('回归：simpleSong 不拆包会整列丢空（「有容量无歌曲」bug）', () {
      // 2026-10-09 线上形态：data[] 是 {simpleSong:{…}} 包裹。
      // mapNeteaseSong 只拆 `song` 时每一项都取不到 id → 全丢，
      // 只剩顶层容量，页面出「云盘暂无歌曲」。这里同时锁两种形态。
      expect(mapNeteaseCloudPage(listRaw).tracks, hasLength(2));
      expect(mapNeteaseCloudPage(listRawFlat).tracks, hasLength(1));
      expect(mapNeteaseCloudPage(listRawFlat).tracks.single.name, '独庄子（3）');
    });
  });

  // ── J4 取流 mapper ─────────────────────────────────────────

  group('J4 mapNeteaseCloudPlayUrl', () {
    test('平铺响应：url 在顶层，防盗链头照旧下发', () {
      final result = mapNeteaseCloudPlayUrl(downloadRaw);
      expect(result.url, startsWith('http://m803.music.126.net/'));
      expect(result.url, contains('vuutv='));
      expect(result.headers['Referer'], 'https://music.163.com');
      expect(result.allUrls, hasLength(1));
      expect(result.isPreviewClip, isFalse);
    });

    test('code=301 → LoginRequired', () {
      expect(
        () => mapNeteaseCloudPlayUrl('{"code":301}'),
        throwsA(isA<LoginRequired>()),
      );
    });

    test('没有 url → NotFound（云盘文件可能已被删）', () {
      expect(
        () => mapNeteaseCloudPlayUrl('{"code":200,"name":"x.mp3"}'),
        throwsA(isA<NotFound>()),
      );
    });
  });

  // ── J5 歌词 mapper ─────────────────────────────────────────

  group('J5 mapNeteaseCloudLyric', () {
    test('lrc 顶层字符串 → 行', () {
      final payload = mapNeteaseCloudLyric(lyricLrcRaw);
      expect(payload.isEmpty, isFalse);
      expect(payload.lines.first.text, '独庄子 - 3');
      expect(payload.sourceTag, 'netease-cloud-lrc');
    });

    test('文件没内嵌歌词：空串不是错误', () {
      final payload = mapNeteaseCloudLyric(lyricEmptyRaw);
      expect(payload.isEmpty, isTrue);
    });

    test('krc 先按 YRC 逐字解', () {
      final payload = mapNeteaseCloudLyric(lyricKrcRaw);
      expect(payload.sourceTag, 'netease-cloud-krc');
      expect(payload.lines, hasLength(1));
      expect(payload.lines.first.text, '北冥有鱼');
      expect(payload.lines.first.chars, hasLength(4));
      expect(payload.lines.first.chars.first.text, '北');
    });
  });

  // ── J2 详情 mapper ─────────────────────────────────────────

  group('J2 mapNeteaseCloudDetails', () {
    test('simpleSong 拆包 + cloudFileId 回填', () {
      final tracks = mapNeteaseCloudDetails(detailRaw);
      expect(tracks, hasLength(1));
      expect(tracks.single.name, '独庄子（3）');
      expect(tracks.single.cloudFileId, '2165810543');
      expect(tracks.single.isCloudTrack, isTrue);
    });
  });

  // ── Source 层 ──────────────────────────────────────────────

  group('NeteaseSource · CloudDiskSource', () {
    test('登录态看 MUSIC_U cookie', () {
      final client = _FakeNeteaseClient();
      final source = NeteaseSource(client: client);
      expect(source.isCloudDiskLoggedIn, isFalse);
      client.loggedIn = true;
      expect(source.isCloudDiskLoggedIn, isTrue);
    });

    test('未登录取列表 → LoginRequired', () async {
      final source = NeteaseSource(client: _FakeNeteaseClient());
      await expectLater(
        source.fetchCloudDiskPage(),
        throwsA(isA<LoginRequired>()),
      );
    });

    test('列表：limit/offset 按页折算，结果过 mapper', () async {
      final client = _FakeNeteaseClient()
        ..listRaw = listRaw
        ..loggedIn = true;
      final source = NeteaseSource(client: client);
      final page = await source.fetchCloudDiskPage(page: 3, pageSize: 50);
      expect(client.lastList['limit'], 50);
      expect(client.lastList['offset'], 100);
      expect(page.tracks, hasLength(2));
      expect(page.total, 460);
    });

    test('取流：把 track 的 songId 打进云盘下载口', () async {
      final client = _FakeNeteaseClient()..downloadRaw = downloadRaw;
      final source = NeteaseSource(client: client);
      final track = const Track(
        id: '2165810543',
        name: '独庄子（3）',
        artist: '未知艺术家',
        album: '',
        coverUrl: '',
        durationMs: 1370196,
        cloudFileId: '2165810543',
      );
      final result = await source.resolveCloudPlayUrl(track);
      expect(client.lastDownloadSongId, 2165810543);
      expect(result.url, startsWith('http://m803.music.126.net/'));
    });

    test('删除：只收 cloudFileId，空目标抛 NotFound', () async {
      final client = _FakeNeteaseClient()
        ..deleteRaw = '{"code":200}'
        ..loggedIn = true;
      final source = NeteaseSource(client: client);
      await source.deleteCloudTracks(const [
        CloudDeleteTarget(cloudFileId: '2165810543'),
        CloudDeleteTarget(cloudFileId: ''),
      ]);
      expect(client.lastDeleteIds, ['2165810543']);

      await expectLater(
        source.deleteCloudTracks(const [CloudDeleteTarget(cloudFileId: '')]),
        throwsA(isA<NotFound>()),
      );
    });

    test('删除失败码 → SourceFailure（不静默）', () async {
      final client = _FakeNeteaseClient()
        ..deleteRaw = '{"code":301}'
        ..loggedIn = true;
      final source = NeteaseSource(client: client);
      await expectLater(
        source.deleteCloudTracks(const [
          CloudDeleteTarget(cloudFileId: '1'),
        ]),
        throwsA(isA<LoginRequired>()),
      );
    });

    test('云盘曲目：resolvePlayUrl / fetchLyric 都走云盘分支', () async {
      final client = _FakeNeteaseClient()
        ..downloadRaw = downloadRaw
        ..lyricRaw = lyricLrcRaw
        ..loggedIn = true
        ..libraryPlayUrlRaw =
            '{"code":200,"data":[{"url":"http://library/","br":128000}]}'
        ..libraryLyricRaw = '{"lrc":{"lyric":"[00:00.00]曲库歌词\n"},"code":200}';
      // 云盘歌词口要 uid：用假 source 顶掉 currentAccount（不打 account/get）。
      final source = _FakeCloudSource(client);
      final track = const Track(
        id: '2165810543',
        name: '独庄子（3）',
        artist: '未知艺术家',
        album: '',
        coverUrl: '',
        durationMs: 1370196,
        cloudFileId: '2165810543',
      );

      final url = await source.resolvePlayUrl(track);
      expect(url.url, startsWith('http://m803.music.126.net/'));

      final lyric = await source.fetchLyric(track);
      expect(lyric.sourceTag, 'netease-cloud-lrc');
      expect(lyric.lines.first.text, '独庄子 - 3');
    });

    test('非云盘曲目：仍走曲库口（不被分支吃掉）', () async {
      final client = _FakeNeteaseClient()
        ..libraryPlayUrlRaw =
            '{"code":200,"data":[{"id":1,"url":"http://library/x.mp3","br":128000,"size":1,"type":"mp3"}]}';
      final source = NeteaseSource(client: client);
      final track = const Track(
        id: '186016',
        name: '晴天',
        artist: '周杰伦',
        album: '叶惠美',
        coverUrl: '',
        durationMs: 269314,
      );
      final result = await source.resolvePlayUrl(track);
      expect(result.url, 'http://library/x.mp3');
      expect(client.lastDownloadSongId, isNull);
    });
  });
}

/// 测试用假客户端：只覆盖 J 组三个口，其余一律不走网络。
class _FakeNeteaseClient extends NeteaseClient {
  String listRaw = '{"code":200,"data":[]}';
  String downloadRaw = '{"code":200,"url":"http://cloud/x.mp3"}';
  String lyricRaw = '{"lrc":"","krc":"","code":200}';
  String deleteRaw = '{"code":200}';

  /// 曲库口：用来证明云盘分支没有把非云盘曲目吃掉。
  String libraryPlayUrlRaw =
      '{"code":200,"data":[{"url":"http://library/","br":128000}]}';
  String libraryLyricRaw = '{"lrc":{"lyric":"[00:00.00]曲库歌词\n"},"code":200}';

  Map<String, Object?> lastList = const {};
  int? lastDownloadSongId;
  List<String> lastDeleteIds = const [];

  @override
  bool get hasLogin => loggedIn;

  bool loggedIn = false;

  @override
  Future<String> cloudDiskListRaw({int limit = 30, int offset = 0}) async {
    lastList = {'limit': limit, 'offset': offset};
    return listRaw;
  }

  @override
  Future<String> cloudDownloadRaw(int songId) async {
    lastDownloadSongId = songId;
    return downloadRaw;
  }

  @override
  Future<String> cloudLyricRaw({required int uid, required int songId}) async {
    return lyricRaw;
  }

  @override
  Future<String> cloudDiskDeleteRaw(List<String> songIds) async {
    lastDeleteIds = songIds;
    return deleteRaw;
  }

  @override
  Future<String> songPlayUrlRaw(
    int songId, {
    String level = 'exhigh',
    String encodeType = 'flac',
    bool isMysql = true,
  }) async {
    return libraryPlayUrlRaw;
  }

  @override
  Future<String> songLyricRaw(int songId) async => libraryLyricRaw;
}

/// 顶掉 [NeteaseSource.currentAccount] 的假 source：云盘歌词口要 uid，
/// 但不该在单测里打 `account/get`。
class _FakeCloudSource extends NeteaseSource {
  _FakeCloudSource(NeteaseClient client) : super(client: client);

  @override
  Future<LoginAccount?> currentAccount() async =>
      const LoginAccount(userId: '1593114455', nickname: 'MZHENGHF');
}
