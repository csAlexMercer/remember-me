import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

class ThemeProvider extends ChangeNotifier {
  static const String _boxName = 'theme_settings';
  static const String _colorKey = 'primary_color';
  static const String _themeModeKey = 'theme_mode';

  late Box _box;

  // Defaults
  Color _primaryColor = const Color(0xFF6200EE); // AppTheme.primaryColor
  ThemeMode _themeMode = ThemeMode.system;

  Color get primaryColor => _primaryColor;
  ThemeMode get themeMode => _themeMode;

  ThemeProvider() {
    _init();
  }

  Future<void> _init() async {
    _box = await Hive.openBox(_boxName);
    
    final colorValue = _box.get(_colorKey) as int?;
    if (colorValue != null) {
      _primaryColor = Color(colorValue);
    }

    final themeModeIndex = _box.get(_themeModeKey) as int?;
    if (themeModeIndex != null && themeModeIndex >= 0 && themeModeIndex < ThemeMode.values.length) {
      _themeMode = ThemeMode.values[themeModeIndex];
    }

    notifyListeners();
  }

  Future<void> updatePrimaryColor(Color color) async {
    _primaryColor = color;
    await _box.put(_colorKey, color.value);
    notifyListeners();
  }

  Future<void> updateThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    await _box.put(_themeModeKey, mode.index);
    notifyListeners();
  }
}
