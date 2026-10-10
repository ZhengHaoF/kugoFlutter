import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kugo/data/storage/credential_store.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    CredentialStore.resetForTesting();
    FlutterSecureStorage.setMockInitialValues({});
  });
  await testMain();
}
