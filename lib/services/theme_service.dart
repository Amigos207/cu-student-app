import 'package:flutter/material.dart';

/// Все темы приложения.
/// Чтобы добавить новую тему — добавь case в [getTheme] и [allThemes].
class ThemeService {
  // ─── СПИСОК ДЛЯ UI ──────────────────────────────────────────────
  static const List<AppTheme> allThemes = [
    AppTheme(id: 'light',  labelKey: 'theme_light',  icon: Icons.light_mode_rounded,    previewColor: Color(0xFF6750A4)),
    AppTheme(id: 'dark',   labelKey: 'theme_dark',   icon: Icons.dark_mode_rounded,     previewColor: Color(0xFF4F378B)),
    AppTheme(id: 'pink',   labelKey: 'theme_pink',   icon: Icons.favorite_rounded,      previewColor: Color(0xFFE91E8C)),
    AppTheme(id: 'hacker', labelKey: 'theme_hacker', icon: Icons.terminal_rounded,      previewColor: Color(0xFF00FF41)),
    AppTheme(id: 'ocean',  labelKey: 'theme_ocean',  icon: Icons.water_rounded,         previewColor: Color(0xFF0077B6)),
  ];

  static ThemeData getTheme(String id) {
    switch (id) {
      case 'dark':   return _dark;
      case 'pink':   return _pink;
      case 'hacker': return _hacker;
      case 'ocean':  return _ocean;
      default:       return _light;
    }
  }

