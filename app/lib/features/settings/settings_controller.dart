import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/cache/cover_cache.dart';
import '../../core/models/audio_quality.dart';
import '../../core/source/music_platform.dart';
import '../../data/storage/queue_store.dart';

export '../../core/models/audio_quality.dart' show AppQuality, AppQualityX;

enum SleepTimerMode { off, m15, m30, m60, custom }

enum AppThemeMode { dark, light, system }

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
    this.mediaLyricSubtitle = false,
    this.themeMode = AppThemeMode.light,
    this.closeBehavior = CloseBehavior.ask,
    this.taskbarProgress = true,
    this.defaultSource = MusicPlatform.kugou,
    this.enabledSources = const {
      MusicPlatform.kugou,
      MusicPlatform.netease,
    },
  });

  final AppQuality quality;
  final SleepTimerMode sleepMode;
  final int sleepCustomMinutes;
  final bool wifiCoverOnly;

  /// 歌词副行：译文（KRC `[language:]` type=1）。
  final bool lyricTranslation;

  /// 歌词副行：音译/罗马音（type=0）。默认关，中文歌收益低。
  final bool lyricRomanization;

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
    bool? mediaLyricSubtitle,
    AppThemeMode? themeMode,
    CloseBehavior? closeBehavior,
    bool? taskbarProgress,
    MusicPlatform? defaultSource,
    Set<MusicPlatform>? enabledSources,
  }) {
    return AppSettings(
      quality: quality ?? this.quality,
      sleepMode: sleepMode ?? this.sleepMode,
      sleepCustomMinutes: sleepCustomMinutes ?? this.sleepCustomMinutes,
      wifiCoverOnly: wifiCoverOnly ?? this.wifiCoverOnly,
      lyricTranslation: lyricTranslation ?? this.lyricTranslation,
      lyricRomanization: lyricRomanization ?? this.lyricRomanization,
      mediaLyricSubtitle: mediaLyricSubtitle ?? this.mediaLyricSubtitle,
      themeMode: themeMode ?? this.themeMode,
      closeBehavior: closeBehavior ?? this.closeBehavior,
      taskbarProgress: taskbarProgress ?? this.taskbarProgress,
      defaultSource: defaultSource ?? this.defaultSource,
      enabledSources: enabledSources ?? this.enabledSources,
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
  static const _kMediaLyric = 'settings.mediaLyricSubtitle';
  static const _kThemeMode = 'settings.themeMode';
  static const _kCloseBehavior = 'settings.closeBehavior';

  /// Legacy boolean key (`closeToTray`); read once for migration, then removed.
  static const _kCloseToTrayLegacy = 'settings.closeToTray';
  static const _kTaskbarProgress = 'settings.taskbarProgress';
  static const _kDefaultSource = 'settings.defaultSource';
  static const _kEnabledSources = 'settings.enabledSources';

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
