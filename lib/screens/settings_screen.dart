import 'package:flutter/material.dart';
import '../services/storage.dart';
import '../services/language.dart';
import '../services/theme_service.dart';
import '../screens/bug_report_screen.dart';
import '../main.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _lang      = 'English';
  String _theme     = 'light';
  bool   _showBoth  = true;

  final _langs = ['English', 'Русский', 'ქართული'];

  @override
  void initState() {
    super.initState();
    _lang     = Storage.getLang();
    _theme    = Storage.getTheme();
    _showBoth = Storage.getTimeFormat();

    if (!_langs.contains(_lang)) _lang = 'English';
    if (!ThemeService.allThemes.any((t) => t.id == _theme)) _theme = 'light';

    LanguageService.currentLang.value = _lang;
    LanguageService.showBothTimes.value = _showBoth;
  }

  void _setLang(String lang) {
    setState(() => _lang = lang);
    Storage.saveLang(lang);
    LanguageService.currentLang.value = lang;
  }

  void _setTheme(String theme) {
    setState(() => _theme = theme);
    Storage.saveTheme(theme);
    themeNotifier.value = theme;
  }

  void _setTimeFormat(bool val) {
    setState(() => _showBoth = val);
    Storage.saveTimeFormat(val);
    LanguageService.showBothTimes.value = val;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: LanguageService.currentLang,
      builder: (context, _, __) {
        final theme  = Theme.of(context);
        final isDark = theme.brightness == Brightness.dark;

        return Scaffold(
          appBar: AppBar(
            title: Text(LanguageService.tr('settings'),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 22)),
            centerTitle: false,
            surfaceTintColor: Colors.transparent,
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [

              // ── ЯЗЫК ──────────────────────────────────────────────
              _SectionLabel(LanguageService.tr('language')),
              _SettingsCard(
                isDark: isDark,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                  child: Row(
                    children: [
                      Icon(Icons.language_rounded, color: theme.colorScheme.primary, size: 22),
                      const SizedBox(width: 14),
                      Expanded(child: Text(LanguageService.tr('language'),
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500))),
                      DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _lang,
                          borderRadius: BorderRadius.circular(12),
                          items: _langs.map((l) => DropdownMenuItem(
                            value: l,
                            child: Text(l, style: const TextStyle(fontSize: 14)),
                          )).toList(),
                          onChanged: (v) { if (v != null) _setLang(v); },
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // ── ТЕМА ──────────────────────────────────────────────
              _SectionLabel(LanguageService.tr('theme')),
              _SettingsCard(
                isDark: isDark,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: GridView.count(
                    crossAxisCount: 3,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    childAspectRatio: 0.85,
                    children: ThemeService.allThemes.map((t) => _ThemeCard(
                      appTheme: t,
                      selected: _theme == t.id,
                      label: LanguageService.tr(t.labelKey),
                      onTap: () => _setTheme(t.id),
                    )).toList(),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // ── ФОРМАТ ВРЕМЕНИ ────────────────────────────────────
              _SectionLabel(LanguageService.tr('time_format')),
              _SettingsCard(
                isDark: isDark,
                child: SwitchListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                  secondary: Icon(Icons.access_time_rounded, color: theme.colorScheme.primary),
                  title: Text(LanguageService.tr('show_both_times'),
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                  subtitle: Text(
                    _showBoth ? '11:15 – 13:10' : '11:15',
                    style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 12),
                  ),
                  value: _showBoth,
                  onChanged: _setTimeFormat,
                ),
              ),

              const SizedBox(height: 20),

              // ── ОБРАТНАЯ СВЯЗЬ ────────────────────────────────────
              _SectionLabel(LanguageService.tr('feedback')),
              _SettingsCard(
                isDark: isDark,
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                  leading: Container(
                    width: 38, height: 38,
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.bug_report_rounded, color: Colors.red, size: 20),
                  ),
                  title: Text(LanguageService.tr('bug_report'),
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                  subtitle: Text(LanguageService.tr('bug_report_sub'),
                      style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const BugReportScreen()),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // ── О ПРИЛОЖЕНИИ ──────────────────────────────────────
              _SectionLabel('About'),
              _SettingsCard(
                isDark: isDark,
                child: Column(
                  children: [
                    _InfoTile(icon: Icons.info_outline_rounded, title: 'Version', value: '1.0.0'),
                    Divider(height: 1, indent: 56, color: theme.dividerColor.withOpacity(0.5)),
                    _InfoTile(icon: Icons.school_outlined, title: 'Platform', value: 'CU Portal'),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─── КАРТОЧКА ТЕМЫ ───────────────────────────────────────────────────

class _ThemeCard extends StatelessWidget {
  final AppTheme   appTheme;
  final bool       selected;
  final String     label;
  final VoidCallback onTap;
  const _ThemeCard({required this.appTheme, required this.selected,
      required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = appTheme.previewColor;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.12) : Colors.grey.withOpacity(0.07),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: selected ? color : Colors.transparent, width: 2),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Превью-кружок с иконкой
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              child: Icon(appTheme.icon, color: Colors.white, size: 20),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                color: selected ? color : Colors.grey,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (selected) ...[
              const SizedBox(height: 4),
              Icon(Icons.check_circle_rounded, color: color, size: 14),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── ВСПОМОГАТЕЛЬНЫЕ ВИДЖЕТЫ ─────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 4, bottom: 8),
    child: Text(text, style: TextStyle(
      fontSize: 12, fontWeight: FontWeight.w600,
      color: Theme.of(context).colorScheme.primary,
      letterSpacing: 0.5,
    )),
  );
}

class _SettingsCard extends StatelessWidget {
  final Widget child;
  final bool   isDark;
  const _SettingsCard({required this.child, required this.isDark});
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(18),
      boxShadow: [
        BoxShadow(color: Colors.black.withOpacity(isDark ? 0.15 : 0.05),
            blurRadius: 12, offset: const Offset(0, 3)),
      ],
    ),
    child: child,
  );
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String title, value;
  const _InfoTile({required this.icon, required this.title, required this.value});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
    child: Row(
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.onSurfaceVariant),
        const SizedBox(width: 16),
        Text(title, style: const TextStyle(fontSize: 14)),
        const Spacer(),
        Text(value, style: TextStyle(
            fontSize: 14, color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ],
    ),
  );
}