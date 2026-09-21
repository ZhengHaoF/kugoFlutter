import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

/// Desktop (Windows / Linux / macOS) runtime detection.
///
/// Used to skip mobile-only subsystems and to branch layout later on.
bool get isDesktopPlatform =>
    !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

/// Whether the platform has an implementation for the system media session
/// (notification / lock screen / Bluetooth AVRCP).
///
/// `audio_session` and `audio_service` only ship Android, iOS, macOS and web
/// implementations. On Windows both are missing, and touching them throws
/// `MissingPluginException` — so the desktop build must skip them entirely
/// (`PlayerController`'s bridge is nullable by design).
bool get hasSystemMediaSession =>
    !kIsWeb && (Platform.isAndroid || Platform.isIOS || Platform.isMacOS);
