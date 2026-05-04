// lib/screens/main_screen.dart
import 'package:flutter/material.dart';

import '../services/language.dart';
import '../services/update_service.dart';
import '../services/notification_service.dart';
import 'home_screen.dart';
import 'academic_screen.dart';
import 'progress_screen.dart';
import '../services/haptic_service.dart';
import 'materials_screen.dart';
import 'more_screen.dart';
import 'notification_history_screen.dart';

// Design constants matching the mockup's dark navy theme
const Color _kNavBg       = Color(0xFF0A1E38);
const Color _kAccentGreen = Color(0xFF22C55E);
const Color _kNotifRed    = Color(0xFFEF4444);

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  /// Programmatic tab switch (0=home, 1=academic, 2=progress, 3=resources, 4=more)
  static final ValueNotifier<int?> tabRequest = ValueNotifier(null);

  @override
  State<MainScreen> createState() => _MainScreenState();
}

enum _Tab { home, academic, progress, resources, more }

class _MainScreenState extends State<MainScreen> {
  _Tab _tab = _Tab.home;
  late final PageController _pageCtrl;

  // Вкладки, посещённые хотя бы раз.
  // Экран строится (и начинает загрузку) только при первом посещении.
  final Set<int> _activated = {0};

  @override
  void initState() {
    super.initState();
    _pageCtrl = PageController(initialPage: _tab.index);
    MainScreen.tabRequest.addListener(_handleTabRequest);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      UpdateService.checkAndPrompt(context, LanguageService.tr);
    });
  }

  @override
  void dispose() {
    MainScreen.tabRequest.removeListener(_handleTabRequest);
    _pageCtrl.dispose();
    super.dispose();
  }

  void _handleTabRequest() {
    final idx = MainScreen.tabRequest.value;
    if (idx == null || !mounted) return;
    MainScreen.tabRequest.value = null;
    int newIdx = idx;
    if (idx == 0) newIdx = 1;
    if (idx == 1) newIdx = 2;
    if (idx == 2) newIdx = 2;
    if (idx == 3) newIdx = 4;
    _onTabTap(newIdx.clamp(0, 4));
  }

  void _onTabTap(int i) {
    setState(() {
      _activated.add(i); // Строим вкладку при первом посещении
      _tab = _Tab.values[i];
    });
    _pageCtrl.jumpToPage(i);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewPadding.bottom;
    final theme = Theme.of(context);

    return ValueListenableBuilder<String>(
      valueListenable: LanguageService.currentLang,
      builder: (_, __, ___) => Scaffold(
        extendBody: true,
        body: PageView(
          controller: _pageCtrl,
          // Свайп включён — пользователь может листать вкладки жестом.
          // _activated обеспечивает lazy-build: экран строится только при первом посещении.
          physics: const ClampingScrollPhysics(),
          onPageChanged: (i) {
            if (mounted) setState(() {
              _activated.add(i);
              _tab = _Tab.values[i];
            });
          },
          children: [
            // _KeepAliveTab сохраняет состояние экрана после первого посещения.
            // Экран строится (initState, загрузка данных) ТОЛЬКО когда
            // пользователь впервые нажимает на вкладку (_activated).
            // До этого — SizedBox.shrink() = нулевая нагрузка.
            _KeepAliveTab(child: _activated.contains(0)
                ? HomeScreen(
                    onAcademicTap: () => _onTabTap(1),
                    onGradesTap: () {
                      _onTabTap(2);
                      ProgressScreen.tabRequest.value = 0;
                    },
                    onAttendanceTap: () {
                      _onTabTap(2);
                      ProgressScreen.tabRequest.value = 1;
                    },
                  )
                : const SizedBox.shrink()),
            _KeepAliveTab(child: _activated.contains(1)
                ? AcademicScreen()
                : const SizedBox.shrink()),
            _KeepAliveTab(child: _activated.contains(2)
                ? ProgressScreen()
                : const SizedBox.shrink()),
            _KeepAliveTab(child: _activated.contains(3)
                ? MaterialsScreen()
                : const SizedBox.shrink()),
            _KeepAliveTab(child: _activated.contains(4)
                ? const MoreScreen()
                : const SizedBox.shrink()),
          ],
        ),
        bottomNavigationBar: _AppNavBar(
          currentTab: _tab,
          onTabTap: _onTabTap,
          bottomInset: bottomInset,
        ),
      ),
    );
  }
}

// ─── Flat Bottom Navigation Bar ──────────────────────────────────

class _AppNavBar extends StatelessWidget {
  final _Tab currentTab;
  final void Function(int) onTabTap;
  final double bottomInset;

  const _AppNavBar({
    required this.currentTab,
    required this.onTabTap,
    required this.bottomInset,
  });

