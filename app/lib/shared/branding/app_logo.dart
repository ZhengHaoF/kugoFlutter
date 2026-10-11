import 'package:flutter/material.dart';

const appLogoAsset = 'assets/app_icon.png';
const windowsAppIconAsset = 'assets/app_icon.ico';

/// Shared, approved G artwork. Do not substitute a generic music-note glyph.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 34});

  final double size;

  @override
  Widget build(BuildContext context) => Image.asset(
    appLogoAsset,
    width: size,
    height: size,
    fit: BoxFit.contain,
    semanticLabel: 'kugo',
    filterQuality: FilterQuality.medium,
  );
}
