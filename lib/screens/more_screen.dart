// lib/screens/more_screen.dart
// The "More" tab — profile header + menu items matching the mockup
import 'package:flutter/material.dart';
import '../services/storage.dart';
import '../services/language.dart';
import '../services/api.dart';
import '../services/parser.dart';
import 'login_screen.dart';
import 'payment_schedule_screen.dart';
import 'settings_screen.dart';
import 'main_screen.dart';
import 'calendar_screen.dart';
import 'schedule_screen.dart';

class MoreScreen extends StatefulWidget {
  const MoreScreen({super.key});

  @override
  State<MoreScreen> createState() => _MoreScreenState();
}

class _MoreScreenState extends State<MoreScreen> {
  Map<String, String> _info    = {};
  bool                _loading = true;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final html = await ApiService.fetchProfileHtml();
      if (html != null && html.isNotEmpty) {
        final info = await Parser.parseProfile(html);
        if (mounted) setState(() { _info = info; _loading = false; });
      } else {
        if (mounted) setState(() => _loading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _logout() async {
    // Сбрасываем ВСЁ: куки, HTML-кэш, данные парсера, кэш расписания.
    // Иначе при повторном входе другого пользователя старая сессия
    // мешает авторизации и выдаёт "Invalid credentials".
    ApiService.clearSession();
    Parser.clearExamCache();       // сбрасывает parse-кэши расписания/посещаемости
    ScheduleScreen.clearCache();   // _cachedSchedule / _cachedSemesters
    LanguageService.clearCodeMap(); // предметы старого аккаунта
    await Storage.clearUser();
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: LanguageService.currentLang,
      builder: (_, __, ___) {
        final theme   = Theme.of(context);
        final isDark  = theme.brightness == Brightness.dark;
        final primary = theme.colorScheme.primary;

        final displayName = LanguageService.formatPortalName(
            _info['გვარი, სახელი (ინგლისურად)'] ??
            _info['გვარი,სახელი (ინგლისურად)'] ??
            Storage.getUser() ?? 'Student');
        final studentId = _info['პირადი ნომერი'] ?? '';
        final _rawStatus = _info['მდგომარეობა'] ?? '';
        // Translate known Georgian status values; fall back to raw text.
        final status = _rawStatus == 'აქტიური'
            ? LanguageService.tr('student_active')
            : _rawStatus == 'პასიური'
                ? LanguageService.tr('status')  // fallback
                : _rawStatus;

        return Scaffold(
          body: RefreshIndicator(
            color: primary,
            onRefresh: _loadProfile,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                // ── Profile Header ──────────────────────────────
                SliverToBoxAdapter(
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                      child: Row(
                        children: [
                          // Avatar
                          Container(
                            width: 68, height: 68,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  primary.withOpacity(0.8),
                                  primary.withOpacity(0.4),
                                ],
                              ),
                              border: Border.all(
                                color: primary.withOpacity(0.4), width: 2),
                            ),
                            child: const Center(
                              child: Icon(Icons.person_rounded,
                                  size: 36, color: Colors.white),
                            ),
                          ),
                          const SizedBox(width: 16),
                          // Name & ID
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  displayName,
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800,
                                    color: theme.colorScheme.onSurface,
                                    height: 1.2,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (studentId.isNotEmpty) ...[ 
                                  const SizedBox(height: 4),
                                  Text(
                                    'ID: $studentId',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: theme.colorScheme.onSurfaceVariant,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                                if (status.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF22C55E)
                                          .withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      status,
                                      style: const TextStyle(
                                        color: Color(0xFF22C55E),
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const NotificationBell(),
                        ],
                      ),
                    ),
                  ),
                ),

                // ── Menu Items ──────────────────────────────────
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    16, 0, 16,
                    140 + MediaQuery.of(context).viewPadding.bottom,
                  ),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      _MenuSection(isDark: isDark, children: [
                        _MenuItem(
                          icon: Icons.receipt_long_rounded,
                          color: const Color(0xFF22C55E),
                          label: LanguageService.tr('payment_schedule'),
                          onTap: () => Navigator.push(context,
                              MaterialPageRoute(
                                  builder: (_) => PaymentScheduleScreen())),
                          isDark: isDark,
                        ),
                        _MenuDivider(isDark: isDark),
                        _MenuItem(
                          icon: Icons.calendar_month_rounded,
                          color: const Color(0xFFA78BFA),
                          label: LanguageService.tr('calendar'),
                          onTap: () => Navigator.push(context,
                              MaterialPageRoute(
                                  builder: (_) => const CalendarScreen())),
                          isDark: isDark,
                        ),
                        _MenuDivider(isDark: isDark),
                        _MenuItem(
                          icon: Icons.settings_rounded,
                          color: const Color(0xFF4E8DF5),
                          label: LanguageService.tr('settings'),
                          onTap: () => Navigator.push(context,
                              MaterialPageRoute(
                                  builder: (_) => const SettingsScreen())),
                          isDark: isDark,
                        ),
                      ]),

                      const SizedBox(height: 20),

                      // ── Logout Button ────────────────────────
                      _LogoutButton(
                        onTap: _logout,
                        isDark: isDark,
                      ),
                    ]),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ─── Menu Section Card ───────────────────────────────────────────

class _MenuSection extends StatelessWidget {
  final List<Widget> children;
  final bool isDark;

  const _MenuSection({required this.children, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: theme.colorScheme.outline.withOpacity(isDark ? 0.18 : 0.10),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.18 : 0.05),
            blurRadius: 12, offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(children: children),
    );
  }
}

// ─── Menu Item ───────────────────────────────────────────────────

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;
  final bool isDark;

  const _MenuItem({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
          child: Row(
            children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: color.withOpacity(isDark ? 0.18 : 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 20, color: color),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: theme.colorScheme.onSurfaceVariant.withOpacity(0.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MenuDivider extends StatelessWidget {
  final bool isDark;
  const _MenuDivider({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 72),
      child: Divider(
        height: 1,
        color: Theme.of(context).colorScheme.outline
            .withOpacity(isDark ? 0.12 : 0.08),
      ),
    );
  }
}

// ─── Logout Button ───────────────────────────────────────────────

class _LogoutButton extends StatelessWidget {
  final VoidCallback onTap;
  final bool isDark;

  const _LogoutButton({required this.onTap, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.red.withOpacity(isDark ? 0.30 : 0.20),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: Text(
                LanguageService.tr('logout'),
                style: const TextStyle(
                  color: Colors.red,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}