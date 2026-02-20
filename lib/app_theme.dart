import 'package:flutter/material.dart';

class AppTheme {
  // Colors
  static const Color bg = Color(0xFF080C0E);
  static const Color surface = Color(0xFF0E1417);
  static const Color surface2 = Color(0xFF141C20);
  static const Color border = Color(0xFF1E2D32);
  static const Color green = Color(0xFF00E676);
  static const Color greenDim = Color(0xFF00C85A);
  static const Color amber = Color(0xFFFFAB00);
  static const Color red = Color(0xFFFF5252);
  static const Color blue = Color(0xFF40C4FF);
  static const Color textPrimary = Color(0xFFE8F0F2);
  static const Color textMuted = Color(0xFF5A7A84);
  static const Color textSecondary = Color(0xFF8AA8B0);

  static ThemeData get dark {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bg,
      colorScheme: const ColorScheme.dark(
        primary: green,
        secondary: blue,
        surface: surface,
        background: bg,
        error: red,
        onPrimary: bg,
        onSecondary: bg,
        onSurface: textPrimary,
        onBackground: textPrimary,
        onError: textPrimary,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: surface,
        foregroundColor: textPrimary,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: 'Syne',
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: textPrimary,
          letterSpacing: -0.5,
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
          side: const BorderSide(color: border),
        ),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface2,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(color: green, width: 1.5),
        ),
        labelStyle: const TextStyle(color: textMuted),
        hintStyle: const TextStyle(color: textMuted),
        prefixIconColor: textMuted,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: green,
          foregroundColor: bg,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 14,
            letterSpacing: 0.5,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: green,
          side: const BorderSide(color: green),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: green,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surface2,
        selectedColor: green.withOpacity(0.2),
        labelStyle: const TextStyle(color: textPrimary, fontSize: 13),
        side: const BorderSide(color: border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      ),
      dividerTheme: const DividerThemeData(color: border, thickness: 1),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: surface,
        selectedItemColor: green,
        unselectedItemColor: textMuted,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surface2,
        contentTextStyle: const TextStyle(color: textPrimary),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
          side: const BorderSide(color: border),
        ),
        behavior: SnackBarBehavior.floating,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
          side: const BorderSide(color: border),
        ),
        titleTextStyle: const TextStyle(
          color: textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
        contentTextStyle: const TextStyle(color: textSecondary, fontSize: 14),
      ),
      textTheme: const TextTheme(
        displayLarge: TextStyle(color: textPrimary, fontWeight: FontWeight.w800),
        displayMedium: TextStyle(color: textPrimary, fontWeight: FontWeight.w700),
        headlineLarge: TextStyle(color: textPrimary, fontWeight: FontWeight.w700, fontSize: 26),
        headlineMedium: TextStyle(color: textPrimary, fontWeight: FontWeight.w700, fontSize: 22),
        headlineSmall: TextStyle(color: textPrimary, fontWeight: FontWeight.w700, fontSize: 18),
        titleLarge: TextStyle(color: textPrimary, fontWeight: FontWeight.w600, fontSize: 16),
        titleMedium: TextStyle(color: textPrimary, fontWeight: FontWeight.w600, fontSize: 14),
        titleSmall: TextStyle(color: textSecondary, fontWeight: FontWeight.w500, fontSize: 13),
        bodyLarge: TextStyle(color: textPrimary, fontSize: 15),
        bodyMedium: TextStyle(color: textSecondary, fontSize: 14),
        bodySmall: TextStyle(color: textMuted, fontSize: 12),
        labelLarge: TextStyle(color: textPrimary, fontWeight: FontWeight.w600, fontSize: 13),
        labelSmall: TextStyle(color: textMuted, fontSize: 11, letterSpacing: 0.08),
      ),
    );
  }
}

// Status colors helper
extension TableStatusColor on String {
  Color get statusColor {
    switch (this) {
      case 'active': return AppTheme.green;
      case 'reserved': return AppTheme.amber;
      case 'open': return AppTheme.textMuted;
      case 'maintenance': return AppTheme.red;
      default: return AppTheme.textMuted;
    }
  }
}