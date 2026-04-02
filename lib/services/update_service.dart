import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

/// Сервис принудительного обновления через GitHub Releases.
///
/// Как работает:
/// 1. При запуске приложение скачивает version.json из репозитория
/// 2. Сравнивает min_version с текущей версией приложения
/// 3. Если текущая версия устарела — показывает неотключаемый экран
///    с кнопкой скачивания нового APK
///
/// Как выпустить обновление:
/// 1. Собери новый APK: flutter build apk
/// 2. Зайди на https://github.com/Amigos207/cu-student-app/releases/new
/// 3. Tag: v1.0.1 (новая версия), загрузи APK файл
/// 4. После создания Release — скопируй прямую ссылку на APK
/// 5. Обнови version.json в репозитории (см. ниже формат)
class UpdateService {
  // ── Твои данные GitHub ─────────────────────────────────────────
  static const _owner = 'Amigos207';
  static const _repo  = 'cu-student-app';

  /// URL файла version.json в главной ветке репозитория.
  /// Этот файл ты обновляешь вручную при каждом релизе.
  static const _versionUrl =
      'https://raw.githubusercontent.com/$_owner/$_repo/main/version.json';

  /// Страница релизов — запасной вариант если прямая ссылка не работает.
  static const _releasesPage =
      'https://github.com/$_owner/$_repo/releases/latest';

  /// Текущая версия приложения.
  /// ОБЯЗАТЕЛЬНО синхронизируй с pubspec.yaml → version: X.Y.Z+build
  static const String currentVersion = '1.0.0';

  // ──────────────────────────────────────────────────────────────

  /// Проверяет версию и если нужно — показывает неотключаемый экран.
  /// Вызывается из SplashScreen после успешного логина.
  static Future<void> checkAndPrompt(
    BuildContext context,
    String Function(String) tr,
  ) async {
    try {
      final res = await http
          .get(
            Uri.parse(_versionUrl),
            headers: {'Cache-Control': 'no-cache'},
          )
          .timeout(const Duration(seconds: 6));

      if (res.statusCode != 200) return;

      final data        = jsonDecode(res.body) as Map<String, dynamic>;
      final minVersion  = (data['min_version'] as String?)?.trim() ?? '0.0.0';
      final downloadUrl = (data['download_url'] as String?)?.trim() ?? _releasesPage;
      final changelog   = data['changelog'] as String?;

      if (_isOutdated(currentVersion, minVersion) && context.mounted) {
        await _showUpdateScreen(context, downloadUrl, changelog, tr);
      }
    } catch (_) {
      // Нет интернета или файл недоступен — молча пропускаем,
      // не мешаем пользователю работать.
    }
  }

  /// true если current < minimum
  static bool _isOutdated(String current, String minimum) {
    final c = _parse(current);
    final m = _parse(minimum);
    for (int i = 0; i < 3; i++) {
      if (c[i] < m[i]) return true;
      if (c[i] > m[i]) return false;
    }
    return false;
  }

  static List<int> _parse(String v) {
    final parts = v.replaceAll(RegExp(r'[^0-9.]'), '').split('.');
    return List.generate(3, (i) => i < parts.length
        ? (int.tryParse(parts[i]) ?? 0) : 0);
  }

  static Future<void> _showUpdateScreen(
    BuildContext context,
    String downloadUrl,
    String? changelog,
    String Function(String) tr,
  ) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _UpdateScreen(
          downloadUrl: downloadUrl,
          changelog: changelog,
          tr: tr,
        ),
        fullscreenDialog: true,
      ),
    );
  }

  static Future<void> openUrl(String url) async {
    final uri = Uri.parse(url);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // Если не открылось — ничего не делаем
    }
  }
}

// ─── Экран обновления ─────────────────────────────────────────────────────

class _UpdateScreen extends StatefulWidget {
  final String downloadUrl;
  final String? changelog;
  final String Function(String) tr;

  const _UpdateScreen({
    required this.downloadUrl,
    required this.changelog,
    required this.tr,
  });

  @override
  State<_UpdateScreen> createState() => _UpdateScreenState();
}

class _UpdateScreenState extends State<_UpdateScreen> {
  bool _downloading = false;

  Future<void> _onUpdate() async {
    setState(() => _downloading = true);
    await UpdateService.openUrl(widget.downloadUrl);
    await Future.delayed(const Duration(seconds: 1));
    if (mounted) setState(() => _downloading = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme   = Theme.of(context);
    final primary = theme.colorScheme.primary;

    return PopScope(
      // Нельзя закрыть кнопкой назад
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Иконка
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color: primary.withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.system_update_rounded,
                    size: 52,
                    color: primary,
                  ),
                ),
                const SizedBox(height: 32),

                // Заголовок
                Text(
                  widget.tr('update_required'),
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),

                // Подзаголовок
                Text(
                  widget.tr('update_message'),
                  style: TextStyle(
                    fontSize: 15,
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),

                // Changelog если есть
                if (widget.changelog != null &&
                    widget.changelog!.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: primary.withOpacity(0.07),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color: primary.withOpacity(0.2)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.new_releases_rounded,
                                size: 16, color: primary),
                            const SizedBox(width: 6),
                            Text(
                              "What's new",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: primary,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          widget.changelog!,
                          style: TextStyle(
                            fontSize: 13,
                            color: theme.colorScheme.onSurfaceVariant,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 40),

                // Кнопка обновления
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: FilledButton.icon(
                    icon: _downloading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2.5,
                            ),
                          )
                        : const Icon(Icons.download_rounded),
                    label: Text(
                      widget.tr('update_btn'),
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    onPressed: _downloading ? null : _onUpdate,
                  ),
                ),

                const SizedBox(height: 16),

                // Версия
                Text(
                  'v${UpdateService.currentVersion}',
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurfaceVariant
                        .withOpacity(0.5),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
