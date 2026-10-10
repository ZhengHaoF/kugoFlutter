import 'dart:async';

import 'package:dbus/dbus.dart';

/// A watcher name alone does not prove a panel is displaying our icon.
/// Probe the host property and recheck on close and while the app is running.
class LinuxTrayHostMonitor {
  LinuxTrayHostMonitor({DBusClient? client})
    : _client = client ?? DBusClient.session();

  final DBusClient _client;
  Timer? _timer;
  bool _closed = false;
  Future<bool>? _pending;
  void Function(bool)? _onChanged;

  Future<void> start(void Function(bool) onChanged) async {
    _onChanged = onChanged;
    await refresh();
    _timer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => unawaited(refresh()),
    );
  }

  Future<bool> refresh() {
    if (_closed) return Future.value(false);
    // A close event must await a running check, not reuse a stale "host exists".
    return _pending ??= _refresh().whenComplete(() => _pending = null);
  }

  Future<bool> _refresh() async {
    var available = false;
    try {
      final watcher = DBusRemoteObject(
        _client,
        name: 'org.kde.StatusNotifierWatcher',
        path: DBusObjectPath('/StatusNotifierWatcher'),
      );
      final value = await watcher
          .getProperty(
            'org.kde.StatusNotifierWatcher',
            'IsStatusNotifierHostRegistered',
            signature: DBusSignature('b'),
          )
          .timeout(const Duration(seconds: 1));
      available = value.asBoolean();
    } catch (_) {
      // No watcher, no host, disconnected bus or denied policy: no safe tray.
    }
    if (!_closed) {
      _onChanged?.call(available);
    }
    return !_closed && available;
  }

  Future<void> close() async {
    _closed = true;
    _timer?.cancel();
    await _client.close();
  }
}
