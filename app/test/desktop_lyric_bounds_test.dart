import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kugo/features/desktop_lyric/desktop_lyric_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'preserves finite negative coordinates for left or upper monitors',
    () async {
      SharedPreferences.setMockInitialValues({
        'desktopLyric.bounds.x': -1200.0,
        'desktopLyric.bounds.y': -200.0,
        'desktopLyric.bounds.w': 720.0,
        'desktopLyric.bounds.h': 88.0,
      });
      final bounds = await DesktopLyricBoundsStore.load();
      expect(bounds.hasPosition, isTrue);
      expect(bounds.x, -1200);
      expect(bounds.y, -200);
    },
  );
}
