import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  static const Color background = Color(0xFF0A0A0F);
  static const Color cardSurface = Color(0xFF0D0D15);
  static const Color primary = Color(0xFFFFFFFF);
  static const Color onPrimary = Color(0xFF000000);
  static const Color secondary = Color(0xFF999999);
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textMuted = Color(0xFF999999);
  static const Color border = Color(0x1AFFFFFF); // white @ 10%
  static const Color errorRed = Color(0xFFFF4444);
  static const Color coral = Color(0xFFE1306C); // Instagram pink — primary
  static const Color sage = Color(0xFF833AB4); // Instagram purple — secondary
  static const Color gold = Color(0xFFF77737); // Instagram orange/gold

  // Glass surface helpers
  static const Color glassSurface = Color(0x1AFFFFFF); // white @ 10%
  static const Color glassBorder = Color(0x26FFFFFF); // white @ 15%

  // V2 accent palette — cyan / magenta / purple
  static const Color neonCyan = Color(0xFF00FFFF);
  static const Color vibrantMagenta = Color(0xFFFF006E);
  static const Color electricPurple = Color(0xFF9D4EDD);

  // Instagram gradient
  static const LinearGradient instaGradient = LinearGradient(
    colors: [Color(0xFF405DE6), Color(0xFF833AB4), Color(0xFFE1306C)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Full Instagram gradient (for legend tier / special elements)
  static const LinearGradient fullInstaGradient = LinearGradient(
    colors: [
      Color(0xFF405DE6),
      Color(0xFF833AB4),
      Color(0xFFE1306C),
      Color(0xFFF77737),
    ],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

class AppStrings {
  AppStrings._();

  static const String appName = 'I';
  static const String supabaseUrl =
      'https://uehqazxnodndutjvxemq.supabase.co';
  static const String supabaseAnonKey =
      'sb_publishable_Vj5_7tm1bwJEL2XjMWbGdw_I8PGv2eV';
}
