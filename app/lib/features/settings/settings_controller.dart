import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/cache/cover_cache.dart';
import '../../core/models/audio_quality.dart';
import '../../core/source/features.dart';
import '../../core/source/music_platform.dart';
import '../../data/storage/queue_store.dart';

export '../../core/models/audio_quality.dart' show AppQuality, AppQualityX;

enum SleepTimerMode { off, m15, m30, m60, custom }

enum AppThemeMode { dark, light, system }

/// 歌词字号倍率可调范围（1.0 = 现有默认字号）。
const double kLyricFontScaleMin = 0.8;
const double kLyricFontScaleMax = 1.6;

/// 歌词行间距倍率可调范围（1.0 = 现有默认行间距）。
/// 下限贴近「文字刚好不重叠」，再小会被行盒高度下限挡住（见 lyrics_view）。
const double kLyricSpacingScaleMin = 0.5;
const double kLyricSpacingScaleMax = 2.0;

/// Desktop: what the window close button does.
///
/// `ask` is the "don't remember" state — the close prompt shows every time,
/// unless the user ticks「记住我的选择」there (which persists `tray` / `quit`).
enum CloseBehavior { ask, tray, quit }

extension CloseBehaviorX on CloseBehavior {
  String get label => switch (this) {
        CloseBehavior.ask => '每次询问',
        CloseBehavior.tray => '最小化到托盘',
        CloseBehavior.quit => '退出应用',
      };

  /// Settings-row subtitle / close-prompt hint.
  String get closeHint => switch (this) {
        CloseBehavior.ask => '关闭时弹出提示，可勾选「记住我的选择」',
        CloseBehavior.tray => '关闭时最小化到系统托盘，不退出应用',
        CloseBehavior.quit => '关闭时直接退出应用',
      };
}

class AppSettings {
  const AppSettings({
    this.quality = AppQuality.hq,
    this.sleepMode = SleepTimerMode.off,
    this.sleepCustomMinutes = 45,
    this.wifiCoverOnly = false,
    this.lyricTranslation = true,
    this.lyricRomanization = false,
    this.lyricFontScale = 1,
    this.lyricSpacingScale = 1,
    this.mediaLyricSubtitle = false,
    this.themeMode = AppThemeMode.light,
    this.closeBehavior = CloseBehavior.ask,
    this.taskbarProgress = true,
    this.defaultSource = MusicPlatform.kugou,
    this.enabledSources = const {
      MusicPlatform.kugou,
      MusicPlatform.netease,
    },
    this.disabledFeatures = const {},
  });

  final AppQuality quality;
  final SleepTimerMode sleepMode;
  final int sleepCustomMinutes;
  final bool wifiCoverOnly;

  /// 歌词副行：译文（KRC `[language:]` type=1）。
  final bool lyricTranslation;

  /// 歌词副行：音译/罗马音（type=0）。默认关，中文歌收益低。
  final bool lyricRomanization;

  /// 歌词字号倍率（[kLyricFontScaleMin]–[kLyricFontScaleMax]，1.0 = 默认）。
  /// 主行/副行字号与行盒同步缩放，桌面与移动端同一套值。
  final double lyricFontScale;

  /// 歌词行间距倍率（[kLyricSpacingScaleMin]–[kLyricSpacingScaleMax]）。
  /// 只影响行与行之间的距离（ListView `itemExtent`），与字号独立。
  final double lyricSpacingScale;

  /// System media (lock screen / Bluetooth) subtitle shows `artist · lyric`.
  final bool mediaLyricSubtitle;
  final AppThemeMode themeMode;

  /// Desktop only: what the window close button does (ask / tray / quit).
  final CloseBehavior closeBehavior;

  /// Windows only: taskbar button progress bar (Echo「任务栏播放进度条」).
  final bool taskbarProgress;

  /// 默认音源：搜索页音源筛选与「我喜欢」页源筛选的初始值（用户当次仍可切换）。
  final MusicPlatform defaultSource;

