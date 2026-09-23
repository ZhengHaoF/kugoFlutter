import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

/// Desktop (Windows / Linux / macOS) runtime detection.
///
/// Used to skip mobile-only subsystems and to branch layout later on.
bool get isDesktopPlatform =>
    !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

/// Windows-only desktop shell extras (taskbar Thumbar / progress).
bool get isWindowsPlatform => !kIsWeb && Platform.isWindows;

/// Whether the platform has an implementation for the system media session
/// (notification / lock screen / Bluetooth AVRCP / Windows SMTC).
///
/// Mobile & macOS use `audio_service` natively; Windows uses the
/// `audio_service_win` federated implementation. Linux has neither here —
/// leave it off rather than throw `MissingPluginException`.
///
/// [PlayerController]'s bridge is nullable by design: platforms without a
/// session simply never call `attachBridge`.
bool get hasSystemMediaSession =>
    !kIsWeb &&
    (Platform.isAndroid ||
        Platform.isIOS ||
        Platform.isMacOS ||
        Platform.isWindows);

/// Whether `audio_session` (audio focus / ducking / interruption) is available.
///
/// Still Android / iOS / macOS only — `audio_service_win` covers media-session
/// UI but does not implement audio focus. Calling `AudioSession.instance` on
/// Windows throws `MissingPluginException`.
bool get hasAudioFocusSession =>
    !kIsWeb && (Platform.isAndroid || Platform.isIOS || Platform.isMacOS);
