import 'package:flutter/material.dart';
import '../services/storage.dart';
import '../services/language.dart';
import 'login_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  Future<void> _logout(BuildContext context) async {
    await Storage.clearUser();
    if (!context.mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final username = Storage.getUser() ?? 'Student';
    final email    = '$username@cu.edu.ge';

    return ValueListenableBuilder<String>(
      valueListenable: LanguageService.currentLang,
      builder: (context, _, __) {
        final theme   = Theme.of(context);
        final isDark  = theme.brightness == Brightness.dark;
        final primary = theme.colorScheme.primary;

        return Scaffold(
          body: CustomScrollView(
            slivers: [
              // ── Gradient header ─────────────────────────────────
              SliverToBoxAdapter(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        primary,
                        primary.withOpacity(0.7),
                      ],
                    ),
                  ),
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
                      child: Column(
                        children: [
                          // Аватар
                          Container(
                            width: 88, height: 88,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white.withOpacity(0.5), width: 2),
                            ),
                            child: const Icon(Icons.person_rounded, size: 48, color: Colors.white),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            username,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Caucasus University',
                            style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // ── Инфо-карточки ───────────────────────────────────
              SliverPadding(
                padding: const EdgeInsets.all(20),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    _InfoCard(
                      isDark: isDark,
                      items: [
                        _InfoRow(icon: Icons.email_outlined, label: 'Email', value: email),
                        _InfoRow(icon: Icons.badge_outlined, label: LanguageService.tr('status'), value: 'Student'),
                        _InfoRow(icon: Icons.school_outlined, label: LanguageService.tr('university'), value: 'CU'),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Кнопка выхода
                    SizedBox(
                      height: 52,
                      child: OutlinedButton.icon(
                        onPressed: () => _logout(context),
                        icon: const Icon(Icons.logout_rounded, size: 20),
                        label: Text(LanguageService.tr('logout')),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                          side: const BorderSide(color: Colors.red, width: 1.5),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                      ),
                    ),
                  ]),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _InfoCard extends StatelessWidget {
  final List<_InfoRow> items;
  final bool isDark;
  const _InfoCard({required this.items, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.15 : 0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: items.asMap().entries.map((e) {
          final isLast = e.key == items.length - 1;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                child: Row(
                  children: [
                    Container(
                      width: 38, height: 38,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(e.value.icon, size: 18, color: Theme.of(context).colorScheme.primary),
                    ),
                    const SizedBox(width: 14),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(e.value.label,
                            style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                        const SizedBox(height: 2),
                        Text(e.value.value,
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ],
                ),
              ),
              if (!isLast)
                Divider(height: 1, indent: 72, color: Theme.of(context).dividerColor.withOpacity(0.5)),
            ],
          );
        }).toList(),
      ),
    );
  }
}

class _InfoRow {
  final IconData icon;
  final String label;
  final String value;
  const _InfoRow({required this.icon, required this.label, required this.value});
}