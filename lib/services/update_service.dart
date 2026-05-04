import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'language.dart';

/// Сервис принудительного обновления через GitHub Releases.
///
/// Как работает:
/// 1. При запуске приложение скачивает version.json из репозитория
/// 2. Сравнивает min_version с текущей версией приложения
/// 3. Если текущая версия устарела — показывает неотключаемый экран
/// 4. Пользователь нажимает «Обновить» → APK скачивается прямо в приложении
///    → открывается стандартный установщик Android → данные сохраняются
///
/// Как выпустить обновление:
/// 1. Собери новый APK: flutter build apk --release
/// 2. Зайди на https://github.com/Amigos207/cu-student-app/releases/new
/// 3. Tag: v1.0.3, загрузи APK файл
/// 4. Скопируй прямую ссылку на APK (кнопка ПКМ → «Копировать адрес»)
/// 5. Обнови version.json: min_version и download_url
class UpdateService {
  // ── Твои данные GitHub ─────────────────────────────────────────
  static const _owner = 'Amigos207';
  static const _repo  = 'cu-student-app';

  static const _versionUrl =
      'https://raw.githubusercontent.com/$_owner/$_repo/main/version.json';

  static const _releasesPage =
      'https://github.com/$_owner/$_repo/releases/latest';

  /// Текущая версия — синхронизируй с pubspec.yaml → version
  static const String currentVersion = '2.0.2';

  // ──────────────────────────────────────────────────────────────

  /// Проверяет версию и если нужно — показывает неотключаемый экран.
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

      final lang    = LanguageService.currentLang.value;
      final langKey = lang == 'Русский'  ? 'changelog_ru'
                    : lang == 'ქართული' ? 'changelog_ka'
                    : 'changelog_en';
      final localized = (data[langKey] as String?)?.trim() ?? '';
      final changelog = localized.isNotEmpty
          ? localized
          : (data['changelog'] as String?)?.trim();

      if (_isOutdated(currentVersion, minVersion) && context.mounted) {
        await _showUpdateScreen(context, downloadUrl, changelog, tr);
      }
    } catch (_) {
      // Нет интернета или файл недоступен — молча пропускаем.
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

  /// Скачивает APK с прогрессом и открывает стандартный установщик Android.
  /// Возвращает null при успехе, строку с ошибкой при неудаче.
  static Future<String?> downloadAndInstall(
    String apkUrl,
    void Function(double progress) onProgress,
    String Function(String) tr,
  ) async {
    try {
      // 1. Запрашиваем разрешение на установку из неизвестных источников
      if (!await Permission.requestInstallPackages.isGranted) {
        final status = await Permission.requestInstallPackages.request();
        if (!status.isGranted) {
          return tr('update_permission_denied');
        }
      }

      // 2. Определяем путь сохранения APK
      final dir = Platform.isAndroid
          ? await getExternalStorageDirectory()
          : await getApplicationDocumentsDirectory();
      final savePath = '${dir!.path}/update.apk';

      // 3. Удаляем старый APK если есть
      final oldFile = File(savePath);
      if (await oldFile.exists()) await oldFile.delete();

      // 4. Скачиваем APK с прогрессом
      final dio = Dio();
      await dio.download(
        apkUrl,
        savePath,
        onReceiveProgress: (received, total) {
          if (total > 0) onProgress(received / total);
        },
        options: Options(
          // Отключаем таймаут для больших файлов
          receiveTimeout: const Duration(minutes: 5),
          sendTimeout: const Duration(seconds: 30),
        ),
      );

      // 5. Проверяем что файл скачался
      final file = File(savePath);
      if (!await file.exists() || await file.length() < 1000) {
        return tr('update_file_corrupted');
      }

      // 6. Открываем стандартный установщик Android
      //    Приложение уйдёт в фон, откроется системный диалог установки.
      //    Данные пользователя сохранятся (при одинаковом keystore).
      final result = await OpenFile.open(savePath, type: 'application/vnd.android.package-archive');
      if (result.type != ResultType.done) {
        return '${tr('update_open_error')}: ${result.message}';
      }

      return null; // успех
    } catch (e) {
      return '${tr('update_download_error')}: $e';
    }
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
  // Состояния экрана
  _DownloadState _state = _DownloadState.idle;
  double _progress = 0.0;
  String? _errorMessage;

  Future<void> _onUpdate() async {
    setState(() {
      _state = _DownloadState.downloading;
      _progress = 0.0;
      _errorMessage = null;
    });

    final error = await UpdateService.downloadAndInstall(
      widget.downloadUrl,
      (p) {
        if (mounted) setState(() => _progress = p);
      },
      widget.tr,
    );

    if (!mounted) return;

    if (error != null) {
      // Ошибка — показываем сообщение, даём попробовать снова
      setState(() {
        _state = _DownloadState.error;
        _errorMessage = error;
      });
    } else {
      // Установщик открылся — ждём пока пользователь установит
      setState(() => _state = _DownloadState.installing);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme   = Theme.of(context);
    final primary = theme.colorScheme.primary;

    return PopScope(
      canPop: false, // Нельзя закрыть кнопкой «назад»
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
                    _state == _DownloadState.installing
                        ? Icons.check_circle_rounded
                        : Icons.system_update_rounded,
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

                // Changelog
                if (widget.changelog != null && widget.changelog!.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: primary.withOpacity(0.07),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: primary.withOpacity(0.2)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.new_releases_rounded, size: 16, color: primary),
                            const SizedBox(width: 6),
                            Text(
                              widget.tr('whats_new'),
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

                // ── Прогресс загрузки ──
                if (_state == _DownloadState.downloading) ...[
                  Column(
                    children: [
                      LinearProgressIndicator(
                        value: _progress > 0 ? _progress : null,
                        borderRadius: BorderRadius.circular(8),
                        minHeight: 8,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _progress > 0
                            ? '${(_progress * 100).toStringAsFixed(0)}%'
                            : widget.tr('connecting'),
                        style: TextStyle(
                          fontSize: 13,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ]

                // ── Установщик открылся, ждём ──
                else if (_state == _DownloadState.installing) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.info_outline, color: Colors.green, size: 18),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            widget.tr('follow_installer'),
                            style: TextStyle(
                              color: Colors.green.shade700,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ]

                // ── Ошибка ──
                else if (_state == _DownloadState.error) ...[
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _errorMessage ?? widget.tr('update_error_unknown'),
                      style: TextStyle(
                        color: theme.colorScheme.onErrorContainer,
                        fontSize: 13,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: FilledButton.icon(
                      icon: const Icon(Icons.refresh_rounded),
                      label: Text(
                        widget.tr('update_retry'),
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      onPressed: _onUpdate,
                    ),
                  ),
                ]

                // ── Начальное состояние: кнопка обновления ──
                else ...[
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: FilledButton.icon(
                      icon: const Icon(Icons.download_rounded),
                      label: Text(
                        widget.tr('update_btn'),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      onPressed: _onUpdate,
                    ),
                  ),
                ],

                const SizedBox(height: 16),

                Text(
                  'v${UpdateService.currentVersion}',
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurfaceVariant.withOpacity(0.5),
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

/// Внутренние состояния экрана обновления
enum _DownloadState {
  idle,        // Начальный экран, кнопка «Обновить»
  downloading, // Идёт загрузка APK
  installing,  // APK скачан, установщик открыт
  error,       // Что-то пошло не так
}
