import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/network_log.dart';

class NetworkLogNotifier extends Notifier<List<NetworkLog>> {
  @override
  List<NetworkLog> build() => const [];

  void addLog(NetworkLog log) {
    state = [log, ...state].take(100).toList();
  }

  void addAll(Iterable<NetworkLog> logs) {
    if (logs.isEmpty) return;
    state = [...logs.toList().reversed, ...state].take(100).toList();
  }

  void clearLogs() {
    state = const [];
  }
}

final networkLogProvider =
    NotifierProvider<NetworkLogNotifier, List<NetworkLog>>(
  NetworkLogNotifier.new,
);