  /// 启用的音源（整源开关）。默认全集；空集合非法，setter 会拒绝。
  ///
  /// 只影响「新内容的入口」：搜索混排、源筛选条、默认源选择器与
  /// 单源功能页（FM/榜单/日推/发现）的空态。已在播放队列中的曲目
  /// 不受影响（播放器按曲目平台取源，不经此开关）。
  final Set<MusicPlatform> enabledSources;

  /// 被**关闭**的「源 × 功能」子开关（[SourceFeature.tokenFor] 的集合）。
  ///
  /// 存「关闭项」而不是「启用项」：缺省（老数据 / 以后新增的功能）= 全开，
  /// 既不需要迁移，也不会让新加的功能一上线就是关的。允许全关——父开关
  /// 关闭时子项只是置灰、取值保留，重新启用父开关即恢复。
  final Set<String> disabledFeatures;

  /// 子开关**自身**的取值（不含父开关），供设置页显示。
  bool isFeatureOn(MusicPlatform p, SourceFeature f) =>
      !disabledFeatures.contains(f.tokenFor(p));

  /// 实际是否生效：父（整源）+ 子（功能）两级 AND。消费点一律用这个。
  bool isFeatureEnabled(MusicPlatform p, SourceFeature f) =>
      enabledSources.contains(p) && isFeatureOn(p, f);

  /// 空态归因用：有「启用中、但该功能被单独关掉」的源 → 返回该功能（页面
  /// 提示「这一项已关闭」）；一个都没有 → 返回 null（页面提示「音源已停用」，
  /// 因为此时锅在整源开关或该源压根没这个能力）。
  ///
  /// 不拿 [effectiveDefaultSource] 判断：它按定义必然落在启用集里，永远为真。
  SourceFeature? featureSwitchCause(SourceFeature f) =>
      enabledSources.any((p) => !isFeatureOn(p, f)) ? f : null;

  /// 默认源被停用后的回退值：按枚举序取第一个仍启用的源。
  MusicPlatform get effectiveDefaultSource =>
      enabledSources.contains(defaultSource)
          ? defaultSource
          : MusicPlatform.values.firstWhere(
              enabledSources.contains,
              orElse: () => MusicPlatform.kugou,
            );

  String get defaultSourceLabel => defaultSource.label;

  ThemeMode get materialThemeMode => switch (themeMode) {
        AppThemeMode.dark => ThemeMode.dark,
        AppThemeMode.light => ThemeMode.light,
        AppThemeMode.system => ThemeMode.system,
      };

  String get themeModeLabel => switch (themeMode) {
        AppThemeMode.dark => '深色',
        AppThemeMode.light => '浅色',
        AppThemeMode.system => '跟随系统',
      };

  int get sleepMinutes => switch (sleepMode) {
        SleepTimerMode.off => 0,
        SleepTimerMode.m15 => 15,
        SleepTimerMode.m30 => 30,
        SleepTimerMode.m60 => 60,
        SleepTimerMode.custom => sleepCustomMinutes,
      };

  String get qualityLabel => quality.label;

  /// 概念版 `/v5/url` 的 quality 参数（song_url.js：quality || 128）。
  String get qualityParam => quality.param;

  AppSettings copyWith({
    AppQuality? quality,
    SleepTimerMode? sleepMode,
    int? sleepCustomMinutes,
    bool? wifiCoverOnly,
    bool? lyricTranslation,
    bool? lyricRomanization,
    double? lyricFontScale,
    double? lyricSpacingScale,
    bool? mediaLyricSubtitle,
    AppThemeMode? themeMode,
    CloseBehavior? closeBehavior,
    bool? taskbarProgress,
    MusicPlatform? defaultSource,
    Set<MusicPlatform>? enabledSources,
    Set<String>? disabledFeatures,
  }) {
    return AppSettings(
      quality: quality ?? this.quality,
      sleepMode: sleepMode ?? this.sleepMode,
      sleepCustomMinutes: sleepCustomMinutes ?? this.sleepCustomMinutes,
      wifiCoverOnly: wifiCoverOnly ?? this.wifiCoverOnly,
      lyricTranslation: lyricTranslation ?? this.lyricTranslation,
      lyricRomanization: lyricRomanization ?? this.lyricRomanization,
      lyricFontScale: lyricFontScale ?? this.lyricFontScale,
      lyricSpacingScale: lyricSpacingScale ?? this.lyricSpacingScale,
      mediaLyricSubtitle: mediaLyricSubtitle ?? this.mediaLyricSubtitle,
      themeMode: themeMode ?? this.themeMode,
      closeBehavior: closeBehavior ?? this.closeBehavior,
      taskbarProgress: taskbarProgress ?? this.taskbarProgress,
      defaultSource: defaultSource ?? this.defaultSource,
      enabledSources: enabledSources ?? this.enabledSources,
      disabledFeatures: disabledFeatures ?? this.disabledFeatures,
    );
  }
}

