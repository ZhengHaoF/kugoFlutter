import 'package:flutter_test/flutter_test.dart';
import 'package:kugo/features/profile/profile_stats.dart';
import 'package:kugo/features/profile/user_profile_detail.dart';

void main() {
  group('formatListeningDuration', () {
    test('seconds under a minute', () {
      expect(formatListeningDuration(42), '42 秒');
    });

    test('days/hours/minutes', () {
      // 1 天 2 小时 3 分钟
      expect(formatListeningDuration(86400 + 7200 + 180), '1 天 2 小时 3 分钟');
    });

    test('falls back to minutes field', () {
      expect(formatListeningDuration(null, 90), '1 小时 30 分钟');
    });
  });

  group('formatAccountAge', () {
    test('unknown without timestamp', () {
      expect(formatAccountAge(null), '未知');
      expect(formatAccountAge(0), '未知');
    });

    test('full months and leftover days', () {
      final start = DateTime.utc(2024, 1, 15);
      final now = DateTime.utc(2024, 4, 20);
      final ts = start.millisecondsSinceEpoch ~/ 1000;
      expect(
        formatAccountAge(ts, now: now),
        '3 个月 5 天',
      );
    });
  });

  group('getGradeProgress', () {
    test('computes remaining and percent', () {
      final p = getGradeProgress({
        'p_grade': 3,
        'p_current_point': 400,
        'p_next_grade': 4,
        'p_next_grade_point': 1000,
      });
      expect(p.available, isTrue);
      expect(p.gradeLabel, 'Lv.3');
      expect(p.remaining, 600);
      expect(p.percent, closeTo(40, 0.01));
    });

    test('missing fields stay unavailable', () {
      final p = getGradeProgress(const {});
      expect(p.available, isFalse);
      expect(p.gradeLabel, '—');
    });
  });

  group('formatGender / vip helpers', () {
    test('gender codes', () {
      expect(formatGender(0), '女');
      expect(formatGender(1), '男');
      expect(formatGender(2), '保密');
      expect(formatGender(null), '保密');
    });

    test('vip expire text', () {
      final now = DateTime(2026, 1, 1);
      expect(formatVipExpireText(null), isNull);
      expect(
        formatVipExpireText(
          now.add(const Duration(days: 400)).millisecondsSinceEpoch,
          now: now,
        ),
        '1年后到期',
      );
      expect(
        formatVipExpireText(
          now.subtract(const Duration(days: 1)).millisecondsSinceEpoch,
          now: now,
        ),
        '已过期',
      );
    });
  });

  group('UserProfileDetail', () {
    test('merge prefers fresher non-empty fields', () {
      const a = UserProfileDetail(signature: 'old', follows: 1, grade: 2);
      const b = UserProfileDetail(signature: 'new', fans: 3, grade: 4);
      final m = a.merge(b);
      expect(m.signature, 'new');
      expect(m.follows, 1);
      expect(m.fans, 3);
      expect(m.grade, 4);
    });

    test('json round-trip', () {
      const d = UserProfileDetail(
        gender: 1,
        follows: 2,
        tvipActive: true,
        tvipEnd: '2026-12-01',
      );
      expect(UserProfileDetail.fromJson(d.toJson()), d);
    });
  });
}
