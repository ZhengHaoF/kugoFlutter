// Quick unit checks for profile formatting helpers.
// Run: dart run tool/check_profile_stats.dart
import 'dart:io';

import '../lib/features/profile/profile_stats.dart';

void check(String name, Object? actual, Object? expected) {
  final ok = actual == expected;
  stdout.writeln('${ok ? 'OK' : 'FAIL'}  $name  actual=$actual  expected=$expected');
  if (!ok) failures++;
}

int failures = 0;

void main() {
  check('formatListeningDuration seconds', formatListeningDuration(42), '42 秒');
  check('formatListeningDuration mixed', formatListeningDuration(86400 + 7200 + 180), '1 天 2 小时 3 分钟');
  check('formatListeningDuration minutes fallback', formatListeningDuration(null, 90), '1 小时 30 分钟');
  check('formatAccountAge unknown', formatAccountAge(null), '未知');

  final p = getGradeProgress({
    'p_grade': 2,
    'p_current_point': 2294,
    'p_next_grade': 3,
    'p_next_grade_point': 3000,
  });
  check('grade label', p.gradeLabel, 'Lv.2');
  check('grade available', p.available, true);
  check('grade remaining', p.remaining, 706);

  check('gender 2', formatGender(2), '保密');
  final expire = formatVipExpireText(
    '2026-12-05 12:31:37',
    now: DateTime(2026, 9, 24),
  );
  check('vip expire text', expire, '2个月后到期');
  check('vip date', formatVipDate('2026-05-24 09:31:37'), '2026-05-24 09:31');

  if (failures > 0) {
    stdout.writeln('$failures failure(s)');
    throw StateError('$failures failure(s)');
  }
  stdout.writeln('all ok');
}
