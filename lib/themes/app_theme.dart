import 'package:flutter/material.dart';

/// Centralized theme builder using Material 3 and the app core colors.
class AppTheme {
  // Tema renkleri
  static const Color darkPrimaryColor = Color(0xFF304411); // Koyu modda
  static const Color lightPrimaryColor = Color(0xFF48631F); // Açık modda
  static const Color lightBackground = Color(0xFFF5F5F5); // Light mode bg
  static const Color lightSurface = Color(
    0xFFF4F4E8,
  ); // Card/containers (light)

  /// Bilgi (i) diyalogları: ThemeMode'dan bağımsız, her zaman açık yeşil + koyu yeşil metin.
  static const Color infoDialogBackground = Color(0xFFDCEDC8);
  static const Color infoDialogForeground = Color(0xFF304411);

  static ThemeData buildThemeData(ThemeMode mode) {
    final bool isDark = mode == ThemeMode.dark;
    final primaryColor = isDark ? darkPrimaryColor : lightPrimaryColor;

    final base = ThemeData(
      useMaterial3: true,
      fontFamily: 'PlayfairDisplay',
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryColor,
        brightness: isDark ? Brightness.dark : Brightness.light,
      ),
      scaffoldBackgroundColor: isDark ? Colors.black : lightBackground,
      visualDensity: VisualDensity.adaptivePlatformDensity,
    );

    final cardColor = isDark ? base.colorScheme.surface : lightSurface;

    return base.copyWith(
      textTheme: base.textTheme.copyWith(
        headlineLarge: base.textTheme.headlineLarge?.copyWith(
          fontWeight: FontWeight.w700,
          height: 1.2,
          letterSpacing: 0.2,
        ),
        headlineMedium: base.textTheme.headlineMedium?.copyWith(
          fontWeight: FontWeight.w700,
          height: 1.2,
          letterSpacing: 0.2,
        ),
        titleLarge: base.textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          height: 1.2,
          letterSpacing: 0.2,
        ),
        titleMedium: base.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
          height: 1.25,
          letterSpacing: 0.15,
        ),
        bodyLarge: base.textTheme.bodyLarge?.copyWith(
          height: 1.35,
          letterSpacing: 0.1,
        ),
        bodyMedium: base.textTheme.bodyMedium?.copyWith(
          height: 1.35,
          letterSpacing: 0.1,
        ),
        bodySmall: base.textTheme.bodySmall?.copyWith(
          height: 1.3,
          letterSpacing: 0.08,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: base.scaffoldBackgroundColor,
        elevation: 0,
        centerTitle: false,
        foregroundColor: Colors.white, // Her zaman beyaz text
        titleTextStyle: base.textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w600,
          color: Colors.white, // Başlık her zaman beyaz
        ),
      ),
      cardTheme: base.cardTheme.copyWith(
        elevation: 0,
        color: cardColor,
        surfaceTintColor: cardColor,
        margin: const EdgeInsets.all(8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: base.colorScheme.primary, width: 1.8),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
      ),
    );
  }
}