  // ─── СВЕТЛАЯ ────────────────────────────────────────────────────
  static final _light = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF6750A4),
      brightness: Brightness.light,
    ),
  );

  // ─── ТЁМНАЯ ─────────────────────────────────────────────────────
  static final _dark = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF6750A4),
      brightness: Brightness.dark,
    ),
  );

  // ─── РОЗОВАЯ ────────────────────────────────────────────────────
  static final _pink = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: const ColorScheme(
      brightness: Brightness.light,
      primary:           Color(0xFFD81B60),
      onPrimary:         Colors.white,
      primaryContainer:  Color(0xFFFFD6E7),
      onPrimaryContainer:Color(0xFF3E001D),
      secondary:         Color(0xFFE91E8C),
      onSecondary:       Colors.white,
      secondaryContainer:Color(0xFFFFD6EC),
      onSecondaryContainer: Color(0xFF3D0023),
      tertiary:          Color(0xFFF06292),
      onTertiary:        Colors.white,
      tertiaryContainer: Color(0xFFFFD1DC),
      onTertiaryContainer: Color(0xFF3B0013),
      error:             Color(0xFFBA1A1A),
      onError:           Colors.white,
      errorContainer:    Color(0xFFFFDAD6),
      onErrorContainer:  Color(0xFF410002),
      surface:           Color(0xFFFFF0F5),
      onSurface:         Color(0xFF1C1B1F),
      surfaceContainerHighest:    Color(0xFFFFD6E7),
      onSurfaceVariant:  Color(0xFF4A3A40),
      outline:           Color(0xFFD4A0B0),
      shadow:            Colors.black,
      inverseSurface:    Color(0xFF313033),
      onInverseSurface:  Color(0xFFF4EFF4),
      inversePrimary:    Color(0xFFFFB0CA),
    ),
    scaffoldBackgroundColor: const Color(0xFFFFF0F5),
    cardTheme: const CardThemeData(color: Colors.white),
  );

  // ─── ХАКЕРСКАЯ (МАТРИЦА) ────────────────────────────────────────
  static final _hacker = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: const ColorScheme(
      brightness: Brightness.dark,
      primary:            Color(0xFF00FF41),
      onPrimary:          Color(0xFF001A09),
      primaryContainer:   Color(0xFF003312),
      onPrimaryContainer: Color(0xFF00FF41),
      secondary:          Color(0xFF00CC33),
      onSecondary:        Color(0xFF001A09),
      secondaryContainer: Color(0xFF002910),
      onSecondaryContainer: Color(0xFF00CC33),
      tertiary:           Color(0xFF39FF14),
      onTertiary:         Color(0xFF001A00),
      tertiaryContainer:  Color(0xFF002600),
      onTertiaryContainer:Color(0xFF39FF14),
      error:              Color(0xFFFF453A),
      onError:            Color(0xFF1A0000),
      errorContainer:     Color(0xFF3A0000),
      onErrorContainer:   Color(0xFFFF453A),
      surface:            Color(0xFF0D1A0F),
      onSurface:          Color(0xFF00FF41),
      surfaceContainerHighest:     Color(0xFF122B17),
      onSurfaceVariant:   Color(0xFF00CC33),
      outline:            Color(0xFF00AA22),
      shadow:             Colors.black,
      inverseSurface:     Color(0xFF00FF41),
      onInverseSurface:   Color(0xFF0A0A0A),
      inversePrimary:     Color(0xFF003312),
    ),
    scaffoldBackgroundColor: const Color(0xFF0A0A0A),
    cardTheme: const CardThemeData(color: Color(0xFF0D1A0F)),
    // Придаём шрифту терминальный вайб
    textTheme: const TextTheme(
      bodyLarge:   TextStyle(fontFamily: 'monospace', color: Color(0xFF00FF41)),
      bodyMedium:  TextStyle(fontFamily: 'monospace', color: Color(0xFF00FF41)),
      bodySmall:   TextStyle(fontFamily: 'monospace', color: Color(0xFF00CC33)),
      titleLarge:  TextStyle(fontFamily: 'monospace', color: Color(0xFF00FF41), fontWeight: FontWeight.bold),
      titleMedium: TextStyle(fontFamily: 'monospace', color: Color(0xFF00FF41)),
      labelLarge:  TextStyle(fontFamily: 'monospace', color: Color(0xFF00FF41)),
      labelSmall:  TextStyle(fontFamily: 'monospace', color: Color(0xFF00CC33)),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFF0A0A0A),
      foregroundColor: Color(0xFF00FF41),
      surfaceTintColor: Colors.transparent,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: const Color(0xFF0D1A0F),
      indicatorColor: const Color(0xFF00FF41).withOpacity(0.2),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const TextStyle(color: Color(0xFF00FF41), fontSize: 12, fontFamily: 'monospace');
        }
        return const TextStyle(color: Color(0xFF00AA22), fontSize: 12, fontFamily: 'monospace');
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const IconThemeData(color: Color(0xFF00FF41));
        }
        return const IconThemeData(color: Color(0xFF00AA22));
      }),
    ),
    dividerTheme: const DividerThemeData(color: Color(0xFF00AA22)),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? const Color(0xFF00FF41) : const Color(0xFF00AA22)),
      trackColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? const Color(0xFF003312) : const Color(0xFF001A09)),
    ),
  );

  // ─── ОКЕАН ──────────────────────────────────────────────────────
  static final _ocean = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: const ColorScheme(
      brightness: Brightness.dark,
      primary:            Color(0xFF48CAE4),
      onPrimary:          Color(0xFF00172B),
      primaryContainer:   Color(0xFF023E8A),
      onPrimaryContainer: Color(0xFF90E0EF),
      secondary:          Color(0xFF0096C7),
      onSecondary:        Color(0xFF00172B),
      secondaryContainer: Color(0xFF03045E),
      onSecondaryContainer: Color(0xFF90E0EF),
      tertiary:           Color(0xFF00B4D8),
      onTertiary:         Color(0xFF001F33),
      tertiaryContainer:  Color(0xFF012A45),
      onTertiaryContainer:Color(0xFF90E0EF),
      error:              Color(0xFFFF6B6B),
      onError:            Color(0xFF200000),
      errorContainer:     Color(0xFF3A0000),
      onErrorContainer:   Color(0xFFFF6B6B),
      surface:            Color(0xFF023E8A),
      onSurface:          Color(0xFFCAF0F8),
      surfaceContainerHighest:     Color(0xFF0077B6),
      onSurfaceVariant:   Color(0xFF90E0EF),
      outline:            Color(0xFF0096C7),
      shadow:             Colors.black,
      inverseSurface:     Color(0xFFCAF0F8),
      onInverseSurface:   Color(0xFF03045E),
      inversePrimary:     Color(0xFF023E8A),
    ),
    scaffoldBackgroundColor: const Color(0xFF03045E),
    cardTheme: const CardThemeData(color: Color(0xFF023E8A)),
  );
}

/// Метаданные одной темы для отображения в UI.
class AppTheme {
  final String id;
  final String labelKey;    // ключ перевода
  final IconData icon;
  final Color previewColor; // цвет превью-кружка

  const AppTheme({
    required this.id,
    required this.labelKey,
    required this.icon,
    required this.previewColor,
  });
}