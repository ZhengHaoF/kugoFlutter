import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 搜索历史最多保留的条数（去重置顶后再截断）。
const kMaxSearchHistory = 20;

/// 本地搜索历史（关键词，最近搜索在前）。
///
/// 只存关键词字符串，很轻，不参与启动关键路径。存储沿用 likes / fm 的
/// SharedPreferences 单 key JSON 方式：零 schema 迁移，`setMockInitialValues`
/// 即可测。以后若需要按频次/时间排序或跨端同步，再迁到 Drift。
class SearchHistoryNotifier extends Notifier<List<String>> {
  static const _kKey = 'search.history.v1';
  SharedPreferences? _prefs;

  @override
  List<String> build() {
    unawaitedLoad();
    return const [];
  }

  Future<void> unawaitedLoad() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      final raw = _prefs?.getString(_kKey);
      if (raw == null || raw.isEmpty) return;
      final list = (jsonDecode(raw) as List)
          .whereType<String>()
          .where((e) => e.trim().isNotEmpty)
          .toList();
      if (list.isNotEmpty) state = list;
    } catch (_) {}
  }

  /// 记录一次搜索：去重（已存在则置顶）、去首尾空白、截断到 [kMaxSearchHistory]。
  ///
  /// 提交即记录，不依赖搜索结果成败——断网/搜不到也应留下，方便复用。
  Future<void> record(String keyword) async {
    final kw = keyword.trim();
    if (kw.isEmpty) return;
    final next = <String>[kw, ...state.where((e) => e != kw)];
    state = next.length > kMaxSearchHistory
        ? next.sublist(0, kMaxSearchHistory)
        : next;
    await _persist();
  }

  /// 删除单条历史。
  Future<void> remove(String keyword) async {
    if (!state.contains(keyword)) return;
    state = state.where((e) => e != keyword).toList();
    await _persist();
  }

  /// 清空全部历史。
  Future<void> clear() async {
    if (state.isEmpty) return;
    state = const [];
    await _persist();
  }

  Future<void> _persist() async {
    try {
      _prefs ??= await SharedPreferences.getInstance();
      await _prefs?.setString(_kKey, jsonEncode(state));
    } catch (_) {}
  }
}

final searchHistoryProvider =
    NotifierProvider<SearchHistoryNotifier, List<String>>(
  SearchHistoryNotifier.new,
);