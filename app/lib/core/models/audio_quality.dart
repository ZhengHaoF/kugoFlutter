import 'track.dart';

/// 用户可选音质档（对齐 EchoMusic 的播放器切换语义，无蝰蛇母带）。
enum AppQuality { standard, hq, sq, hiRes }

/// 单条可用音质记录（列表/privilege 返回的 relate_goods 等）。
class RelateGood {
  const RelateGood({this.hash = '', this.quality = '', this.level});

  final String hash;
  final String quality;
  final int? level;
}

extension AppQualityX on AppQuality {
  /// `/v5/url` quality 参数（song_url.js：quality || 128）。
  String get param => switch (this) {
        AppQuality.standard => '128',
        AppQuality.hq => '320',
        AppQuality.sq => 'flac',
        AppQuality.hiRes => 'hires',
      };

  String get label => switch (this) {
        AppQuality.standard => '标准',
        AppQuality.hq => '高品',
        AppQuality.sq => '无损',
        AppQuality.hiRes => 'Hi-Res',
      };

  /// 播放页徽章短标签（EchoMusic：SD/HQ/SQ/HR）。
  String get badge => switch (this) {
        AppQuality.standard => 'SD',
        AppQuality.hq => 'HQ',
        AppQuality.sq => 'SQ',
        AppQuality.hiRes => 'HR',
      };

  /// 从高到低的向下兼容候选（含自身）。
  List<AppQuality> get candidatesDownward {
    const order = [
      AppQuality.hiRes,
      AppQuality.sq,
      AppQuality.hq,
      AppQuality.standard,
    ];
    final i = order.indexOf(this);
    return order.sublist(i < 0 ? 0 : i);
  }
}

/// 音质工具：解析 / 可用性 / 降级 — 参照 EchoMusic `utils/song.ts`。
abstract final class AudioQualityUtil {
  /// 解析 API 里的 quality 字符串 → [AppQuality]；未知返回 null。
  static AppQuality? parseQualityToken(Object? raw) {
    final s = raw?.toString().trim().toLowerCase();
    if (s == null || s.isEmpty || s == 'null') return null;
    return switch (s) {
      '128' || '128k' || 'sd' || 'low' => AppQuality.standard,
      '320' || '320k' || 'hq' || 'high_quality' => AppQuality.hq,
      'flac' || 'sq' || 'lossless' => AppQuality.sq,
      'hires' || 'high' || 'hi-res' || 'hi_res' || 'res' => AppQuality.hiRes,
      _ => null,
    };
  }

  /// level 字段（EchoMusic：4=HQ, 5=SQ, 6=HR）。
  static AppQuality? parseQualityLevel(Object? raw) {
    final n = int.tryParse(raw?.toString() ?? '');
    if (n == null) return null;
    return switch (n) {
      4 => AppQuality.hq,
      5 => AppQuality.sq,
      6 => AppQuality.hiRes,
      _ => null,
    };
  }

  /// 从任意 JSON 片段构建 relate goods（对齐 EchoMusic `buildRelateGoods`）。
  static List<RelateGood> buildRelateGoods(Map<String, dynamic> json) {
    final goods = <RelateGood>[];

    void push(Object? hash, Object? quality, [Object? level]) {
      final h = hash?.toString().trim() ?? '';
      if (h.isEmpty || h == 'null') return;
      goods.add(
        RelateGood(
          hash: h,
          quality: quality?.toString().trim() ?? '',
          level: int.tryParse(level?.toString() ?? ''),
        ),
      );
    }

    void pushQualityHash(Object? hash, String quality) => push(hash, quality);

    Map<String, dynamic> asMap(Object? v) => v is Map
        ? Map<String, dynamic>.from(v)
        : const <String, dynamic>{};

    Object? pick(Map<String, dynamic> map, List<String> keys) {
      for (final k in keys) {
        final v = map[k];
        if (v == null) continue;
        if (v is Map || v is List) continue;
        final t = v.toString().trim();
        if (t.isEmpty || t == 'null') continue;
        return v;
      }
      return null;
    }

    final sources = <Map<String, dynamic>>[
      json,
      asMap(json['extra']),
      asMap(json['audio_info']),
      asMap(json['privilege']),
      asMap(json['trans_param']),
    ];

    for (final src in sources) {
      final rawGoods = src['relate_goods'] ?? src['relateGoods'];
      if (rawGoods is List) {
        for (final item in rawGoods) {
          if (item is! Map) continue;
          final m = Map<String, dynamic>.from(item);
          final hash = pick(m, ['hash', 'Hash', 'file_hash', 'fileHash']);
          final quality = pick(m, ['quality', 'Quality', 'q']);
          final level = pick(m, ['level', 'quality_level', 'qualityLevel']);
          push(hash, quality, level);
        }
      }
    }

    for (final src in sources) {
      pushQualityHash(pick(src, ['hash_320', 'hash320', '320hash']), '320');
      pushQualityHash(
        pick(src, ['hash_flac', 'hashflac', 'flachash', 'sqhash', 'hash_sq']),
        'flac',
      );
      pushQualityHash(
        pick(src, ['hash_high', 'hashhigh', 'highhash', 'hash_hires', 'hiresshash']),
        'high',
      );
      final hq = asMap(src['HQ']);
      final sq = asMap(src['SQ']);
      final res = asMap(src['Res']);
      pushQualityHash(pick(hq, ['Hash', 'hash']), '320');
      pushQualityHash(pick(sq, ['Hash', 'hash']), 'flac');
      pushQualityHash(pick(res, ['Hash', 'hash']), 'high');
    }

    return goods;
  }

