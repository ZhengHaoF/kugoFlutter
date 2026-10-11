import 'package:window_manager/window_manager.dart';

import 'app_logo.dart';

/// Windows only. window_manager expands this asset-relative path itself.
Future<void> applyWindowsWindowIcon() =>
    windowManager.setIcon(windowsAppIconAsset);
