import 'package:flutter_test/flutter_test.dart';
import 'package:kugo/shared/taskbar/taskbar_bridge.dart';

void main() {
  group('taskbarModeFor', () {
    test('no track is none', () {
      expect(
        taskbarModeFor(hasTrack: false, isPlaying: true, durationMs: 180000),
        TaskbarProgressMode.none,
      );
    });

    test('unknown duration while playing is indeterminate', () {
      expect(
        taskbarModeFor(hasTrack: true, isPlaying: true, durationMs: 0),
        TaskbarProgressMode.indeterminate,
      );
    });

    test('playing with duration is normal', () {
      expect(
        taskbarModeFor(hasTrack: true, isPlaying: true, durationMs: 180000),
        TaskbarProgressMode.normal,
      );
    });

    test('paused with duration is paused', () {
      expect(
        taskbarModeFor(hasTrack: true, isPlaying: false, durationMs: 180000),
        TaskbarProgressMode.paused,
      );
    });
  });

  group('TaskbarProgressModeWire', () {
    test('wire names match native ParseProgressMode', () {
      expect(TaskbarProgressMode.none.wireName, 'none');
      expect(TaskbarProgressMode.normal.wireName, 'normal');
      expect(TaskbarProgressMode.paused.wireName, 'paused');
      expect(TaskbarProgressMode.indeterminate.wireName, 'indeterminate');
    });
  });
}
