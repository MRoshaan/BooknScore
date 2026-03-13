import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists the user's [ThemeMode] choice across app restarts.
///
/// Defaults to [ThemeMode.system] on first launch.
/// Saves the selection under the key [_prefKey] in SharedPreferences.
class ThemeProvider extends ChangeNotifier {
  static const String _prefKey = 'theme_mode';

  ThemeMode _mode = ThemeMode.system;

  ThemeMode get mode => _mode;

  /// Call once during app startup (before [runApp]).
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefKey);
    _mode = _fromString(saved);
    // No notifyListeners here — called before the widget tree exists.
  }

  Future<void> setMode(ThemeMode mode) async {
    if (_mode == mode) return;
    _mode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, _toString(mode));
  }

  // ── Serialisation helpers ──────────────────────────────────────────────────

  static ThemeMode _fromString(String? value) {
    switch (value) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  static String _toString(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }

  /// Human-readable label for UI.
  static String label(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'Light';
      case ThemeMode.dark:
        return 'Dark';
      case ThemeMode.system:
        return 'System';
    }
  }

  static const List<ThemeMode> allModes = [
    ThemeMode.system,
    ThemeMode.light,
    ThemeMode.dark,
  ];
}
