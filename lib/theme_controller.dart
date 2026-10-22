import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Holds the user's chosen theme (System / Light / Dark) and persists it.
class ThemeController extends ChangeNotifier {
  static const _key = 'theme_mode';
  ThemeMode _mode = ThemeMode.system;
  SharedPreferences? _prefs;

  ThemeMode get mode => _mode;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    switch (_prefs?.getString(_key)) {
      case 'light':
        _mode = ThemeMode.light;
      case 'dark':
        _mode = ThemeMode.dark;
      default:
        _mode = ThemeMode.system;
    }
    notifyListeners();
  }

  Future<void> cycle() async {
    _mode = switch (_mode) {
      ThemeMode.system => ThemeMode.light,
      ThemeMode.light => ThemeMode.dark,
      ThemeMode.dark => ThemeMode.system,
    };
    await _prefs?.setString(_key, _mode.name);
    notifyListeners();
  }

  static IconData iconFor(ThemeMode m) => switch (m) {
    ThemeMode.light => Icons.light_mode_rounded,
    ThemeMode.dark => Icons.dark_mode_rounded,
    ThemeMode.system => Icons.brightness_auto_rounded,
  };
}
