import 'package:flutter/material.dart';
import 'services/storage.dart';
import 'services/language.dart';
import 'services/theme_service.dart';
import 'services/notification_service.dart';
import 'services/lesson_override_service.dart';
import 'screens/splash_screen.dart';

final themeNotifier = ValueNotifier<String>('light');

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Future.wait([
    Storage.init(),
    NotificationService.init(),
    LessonOverrideService.init(),
  ]);

  final savedLang  = Storage.getLang();
  final savedTheme = Storage.getTheme();

  LanguageService.currentLang.value   = savedLang;
  LanguageService.showBothTimes.value = Storage.getTimeFormat();
  themeNotifier.value                 = savedTheme;

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
              home: const SplashScreen(),
            );
          },
        );
      },
    );
  }
}
