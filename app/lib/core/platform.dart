import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

/// Desktop (Windows / Linux / macOS) runtime detection.
///
/// Used to skip mobile-only subsystems and to branch layout later on.
bool get isDesktopPlatform =>
    !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

/// Windows-only desktop shell extras (taskbar Thumbar / progress).
bool get isWindowsPlatform => !kIsWeb && Platform.isWindows;

bool get isLinuxPlatform => !kIsWeb && Platform.isLinux;

/// The native lyric host is currently implemented only by the Windows runner.
/// Linux overlays are intentionally outside P0/P1.
bool get supportsDesktopLyrics => isWindowsPlatform;

/// Android runtime detection — mobile-only integrations (PiP 等).
bool get isAndroidPlatform => !kIsWeb && Platform.isAndroid;

/// Whether the platform has an implementation for the system media session
/// (notification / lock screen / Bluetooth AVRCP / Windows SMTC).
///
/// Mobile & macOS use `audio_service` natively; Windows uses the
/// `audio_service_win` federated implementation. This gate is for audio_service
/// initialization only; Linux uses our session D-Bus bridge separately.
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
