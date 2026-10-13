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
    final triggerNames = RegExp(
      r'^  ([a-z_]+):',
      multiLine: true,
    ).allMatches(events!.group(1)!).map((match) => match.group(1));
    expect(triggerNames, ['workflow_dispatch']);
    expect(events.group(1), contains('      version:\n'));
    expect(events.group(1), contains('      publish:\n'));
    expect(events.group(1), contains('        default: false\n'));
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

  test('Android Release builds all supported ABIs without debug signing', () {
    expect(
      workflow,
      contains("ORG_GRADLE_PROJECT_overtoneAllowTestSigning: 'false'"),
    );
    expect(workflow, contains('--split-per-abi'));
    expect(
      workflow,
      contains('--target-platform android-arm,android-arm64,android-x64'),
    );
    for (final secret in [
      'ANDROID_KEYSTORE_BASE64',
      'ANDROID_KEYSTORE_PASSWORD',
      'ANDROID_KEY_ALIAS',
      'ANDROID_KEY_PASSWORD',
    ]) {
      expect(workflow, contains('secrets.$secret'));
    }
    for (final compatibleSecret in [
      'KEYSTORE_B64',
      'KEYSTORE_PASSWORD',
      'KEY_ALIAS',
      'KEY_PASSWORD',
    ]) {
      expect(workflow, contains('secrets.$compatibleSecret'));
    }
    expect(workflow, contains('bash tool/package_android_release.sh'));
    expect(workflow, isNot(contains('overtone-android-test-only-')));
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    expect(gradle, contains('!hasReleaseSigning && !allowTestSigning'));
    expect(gradle, contains('releaseSigning.values.all'));
  });

  test(
    'Windows installer consumes saved Release bundle, never probe or Debug',
    () {
      expect(workflow, contains('tool\\windows_installer.iss'));
      expect(workflow, contains('build\\deliverables\\windows\\portable'));
      expect(workflow, contains('./tool/test_windows_installer.ps1'));
      final installer = File('tool/windows_installer.iss').readAsStringSync();
      expect(installer, contains('PrivilegesRequired=lowest'));
      expect(installer, contains('ArchitecturesAllowed=x64compatible'));
      expect(installer, contains('recursesubdirs createallsubdirs'));
      expect(installer, isNot(contains('runner\\Debug')));
      expect(installer, isNot(contains('native_credential_probe')));
      final identity = File(
        'windows/runner/app_identity.cpp',
      ).readAsStringSync();
      final aumid = RegExp(
        r'kAppUserModelId\[\] = L"([^"]+)"',
      ).firstMatch(identity)!.group(1);
      expect(
        RegExp(
          r'AppUserModelID: "([^"]+)"',
        ).allMatches(installer).map((match) => match.group(1)),
        [aumid, aumid],
      );
      expect(installer, contains(r'IconFilename: "{app}\data\flutter_assets'));
      final probe = File('tool/test_windows_installer.ps1').readAsStringSync();
      expect(probe, contains('Remove-OvertoneProbeDirectory'));
      expect(probe, contains('Write-Error -ErrorRecord'));
      final iconProbe = File(
        'tool/test_windows_app_icons.ps1',
      ).readAsStringSync();
      expect(iconProbe, contains('Stop-OvertoneProbeProcess'));
    },
  );

  test(
    'Official publication is a separate explicit opt-in with no overwrite',
    () {
      expect(workflow, contains('        if: inputs.publish\n'));
      expect(
        workflow,
        contains('--draft=false --prerelease=false --latest=true'),
      );
      expect(
        workflow,
        contains('Version already published. Use a new version'),
      );
      expect(workflow, contains('bash app/tool/package_release.sh'));
      expect(workflow, isNot(contains('tag="test-')));
    },
  );
}
