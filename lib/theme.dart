import 'package:flutter/material.dart';

/// Colours taken from imigongo art: red earth and deep ink, with Rwanda's sky blue as a second accent.
class Palette {
  static const earth = Color(0xFF8C3A22);
  static const earthDark = Color(0xFFE08A6C);
  static const sky = Color(0xFF2A6F97);
  static const skyDark = Color(0xFF79B3D6);
}

/// The conversation is centred in a column this wide on large screens.
const conversationMaxWidth = 720.0;

ThemeData buildTheme(Brightness brightness) {
  final light = brightness == Brightness.light;
  final scheme = ColorScheme.fromSeed(
    seedColor: Palette.earth,
    brightness: brightness,
    primary: light ? Palette.earth : Palette.earthDark,
    secondary: light ? Palette.sky : Palette.skyDark,
  );
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    ),
  );
}