  static const _items = [
    _NavItem(icon: Icons.home_rounded,          label: 'nav_home'),
    _NavItem(icon: Icons.school_rounded,         label: 'nav_academic'),
    _NavItem(icon: Icons.bar_chart_rounded,      label: 'nav_progress'),
    _NavItem(icon: Icons.library_books_rounded,  label: 'nav_resources'),
    _NavItem(icon: Icons.more_horiz_rounded,     label: 'nav_more'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme  = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final bgColor = isDark ? _kNavBg : theme.colorScheme.surface;
    final borderColor = isDark
        ? Colors.white.withOpacity(0.06)
        : theme.colorScheme.outline.withOpacity(0.15);

    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        border: Border(
          top: BorderSide(color: borderColor, width: 1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.35 : 0.08),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 62,
          child: Row(
            children: List.generate(_items.length, (i) {
              final active = currentTab.index == i;
              return Expanded(
                child: _NavItemWidget(
                  item: _items[i],
                  active: active,
                  isDark: isDark,
                  onTap: () => onTabTap(i),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final String label;
  const _NavItem({required this.icon, required this.label});
}

class _NavItemWidget extends StatelessWidget {
  final _NavItem item;
  final bool active;
  final bool isDark;
  final VoidCallback onTap;

  const _NavItemWidget({
    required this.item,
    required this.active,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final activeColor   = _kAccentGreen;
    final inactiveColor = isDark
        ? Colors.white.withOpacity(0.40)
        : Colors.black.withOpacity(0.38);

    return GestureDetector(
      onTap: () {
        HapticService.tabSwitch();
        onTap();
      },
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            width: active ? 46 : 36,
            height: active ? 30 : 24,
            decoration: BoxDecoration(
              color: active
                  ? _kAccentGreen.withOpacity(0.18)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Icon(
                item.icon,
                size: active ? 22 : 20,
                color: active ? activeColor : inactiveColor,
              ),
            ),
          ),
          const SizedBox(height: 3),
          AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 220),
            style: TextStyle(
              fontSize: 10,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              color: active ? activeColor : inactiveColor,
            ),
            child: Text(
              _labelFor(item.label),
              maxLines: 1,
              overflow: TextOverflow.clip,
            ),
          ),
        ],
      ),
    );
  }

  String _labelFor(String key) {
    // simple key lookup
    const labels = <String, String>{
      'nav_home':      'Home',
      'nav_academic':  'Academic',
      'nav_progress':  'Progress',
      'nav_resources': 'Resources',
      'nav_more':      'More',
    };
    // Try language service first; fallback to English
    try {
      final tr = LanguageService.tr(key);
      if (tr != key) return tr;
    } catch (_) {}
    return labels[key] ?? key;
  }
}

// ─── NotificationBell (shared widget) ────────────────────────────

class NotificationBell extends StatelessWidget {
  const NotificationBell({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: NotificationService.unreadCount,
      builder: (ctx, count, _) {
        final scheme = Theme.of(ctx).colorScheme;
        return Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              IconButton(
                icon: Icon(
                  count > 0
                      ? Icons.notifications_rounded
                      : Icons.notifications_outlined,
                  size: 24,
                ),
                onPressed: () => Navigator.push(
                  ctx,
                  MaterialPageRoute(
                      builder: (_) => const NotificationHistoryScreen()),
                ),
              ),
              if (count > 0)
                Positioned(
                  right: 8, top: 8,
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: _kNotifRed,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: scheme.surface, width: 1.5),
                    ),
                    child: Text(
                      count > 99 ? '99+' : '$count',
                      style: const TextStyle(
                        color: Colors.white, fontSize: 9,
                        fontWeight: FontWeight.bold, height: 1,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

// ─── Shared AppBars ───────────────────────────────────────────────

PreferredSizeWidget buildPushedAppBar(
  BuildContext context, {
  required String title,
  VoidCallback? onMenuTap,
}) {
  return AppBar(
    leading: Navigator.of(context).canPop()
        ? IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
            onPressed: () => Navigator.of(context).pop(),
          )
        : (onMenuTap != null
            ? IconButton(
                icon: const Icon(Icons.grid_view_rounded, size: 22),
                onPressed: onMenuTap,
              )
            : null),
    title: Text(title,
        style: const TextStyle(
            fontWeight: FontWeight.w800, fontSize: 21, letterSpacing: -0.3)),
    centerTitle: false,
    surfaceTintColor: Colors.transparent,
    actions: const [NotificationBell()],
  );
}

PreferredSizeWidget buildMainAppBar(
  BuildContext context, {
  required String title,
  VoidCallback? onMenuTap,
  List<Widget> extraActions = const [],
}) {
  return AppBar(
    leading: onMenuTap == null
        ? null
        : IconButton(
            icon: const Icon(Icons.grid_view_rounded, size: 22),
            onPressed: onMenuTap,
          ),
    title: Text(title,
        style: const TextStyle(
            fontWeight: FontWeight.w800, fontSize: 21, letterSpacing: -0.3)),
    centerTitle: false,
    surfaceTintColor: Colors.transparent,
    actions: [...extraActions, const NotificationBell()],
  );
}

// ─── _KeepAliveTab ────────────────────────────────────────────────
//
// Обёртка для вкладок PageView.
// AutomaticKeepAliveClientMixin + wantKeepAlive = true говорит PageView:
// «не уничтожай этот виджет, когда он уходит за пределы viewport».
// В результате состояние экрана (загруженные данные, позиция прокрутки)
// сохраняется при переключении между вкладками.
//
// Когда child = SizedBox.shrink() (вкладка не посещалась), никаких
// HTTP-запросов не происходит — нет состояния для сохранения.
// Когда child = ActualScreen (вкладка открыта впервые), initState
// срабатывает один раз, данные загружаются и больше не перегружаются.

class _KeepAliveTab extends StatefulWidget {
  final Widget child;
  const _KeepAliveTab({required this.child});

  @override
  State<_KeepAliveTab> createState() => _KeepAliveTabState();
}

class _KeepAliveTabState extends State<_KeepAliveTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required by AutomaticKeepAliveClientMixin
    return widget.child;
  }
}