import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';    // ← новый импорт
import '../services/language.dart';
import '../services/update_service.dart';

class BugReportScreen extends StatefulWidget {
  const BugReportScreen({super.key});
  @override
  State<BugReportScreen> createState() => _BugReportScreenState();
}

class _BugReportScreenState extends State<BugReportScreen> {
  final _descCtrl  = TextEditingController();
  final _stepsCtrl = TextEditingController();
  String _category = 'ui';
  bool   _sent     = false;
  bool   _sending  = false;

  // ★ ВПИШИ СВОЙ EMAIL ЗДЕСЬ ★
  static const _devEmail = 'georgiynuralov@gmail.com';

  final _categories = ['ui', 'schedule', 'attendance', 'login', 'other'];

  @override
  void dispose() {
    _descCtrl.dispose();
    _stepsCtrl.dispose();
    super.dispose();
  }

  String _buildReport() {
    final lang = LanguageService.currentLang.value;
    return '''[BUG REPORT — CU Student App v${UpdateService.currentVersion}]
Lang: $lang | Category: $_category

--- Description ---
${_descCtrl.text.trim()}

--- Steps to reproduce ---
${_stepsCtrl.text.trim()}
''';
  }

  Future<void> _send() async {
    if (_descCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(LanguageService.tr('bug_fill_required')),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.orange,
      ));
      return;
    }

    setState(() => _sending = true);

    final report = _buildReport();

    // Формируем mailto: ссылку
    final emailUri = Uri(
      scheme: 'mailto',
      path: _devEmail,
      queryParameters: {
        'subject': '[BUG] CU App v${UpdateService.currentVersion} — $_category',
        'body': report,
      },
    );

    bool opened = false;
    try {
      opened = await launchUrl(emailUri);
    } catch (e) {
      debugPrint('url_launcher error: $e');
    }

    // Если почтового клиента нет — копируем в буфер как запасной вариант
    if (!opened) {
      await Clipboard.setData(ClipboardData(text: report));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(LanguageService.tr('bug_copied')),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.green,
      ));
    }

    if (!mounted) return;
    setState(() { _sending = false; _sent = true; });
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: LanguageService.currentLang,
      builder: (context, _, __) {
        final theme   = Theme.of(context);
        final primary = theme.colorScheme.primary;

        return Scaffold(
          appBar: AppBar(
            title: Text(LanguageService.tr('bug_report'),
                style: const TextStyle(fontWeight: FontWeight.bold)),
            centerTitle: false,
          ),
          body: _sent
              ? _buildSuccessState(primary)
              : _buildForm(theme, primary),
        );
      },
    );
  }

  Widget _buildForm(ThemeData theme, Color primary) {
    final isDark = theme.brightness == Brightness.dark;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Шапка
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Icon(Icons.bug_report_rounded, color: primary, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        LanguageService.tr('bug_intro'),
                        style: TextStyle(
                          fontSize: 14,
                          color: theme.colorScheme.onSurfaceVariant,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 6),
                      // Показываем куда полетит письмо
                      Row(
                        children: [
                          Icon(Icons.send_rounded, size: 12,
                              color: primary.withOpacity(0.7)),
                          const SizedBox(width: 4),
                          Text(
                            _devEmail,
                            style: TextStyle(
                              fontSize: 12,
                              color: primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Категория
          Text(LanguageService.tr('bug_category'),
              style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _categories.map((cat) {
              final sel = _category == cat;
              return FilterChip(
                label: Text(
                  LanguageService.tr('bug_cat_$cat'),
                  style: TextStyle(
                    color: sel
                        ? primary
                        : theme.colorScheme.onSurfaceVariant,
                    fontWeight:
                        sel ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                selected: sel,
                selectedColor: primary.withOpacity(0.15),
                checkmarkColor: primary,
                side: BorderSide(
                    color: sel ? primary : Colors.transparent),
                onSelected: (_) => setState(() => _category = cat),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),

          // Описание
          Text(LanguageService.tr('bug_desc_label'),
              style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface)),
          const SizedBox(height: 8),
          _buildTextField(
            controller: _descCtrl,
            hint: LanguageService.tr('bug_desc_hint'),
            maxLines: 4,
            isDark: isDark,
            primary: primary,
          ),
          const SizedBox(height: 20),

          // Шаги
          Text(LanguageService.tr('bug_steps_label'),
              style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface)),
          const SizedBox(height: 8),
          _buildTextField(
            controller: _stepsCtrl,
            hint: LanguageService.tr('bug_steps_hint'),
            maxLines: 3,
            isDark: isDark,
            primary: primary,
          ),
          const SizedBox(height: 10),
          Text(
            LanguageService.tr('bug_screenshot_hint'),
            style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 28),

          // Кнопка
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton.icon(
              icon: _sending
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2.5))
                  : const Icon(Icons.send_rounded),
              label: Text(
                LanguageService.tr('send_report'),
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold),
              ),
              onPressed: _sending ? null : _send,
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              'v${UpdateService.currentVersion}',
              style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required int maxLines,
    required bool isDark,
    required Color primary,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        fillColor:
            (isDark ? Colors.white : Colors.black).withOpacity(0.04),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: primary, width: 1.5),
        ),
      ),
    );
  }

  Widget _buildSuccessState(Color primary) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80, height: 80,
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle_rounded,
                  color: Colors.green, size: 44),
            ),
            const SizedBox(height: 20),
            Text(
              LanguageService.tr('bug_thanks'),
              style: const TextStyle(
                  fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              LanguageService.tr('bug_thanks_sub'),
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 32),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(LanguageService.tr('back')),
            ),
          ],
        ),
      ),
    );
  }
}
