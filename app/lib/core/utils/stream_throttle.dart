import 'dart:async';

/// Coalesces a high-frequency stream into at most one event per [interval].
///
/// Why not `Stream.debounce`: debounce only fires after the source goes quiet,
/// so a continuous position stream (libmpv reports on its own clock, roughly
/// once per frame) would *never* emit and the progress bar would freeze.
///
/// This operator instead uses a leading-edge window:
/// * the first sample after an idle gap is delivered immediately, so seek and
///   track-start stay snappy;
/// * samples arriving inside the window are collapsed to the newest value,
///   which is flushed when the window closes.
///
/// Ordering and completeness are preserved: only the newest value survives a
/// window, and it is always flushed, so a cursor built on this stream never
/// stalls short of the real playback position.
Stream<T> throttleStream<T>(Stream<T> source, Duration interval) {
  final controller = StreamController<T>.broadcast();
  StreamSubscription<T>? sub;
  Timer? timer;
  T? pending;
  var hasPending = false;
  // Far enough in the past that the very first sample takes the leading edge.
  var lastEmit = DateTime.fromMillisecondsSinceEpoch(0);

  void flush() {
    timer?.cancel();
    timer = null;
    if (!hasPending) return;
    final value = pending as T;
    hasPending = false;
    pending = null;
    lastEmit = DateTime.now();
    if (controller.isClosed) return;
    controller.add(value);
  }

  void onData(T value) {
    final elapsed = DateTime.now().difference(lastEmit);
    if (elapsed >= interval) {
      // Leading edge — deliver now and open a fresh window.
      timer?.cancel();
      timer = null;
      hasPending = false;
      pending = null;
      lastEmit = DateTime.now();
      if (!controller.isClosed) controller.add(value);
      return;
    }
    pending = value;
    hasPending = true;
    timer ??= Timer(interval - elapsed, flush);
  }

  controller.onListen = () {
    sub = source.listen(
      onData,
      onError: controller.addError,
      onDone: () {
        flush();
        if (!controller.isClosed) controller.close();
      },
    );
  };
  controller.onCancel = () async {
    timer?.cancel();
    timer = null;
    hasPending = false;
    pending = null;
    final s = sub;
    sub = null;
    await s?.cancel();
  };

  return controller.stream;
}
