import 'package:flutter/material.dart';
import 'services/storage.dart';
import 'services/language.dart';
import 'services/theme_service.dart';
import 'screens/splash_screen.dart';

/// Глобальный нотификатор темы (используется в SettingsScreen).
final themeNotifier = ValueNotifier<String>('light');

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Storage.init();

  final savedLang  = Storage.getLang();
  final savedTheme = Storage.getTheme();

  LanguageService.currentLang.value   = savedLang;
  LanguageService.showBothTimes.value = Storage.getTimeFormat();
  themeNotifier.value = savedTheme;

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: themeNotifier,
      builder: (context, theme, _) {
        return ValueListenableBuilder<String>(
          valueListenable: LanguageService.currentLang,
          builder: (context, lang, _) {
            return MaterialApp(
              title: LanguageService.tr('app_name'),
              debugShowCheckedModeBanner: false,
              theme: ThemeService.getTheme(theme),
              // ИСПРАВЛЕНИЕ #1: всегда стартуем через SplashScreen.
              // SplashScreen делает авто-вход и устанавливает куки сессии,
              // после чего маршрутизирует в MainScreen или LoginScreen.
              // Раньше при наличии сохранённого username приложение шло
              // напрямую в MainScreen — куки были пустые → расписание пустое.
              home: const SplashScreen(),
            );
          },
        );
      },
    );
  }
}
