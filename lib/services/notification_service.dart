// lib/services/notification_service.dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/notification_item.dart';

/// Сервис in-app уведомлений.
/// История хранится в SharedPreferences.
/// [unreadCount] — ValueNotifier для бейджа на колокольчике.
class NotificationService {
  NotificationService._();

  static const _kKey = 'notification_history';

  static final ValueNotifier<int> unreadCount = ValueNotifier(0);
  static final List<NotificationItem> _items  = [];

  // Cached after init() so every _persist() call is O(1) — no async lookup.
  static SharedPreferences? _prefs;

  // ── ИНИЦИАЛИЗАЦИЯ ─────────────────────────────────────────────

  static Future<void> init() async {
    try {
      _prefs      = await SharedPreferences.getInstance();
      final raw   = _prefs!.getString(_kKey);
      if (raw != null) {
        final list = jsonDecode(raw) as List<dynamic>;
        _items.clear();
        for (final e in list) {
          try { _items.add(NotificationItem.fromJson(e as Map<String, dynamic>)); }
          catch (_) {}
        }
      }
      _recalcBadge();
    } catch (e) {
      debugPrint('NotificationService.init ERROR: $e');
    }
  }

  // ── API ────────────────────────────────────────────────────────

  /// Добавляет уведомление (вставляет в начало, лимит 100).
  static Future<void> add(NotificationItem item) async {
    _items.insert(0, item);
    if (_items.length > 100) _items.removeRange(100, _items.length);
    _recalcBadge();
    await _persist();
  }

  /// Хелпер: создаёт и добавляет уведомление одной строкой.
  static Future<void> notify({
    required String title,
    required String body,
    NotificationType type = NotificationType.info,
    DateTime? date,
  }) async {
    await add(NotificationItem(
      id:        '${DateTime.now().millisecondsSinceEpoch}',
      title:     title,
      body:      body,
      timestamp: DateTime.now(),
      type:      type,
      date:      date,
      isRead:    false,
    ));
  }

  /// Помечает все непрочитанные как прочитанные.
  static Future<void> markAllRead() async {
    bool changed = false;
    for (final item in _items) {
      if (!item.isRead) { item.isRead = true; changed = true; }
    }
    if (changed) { _recalcBadge(); await _persist(); }
  }

  /// Удаляет одно уведомление по ID.
  static Future<void> remove(String id) async {
    _items.removeWhere((e) => e.id == id);
    _recalcBadge();
    await _persist();
  }

  /// Удаляет всю историю.
  static Future<void> clearAll() async {
    _items.clear();
    _recalcBadge();
    await _persist();
  }

  /// Возвращает неизменяемый снимок списка.
  static List<NotificationItem> getAll() => List.unmodifiable(_items);

  // ── ВНУТРЕННИЕ ────────────────────────────────────────────────

  static void _recalcBadge() {
    unreadCount.value = _items.where((e) => !e.isRead).length;
  }

  static Future<void> _persist() async {
    try {
      // Use the SharedPreferences instance cached during init() — avoids an
      // unnecessary async platform-channel round-trip on every write.
      final prefs = _prefs ?? await SharedPreferences.getInstance();
      await prefs.setString(
          _kKey, jsonEncode(_items.map((e) => e.toJson()).toList()));
    } catch (e) {
      debugPrint('NotificationService._persist ERROR: $e');
    }
  }
}
