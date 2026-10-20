import 'package:flutter/material.dart';

const careFlowTeal = Color(0xFF0C766D);
const careFlowNavy = Color(0xFF0C2432);
const careFlowMint = Color(0xFF85E7D6);
const careFlowCanvas = Color(0xFFEEF3F6);

ThemeData buildCareFlowTheme() {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: careFlowTeal,
    brightness: Brightness.light,
    surface: Colors.white,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: careFlowCanvas,
    fontFamilyFallback: const ['Aptos', 'Segoe UI', 'sans-serif'],
    appBarTheme: const AppBarTheme(
      centerTitle: false,
      elevation: 0,
      backgroundColor: careFlowCanvas,
      foregroundColor: careFlowNavy,
      surfaceTintColor: Colors.transparent,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFD8E3E8)),
      ),
      margin: EdgeInsets.zero,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(11),
        borderSide: const BorderSide(color: Color(0xFFC5D5DC)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(11),
        borderSide: const BorderSide(color: Color(0xFFC5D5DC)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(11),
        borderSide: const BorderSide(color: careFlowTeal, width: 1.6),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: careFlowTeal,
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        side: const BorderSide(color: Color(0xFFC5D5DC)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 72,
      backgroundColor: Colors.white,
      indicatorColor: const Color(0xFFDDF1ED),
      labelTextStyle: WidgetStateProperty.all(
        const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: careFlowNavy,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
    ),
    dividerTheme: const DividerThemeData(color: Color(0xFFD8E3E8), space: 1),
  );
}

Color statusColor(String status) {
  switch (status) {
    case 'EMERGENCY':
    case 'failed':
      return const Color(0xFFB3261E);
    case 'PRIORITY_REVIEW':
    case 'pending':
    case 'draft':
    case 'suggested':
      return const Color(0xFF9A5B00);
    case 'ROUTINE_REVIEW':
    case 'sent':
    case 'approved':
    case 'answered':
      return const Color(0xFF17663F);
    case 'UNASSESSED':
      return const Color(0xFF6544A8);
    default:
      return const Color(0xFF647A86);
  }
}

Color statusBackground(String status) {
  switch (status) {
    case 'EMERGENCY':
    case 'failed':
      return const Color(0xFFFDEcea);
    case 'PRIORITY_REVIEW':
    case 'pending':
    case 'draft':
    case 'suggested':
      return const Color(0xFFFFF4DF);
    case 'ROUTINE_REVIEW':
    case 'sent':
    case 'approved':
    case 'answered':
      return const Color(0xFFE7F6EE);
    case 'UNASSESSED':
      return const Color(0xFFF1ECFC);
    default:
      return const Color(0xFFEEF4F7);
  }
}
