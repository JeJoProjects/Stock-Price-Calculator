/// TradingView-inspired dark palette, ported 1:1 from src/ui/theme.hpp so the
/// look carries over exactly from the old C++/ImGui app.
library;

import 'package:flutter/material.dart';

class AppColors {
  static const bgPrimary = Color(0xFF131722);
  static const bgSecondary = Color(0xFF1E222D);
  static const bgInput = Color(0xFF2A2E39);
  static const bgHover = Color(0xFF363C4E);
  static const border = Color(0xFF363C4E);
  static const textPrimary = Color(0xFFD1D4DC);
  static const textMuted = Color(0xFF787B86);
  static const accentBlue = Color(0xFF2962FF);
  static const profitGreen = Color(0xFF089981);
  static const lossRed = Color(0xFFF23645);
  static const white = Color(0xFFFFFFFF);
}

ThemeData buildAppTheme() {
  return ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: AppColors.bgPrimary,
    fontFamily: 'Segoe UI',
    colorScheme: const ColorScheme.dark(
      primary: AppColors.accentBlue,
      secondary: AppColors.accentBlue,
      surface: AppColors.bgSecondary,
      error: AppColors.lossRed,
    ),
    textTheme: const TextTheme(
      bodyMedium: TextStyle(color: AppColors.textPrimary),
      bodySmall: TextStyle(color: AppColors.textMuted),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.bgInput,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: AppColors.accentBlue, width: 1.5),
      ),
    ),
    dividerColor: AppColors.border,
  );
}

const kCardRadius = 12.0;
const kInputRadius = 6.0;
const kPanelSpacing = 16.0;
const kPanelWidth = 280.0;
