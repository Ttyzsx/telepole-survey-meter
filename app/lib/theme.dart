import 'package:flutter/material.dart';

import 'models/reading.dart';

/// โทนสีแบบเครื่องมือวัดภาคสนาม: พื้นเข้ม + ตัวเลขเรืองแสง
class AppTheme {
  static const bg = Color(0xFF0B0F14);
  static const surface = Color(0xFF141B23);
  static const surfaceAlt = Color(0xFF1C2733);
  static const outline = Color(0xFF2C3A48);
  static const textPrimary = Color(0xFFE8F1F8);
  static const textMuted = Color(0xFF8CA0B3);

  static const safe = Color(0xFF3DDC97);
  static const warn = Color(0xFFFFC145);
  static const danger = Color(0xFFFF4D5E);

  static Color colorFor(HazardLevel level) => switch (level) {
        HazardLevel.normal => safe,
        HazardLevel.elevated => warn,
        HazardLevel.alarm => danger,
      };

  static String labelFor(HazardLevel level) => switch (level) {
        HazardLevel.normal => 'ปกติ',
        HazardLevel.elevated => 'เฝ้าระวัง',
        HazardLevel.alarm => 'เกินเกณฑ์',
      };

  static ThemeData build() {
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: bg,
      colorScheme: base.colorScheme.copyWith(
        surface: surface,
        primary: safe,
        error: danger,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: bg,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
      ),
      textTheme: base.textTheme.apply(bodyColor: textPrimary, displayColor: textPrimary),
    );
  }
}
