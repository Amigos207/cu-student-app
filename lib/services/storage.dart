// lib/services/storage.dart
import 'package:shared_preferences/shared_preferences.dart';

class Storage {
  static late SharedPreferences _prefs;

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  // ─── ПОЛЬЗОВАТЕЛЬ ───────────────────────────────────────────────

  static Future<void> saveUser(String username) async =>
      _prefs.setString('username', username);

  static String? getUser() => _prefs.getString('username');

  static Future<void> savePassword(String password) async =>
      _prefs.setString('password', password);

  static String? getPassword() => _prefs.getString('password');

  static Future<void> clearUser() async {
    await _prefs.remove('username');
    await _prefs.remove('password');
  }

  // ─── НАСТРОЙКИ ──────────────────────────────────────────────────

  static Future<void> saveLang(String lang) async =>
      _prefs.setString('lang', lang);

  static String getLang() => _prefs.getString('lang') ?? 'English';

  static Future<void> saveTheme(String theme) async =>
      _prefs.setString('theme', theme);

  static String getTheme() => _prefs.getString('theme') ?? 'light';

  static Future<void> saveTimeFormat(bool showEndTime) async =>
      _prefs.setBool('show_end_time', showEndTime);

  static bool getTimeFormat() => _prefs.getBool('show_end_time') ?? true;

  static Future<void> saveHaptic(bool enabled) async =>
      _prefs.setBool('haptic_enabled', enabled);

  static bool getHaptic() => _prefs.getBool('haptic_enabled') ?? true;

  // ─── ВСПОМОГАТЕЛЬНЫЕ (проксируем SharedPreferences напрямую) ────
  // NotificationService и LessonOverrideService работают с SharedPreferences
  // напрямую через собственные ключи, но объявляем getter здесь для ясности.

  static SharedPreferences get prefs => _prefs;
}