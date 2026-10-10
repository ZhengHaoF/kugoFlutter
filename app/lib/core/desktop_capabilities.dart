import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'platform.dart';

/// Capabilities are about the actual GDK backend, not just the login session.
/// A Wayland session can run this process through XWayland.
class DesktopCapabilities {
  const DesktopCapabilities({
    this.isLinux = false,
    this.backend = 'unknown',
    this.desktopLyrics = false,
    this.trayTooltip = false,
    this.absolutePosition = false,
    this.alwaysOnTop = false,
  });

  final bool isLinux;
  final String backend;
  final bool desktopLyrics;
  final bool trayTooltip;
  final bool absolutePosition;
  final bool alwaysOnTop;

  factory DesktopCapabilities.linux(String backend) => DesktopCapabilities(
    isLinux: true,
    backend: backend,
    absolutePosition: backend == 'x11',
    alwaysOnTop: backend == 'x11',
  );

  static DesktopCapabilities current = isLinuxPlatform
      ? DesktopCapabilities.linux('unknown')
      : DesktopCapabilities(
          desktopLyrics: isWindowsPlatform,
          trayTooltip: isDesktopPlatform,
          absolutePosition: isDesktopPlatform,
          alwaysOnTop: isDesktopPlatform,
        );

  static Future<void> initialize() async {
    if (!isLinuxPlatform) return;
    try {
      final backend = await const MethodChannel(
        'kugo/linux_desktop',
      ).invokeMethod<String>('getBackend').timeout(const Duration(seconds: 2));
      current = DesktopCapabilities.linux(backend ?? 'unknown');
    } catch (_) {
      // Conservative fallback: never promise positioning on an unknown backend.
      current = DesktopCapabilities.linux('unknown');
    }
  }
}

final desktopTrayAvailableProvider = StateProvider<bool>((ref) => false);

/// Safe startup policy: Linux must have a session bus, not a system bus.
bool get hasLinuxSessionBus =>
    isLinuxPlatform &&
    (Platform.environment['DBUS_SESSION_BUS_ADDRESS'] ?? '').isNotEmpty;
