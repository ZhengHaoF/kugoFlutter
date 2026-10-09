/// 网易云端点与请求常量（对齐 NeriPlayer `NeteaseClient`）。
abstract final class NeteaseEndpoints {
  static const mainHost = 'https://music.163.com';
  static const interfaceHost = 'https://interface.music.163.com';
  static const interface3Host = 'https://interface3.music.163.com';

  /// 一期：搜索/播放/歌词/单曲详情
  ///
  /// 注意：`cloudsearch/get/web` 实测可能回 `50000005`；**可用**旧口
  /// `/weapi/search/get`。
  static const search = '/weapi/search/get';
  static const searchCloud = '/weapi/cloudsearch/get/web';
  static const songPlayUrlV1 = '/eapi/song/enhance/player/url/v1';
  static const songPlayUrlWeapi = '/weapi/song/enhance/player/url';
  static const songLyricV1 = '/eapi/song/lyric/v1';
  static const songLyricPlain = '/api/song/lyric';
  static const songDetail = '/weapi/v3/song/detail';

  /// 登录 / 账号
  static const account = '/weapi/w/nuser/account/get';
  static const qrUnikey = '/weapi/login/qrcode/unikey';
  static const qrCheck = '/weapi/login/qrcode/client/login';
  static const loginCellphone = '/w/login/cellphone';
  static const smsSend = '/weapi/sms/captcha/sent';
  static const smsVerify = '/weapi/sms/captcha/verify';

  /// 我喜欢 / 用户歌单
  static const userPlaylist = '/weapi/user/playlist';
  static const songLikeGet = '/weapi/song/like/get';
  static const songLike = '/song/like';
  static const playlistManipulateTracks = '/playlist/manipulate/tracks';
  static const userAlbums = '/eapi/mine/rn/resource/list';

  /// H 组账号档案 / 会员（个人中心网易侧，2026-10-08 探针实测）。
  ///
  /// 三个口**明文即通**，故走 [NeteaseClient.callPlainApi]，不套 weapi 预热
  /// （省一次首页 GET，也少一个风控暴露面；同 G12/G13 结论）。
  ///
  /// - H6 [userDetail]：身份 / 等级 / 关注(`profile.follows`) / 粉丝
  ///   (`profile.followeds`) / 累计听歌(`listenSongs`) / 云贝(`userPoint`) /
  ///   档案(`createTime`/`gender`/`province`/`city`/`signature`)。
  ///   一个请求顶 H3+H4 多数字段，故产品侧**不打** getfollows/getfolloweds/subcount。
  /// - H1 [vipInfo]：VIP 等级 + 到期。`redVipLevel` 是**历史等级**（过期不归零），
  ///   判生效必须比对 `expireTime`。
  /// - H2 [userLevel]：升级进度（`progress` 是服务端算好的 0–1 比值）+ 权益串 `info`。
  static const userDetail = '/api/v1/user/detail';
  static const vipInfo = '/api/music-vip-membership/front/vip/info';
  static const userLevel = '/api/user/level';

  /// 详情（歌单 / 专辑 / 歌人）
  static const playlistDetail = '/api/v6/playlist/detail';
  static const albumDetail = '/weapi/v1/album/';
  static const artistHeadInfo = '/api/artist/head/info/get';
  static const artistDynamic = '/api/artist/detail/dynamic';
  static const artistSongs = '/api/v1/artist/songs';
  static const artistAlbums = '/api/artist/albums/';

  /// 推荐 / 发现（G 组）
  static const personalizedPlaylist = '/weapi/personalized/playlist';
  static const dailyRecommendResource = '/v1/discovery/recommend/resource';
  static const dailyRecommendSongs = '/v3/discovery/recommend/songs';
  static const personalFm = '/v1/radio/get';
  static const personalizedNewSong = '/personalized/newsong';
  static const topPlaylists = '/playlist/list';
  static const highQualityList = '/playlist/highquality/list';
  static const highQualityTags = '/api/playlist/highquality/tags';
  static const radarPlaylistMeta = '/api/playlist/detail';

  /// G11 榜单列表：全部官方榜的**元数据**（id / name / coverImgUrl /
  /// trackCount / updateFrequency），与 G10 的「按 id 取曲目」互补。
  /// 免登录 PLAIN API，形态与 `playlistDetail` 同族。
  static const toplistDetail = '/api/toplist/detail';

  /// G12 新碟上架：`area`（ALL / ZH / EA / KR / JP）+ `limit` / `offset` / `total`。
  ///
  /// 2026-09-26 实测**明文即通**（5 区全 `code=200`、`total=500`、`area` 真生效）——
  /// 参考实现（NeteaseCloudMusicApi `module/album_new.js`）用 weapi，但网易这口双认，
  /// 故留明文以免每次预热。
  static const albumNew = '/api/album/new';

  /// G13 歌手列表：`type`（-1 全部 / 1 男 / 2 女 / 3 乐队）+ `area`
  /// （-1 全部 / 7 华语 / 96 欧美 / 8 日本 / 16 韩国 / 0 其他）+ `initial`
  /// + `limit` / `offset` / `total`。
  ///
  /// **路径必须带 `v1`**（2026-09-26 实测）：`/api/artist/list`（无 `v1`）是**旧路由**，
  /// 只认 `limit`，`type`/`area`/`initial` 全被忽略（换参数响应逐字节相同）；
  /// 参照 NeteaseCloudMusicApi `module/artist_list.js` 打 `/api/v1/artist/list`。
  /// 另注意 `initial` 需转**大写 ASCII 码**（`a` → `65`），见 `NeteaseClient._artistInitialCode`。
  static const artistList = '/api/v1/artist/list';

