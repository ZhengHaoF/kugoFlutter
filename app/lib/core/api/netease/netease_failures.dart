import '../../source/music_source.dart';

/// 网易业务码 → [SourceFailure]。301 只属网易；酷狗 20028 勿混用。
SourceFailure mapNeteaseCode(int? code, {String message = ''}) {
  final msg = message.isEmpty ? 'netease code=$code' : message;
  switch (code) {
    case 200:
      return UpstreamChanged(msg);
    case 301:
      return LoginRequired(msg);
    case 302:
    case 800:
    case 801:
    case 802:
    case 803:
      return LoginRequired(msg);
    case 404:
      return NotFound(msg);
    case -460:
    case -462:
    case 405:
      return RateLimited(msg);
    case 403:
      return NoPermission(msg);
    default:
      return UpstreamChanged(msg);
  }
}

/// 播放响应里曲目级失败。
SourceFailure mapNeteasePlayFailure({
  required int? dataCode,
  required int fee,
  int? cannotListenReason,
  String message = '',
}) {
  if (cannotListenReason == 1 || (fee > 0 && dataCode != 200)) {
    return NoPermission(message.isEmpty ? '没有播放权限 fee=$fee' : message);
  }
  if (dataCode == 404) {
    return NotFound(message.isEmpty ? '曲目不存在' : message);
  }
  return NoPermission(message.isEmpty ? '无播放地址 code=$dataCode' : message);
}
