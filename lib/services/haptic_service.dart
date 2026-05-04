// lib/services/haptic_service.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'storage.dart';

/// Централизованный сервис тактильной обратной связи.
///
/// Использование:
///   HapticService.light();    // лёгкий тап (карточки, переключатели)
///   HapticService.medium();   // средний (кнопки действий, навигация)
///   HapticService.heavy();    // тяжёлый (деструктивные действия, ошибки)
///   HapticService.selection(); // смена выбора (табы, чипы)
///
/// Все методы — no-op если:
///  • хаптик выключен пользователем в настройках
///  • платформа не поддерживает (web / desktop)
class HapticService {
  HapticService._();

  static const _key = 'haptic_enabled';

  // In-memory кеш, чтобы isEnabled не зависел от асинхронности SharedPreferences.
  // null = ещё не инициализирован, читается лениво при первом обращении.
  static bool? _enabled;

  // ─── Настройка ──────────────────────────────────────────────────

  /// Включён ли хаптик (по умолчанию true).
  static bool get isEnabled {
    _enabled ??= Storage.prefs.getBool(_key) ?? true;
    return _enabled!;
  }

  /// Обновляет кеш мгновенно и сохраняет на диск.
  static Future<void> setEnabled(bool value) async {
    _enabled = value;                          // сразу, без ожидания диска
    await Storage.prefs.setBool(_key, value);  // персистим
  }

  // ─── Публичное API ───────────────────────────────────────────────

  /// Лёгкий импульс — карточки, тоггл-переключатели, раскрытие секций.
  static Future<void> light() => _fire(HapticFeedback.lightImpact);

  /// Средний импульс — основные кнопки, переключение вкладок навигации.
  static Future<void> medium() => _fire(HapticFeedback.mediumImpact);

  /// Тяжёлый импульс — деструктивные действия, ошибки.
  static Future<void> heavy() => _fire(HapticFeedback.heavyImpact);

  /// Селекционный клик — смена вкладки внутри экрана, выбор из списка.
  static Future<void> selection() => _fire(HapticFeedback.selectionClick);

  /// Двойной импульс для переключения основных вкладок навигации.
  /// Heavy + короткая пауза + Medium — ощущается заметно сильнее одного импульса.
  static Future<void> tabSwitch() async {
    if (!isEnabled) return;
    if (kIsWeb) return;
    if (defaultTargetPlatform != TargetPlatform.iOS &&
        defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await HapticFeedback.heavyImpact();
      await Future<void>.delayed(const Duration(milliseconds: 48));
      await HapticFeedback.mediumImpact();
    } catch (_) {
      // Молча игнорируем: устройство может не поддерживать конкретный тип.
    }
  }

  // ─── Внутренняя реализация ───────────────────────────────────────

  static Future<void> _fire(AsyncCallback haptic) async {
    if (!isEnabled) return;
    // Хаптик поддерживается только на iOS и Android.
    if (kIsWeb) return;
    if (defaultTargetPlatform != TargetPlatform.iOS &&
        defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await haptic();
    } catch (_) {
      // Молча игнорируем: устройство может не поддерживать конкретный тип.
    }
  }
}