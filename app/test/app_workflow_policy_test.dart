import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final workflow = File('../.github/workflows/apps.yml').readAsStringSync();
  const guard =
      "github.repository == 'ZhengHaoF/kugoFlutter' && "
      "github.ref == 'refs/heads/main' && "
      "github.event_name == 'workflow_dispatch'";

  test('App workflow exposes only a manual trigger', () {
    final events = RegExp(
      r'^on:\n([\s\S]*?)^permissions:',
      multiLine: true,
    ).firstMatch(workflow);
    expect(events, isNotNull);
    expect(events!.group(1)!.trim(), 'workflow_dispatch:');
  });

  test('Every job is guarded by repository, main branch and manual event', () {
    final jobs = RegExp(
      r'^  ([a-z][a-z0-9-]*):\n([\s\S]*?)(?=^  [a-z][a-z0-9-]*:\n|(?![\s\S]))',
      multiLine: true,
    ).allMatches(workflow.substring(workflow.indexOf('\njobs:\n') + 7));
    expect(jobs.map((job) => job.group(1)), [
      'quality',
      'android',
      'windows-media-native',
      'windows',
      'release',
    ]);
    for (final job in jobs) {
      expect(
        job.group(2),
        contains('    if: $guard\n'),
        reason: '${job.group(1)} must never build automatically or off main',
      );
    }
  });

  test(
    'Platform and release jobs still depend on successful quality gates',
    () {
      expect(workflow, contains('  android:\n    needs: quality\n'));
      expect(
        workflow,
        contains('  windows:\n    needs: [quality, windows-media-native]\n'),
      );
      expect(workflow, contains('  release:\n    needs: [android, windows]\n'));
    },
  );

  test('No other app workflows reintroduce automatic builds', () {
    final files = Directory('../.github/workflows')
        .listSync()
        .whereType<File>()
        .where((file) => RegExp(r'\.ya?ml$').hasMatch(file.path))
        .map((file) => file.uri.pathSegments.last)
        .toList();
    expect(files, ['apps.yml']);
  });
}
