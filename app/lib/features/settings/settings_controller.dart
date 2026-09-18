import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/cache/cover_cache.dart';
import '../../core/models/audio_quality.dart';
import '../../data/storage/queue_store.dart';

export '../../core/models/audio_quality.dart' show AppQuality, AppQualityX;

enum SleepTimerMode { off, m15, m30, m60, custom }

enum AppThemeMode { dark, light, system }

class AppSettings {
  const AppSettings({
    this.quality = AppQuality.hq,
    this.sleepMode = SleepTimerMode.off,
    this.sleepCustomMinutes = 45,
    this.wifiCoverOnly = false,
    this.lyricTranslation = true,
    this.themeMode = AppThemeMode.dark,
  });

  final AppQuality quality;
  final SleepTimerMode sleepMode;
  final int sleepCustomMinutes;
  final bool wifiCoverOnly;
  final bool lyricTranslation;
  final AppThemeMode themeMode;

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
    AppThemeMode? themeMode,
  }) {
    return AppSettings(
      quality: quality ?? this.quality,
      sleepMode: sleepMode ?? this.sleepMode,
      sleepCustomMinutes: sleepCustomMinutes ?? this.sleepCustomMinutes,
      wifiCoverOnly: wifiCoverOnly ?? this.wifiCoverOnly,
      lyricTranslation: lyricTranslation ?? this.lyricTranslation,
      themeMode: themeMode ?? this.themeMode,
    );
  }
}

class SettingsController extends Notifier<AppSettings> {
  static const _kQuality = 'settings.quality';
  static const _kSleep = 'settings.sleep';
  static const _kSleepCustom = 'settings.sleepCustom';
  static const _kWifiCover = 'settings.wifiCover';
  static const _kLyricTr = 'settings.lyricTranslation';
  static const _kThemeMode = 'settings.themeMode';

  @override
  AppSettings build() {
    unawaited(_restore());
    return const AppSettings();
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
        themeMode: AppThemeMode.values.firstWhere(
          (e) => e.name == themeName,
          orElse: () => AppThemeMode.dark,
        ),
      );
    } catch (_) {}
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
