import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:kugo/data/storage/credential_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// CI-only entrypoint. This executable is never copied into the application
/// artifact. It uses an isolated test key, never real account credentials.
void main(List<String> args) {
  runZonedGuarded(
    () {
      WidgetsFlutterBinding.ensureInitialized();
      runApp(const MaterialApp(home: Text('Native credential probe')));
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final reportArg = args.where((a) => a.startsWith('--probe-report='));
        if (reportArg.isEmpty) exit(64);
        final report = File(
          reportArg.first.substring('--probe-report='.length),
        );
        final checks = <String>[];
        const key = 'ci.native.credential.probe.v1';
        try {
          final prefs = await SharedPreferences.getInstance();
          await CredentialStore.clear(key);
          await prefs.remove('$key.secure.blocked.v1');
          await prefs.setString(key, 'synthetic-migration-fixture');
          if (await CredentialStore.read(key) !=
              'synthetic-migration-fixture') {
            throw StateError('Native migration failed');
          }
          checks.add('PASS native legacy migration/read-back');
          if (prefs.containsKey(key)) throw StateError('Plaintext survived');
          checks.add('PASS legacy plaintext removed');
          await CredentialStore.write(key, 'synthetic-new-session');
          if (await CredentialStore.read(key) != 'synthetic-new-session') {
            throw StateError('Native write/read failed');
          }
          checks.add('PASS native replacement write/read');
          await CredentialStore.clear(key);
          if (await CredentialStore.read(key) != null) {
            throw StateError('Logged-out value restored');
          }
          checks.add('PASS logout blocks restore');
          // Removing the tombstone allows checking that the native delete also
          // succeeded, rather than merely testing the logical logout guard.
          await prefs.remove('$key.secure.blocked.v1');
          if (await CredentialStore.read(key) != null) {
            throw StateError('Native delete failed');
          }
          checks.add('PASS native secure delete');
          await report.writeAsString('${checks.join('\n')}\n', flush: true);
          exit(0);
        } catch (error) {
          await report.writeAsString(
            '${checks.join('\n')}\nFAIL ${error.runtimeType}\n',
            flush: true,
          );
          exit(1);
        }
      });
    },
    (error, stack) {
      stderr.writeln('Native credential probe: ${error.runtimeType}');
      exit(1);
    },
  );
}
