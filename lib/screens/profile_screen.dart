import 'package:flutter/material.dart';
import '../services/storage.dart';
import '../services/language.dart';
import '../services/api.dart';
import '../services/parser.dart';
import '../services/mock_data.dart';
import 'login_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, String> _info = {};
  bool _loading = true;
  bool _error   = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    if (!mounted) return;
    setState(() { _loading = true; _error = false; });
    try {
      // ── ADMIN SANDBOX ────────────────────────────────────────
      if (MockDataService.isActive) {
        if (mounted) setState(() { _info = MockDataService.mockProfile; _loading = false; });
        return;
      }
      // ────────────────────────────────────────────────────────
      final html = await ApiService.fetchProfileHtml();
      if (html == null || html.isEmpty) {
        if (mounted) setState(() { _loading = false; _error = true; });
        return;
      }
      final info = await Parser.parseProfile(html);
      if (mounted) setState(() { _info = info; _loading = false; });
    } catch (_) {
      if (mounted) setState(() { _loading = false; _error = true; });
    }
  }

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
    return ValueListenableBuilder<String>(
      valueListenable: LanguageService.currentLang,
      builder: (context, _, __) {
        final theme   = Theme.of(context);
        final isDark  = theme.brightness == Brightness.dark;
        final primary = theme.colorScheme.primary;

        final displayName = _info['გვარი, სახელი (ინგლისურად)'] ??
            _info['გვარი,სახელი (ინგლისურად)'] ??
            Storage.getUser() ?? 'Student';
        final georgianName = _info['გვარი,სახელი'] ?? _info['გვარი, სახელი'] ?? '';
        final email = _info['ელ. ფოსტა'] ??
            '${Storage.getUser() ?? ''}@cu.edu.ge';

        return Scaffold(
          body: RefreshIndicator(
            onRefresh: _loadProfile,
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [primary, primary.withOpacity(0.7)],
                      ),
                    ),
                    child: SafeArea(
                      bottom: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
                        child: Column(
                          children: [
                            Container(
                              width: 88, height: 88,
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color: Colors.white.withOpacity(0.5), width: 2),
                              ),
                              child: const Icon(Icons.person_rounded,
                                  size: 48, color: Colors.white),
                            ),
                            const SizedBox(height: 14),
                            Text(displayName,
                              style: const TextStyle(
                                color: Colors.white, fontSize: 22,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (georgianName.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(georgianName,
                                style: TextStyle(
                                    color: Colors.white.withOpacity(0.85),
                                    fontSize: 14),
                              ),
                            ],
                            const SizedBox(height: 4),
                            Text('Caucasus University',
                              style: TextStyle(
                                  color: Colors.white.withOpacity(0.7),
                                  fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    20, 20, 20,
                    32 + MediaQuery.of(context).padding.bottom +
                        kBottomNavigationBarHeight,
                  ),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      if (_loading)
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.all(40),
                            child: CircularProgressIndicator(),
                          ),
                        )
                      else if (_error)
                        _ErrorCard(onRetry: _loadProfile)
                      else ...[
                        _SectionLabel(LanguageService.tr('academic_info')),
                        _InfoCard(isDark: isDark, items: [
                          if (_info['მდგომარეობა']?.isNotEmpty == true)
                            _InfoRow(
                              icon: Icons.verified_rounded,
                              label: LanguageService.tr('status'),
                              value: _info['მდგომარეობა']!,
                              valueColor: _info['მდგომარეობა'] == 'აქტიური'
                                  ? Colors.green : null,
                            ),
                          if (_info['კურსი']?.isNotEmpty == true)
                            _InfoRow(
                              icon: Icons.school_outlined,
                              label: LanguageService.tr('course'),
                              value: _info['კურსი']!,
                            ),
                          if (_info['ჩაბარების წელი']?.isNotEmpty == true)
                            _InfoRow(
                              icon: Icons.calendar_today_outlined,
                              label: LanguageService.tr('enrollment_year'),
                              value: _info['ჩაბარების წელი']!,
                            ),
                          if (_info['გრანტი']?.isNotEmpty == true)
                            _InfoRow(
                              icon: Icons.emoji_events_outlined,
                              label: LanguageService.tr('grant'),
                              value: _info['გრანტი']!,
                            ),
                          if (_info['კონცენტრაცია']?.isNotEmpty == true)
                            _InfoRow(
                              icon: Icons.alt_route_rounded,
                              label: LanguageService.tr('concentration'),
                              value: _info['კონცენტრაცია']!,
                            ),
                          if (_info['რეიტინგი']?.isNotEmpty == true)
                            _InfoRow(
                              icon: Icons.leaderboard_outlined,
                              label: LanguageService.tr('rating'),
                              value: _info['რეიტინგი']!,
                            ),
                        ]),

                        const SizedBox(height: 20),

                        _SectionLabel(LanguageService.tr('personal_info')),
                        _InfoCard(isDark: isDark, items: [
                          if (_info['პირადი ნომერი']?.isNotEmpty == true)
                            _InfoRow(
                              icon: Icons.badge_outlined,
                              label: LanguageService.tr('personal_id'),
                              value: _info['პირადი ნომერი']!,
                            ),
                          if (email.isNotEmpty)
                            _InfoRow(
                              icon: Icons.email_outlined,
                              label: LanguageService.tr('email'),
                              value: email,
                            ),
                          if (_info['პირადი ელ. ფოსტა']?.isNotEmpty == true)
                            _InfoRow(
                              icon: Icons.alternate_email_rounded,
                              label: LanguageService.tr('personal_email'),
                              value: _info['პირადი ელ. ფოსტა']!,
                            ),
                          if (_info['მობილური']?.isNotEmpty == true)
                            _InfoRow(
                              icon: Icons.phone_android_rounded,
                              label: LanguageService.tr('mobile'),
                              value: _info['მობილური']!,
                            ),
                          if (_info['ტელეფონი']?.isNotEmpty == true)
                            _InfoRow(
                              icon: Icons.phone_outlined,
                              label: LanguageService.tr('phone'),
                              value: _info['ტელეფონი']!,
                            ),
                        ]),
                      ],

                      const SizedBox(height: 24),
                      SizedBox(
                        height: 52,
                        child: OutlinedButton.icon(
                          onPressed: () => _logout(context),
                          icon: const Icon(Icons.logout_rounded, size: 20),
                          label: Text(LanguageService.tr('logout')),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                            side: const BorderSide(color: Colors.red, width: 1.5),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16)),
                          ),
                        ),
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

// ─── Helpers ──────────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 4, bottom: 10),
    child: Text(text, style: TextStyle(
      fontSize: 12, fontWeight: FontWeight.w600,
      color: Theme.of(context).colorScheme.primary, letterSpacing: 0.5,
    )),
  );
}

