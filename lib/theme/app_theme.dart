import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  static const Color defaultPrimaryColor = Color(0xFF6200EE);
  static const Color accentColor = Color(0xFF03DAC6);
  static const Color backgroundColorLight = Color(0xFFF5F5F5);
  static const Color backgroundColorDark = Color(0xFF121212);

  static ThemeData lightTheme(Color primaryColor) {
    return ThemeData(
      brightness: Brightness.light,
      primaryColor: primaryColor,
      scaffoldBackgroundColor: backgroundColorLight,
      colorScheme: ColorScheme.light(
        primary: primaryColor,
        secondary: accentColor,
      ),
      textTheme: GoogleFonts.interTextTheme(ThemeData.light().textTheme),
      appBarTheme: AppBarTheme(
        backgroundColor: primaryColor,
        elevation: 0,
        foregroundColor: Colors.white,
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: Colors.white,
        unselectedLabelColor: Colors.white70,
      ),
      useMaterial3: true,
    );
  }

  static ThemeData darkTheme(Color primaryColor) {
    return ThemeData(
      brightness: Brightness.dark,
      primaryColor: primaryColor,
      scaffoldBackgroundColor: backgroundColorDark,
      colorScheme: ColorScheme.dark(
        primary: primaryColor,
        secondary: accentColor,
      ),
      textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
      appBarTheme: AppBarTheme(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: Colors.white,
        unselectedLabelColor: Colors.white70,
      ),
      useMaterial3: true,
    );
  }
}
