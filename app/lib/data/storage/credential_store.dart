import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// All credential operations are ordered per source. There is deliberately no
/// plaintext fallback when the OS vault is locked, unavailable or corrupted.
abstract final class CredentialStore {
  static const _vault = FlutterSecureStorage(
    aOptions: AndroidOptions(migrateWithBackup: true, resetOnError: false),
  );
  static final Map<String, Future<void>> _tails = {};
  static final Map<String, int> _revisions = {};

  @visibleForTesting
  static void resetForTesting() {
    _tails.clear();
    _revisions.clear();
  }

  static int revision(String key) => _revisions[key] ?? 0;

  /// Invalidates only a pending restore, without deleting the saved login.
  static void invalidateRestore(String key) {
    _revisions[key] = revision(key) + 1;
  }

  static String _blocked(String key) => '$key.secure.blocked.v1';
  static String _secureKey(String key) => 'kugo.credentials.$key';

  static Future<T> _ordered<T>(String key, Future<T> Function() action) {
    final next = (_tails[key] ?? Future<void>.value()).then((_) => action());
    final tail = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    _tails[key] = tail;
    unawaited(
      tail.then((_) {
        if (identical(_tails[key], tail)) _tails.remove(key);
      }),
    );
    return next;
  }

  /// Import legacy records only after a verified secure write. A failed import
  /// leaves the legacy record intact, but never authenticates from plaintext.
  static Future<String?> read(String key) => _ordered(key, () async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_blocked(key)) == true) return null;
    final value = await _vault.read(key: _secureKey(key));
    if (value != null) {
      if (!await prefs.remove(key)) {
        throw StateError('Legacy credential cleanup failed');
      }
      return value;
    }
    final legacy = prefs.getString(key);
    if (legacy == null || legacy.isEmpty) return null;
    await _vault.write(key: _secureKey(key), value: legacy);
    if (await _vault.read(key: _secureKey(key)) != legacy) {
      throw StateError('Credential migration verification failed');
    }
    if (!await prefs.remove(key)) {
      throw StateError('Legacy credential cleanup failed');
    }
    return legacy;
  });

  static Future<void> write(String key, String value) {
    _revisions[key] = revision(key) + 1;
    final revisionAtStart = revision(key);
    return _ordered(key, () async {
      final prefs = await SharedPreferences.getInstance();
      // Prevent resurrection of an older account after a failed replacement.
      if (!await prefs.setBool(_blocked(key), true)) {
        throw StateError('Credential persistence guard failed');
      }
      await _vault.write(key: _secureKey(key), value: value);
      if (await _vault.read(key: _secureKey(key)) != value) {
        throw StateError('Credential write verification failed');
      }
      if (!await prefs.remove(key)) {
        throw StateError('Credential cleanup failed');
      }
      if (revisionAtStart == revision(key) &&
          !await prefs.remove(_blocked(key))) {
        throw StateError('Credential cleanup failed');
      }
    });
  }

  static Future<void> clear(String key) {
    _revisions[key] = revision(key) + 1;
    // The tombstone must not wait behind a stalled native save.
    final guard = () async {
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs.setBool(_blocked(key), true)) {
        throw StateError('Credential logout guard failed');
      }
      if (!await prefs.remove(key)) {
        throw StateError('Legacy credential cleanup failed');
      }
    }();
    // Attach the rejection handler immediately, even if the queue is stalled.
    final guarded = guard.then<Object?>((_) => null, onError: (Object e) => e);
    return _ordered(key, () async {
      final error = await guarded;
      if (error != null) throw error;
      await _vault.delete(key: _secureKey(key));
      // Keep the guard until a later successful login explicitly replaces it.
    });
  }
}