class SettingsController extends Notifier<AppSettings> {
  static const _kQuality = 'settings.quality';
  static const _kSleep = 'settings.sleep';
  static const _kSleepCustom = 'settings.sleepCustom';
  static const _kWifiCover = 'settings.wifiCover';
  static const _kLyricTr = 'settings.lyricTranslation';
  static const _kLyricRo = 'settings.lyricRomanization';
  static const _kLyricFontScale = 'settings.lyricFontScale';
  static const _kLyricSpacingScale = 'settings.lyricSpacingScale';
  static const _kMediaLyric = 'settings.mediaLyricSubtitle';
  static const _kThemeMode = 'settings.themeMode';
  static const _kCloseBehavior = 'settings.closeBehavior';

  /// Legacy boolean key (`closeToTray`); read once for migration, then removed.
  static const _kCloseToTrayLegacy = 'settings.closeToTray';
  static const _kTaskbarProgress = 'settings.taskbarProgress';
  static const _kDefaultSource = 'settings.defaultSource';
  static const _kEnabledSources = 'settings.enabledSources';
  static const _kDisabledFeatures = 'settings.disabledFeatures';

  @override
  AppSettings build() {
    _restoreFuture = _restore();
    return const AppSettings();
  }

  Future<void>? _restoreFuture;

