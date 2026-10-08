import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/netease/netease_account_models.dart';
import '../../core/api/netease/netease_account_source.dart';
import '../../data/sources/netease/netease_source.dart';
import '../auth/netease_login_controller.dart';
import 'profile_stats.dart'
    show formatAccountAge, formatGender, formatVipDate, formatVipExpireText;

/// 网易云账号档案 / 会员的**页面态**（个人中心网易侧）。
///
/// 三个数据源一次并发拉齐（[NeteaseAccountProfileNotifier.load]），
/// `loaded` 后不重复打——进页面只花 3 个明文请求，手动刷新才 `force`。
class NeteaseAccountProfileState {
  const NeteaseAccountProfileState({
    this.detail = NeteaseUserDetail.empty,
    this.vip = NeteaseVipInfo.empty,
    this.level = NeteaseLevelInfo.empty,
    this.loading = false,
    this.loaded = false,
    this.error = '',
  });

  final NeteaseUserDetail detail;
  final NeteaseVipInfo vip;
  final NeteaseLevelInfo level;

  final bool loading;
  final bool loaded;

  /// 任一接口失败时的可读原因；成功为空串。
  final String error;

  /// 是否拿到有效身份（uid 非空）。
  bool get hasIdentity => detail.userId.isNotEmpty;

  NeteaseAccountProfileState copyWith({
    NeteaseUserDetail? detail,
    NeteaseVipInfo? vip,
    NeteaseLevelInfo? level,
    bool? loading,
    bool? loaded,
    String? error,
  }) {
    return NeteaseAccountProfileState(
      detail: detail ?? this.detail,
      vip: vip ?? this.vip,
      level: level ?? this.level,
      loading: loading ?? this.loading,
      loaded: loaded ?? this.loaded,
      error: error ?? this.error,
    );
  }
}

class NeteaseAccountProfileNotifier
    extends Notifier<NeteaseAccountProfileState> {
  @override
  NeteaseAccountProfileState build() {
    // 登录态是异步回填的：既听转换，也在已登录时补一次（与
    // `netease_collections_controller` 同构）。登出要清空，否则换账号
    // 会残留上一个号的档案。
    ref.listen<NeteaseLoginState>(neteaseLoginControllerProvider, (prev, next) {
      if (next.isLogged && !state.loaded) {
        load();
      } else if (!next.isLogged && state.loaded) {
        state = const NeteaseAccountProfileState();
      }
    });
    if (ref.read(neteaseLoginControllerProvider).isLogged) {
      Future.microtask(load);
    }
    return const NeteaseAccountProfileState();
  }

  /// [force] 忽略 `loaded` 重新拉（下拉刷新 / 登录后立即刷新）。
  ///
  /// 三个口**并发**发（`Future.wait`），失败的那个留 empty 并由 [error]
  /// 说明——不因一个口挂掉整块档案不出。
  Future<void> load({bool force = false}) async {
    if (state.loading) return;
    if (!force && state.loaded) return;

    // uid 从已缓存的登录态取，不额外打 account/get。
    final uid = int.tryParse(
          ref.read(neteaseLoginControllerProvider).account?.userId ?? '',
        ) ??
        0;
    if (uid <= 0) {
      state = const NeteaseAccountProfileState(loaded: true, error: '需登录后查看');
      return;
    }

    state = state.copyWith(loading: true, error: '');
    final source = ref.read(neteaseAccountSourceProvider);
    // 三个口并发；单个失败不拖垮另外两个（失败的那个留 empty）。
    final results = await Future.wait([
      _guard(() => source.userDetail(uid)),
      _guard(() => source.vipInfo(userId: uid)),
      _guard(() => source.userLevel()),
    ]);

    final detail = results[0].value;
    final vip = results[1].value;
    final level = results[2].value;
    final firstError = [
      for (final r in results)
        if (r.error != null) _msg(r.error!),
    ].firstOrNull;

    state = NeteaseAccountProfileState(
      detail: detail is NeteaseUserDetail ? detail : NeteaseUserDetail.empty,
      vip: vip is NeteaseVipInfo ? vip : NeteaseVipInfo.empty,
      level: level is NeteaseLevelInfo ? level : NeteaseLevelInfo.empty,
      loaded: true,
      error: firstError == null ? '' : '部分账号信息获取失败：$firstError',
    );
  }

  /// 把一次请求收成 `(value, error)`，供 [Future.wait] 后逐个判成败。
  static Future<({Object? value, Object? error})> _guard<T>(
    Future<T> Function() call,
  ) async {
    try {
      return (value: await call(), error: null);
    } catch (e) {
      return (value: null, error: e);
    }
  }

  String _msg(Object e) {
    final s = e.toString().split('\n').first.trim();
    return s.isEmpty ? '网络异常' : s;
  }
}

