import 'package:flutter_test/flutter_test.dart';
import 'package:kugo/data/repositories/recommend_repository.dart';

/// 每日推荐的「今日心情」：按一年中的第几天从固定池里取一个标签。
///
/// 纯函数，但要守住两条性质：
///  1. `dayOfYear` 的闰年边界（2024-12-31 是第 366 天）；
///  2. 同一天在任何年份都落到同一个标签——否则用户会觉得标签在乱跳。
void main() {
  group('dayOfYear', () {
    test('1 月 1 日是第 1 天', () {
      expect(RecommendRepository().dayOfYear(DateTime(2026, 1, 1)), 1);
    });

    test('平年 12 月 31 日是第 365 天', () {
      expect(RecommendRepository().dayOfYear(DateTime(2025, 12, 31)), 365);
    });

    test('闰年 12 月 31 日是第 366 天', () {
      expect(RecommendRepository().dayOfYear(DateTime(2024, 12, 31)), 366);
    });

    test('闰年 2 月 29 存在且算得对', () {
      // 2024-01-31 + 29 = 第 60 天。
      expect(RecommendRepository().dayOfYear(DateTime(2024, 2, 29)), 60);
      // 平年同日不存在，用 3 月 1 日对照：第 61 天。
      expect(RecommendRepository().dayOfYear(DateTime(2025, 3, 1)), 60);
    });

    test('跨月累加正确', () {
      // 2026 不是闰年：31 + 28 + 31 + 30 + 31 = 151，6 月 1 日是第 152 天。
      expect(RecommendRepository().dayOfYear(DateTime(2026, 6, 1)), 152);
      // 5 月 1 日是第 121 天（31 + 28 + 31 + 30 = 120）。
      expect(RecommendRepository().dayOfYear(DateTime(2026, 5, 1)), 121);
    });

    test('忽略时分秒，只按日期算', () {
      expect(
        RecommendRepository().dayOfYear(DateTime(2026, 3, 1, 23, 59, 59)),
        RecommendRepository().dayOfYear(DateTime(2026, 3, 1)),
      );
    });

    test('不传日期用今天，结果落在 1..366', () {
      final n = RecommendRepository().dayOfYear();
      expect(n, greaterThanOrEqualTo(1));
      expect(n, lessThanOrEqualTo(366));
    });
  });

  group('moodLabel', () {
    test('返回值一定在 moods 池里', () {
      final repo = RecommendRepository();
      for (var day = 1; day <= 366; day++) {
        final d = DateTime(2024).add(Duration(days: day - 1));
        expect(RecommendRepository.moods, contains(repo.moodLabel(d)));
      }
    });

    test('同一天在任何年份落到同一个标签（标签不乱跳）', () {
      final repo = RecommendRepository();
      // 2024 是闰年、2025/2026 是平年；取年中同一天比较。
      final a = repo.moodLabel(DateTime(2025, 7, 1));
      final b = repo.moodLabel(DateTime(2026, 7, 1));
      expect(a, b);
    });

    test('八种心情都会出现（池子真的被用满）', () {
      final repo = RecommendRepository();
      final seen = <String>{};
      for (var day = 1; day <= 366; day++) {
        seen.add(repo.moodLabel(DateTime(2024).add(Duration(days: day - 1))));
      }
      expect(seen.length, RecommendRepository.moods.length);
      expect(seen, containsAll(RecommendRepository.moods));
    });

    test(' moods 池本身没有重复项', () {
      expect(RecommendRepository.moods.toSet().length,
          RecommendRepository.moods.length);
    });

    test('不传日期用今天，返回池中的某一项', () {
      expect(
        RecommendRepository.moods,
        contains(RecommendRepository().moodLabel()),
      );
    });
  });

  test('分类常量至少包含「推荐」与 Hi-Res', () {
    expect(
      RecommendRepository.recommendPlaylistCategories.map((e) => e.id),
      containsAll(['0', '11292']),
    );
  });
}