class _ErrorCard extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorCard({required this.onRetry});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 32),
    child: Column(
      children: [
        Icon(Icons.cloud_off_rounded, size: 48,
            color: Theme.of(context).colorScheme.onSurfaceVariant),
        const SizedBox(height: 12),
        Text(LanguageService.tr('no_data'),
            style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
        const SizedBox(height: 16),
        TextButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Retry'),
        ),
      ],
    ),
  );
}

class _InfoCard extends StatelessWidget {
  final List<_InfoRow> items;
  final bool isDark;
  const _InfoCard({required this.items, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final visible = items.where((r) => r.value.isNotEmpty).toList();
    if (visible.isEmpty) return const SizedBox.shrink();
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.15 : 0.06),
            blurRadius: 16, offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: visible.asMap().entries.map((e) {
          final isLast = e.key == visible.length - 1;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
                child: Row(
                  children: [
                    Container(
                      width: 38, height: 38,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(e.value.icon, size: 18,
                          color: Theme.of(context).colorScheme.primary),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(e.value.label,
                              style: TextStyle(fontSize: 11,
                                  color: Theme.of(context)
                                      .colorScheme.onSurfaceVariant)),
                          const SizedBox(height: 2),
                          Text(e.value.value,
                              style: TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w600,
                                color: e.value.valueColor,
                              )),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (!isLast)
                Divider(height: 1, indent: 72,
                    color: Theme.of(context).dividerColor.withOpacity(0.5)),
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
  final Color? valueColor;
  const _InfoRow({
    required this.icon, required this.label,
    required this.value, this.valueColor,
  });
}