  /// Lets `main()` wait for persisted settings before the first frame, so the
  /// app never paints one theme and then flips to the saved one.
  Future<void> ensureRestored() async {
    await (_restoreFuture ??= _restore());
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final q = prefs.getString(_kQuality);
      final s = prefs.getString(_kSleep);
      final themeName = prefs.getString(_kThemeMode);
      state = AppSettings(
        quality: AppQuality.values.firstWhere(
          (e) => e.name == q,
          orElse: () => AppQuality.hq,
        ),
        sleepMode: SleepTimerMode.values.firstWhere(
          (e) => e.name == s,
          orElse: () => SleepTimerMode.off,
        ),
        sleepCustomMinutes: prefs.getInt(_kSleepCustom) ?? 45,
        wifiCoverOnly: prefs.getBool(_kWifiCover) ?? false,
        lyricTranslation: prefs.getBool(_kLyricTr) ?? true,
        lyricRomanization: prefs.getBool(_kLyricRo) ?? false,
        lyricFontScale: _readScale(
          prefs,
          _kLyricFontScale,
          kLyricFontScaleMin,
          kLyricFontScaleMax,
        ),
        lyricSpacingScale: _readScale(
          prefs,
          _kLyricSpacingScale,
          kLyricSpacingScaleMin,
          kLyricSpacingScaleMax,
        ),
        mediaLyricSubtitle: prefs.getBool(_kMediaLyric) ?? false,
        themeMode: AppThemeMode.values.firstWhere(
          (e) => e.name == themeName,
          orElse: () => AppThemeMode.light,
        ),
        closeBehavior: _readCloseBehavior(prefs),
        taskbarProgress: prefs.getBool(_kTaskbarProgress) ?? true,
        defaultSource: MusicPlatform.fromWire(
          prefs.getString(_kDefaultSource) ?? '',
        ),
        enabledSources: _readEnabledSources(prefs),
        disabledFeatures: _readDisabledFeatures(prefs),
      );
    } catch (_) {}
  }

  /// 读取整源开关。缺失 / 空列表（非法态）/ 全部未知 → 全集兜底。
  ///
  /// 不用 [MusicPlatform.fromWire]：它对未知值回退 kugou，会把脏数据
  /// 误读成「酷狗启用」，这里按 wireName 精确匹配后丢弃未知值。
  Set<MusicPlatform> _readEnabledSources(SharedPreferences prefs) {
    final raw = prefs.getStringList(_kEnabledSources);
    if (raw == null) return AppSettings().enabledSources;
    final parsed = MusicPlatform.values
        .where((p) => raw.contains(p.wireName))
        .toSet();
    return parsed.isEmpty ? AppSettings().enabledSources : parsed;
  }

  /// 读取「源 × 功能」子开关的**关闭**项。缺失（老数据）→ 空集 = 全开。
  ///
  /// 只认当前存在的 token：源或功能被移除后遗留的脏值会被丢弃，避免它
  /// 影响同名功能的判断。空列表是合法态（全部功能都关）。
  Set<String> _readDisabledFeatures(SharedPreferences prefs) {
    final raw = prefs.getStringList(_kDisabledFeatures);
    if (raw == null) return const {};
    final known = {
      for (final p in MusicPlatform.values)
        for (final f in SourceFeature.values) f.tokenFor(p),
    };
    return {for (final t in raw) if (known.contains(t)) t};
  }

  /// 读取倍率。缺失 / 非数字 / 越界（旧版本或脏数据）→ 回落 1.0（默认）。
  double _readScale(SharedPreferences prefs, String key, double min, double max) {
    final raw = double.tryParse(prefs.getString(key) ?? '');
    if (raw == null || raw < min || raw > max) return 1;
    return raw;
  }

  /// New key wins; otherwise migrate the old `closeToTray` boolean.
  /// Missing both → the new default「每次询问」.
  CloseBehavior _readCloseBehavior(SharedPreferences prefs) {
    final name = prefs.getString(_kCloseBehavior);
    if (name != null) {
      return CloseBehavior.values.firstWhere(
        (e) => e.name == name,
        orElse: () => CloseBehavior.ask,
      );
    }
    final legacy = prefs.getBool(_kCloseToTrayLegacy);
    if (legacy == null) return CloseBehavior.ask;
    return legacy ? CloseBehavior.tray : CloseBehavior.quit;
  }

  Future<void> setThemeMode(AppThemeMode mode) async {
    state = state.copyWith(themeMode: mode);
    await _save(_kThemeMode, mode.name);
  }

  Future<void> setQuality(AppQuality v) async {
    state = state.copyWith(quality: v);
    await _save(_kQuality, v.name);
  }

  Future<void> setSleep(SleepTimerMode mode, {int? customMinutes}) async {
    state = state.copyWith(
      sleepMode: mode,
      sleepCustomMinutes: customMinutes ?? state.sleepCustomMinutes,
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kSleep, mode.name);
    if (customMinutes != null) {
      await prefs.setInt(_kSleepCustom, customMinutes);
    }
  }

  Future<void> setWifiCoverOnly(bool v) async {
    state = state.copyWith(wifiCoverOnly: v);
    await _save(_kWifiCover, v);
  }

  Future<void> setLyricTranslation(bool v) async {
    state = state.copyWith(lyricTranslation: v);
    await _save(_kLyricTr, v);
  }

  Future<void> setLyricRomanization(bool v) async {
    state = state.copyWith(lyricRomanization: v);
    await _save(_kLyricRo, v);
  }

  /// 歌词字号倍率。拖动过程中传 `persist: false` 只改内存态做即时预览，
  /// 松手（`onChangeEnd`）再落盘，避免一次拖动写几十次 SharedPreferences。
  Future<void> setLyricFontScale(double v, {bool persist = true}) async {
    final next = _normalizeScale(v, kLyricFontScaleMin, kLyricFontScaleMax);
    if (next == state.lyricFontScale) return;
    state = state.copyWith(lyricFontScale: next);
    if (persist) await _save(_kLyricFontScale, next);
  }

  /// 歌词行间距倍率。`persist` 语义同 [setLyricFontScale]。
  Future<void> setLyricSpacingScale(double v, {bool persist = true}) async {
    final next = _normalizeScale(v, kLyricSpacingScaleMin, kLyricSpacingScaleMax);
    if (next == state.lyricSpacingScale) return;
    state = state.copyWith(lyricSpacingScale: next);
    if (persist) await _save(_kLyricSpacingScale, next);
  }

  /// 夹到合法区间并收敛到 0.01 精度（滑块取值连续，落盘前归一）。
  double _normalizeScale(double v, double min, double max) =>
      (v.clamp(min, max) * 100).roundToDouble() / 100;

  Future<void> setMediaLyricSubtitle(bool v) async {
    state = state.copyWith(mediaLyricSubtitle: v);
    await _save(_kMediaLyric, v);
  }

  Future<void> setCloseBehavior(CloseBehavior v) async {
    state = state.copyWith(closeBehavior: v);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kCloseBehavior, v.name);
      // Migration done — drop the stale boolean so it can't shadow the new key.
      await prefs.remove(_kCloseToTrayLegacy);
    } catch (_) {}
  }

  Future<void> setTaskbarProgress(bool v) async {
    state = state.copyWith(taskbarProgress: v);
    await _save(_kTaskbarProgress, v);
  }

  Future<void> setDefaultSource(MusicPlatform v) async {
    state = state.copyWith(defaultSource: v);
    await _save(_kDefaultSource, v.wireName);
  }

  /// 页面内「切音源」筛选条切换时调用：把**具体源**同步为全局默认源。
  ///
  /// 「全部」(`null`) 是混排视图、不代表任何一个源，**不写**——否则「全部」
  /// 会被曲解成「用默认源」。已等于当前默认源时也不需要落盘。
  ///
  /// 放在这里而不是 [SourceFilterBar] 内部：`shared/` 不反向依赖 `features/`，
  /// 由 9 处调用点的 `onSelect` 各自调用（口径见方案 §11 决策记录）。
  void syncDefaultSourceFromFilter(MusicPlatform? platform) {
    if (platform == null || platform == state.defaultSource) return;
    setDefaultSource(platform);
  }

  /// 整源开关。空集合直接拒绝（至少保留一个源，否则 App 没有可用音源）。
  ///
  /// 停用当前默认源时，默认源联动回退到第一个仍启用的源并落盘，
  /// 消费点（搜索页 / 我喜欢页初始筛选）无需各自处理该边界。
  Future<void> setEnabledSources(Set<MusicPlatform> v) async {
    if (v.isEmpty || v.length == state.enabledSources.length &&
            v.containsAll(state.enabledSources)) {
      return;
    }
    var next = state.copyWith(enabledSources: v);
    if (!v.contains(next.defaultSource)) {
      next = next.copyWith(defaultSource: next.effectiveDefaultSource);
    }
    state = next;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        _kEnabledSources,
        [for (final p in MusicPlatform.values) if (v.contains(p)) p.wireName],
      );
      // 默认源可能被联动修正，两个 key 要一起写。
      await prefs.setString(_kDefaultSource, state.defaultSource.wireName);
    } catch (_) {}
  }

  /// 「源 × 功能」子开关。与整源开关不同，**允许全关**（父开关关闭时子项
  /// 只是置灰、取值保留，重新开启父开关即恢复），所以这里不拒绝空集合。
  Future<void> setFeatureEnabled(
    MusicPlatform platform,
    SourceFeature feature,
    bool v,
  ) async {
    final token = feature.tokenFor(platform);
    final next = {...state.disabledFeatures};
    if (v) {
      if (!next.remove(token)) return;
    } else {
      if (!next.add(token)) return;
    }
    state = state.copyWith(disabledFeatures: next);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_kDisabledFeatures, next.toList()..sort());
    } catch (_) {}
  }

  /// Clear cover disk/memory cache + play history. Returns a status label.
  Future<String> clearImageAndHistoryCache() async {
    await CoverCache.instance.clear();
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    try {
      final store = await QueueStore.open();
      await store.clearAll();
    } catch (_) {}
    return '已清理图片缓存与播放历史';
  }

  Future<void> _save(String key, Object value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (value is bool) {
        await prefs.setBool(key, value);
      } else {
        await prefs.setString(key, '$value');
      }
    } catch (_) {}
  }
}

final settingsControllerProvider =
    NotifierProvider<SettingsController, AppSettings>(SettingsController.new);
