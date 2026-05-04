// lib/screens/progress_screen.dart
// Wraps GradesScreen + AttendanceScreen under a shared TabBar (Grades / Attendance)
import 'package:flutter/material.dart';
import '../services/language.dart';
import '../services/notification_service.dart';
import 'grades_screen.dart';
import 'attendance_screen.dart';
import 'notification_history_screen.dart';

class ProgressScreen extends StatefulWidget {
  const ProgressScreen({super.key});

  /// Установи значение 0 (Grades) или 1 (Attendance) чтобы переключить таб извне.
  static final ValueNotifier<int?> tabRequest = ValueNotifier(null);

  @override
  State<ProgressScreen> createState() => ProgressScreenState();
}

class ProgressScreenState extends State<ProgressScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;

  // AttendanceScreen строится только когда пользователь впервые открывает вкладку
  bool _attendanceActivated = false;

  /// Переключает внутренний таб (0 = Grades, 1 = Attendance).
  /// Вызывается извне через GlobalKey.
  void jumpToTab(int index) {
    if (index == 1 && !_attendanceActivated) {
      setState(() => _attendanceActivated = true);
    }
    _tabCtrl.animateTo(index);
  }

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _tabCtrl.addListener(_onTabSettled);
    ProgressScreen.tabRequest.addListener(_handleTabRequest);
    // Handle the case where tabRequest was set BEFORE this screen was built
    // (mirrors the pattern used in AcademicScreen.initState for examRequest).
    // On real devices the Progress tab may not be constructed in the same frame
    // that fires the postFrameCallback from HomeScreen, so the value is already
    // stored in the notifier by the time initState runs.
    if (ProgressScreen.tabRequest.value != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _handleTabRequest());
    }
  }

  void _handleTabRequest() {
    final idx = ProgressScreen.tabRequest.value;
    if (idx == null) return;
    ProgressScreen.tabRequest.value = null;
    if (!mounted) return;
    jumpToTab(idx);
  }

  void _onTabSettled() {
    if (_tabCtrl.indexIsChanging) return;
    if (_tabCtrl.index == 1 && !_attendanceActivated) {
      setState(() => _attendanceActivated = true);
    }
  }

  @override
  void dispose() {
    _tabCtrl.removeListener(_onTabSettled);
    ProgressScreen.tabRequest.removeListener(_handleTabRequest);
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme   = Theme.of(context);
    final isDark  = theme.brightness == Brightness.dark;
    final primary = theme.colorScheme.primary;

    return ValueListenableBuilder<String>(
      valueListenable: LanguageService.currentLang,
      builder: (_, __, ___) => Scaffold(
        body: Column(
          children: [
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: _SegmentedTabBar(
                        controller: _tabCtrl,
                        tabs: [
                          LanguageService.tr('grades'),
                          LanguageService.tr('attendance'),
                        ],
                        isDark: isDark,
                        primary: primary,
                      ),
                    ),
                    // ── Колокольчик в одну строку с переключателем ──
                    _ProgressNotificationBell(),
                  ],
                ),
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabCtrl,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  GradesScreen(),
                  _attendanceActivated
                      ? AttendanceScreen()
                      : const Center(child: SizedBox.shrink()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SegmentedTabBar extends StatefulWidget {
  final TabController controller;
  final List<String> tabs;
  final bool isDark;
  final Color primary;

  const _SegmentedTabBar({
    required this.controller,
    required this.tabs,
    required this.isDark,
    required this.primary,
  });

  @override
  State<_SegmentedTabBar> createState() => _SegmentedTabBarState();
}

class _SegmentedTabBarState extends State<_SegmentedTabBar> {
  int _current = 0;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTabChanged);
  }

  void _onTabChanged() {
    if (widget.controller.indexIsChanging) return;
    if (mounted && _current != widget.controller.index) {
      setState(() => _current = widget.controller.index);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTabChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = widget.isDark
        ? Colors.white.withOpacity(0.07)
        : Colors.black.withOpacity(0.06);

    return Container(
      height: 42,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: List.generate(widget.tabs.length, (i) {
          final active = _current == i;
          return Expanded(
            child: GestureDetector(
              onTap: () {
                widget.controller.animateTo(i);
                if (mounted) setState(() => _current = i);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                decoration: BoxDecoration(
                  color: active
                      ? (widget.isDark
                          ? const Color(0xFF1A3A6E)
                          : Colors.white)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(11),
                  boxShadow: active
                      ? [BoxShadow(
                          color: Colors.black.withOpacity(0.12),
                          blurRadius: 6, offset: const Offset(0, 2))]
                      : null,
                ),
                child: Center(
                  child: Text(
                    widget.tabs[i],
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                      color: active
                          ? widget.primary
                          : (widget.isDark
                              ? Colors.white54
                              : Colors.black45),
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ── Колокольчик уведомлений ───────────────────────────────────────
// Отдельный виджет чтобы не тащить зависимость main_screen.dart

class _ProgressNotificationBell extends StatelessWidget {
  const _ProgressNotificationBell();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: NotificationService.unreadCount,
      builder: (ctx, count, _) {
        final scheme = Theme.of(ctx).colorScheme;
        return Stack(
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
                  constraints:
                      const BoxConstraints(minWidth: 16, minHeight: 16),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: scheme.surface, width: 1.5),
                  ),
                  child: Text(
                    count > 99 ? '99+' : '$count',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      height: 1,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}