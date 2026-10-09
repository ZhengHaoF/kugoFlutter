/// 哔哩哔哩端点与请求常量（对齐 NeriPlayer `core/api/bili/BiliClient.kt`，
/// 端点已逐个核对一致）。
///
/// B 站是纯 HTTP API（没有网易 weapi/eapi 那套加密），但 WBI 反爬签名
/// （`bili_sign.dart`）与防盗链头（Referer/UA，见 [referer] / [webUA]）
/// 必须自己做。
abstract final class BiliEndpoints {
  static const apiHost = 'https://api.bilibili.com';
  static const passportHost = 'https://passport.bilibili.com';

  /// 取流 / 封面防盗链 Referer（NeriPlayer `BiliClient.REFERER`）。
  static const referer = 'https://www.bilibili.com';

  /// Web UA。不能用 Dart 默认 UA——B 站 CDN 会按 UA 拒匿名客户端。
  /// 取流直链（`*.bilivideo.com`）同样校验 UA + Referer。
  static const webUA =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

  // ── 基础设施 ──────────────────────────────────────────────

  /// I1 WBI 签名材料：`data.wbi_img.img_url` / `sub_url`。本身不带 WBI 签名。
  static const nav = '/x/web-interface/nav';

  /// I3 匿名设备指纹：`b_3` / `b_4` / `buvid_fp` / `buvid_fp_plain`。
  static const fingerSpi = '/x/frontend/finger/spi';

  /// I2 WebTicket 兜底（P1）：`nav` 取不到 `wbi_img` 时退化到它。
  static const genWebTicket =
      '/bapis/bilibili.api.ticket.v1.Ticket/GenWebTicket';

  // ── 业务（B1 探针范围）────────────────────────────────────

  /// A1 搜索视频：`search_type=video`，WBI 签名。一个视频 = 一首「歌」。
  static const searchType = '/x/web-interface/wbi/search/type';

  /// B1 取流：DASH 音轨，WBI 签名。必须带 `bvid` + `cid`。
  static const playurl = '/x/player/wbi/playurl';

  /// B2 分 P 列表：不带签名。裸 `bvid` → 各 P 的 `cid`。
  static const pagelist = '/x/player/pagelist';

  /// C1 视频信息：WBI 签名。
  static const view = '/x/web-interface/wbi/view';

  // ── 账号（B3，端点先留位）─────────────────────────────────

  /// G1 扫码-生成。注意 host 是 passport，Referer 用 [loginPageUrl]。
  static const qrcodeGenerate = '/x/passport-login/web/qrcode/generate';

  /// G2 扫码-轮询（86101 等待 / 86090 已扫 / 86038 过期 / 0 成功）。
  static const qrcodePoll = '/x/passport-login/web/qrcode/poll';

  /// 扫码链路专用 Referer（NeriPlayer `BiliQrLoginClient.BILI_REFERER`）。
  static const loginPageUrl = 'https://passport.bilibili.com/login';

  // ── fnval 位（对齐 NeriPlayer）────────────────────────────

  /// DASH 开关（16）。不开只有 `durl`（整段 MP4）。
  static const fnvalDash = 1 << 4;

  /// 杜比音频（256）。要拿 `dash.dolby.audio` 必开。
  static const fnvalDolby = 1 << 8;

  /// 默认：DASH + 杜比 = 272。Hi-Res flac 随 DASH 一并下发（`dash.flac`）。
  static const fnvalDefault = fnvalDash | fnvalDolby;

  /// WebTicket HMAC key（NeriPlayer `WEB_TICKET_KEY`，硬编码事实，勿改）。
  static const webTicketKey = 'XgwSnGZ1p';
}
