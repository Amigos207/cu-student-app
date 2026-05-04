// lib/screens/academic_screen.dart
// Wraps ScheduleScreen + ExamScreen under a shared TabBar (Schedule / Exams)
import 'package:flutter/material.dart';
import '../services/language.dart';
import 'schedule_screen.dart';
import 'exam_screen.dart';
import 'main_screen.dart';

class AcademicScreen extends StatefulWidget {
  const AcademicScreen({super.key});

  /// Set to `true` to programmatically jump to the Exams tab.
  /// Consumed (reset to false) by _AcademicScreenState after the jump.
  static final ValueNotifier<bool> examRequest    = ValueNotifier(false);
  static final ValueNotifier<bool> scheduleRequest = ValueNotifier(false);

  @override
  State<AcademicScreen> createState() => _AcademicScreenState();
}

class _AcademicScreenState extends State<AcademicScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;

  // ExamScreen строится только когда пользователь впервые открывает вкладку Exams.
  // До этого момента — SizedBox.shrink(), никаких сетевых запросов.
  bool _examActivated = false;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    // Слушаем только завершение анимации (indexIsChanging = true во ВРЕМЯ
    // анимации, false когда анимация закончилась).
    _tabCtrl.addListener(_onTabSettled);
    AcademicScreen.examRequest.addListener(_handleExamRequest);
    AcademicScreen.scheduleRequest.addListener(_handleScheduleRequest);
    if (AcademicScreen.examRequest.value) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _handleExamRequest());
    }
  }

  void _handleExamRequest() {
    if (!AcademicScreen.examRequest.value) return;
    AcademicScreen.examRequest.value = false;
    if (!mounted) return;
    if (!_examActivated) setState(() => _examActivated = true);
    _tabCtrl.animateTo(1);
  }

  void _handleScheduleRequest() {
    if (!AcademicScreen.scheduleRequest.value) return;
    AcademicScreen.scheduleRequest.value = false;
    if (!mounted) return;
    _tabCtrl.animateTo(0);
  }

  void _onTabSettled() {
    // Срабатывает на каждый кадр анимации — пропускаем
    if (_tabCtrl.indexIsChanging) return;
    // Анимация завершена, пользователь на вкладке _tabCtrl.index
    if (_tabCtrl.index == 1 && !_examActivated) {
      setState(() => _examActivated = true);
    }
  }

  @override
  void dispose() {
    _tabCtrl.removeListener(_onTabSettled);
    AcademicScreen.examRequest.removeListener(_handleExamRequest);
    AcademicScreen.scheduleRequest.removeListener(_handleScheduleRequest);
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
                          LanguageService.tr('schedule'),
                          LanguageService.tr('exams'),
                        ],
                        isDark: isDark,
                        primary: primary,
                      ),
                    ),
                    const NotificationBell(),
                  ],
                ),
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabCtrl,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  ScheduleScreen(),
                  // ExamScreen строится только при первом открытии вкладки
                  _examActivated
                      ? ExamScreen()
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

// ─── Segmented pill-style tab bar ────────────────────────────────

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
    // Обновляем индикатор выбранной вкладки только когда анимация завершена
    widget.controller.addListener(_onTabChanged);
  }

  void _onTabChanged() {
    // Пропускаем промежуточные кадры анимации
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
                // Обновляем локальный индикатор сразу (без ожидания анимации)
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