/// 账号档案数据源（默认全局网易源；测试覆盖成假源）。
final neteaseAccountSourceProvider = Provider<NeteaseAccountSource>(
  (ref) => neteaseSource,
);

final neteaseAccountProfileProvider =
    NotifierProvider<NeteaseAccountProfileNotifier, NeteaseAccountProfileState>(
  NeteaseAccountProfileNotifier.new,
);

// ── 格式化（对齐酷狗侧 profile_stats.dart 的口径） ───────────

/// 省级行政区划编码 → 名称（网易 `profile.province` 给的是编码，不是中文）。
///
/// **只到省级**：市级要 ~300 条映射表，收益不抵体积；且网易不下发省市文本，
/// 县级/市辖区还得再转一次。要显示「浙江 - 杭州」需另加市级表。
///
/// 键取编码**前两位**（`330000` → `33`），兼容服务端给 `33`/`3300`/`330000`。
const Map<String, String> neteaseProvinceNames = {
  '11': '北京',
  '12': '天津',
  '13': '河北',
  '14': '山西',
  '15': '内蒙古',
  '21': '辽宁',
  '22': '吉林',
  '23': '黑龙江',
  '31': '上海',
  '32': '江苏',
  '33': '浙江',
  '34': '安徽',
  '35': '福建',
  '36': '江西',
  '37': '山东',
  '41': '河南',
  '42': '湖北',
  '43': '湖南',
  '44': '广东',
  '45': '广西',
  '46': '海南',
  '50': '重庆',
  '51': '四川',
  '52': '贵州',
  '53': '云南',
  '54': '西藏',
  '61': '陕西',
  '62': '甘肃',
  '63': '青海',
  '64': '宁夏',
  '65': '新疆',
  '71': '台湾',
  '81': '香港',
  '82': '澳门',
};

/// 编码 → 省级名称；无法识别返回空串（UI 出 `—`，不显示原始编码）。
String neteaseProvinceName(String code) {
  final s = code.trim();
  if (s.length < 2) return '';
  return neteaseProvinceNames[s.substring(0, 2)] ?? '';
}

/// 档案「所在地区」：只到省级（见 [neteaseProvinceNames] 注释）。
String neteaseLocationText(String provinceCode) =>
    neteaseProvinceName(provinceCode);

/// 性别。网易 `profile.gender` 与酷狗同口径（0 女 / 1 男 / 其他保密），
/// 故直接复用 [formatGender]。
String neteaseGenderLabel(Object? gender) => formatGender(gender);

/// 乐龄。网易 `createTime` 是 **epoch 毫秒**，而 [formatAccountAge] 要秒，
/// 这里先 `/1000`。[now] 可注入，便于测试。
String neteaseAccountAge(Object? createTimeMs, {DateTime? now}) {
  if (createTimeMs is! num || createTimeMs <= 0) return '未知';
  return formatAccountAge(createTimeMs ~/ 1000, now: now);
}

/// 累计听歌。网易给的是**歌曲数**（`listenSongs`，实测 10904），
/// 酷狗给的是时长——两者语义不同，别复用 [formatListeningDuration]。
String neteaseListenSongsLabel(int count) =>
    count <= 0 ? '—' : '$count 首';

/// 生效中的主会员名（徽章文案）。黑胶VIP 优先，其次音乐包。
///
/// 判生效用 [NeteaseVipMembership.isActiveAt] 比对 `expireTime`，
/// **不用 `redVipLevel > 0`**——实测账号等级 7 但会员已过期两个月。
String? neteaseVipBadgeLabel(NeteaseVipInfo vip, {DateTime? now}) {
  final clock = now ?? DateTime.now();
  for (final m in vip.activeAt(clock)) {
    if (m.vipCode == 100) return '黑胶VIP';
    if (m.vipCode == 220) return '音乐包';
  }
  return null;
}

/// 会员到期提示。直接复用酷狗的 [formatVipExpireText]——网易 `expireTime`
/// 是 13 位 epoch 毫秒，`parseKugoDateTime` 已能吃。
String? neteaseVipExpireText(
  NeteaseVipInfo vip, {
  DateTime? now,
}) {
  final clock = now ?? DateTime.now();
  for (final m in vip.activeAt(clock)) {
    final text = formatVipExpireText(m.expireTime, now: clock);
    if (text != null) return text;
  }
  return null;
}

/// 到期日（`yyyy-MM-dd HH:mm`），tooltip 用。
String neteaseVipExpireDate(NeteaseVipInfo vip) {
  final clock = DateTime.now();
  for (final m in vip.activeAt(clock)) {
    return formatVipDate(m.expireTime);
  }
  return '--';
}

/// 听歌等级标签（`Lv.9`），与酷狗 [GradeProgress.gradeLabel] 同形。
String neteaseLevelLabel(int level) => level <= 0 ? '—' : 'Lv.$level';
