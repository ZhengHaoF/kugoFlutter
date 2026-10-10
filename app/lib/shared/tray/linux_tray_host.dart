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
  bool _checking = false;
  bool _available = false;
  void Function(bool)? _onChanged;

  Future<void> start(void Function(bool) onChanged) async {
    _onChanged = onChanged;
    await refresh();
    _timer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => unawaited(refresh()),
    );
  }

  Future<bool> refresh() async {
    if (_closed) return false;
    if (_checking) return _available;
    _checking = true;
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
    } finally {
      _checking = false;
    }
    if (!_closed) {
      _available = available;
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
