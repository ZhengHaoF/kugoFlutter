import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kugo/features/auth/auth_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  test('login does not invent local session when gateway fails', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final auth = container.read(authControllerProvider.notifier);

    final ok = await auth.loginWithSms(phone: '13800138000', code: '1234');
    final state = container.read(authControllerProvider);
    // Gateway likely unreachable in CI / filtered network → must fail cleanly.
    if (!ok) {
      expect(state.isLogged, isFalse);
      expect(state.user?.isLocalDemo ?? false, isFalse);
      expect(state.errorMessage, isNotEmpty);
    } else {
      expect(state.isLogged, isTrue);
      expect(state.user?.isLocalDemo, isFalse);
    }
  });

  test('invalid phone rejects without network', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final auth = container.read(authControllerProvider.notifier);
    await auth.sendSmsCode('123');
    expect(container.read(authControllerProvider).errorMessage, isNotEmpty);
  });

  test('guest continue clears session', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final auth = container.read(authControllerProvider.notifier);
    await auth.continueAsGuest();
    final s = container.read(authControllerProvider);
    expect(s.isLogged, isFalse);
    expect(s.isGuest, isTrue);
  });

  test('logout returns to guest', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final auth = container.read(authControllerProvider.notifier);
    await auth.logout();
    expect(container.read(authControllerProvider).isLogged, isFalse);
  });
}
