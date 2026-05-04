// lib/screens/notification_history_screen.dart
import 'package:flutter/material.dart';
import '../models/notification_item.dart';
import '../services/notification_service.dart';
import '../services/language.dart';
import 'main_screen.dart';
import 'schedule_screen.dart';

class NotificationHistoryScreen extends StatefulWidget {
  const NotificationHistoryScreen({super.key});

  @override
  State<NotificationHistoryScreen> createState() =>
      _NotificationHistoryScreenState();
}

class _NotificationHistoryScreenState
    extends State<NotificationHistoryScreen> {

  @override
  void initState() {
    super.initState();
    // Помечаем все прочитанными при открытии экрана
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await NotificationService.markAllRead();
      if (mounted) setState(() {});
    });
  }

  String _relativeTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return LanguageService.tr('notif_just_now');
    if (diff.inMinutes < 60) {
      return '${diff.inMinutes} ${LanguageService.tr('minutes')} ${LanguageService.tr('notif_ago')}';
    }
    if (diff.inHours < 24) {
      return '${diff.inHours} ${LanguageService.tr('notif_hours')} ${LanguageService.tr('notif_ago')}';
    }
    if (diff.inDays < 7) {
      return '${diff.inDays} ${LanguageService.tr('notif_days')} ${LanguageService.tr('notif_ago')}';
    }
    return '${dt.day.toString().padLeft(2,'0')}.${dt.month.toString().padLeft(2,'0')}.${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: LanguageService.currentLang,
      builder: (_, __, ___) {
        final theme   = Theme.of(context);
        final primary = theme.colorScheme.primary;
        final items   = NotificationService.getAll();

        return Scaffold(
          appBar: AppBar(
            leading: Navigator.of(context).canPop()
                ? IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  )
                : null,
            title: Text(
              LanguageService.tr('notifications'),
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 21),
            ),
            centerTitle: false,
            surfaceTintColor: Colors.transparent,
            actions: [
              if (items.isNotEmpty)
                TextButton(
                  onPressed: () async {
                    await NotificationService.clearAll();
                    if (mounted) setState(() {});
                  },
                  child: Text(
                    LanguageService.tr('notif_clear_all'),
                    style: TextStyle(
                      color:      theme.colorScheme.error,
                      fontWeight: FontWeight.w600,
                      fontSize:   13,
                    ),
                  ),
                ),
            ],
          ),
          body: items.isEmpty
              ? _buildEmpty(theme, primary)
              : ListView.builder(
                  padding: EdgeInsets.fromLTRB(
                      16, 8, 16,
                      110 + MediaQuery.of(context).viewPadding.bottom),
                  itemCount: items.length,
                  itemBuilder: (_, i) => _buildCard(items[i], theme),
                ),
        );
      },
    );
  }

  // ── Пустой экран ────────────────────────────────────────────────

  Widget _buildEmpty(ThemeData theme, Color primary) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.notifications_none_rounded,
                size: 64,
                color: theme.colorScheme.onSurfaceVariant.withOpacity(0.3)),
            const SizedBox(height: 16),
            Text(
              LanguageService.tr('notif_empty'),
              style: TextStyle(
                fontSize:   16,
                fontWeight: FontWeight.w600,
                color:      theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );

  // ── Карточка уведомления ────────────────────────────────────────

  Widget _buildCard(NotificationItem item, ThemeData theme) {
    final isDark   = theme.brightness == Brightness.dark;
    final isUnread = !item.isRead;
    final color    = item.color;

    // Типы, по которым есть дата и смысл перейти к расписанию
    final hasDate = item.date != null && (
      item.type == NotificationType.lessonAdded ||
      item.type == NotificationType.lessonCancelled ||
      item.type == NotificationType.lessonRestored
    );

    void handleTap() {
      if (!hasDate) return;
      // Закрываем экран уведомлений до корня
      Navigator.of(context).popUntil((r) => r.isFirst);
      // Переключаемся на вкладку Academic (Schedule) — tabRequest.value=0
      // maps to newIdx=1 (Academic) via _handleTabRequest in main_screen.dart
      MainScreen.tabRequest.value = 0;
      // После кадра запрашиваем мигание нужной даты в календаре
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScheduleScreen.highlightRequest.value = item.date;
      });
    }

    return Dismissible(
      key: Key(item.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin:  const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color:        theme.colorScheme.error.withOpacity(0.85),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.delete_outline_rounded,
            color: Colors.white, size: 24),
      ),
      onDismissed: (_) async {
        await NotificationService.remove(item.id);
        if (mounted) setState(() {});
      },
      child: GestureDetector(
        onTap: hasDate ? handleTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: isUnread
                ? (isDark
                    ? color.withOpacity(0.10)
                    : color.withOpacity(0.06))
                : theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isUnread
                  ? color.withOpacity(0.30)
                  : theme.colorScheme.outline.withOpacity(0.12),
              width: isUnread ? 1.5 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color:      Colors.black.withOpacity(isDark ? 0.15 : 0.05),
                blurRadius: 8,
                offset:     const Offset(0, 2),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Иконка ──────────────────────────────────────
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color.withOpacity(0.13),
                  ),
                  child: Icon(item.icon, size: 20, color: color),
                ),
                const SizedBox(width: 12),

                // ── Текст ────────────────────────────────────────
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              item.title,
                              style: TextStyle(
                                fontWeight: isUnread
                                    ? FontWeight.w800
                                    : FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          if (isUnread) ...[
                            const SizedBox(width: 6),
                            Container(
                              width: 8, height: 8,
                              margin: const EdgeInsets.only(top: 4),
                              decoration: BoxDecoration(
                                color:  color,
                                shape:  BoxShape.circle,
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (item.body.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          item.body,
                          style: TextStyle(
                            fontSize: 13,
                            color: theme.colorScheme.onSurfaceVariant,
                            height: 1.35,
                          ),
                        ),
                      ],
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Text(
                            _relativeTime(item.timestamp),
                            style: TextStyle(
                              fontSize: 11,
                              color: theme.colorScheme.onSurfaceVariant
                                  .withOpacity(0.65),
                            ),
                          ),
                          if (hasDate) ...[
                            const SizedBox(width: 8),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.open_in_new_rounded,
                                    size: 11,
                                    color: color.withOpacity(0.7)),
                                const SizedBox(width: 3),
                                Text(
                                  LanguageService.tr('open_in_schedule'),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: color.withOpacity(0.8),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ],
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
