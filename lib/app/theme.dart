/// Visual language (design §9): Material 3, `ColorScheme.fromSeed(0xff356859)`,
/// light + dark with `ThemeMode.system`, content columns `maxWidth: 640`,
/// primary buttons at least 56 dp tall.
library;

import 'package:flutter/material.dart';

/// Seed for both brightnesses (design §9).
const Color loadoutSeedColor = Color(0xff356859);

/// Content column width cap shared by every screen (design §9).
const double contentMaxWidth = 640;

/// Minimum size for primary action buttons (design §9: primary >= 56 dp).
const Size primaryButtonMinSize = Size.fromHeight(56);

ThemeData loadoutTheme(Brightness brightness) => ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(
    seedColor: loadoutSeedColor,
    brightness: brightness,
  ),
);
