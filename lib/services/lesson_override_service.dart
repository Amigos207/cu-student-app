// lib/services/lesson_override_service.dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/lesson_override.dart';

/// Сервис локальных изменений расписания.
/// Хранит список [LessonOverride] в SharedPreferences (JSON).
/// Поддерживает: отмену лекций, добавление, восстановление.
class LessonOverrideService {
  LessonOverrideService._();

  static const _kKey = 'lesson_overrides';

  // Нотификатор — все виджеты с override-зависимостью подписываются на него
  static final ValueNotifier<int> version = ValueNotifier(0);

  static final List<LessonOverride> _overrides = [];

  // ── ИНИЦИАЛИЗАЦИЯ ─────────────────────────────────────────────

  static Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw   = prefs.getString(_kKey);
      if (raw != null) {
        final list = jsonDecode(raw) as List<dynamic>;
        _overrides.clear();
        for (final e in list) {
          try { _overrides.add(LessonOverride.fromJson(e as Map<String, dynamic>)); }
          catch (_) {}
        }
      }
    } catch (e) {
      debugPrint('LessonOverrideService.init ERROR: $e');
    }
  }

  // ── ДОБАВЛЕНИЕ / УДАЛЕНИЕ ──────────────────────────────────────

  static Future<void> add(LessonOverride override) async {
    _overrides.add(override);
    _bump();
    await _persist();
  }

  static Future<void> remove(String id) async {
    _overrides.removeWhere((e) => e.id == id);
    _bump();
    await _persist();
  }

  /// Removes every override — used by the admin sandbox reset.
  static Future<void> clearAll() async {
    _overrides.clear();
    _bump();
    await _persist();
  }

  // ── ЗАПРОСЫ ───────────────────────────────────────────────────

  /// Все отмены и добавления для конкретной даты (без времени).
  static List<LessonOverride> forDate(DateTime date) {
    final d = _dateOnly(date);
    return _overrides.where((e) => _dateOnly(e.date) == d).toList();
  }

  /// Только отменённые лекции (из любой даты).
  static List<LessonOverride> getCancelled() =>
      _overrides.where((e) => e.isCancelled).toList();

  /// Все отмены для конкретной даты.
  static List<LessonOverride> getCancelledForDate(DateTime date) {
    final d = _dateOnly(date);
    return _overrides
        .where((e) => e.isCancelled && _dateOnly(e.date) == d)
        .toList();
  }

  /// Все добавленные/восстановленные лекции для даты.
  static List<LessonOverride> getAddedForDate(DateTime date) {
    final d = _dateOnly(date);
    return _overrides
        .where((e) => e.isAdded && _dateOnly(e.date) == d)
        .toList();
  }

  /// Проверяет, отменена ли конкретная лекция (по name+teacher) на дату.
  static bool isCancelled(
      String lessonName, String lessonTeacher, DateTime date) {
    final d = _dateOnly(date);
    return _overrides.any((e) =>
        e.isCancelled &&
        _dateOnly(e.date) == d &&
        _norm(e.lessonName) == _norm(lessonName) &&
        (lessonTeacher.isEmpty ||
            e.lessonTeacher.isEmpty ||
            _norm(e.lessonTeacher) == _norm(lessonTeacher)));
  }

  /// Все добавленные лекции (для выбора «Восстановить»).
  static List<LessonOverride> getAll() => List.unmodifiable(_overrides);

  // ── ВНУТРЕННИЕ ────────────────────────────────────────────────

  static void _bump() => version.value++;

  static DateTime _dateOnly(DateTime d) =>
      DateTime(d.year, d.month, d.day);

  static String _norm(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'\s+'), '');

  static Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _kKey, jsonEncode(_overrides.map((e) => e.toJson()).toList()));
    } catch (e) {
      debugPrint('LessonOverrideService._persist ERROR: $e');
    }
  }
}