  /// goods → 可用 [AppQuality] 集合。空集合表示「未知」。
  static Set<AppQuality> availableFromGoods(List<RelateGood> goods) {
    if (goods.isEmpty) return <AppQuality>{};
    final out = <AppQuality>{AppQuality.standard};
    for (final g in goods) {
      final q = parseQualityToken(g.quality) ?? parseQualityLevel(g.level);
      if (q != null) out.add(q);
    }
    return out;
  }

  /// 该曲目是否有指定音质。[available] 为空时视为未知 → 允许尝试。
  ///
  /// [catalogComplete] 为 true 表示接口给出了完整 relate_goods 目录；
  /// 移动端 search 往往只有 320hash/sqhash、没有 hi-res 字段，
  /// 此时 hiRes 视为未知，不禁用（播放时向下 resolve）。
  static bool hasQuality(
    Set<AppQuality> available,
    AppQuality q, {
    bool catalogComplete = true,
  }) {
    if (q == AppQuality.standard) return true;
    if (available.isEmpty) return true;
    if (available.contains(q)) return true;
    if (q == AppQuality.hiRes && !catalogComplete) return true;
    return false;
  }

  /// 请求候选：偏好档向下；若已知可用音质则过滤。
  static List<AppQuality> resolveCandidates({
    required AppQuality preferred,
    required Set<AppQuality> available,
    bool compatibilityMode = true,
    bool catalogComplete = true,
  }) {
    final base = compatibilityMode
        ? preferred.candidatesDownward
        : [preferred];
    if (available.isEmpty) return base;
    return [
      for (final q in base)
        if (hasQuality(available, q, catalogComplete: catalogComplete)) q,
      if (!base.any((q) => q == AppQuality.standard) &&
          hasQuality(available, AppQuality.standard,
              catalogComplete: catalogComplete))
        AppQuality.standard,
    ];
  }

  /// UI 展示的「当前音质」：优先实际解析结果，否则用户偏好。
  static String badgeLabel({
    required AppQuality preferred,
    String? resolvedParam,
  }) {
    final resolved = parseQualityToken(resolvedParam);
    return (resolved ?? preferred).badge;
  }

  /// 从 resolved 字符串（128/320/flac/hires/128k…）得到展示用 label。
  static String displayLabelFromParam(String? param) {
    final q = parseQualityToken(param);
    return q?.label ?? '';
  }
}

extension TrackQualityX on Track {
  /// 是否已知该音质可用（availableQualities 空 = 未知，不 disable）。
  bool qualityKnownAvailable(AppQuality q) => AudioQualityUtil.hasQuality(
        availableQualities,
        q,
        catalogComplete: qualityCatalogComplete,
      );

  /// 可选音质集合（未知时为空）。
  bool get qualityAvailabilityKnown => availableQualities.isNotEmpty;

  /// 最高可用音质徽章（未知时回退 track.quality 字符串）。
  String get qualityBadgeLabel {
    if (availableQualities.isNotEmpty) {
      for (final q in const [
        AppQuality.hiRes,
        AppQuality.sq,
        AppQuality.hq,
        AppQuality.standard,
      ]) {
        if (availableQualities.contains(q)) {
          return availableQualities.length == 1 &&
                  availableQualities.contains(AppQuality.standard)
              ? quality
              : q.badge;
        }
      }
    }
    return quality;
  }

  Track withAvailableQualities(Set<AppQuality> values) {
    final highest = values.isEmpty
        ? null
        : (values.contains(AppQuality.hiRes)
            ? 'Hi-Res'
            : values.contains(AppQuality.sq)
                ? 'SQ'
                : values.contains(AppQuality.hq)
                    ? 'HQ'
                    : 'SD');
    return copyWith(
      availableQualities: values,
      quality: highest ?? quality,
    );
  }
}
