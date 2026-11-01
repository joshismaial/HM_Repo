import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Colours: "Trust blue" (22 Oct 2026): solid #1560BD everywhere (no gradient), grey ground,
/// white cards with a thin #DCE3EC border + very light shadow.
/// Text: one font (Plus Jakarta Sans), 6 sizes (24 · 20 · 16 · 14 · 12.5 · 11, nothing smaller than 11),
/// 3 weights (400 / 600 / 800), 4 corner sizes (8 chips · 12 buttons/inputs · 16 cards · round pills).
class AppColors {
  static const primary = Color(0xFF1560BD);
  static const primaryDark = Color(0xFF0C447C);
  static const primarySoft = Color(0xFFE8F0FA);
  static const primaryTint = Color(0xFFE8F0FA);
  static const primaryLine = Color(0xFFB9CDEB);
  static const onBlueMuted = Color(0xFFD6ECFC);
  static const ground = Color(0xFFF2F5F9);
  static const card = Colors.white;
  static const ink = Color(0xFF14213D);
  static const muted = Color(0xFF5C6782);
  static const line = Color(0xFFDCE3EC);
  static const field = Color(0xFFC5D0DC);
  static const success = Color(0xFF15803D);
  static const successSoft = Color(0xFFDCF3E3);
  static const warning = Color(0xFF6B4200);
  static const warningSoft = Color(0xFFFFF1D6);
  static const danger = Color(0xFFDC2626);
  static const dangerSoft = Color(0xFFFDE8E8);
  static const whatsapp = Color(0xFF1B7A43);
}

ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      primary: AppColors.primary,
      surface: AppColors.card,
      error: AppColors.danger,
    ),
    scaffoldBackgroundColor: AppColors.ground,
  );
  // 6 sizes and 3 weights only (see AppColors).
  TextStyle? sz(TextStyle? st, double size, FontWeight w) => st?.copyWith(fontSize: size, fontWeight: w);
  final t0 = GoogleFonts.plusJakartaSansTextTheme(base.textTheme);
  final text = t0
      .copyWith(
        displayLarge: sz(t0.displayLarge, 24, FontWeight.w800),
        displayMedium: sz(t0.displayMedium, 24, FontWeight.w800),
        displaySmall: sz(t0.displaySmall, 24, FontWeight.w800),
        headlineLarge: sz(t0.headlineLarge, 24, FontWeight.w800),
        headlineMedium: sz(t0.headlineMedium, 24, FontWeight.w800),
        headlineSmall: sz(t0.headlineSmall, 20, FontWeight.w800),
        titleLarge: sz(t0.titleLarge, 20, FontWeight.w800),
        titleMedium: sz(t0.titleMedium, 16, FontWeight.w600),
        titleSmall: sz(t0.titleSmall, 14, FontWeight.w600),
        bodyLarge: sz(t0.bodyLarge, 16, FontWeight.w400),
        bodyMedium: sz(t0.bodyMedium, 14, FontWeight.w400),
        bodySmall: sz(t0.bodySmall, 12.5, FontWeight.w400),
        labelLarge: sz(t0.labelLarge, 14, FontWeight.w600),
        labelMedium: sz(t0.labelMedium, 12.5, FontWeight.w600),
        labelSmall: sz(t0.labelSmall, 11, FontWeight.w600),
      )
      .apply(bodyColor: AppColors.ink, displayColor: AppColors.ink);
  const radius = BorderRadius.all(Radius.circular(12));
  return base.copyWith(
    textTheme: text,
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: AppColors.ink,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      titleTextStyle: text.titleLarge?.copyWith(fontWeight: FontWeight.w800, fontSize: 20),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: AppColors.field, width: 1.5)),
      enabledBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: AppColors.field, width: 1.5)),
      focusedBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: AppColors.primary, width: 2)),
      errorBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: AppColors.danger, width: 1.5)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        shape: const RoundedRectangleBorder(borderRadius: radius),
        textStyle: text.titleSmall?.copyWith(fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        shape: const RoundedRectangleBorder(borderRadius: radius),
        side: const BorderSide(color: AppColors.field, width: 1.5),
        foregroundColor: AppColors.ink,
        textStyle: text.titleSmall?.copyWith(fontWeight: FontWeight.w600),
      ),
    ),
    // lifted floating tab bar (see OwnerShell / StudentShell): pale blue pill on the selected tab
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      height: 64,
      indicatorColor: AppColors.primarySoft,
      labelTextStyle: WidgetStateProperty.resolveWith((st) => text.labelSmall?.copyWith(
          fontSize: 11,
          fontWeight: st.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w400,
          color: st.contains(WidgetState.selected) ? AppColors.primary : AppColors.muted)),
      iconTheme: WidgetStateProperty.resolveWith((st) =>
          IconThemeData(size: 22, color: st.contains(WidgetState.selected) ? AppColors.primary : AppColors.muted)),
    ),
    cardTheme: const CardThemeData(
      color: Colors.white,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
        side: BorderSide(color: AppColors.line),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}