  /// N1 评论：E1 列表 / E2 楼层。
  ///
  /// **E1 是 eapi + `interfaceHost` 的新口**（`/eapi/v2/resource/comments`），
  /// 与一期验证过的 `/eapi/song/*` 同族但路径不同；这里写**不带 `/eapi` 前缀**
  /// 的短路径，由 `NeteaseClient.callEApi` 自动补前缀。
  /// 老口 `/weapi/v1/resource/comments/{threadId}` 是顶层平铺，**不要混用**
  /// （两套包裹不同，按错的那套读会拿到空列表）。
  static const commentList = '/v2/resource/comments';

  /// E2 楼层：weapi（`/weapi/resource/comment/floor/get`），同样是短路径。
  static const commentFloor = '/resource/comment/floor/get';

  /// N3 热搜：weapi，`type=1111`（参考 `module/search_hot.js`）。
  static const searchHot = '/weapi/search/hot';

  /// A1-MV 详情 / 取流（对齐 api-enhanced `module/mv_detail.js` / `mv_url.js`）。
  ///
  /// ★ weapi 路径坑：其 request 做 `'/weapi/' + uri.substr(5)` 剥掉 `/api/`，
  /// module 写 `/api/v1/mv/detail` 实际打 `/weapi/v1/mv/detail`。
  /// 这里直接写**已剥前缀**的路径，由 [NeteaseClient.callWeApi] 补 `/weapi`。
  /// 传 `/api/...` 会得到 `code=404 「接口未找到！」`（2026-09-28 实测）。
  static const mvDetail = '/v1/mv/detail';
  static const mvUrl = '/song/enhance/play/mv/url';

  /// N2 写侧：发评论 / 回复楼层 / 点赞（取消赞是 `/unlike`）。
  ///
  /// 三个口都**要登录**（游客实测回 `301`）。
  static const commentAdd = '/weapi/resource/comments/add';
  static const commentReply = '/weapi/resource/comments/reply';
  static const commentLike = '/weapi/v1/comment/like';
  static const commentUnlike = '/weapi/v1/comment/unlike';

  /// J 组音乐云盘（对齐 api-enhanced `module/user_cloud*.js` / `cloud*.js`，
  /// 2026-10-09 起接；协议面齐全，字段形态待探针实测）。
  ///
  /// **全部要登录**（游客预期 `301`）。加密口径分三族，别混：
  /// - 列表 / 详情 / 删除 / 匹配 = **weapi**（走 [NeteaseClient.callWeApi]，
  ///   这里写不带 `/api` 的短路径，由它补 `/weapi`）；
  /// - 取流 / 歌词 = **eapi**（走 [NeteaseClient.callEApi]，补 `/eapi`）；
  /// - 上传链（check / nos token / info / pub）= **明文**（[NeteaseClient.callPlainApi]）。
  ///
  /// ⚠️ [cloudDownload] 上游拼写就是 `dowonload`（少一个 `l`），照抄才不会 404
  /// ——和 `/api/subcount` 少一段 `user/`、`/api/v1/artist/list` 缺 `v1` 同类。
  ///
  /// ⚠️ weapi 的坑（G13 实测）：NeteaseCloudMusicApi 对 weapi 会把**路径前缀**
  /// 一起换掉（`/api/v1/...` → `/weapi/v1/...`），不是「加密体 + 原 `/api/` 路径」。
  /// 故 weapi 口一律写已剥前缀的短路径，别图省事把 `/api/...` 塞给 `callWeApiAt`。
  static const cloudGet = '/v1/cloud/get';
  static const cloudGetByIds = '/v1/cloud/get/byids';
  static const cloudDel = '/cloud/del';
  static const cloudDownload = '/cloud/dowonload';
  static const cloudLyric = '/cloud/lyric/get';
  static const cloudMatch = '/cloud/user/song/match';

  /// 上传链（明文）。[cloudNosTokenAlloc] 的 bucket 由上游固定。
  static const cloudUploadCheck = '/api/cloud/upload/check';
  static const cloudNosTokenAlloc = '/api/nos/token/alloc';
  static const cloudUploadInfo = '/api/upload/cloud/info/v2';
  static const cloudPub = '/api/cloud/pub/v2';
  static const cloudImport = '/api/cloud/user/song/import';

  /// 网易云盘上传对象存储 bucket（api-enhanced `module/cloud_upload_token.js` 硬编码）。
  static const cloudNosBucket = 'jd-musicrep-privatecloud-audio-public';

  /// NOS 上传节点发现（LBS）：`GET {cloudNosLbs}{bucket}` → `upload[0]`。
  static const cloudNosLbs = 'https://wanproxy.127.net/lbs?version=1.0&bucketname=';

  static String weapiUrl(String path, {String host = mainHost}) {
    final p = path.startsWith('/') ? path : '/$path';
    return '$host/weapi$p'.replaceFirst('/weapi/weapi', '/weapi');
  }

  static String eapiUrl(String path, {String host = interfaceHost}) {
    final p = path.startsWith('/') ? path : '/$path';
    if (p.startsWith('/eapi')) return '$host$p';
    return '$host/eapi$p';
  }

  static String plainUrl(String path, {String host = mainHost}) {
    final p = path.startsWith('/') ? path : '/$path';
    return '$host$p';
  }
}
