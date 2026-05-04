// lib/services/local_notification_helper.dart
//
// ═══════════════════════════════════════════════════════════════════
//  NOTIFICATION BUG-FIX CHANGELOG
// ═══════════════════════════════════════════════════════════════════
//  Bug #1 (CRITICAL): tz.local was UTC. tz.setLocalLocation() was
//          never called → all scheduled times were offset by +4h for
//          Tbilisi users. Fixed: flutter_timezone detects the IANA
//          zone; tz.setLocalLocation() is called during init().
//
//  Bug #2 (CRITICAL): scheduleReminder() hardcoded 09:00 regardless
//          of user's selected time. Merged into scheduleReminderAtTime()
//          which always requires explicit hour + minute.
//
//  Bug #5: Past-time silently dropped. Now returns ScheduleResult
//          with a user-visible error message when the computed time
//          is in the past, so the UI can warn the user.
//
//  Bug #6: No explicit Android notification channel creation in init().
//
//  Bug #7 (THIS REFACTOR): exactAllowWhileIdle was used unconditionally.
//          On Android 12+ without SCHEDULE_EXACT_ALARM approval the OS
//          silently drops the alarm.  Now _resolveScheduleMode() checks
//          hasExactAlarmPermission() at schedule-time and falls back to
//          inexactAllowWhileIdle when exact alarms are not permitted.
//          Both scheduleReminderAtTime() and scheduleTestIn5Seconds()
//          use this safe resolution.
//
// ═══════════════════════════════════════════════════════════════════
//
// pubspec.yaml requirements:
//   dependencies:
//     flutter_local_notifications: ^17.2.4
//     flutter_timezone: 5.0.2          ← pin to avoid API breakage
//     timezone: ^0.9.0
//
// android/app/src/main/AndroidManifest.xml (inside <manifest>):
//   <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
//   <uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM"/>
//   <uses-permission android:name="android.permission.USE_EXACT_ALARM"/>
//   <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>
//
// android/app/src/main/AndroidManifest.xml (inside <application>):
//   <receiver android:exported="false"
//     android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver"/>
//   <receiver android:exported="false"
//     android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">
//     <intent-filter>
//       <action android:name="android.intent.action.BOOT_COMPLETED"/>
//       <action android:name="android.intent.action.MY_PACKAGE_REPLACED"/>
//     </intent-filter>
//   </receiver>
//   <receiver android:exported="false"
//     android:name="com.dexterous.flutterlocalnotifications.ActionBroadcastReceiver"/>
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;

// ── Result type ───────────────────────────────────────────────────

enum ScheduleStatus {
  success,      // notification was scheduled successfully
  inThePast,    // computed fire-time is before now → not scheduled
  noPermission, // plugin not ready / notification permission denied
  error,        // unexpected error
}

class ScheduleResult {
  final ScheduleStatus status;

  /// The exact local DateTime the notification will fire (null on failure).
  final DateTime? scheduledAt;
  final String? errorMessage;

  const ScheduleResult._({
    required this.status,
    this.scheduledAt,
    this.errorMessage,
  });

  factory ScheduleResult.success(DateTime at) =>
      ScheduleResult._(status: ScheduleStatus.success, scheduledAt: at);

  factory ScheduleResult.inThePast(DateTime attempted) =>
      ScheduleResult._(
        status:       ScheduleStatus.inThePast,
        scheduledAt:  attempted,
        errorMessage: 'Selected time ${_fmt(attempted)} has already passed.',
      );

  factory ScheduleResult.noPermission() => const ScheduleResult._(
        status:       ScheduleStatus.noPermission,
        errorMessage: 'Notifications permission not granted.',
      );

  factory ScheduleResult.error(Object e) => ScheduleResult._(
        status:       ScheduleStatus.error,
        errorMessage: e.toString(),
      );

  bool get succeeded => status == ScheduleStatus.success;

  static String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/'
      '${d.year} '
      '${d.hour.toString().padLeft(2, '0')}:'
      '${d.minute.toString().padLeft(2, '0')}';

  @override
  String toString() => 'ScheduleResult($status, scheduledAt=$scheduledAt)';
}

// ── Main service class ────────────────────────────────────────────

class LocalNotificationHelper {
  LocalNotificationHelper._();

  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready   = false;

  static const _channelId   = 'cu_reminders';
  static const _channelName = 'Reminders';
  static const _channelDesc = 'Lecture and exam reminders';

  // ── INITIALISATION ───────────────────────────────────────────────

  /// Must be called in `main()` BEFORE `runApp()`.
  ///
  /// Initialises timezone data and sets [tz.local] to the device's
  /// actual IANA timezone via [flutter_timezone].  Without this step
  /// [tz.local] defaults to UTC, causing all scheduled times to be
  /// offset by the device's UTC delta (Bug #1).
  static Future<void> init() async {
    try {
      // ── 1. Load full timezone database ───────────────────────────
      tz_data.initializeTimeZones();

      // ── 2. Detect device IANA timezone & set tz.local ────────────
      // flutter_timezone 5.x returns TimezoneInfo; use .identifier
      // for the IANA name (e.g. "Asia/Tbilisi").
      try {
        final tzInfo   = await FlutterTimezone.getLocalTimezone();
        final deviceTz = tzInfo.identifier;
        tz.setLocalLocation(tz.getLocation(deviceTz));
        debugPrint('[LNH] Device timezone: $deviceTz');
      } catch (tzErr) {
        debugPrint('[LNH] flutter_timezone error ($tzErr) — offset fallback');
        _setLocalByOffset();
      }

      // ── 3. Initialise flutter_local_notifications ─────────────────
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      const ios     = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      await _plugin.initialize(
        const InitializationSettings(android: android, iOS: ios),
      );

      // ── 4. Create Android notification channel (Bug #6) ───────────
      // On Android 8+ channels MUST be created explicitly.  Defining
      // the channel only inside NotificationDetails is insufficient
      // for guaranteed delivery on some OEM ROMs.
      final androidImpl = _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();

      await androidImpl?.createNotificationChannel(
        const AndroidNotificationChannel(
          _channelId,
          _channelName,
          description:     _channelDesc,
          importance:      Importance.high,
          playSound:       true,
          enableVibration: true,
          showBadge:       true,
        ),
      );

      // ── 5. Request runtime permissions ────────────────────────────
      // POST_NOTIFICATIONS — required on Android 13+ (API 33+).
      await androidImpl?.requestNotificationsPermission();
      // SCHEDULE_EXACT_ALARM — required on Android 12+ (API 31+).
      // This opens the system settings page; the user must toggle it.
      await androidImpl?.requestExactAlarmsPermission();

      _ready = true;
      debugPrint('[LNH] init OK  tz.local=${tz.local.name}');
    } catch (e) {
      debugPrint('[LNH] init ERROR: $e');
    }
  }

  /// Fallback: match device UTC offset to a known IANA location.
  static void _setLocalByOffset() {
    try {
      final deviceOffset = DateTime.now().timeZoneOffset;
      final candidates   = tz.timeZoneDatabase.locations.entries
          .where((e) => !e.key.startsWith('Etc/'))
          .where((e) =>
              tz.TZDateTime.now(e.value).timeZoneOffset == deviceOffset)
          .toList();

      if (candidates.isNotEmpty) {
        tz.setLocalLocation(candidates.first.value);
        debugPrint('[LNH] Offset fallback → ${candidates.first.key}');
      } else {
        debugPrint('[LNH] No timezone matched offset $deviceOffset');
      }
    } catch (e) {
      debugPrint('[LNH] _setLocalByOffset ERROR: $e');
    }
  }

  // ── SCHEDULE MODE RESOLUTION (Bug #7 fix) ───────────────────────
  //
  // ROOT CAUSE: exactAllowWhileIdle was used unconditionally.
  //
  // On Android 12+ (API 31+), SCHEDULE_EXACT_ALARM requires explicit
  // user approval via Settings → Apps → Special access → Alarms &
  // reminders.  If NOT granted, zonedSchedule() accepts the call
  // without throwing but the OS silently discards the alarm — the
  // notification never fires and there is no error in the logs.
  //
  // FIX: call hasExactAlarmPermission() before every schedule call:
  //   • GRANTED  → exactAllowWhileIdle   (fires precisely, even in Doze)
  //   • DENIED   → inexactAllowWhileIdle (may be delayed up to ~15 min
  //                                       but WILL eventually fire)
  //
  // inexactAllowWhileIdle is always better than silently nothing.
  // A slightly late reminder is infinitely more useful than no reminder.

  /// Returns the safest [AndroidScheduleMode] available at call time.
  ///
  /// Logs clearly show which mode was chosen and why.  Check logcat
  /// for `[LNH] id=...` lines to confirm which path was taken.
  static Future<AndroidScheduleMode> _resolveScheduleMode(int id) async {
    final hasExact = await hasExactAlarmPermission();

    if (hasExact) {
      debugPrint('[LNH] id=$id  mode=exactAllowWhileIdle '
          '(SCHEDULE_EXACT_ALARM ✓ granted)');
      return AndroidScheduleMode.exactAllowWhileIdle;
    } else {
      debugPrint('[LNH] id=$id  mode=inexactAllowWhileIdle '
          '(SCHEDULE_EXACT_ALARM ✗ not granted — safe fallback active). '
          'To get precise timing: Settings → Apps → Special access → '
          'Alarms & reminders → enable this app.');
      return AndroidScheduleMode.inexactAllowWhileIdle;
    }
  }

  // ── SCHEDULING ───────────────────────────────────────────────────

  /// Schedules a notification to fire at [hour]:[minute] on the day
  /// that is [daysBefore] days before [targetDate].
  ///
  /// Never throws — returns [ScheduleResult].  Check [succeeded] and
  /// surface [inThePast] / [error] states to the user.
  ///
  /// Scheduling mode is resolved safely at call time (Bug #7 fix):
  ///   exact   → if SCHEDULE_EXACT_ALARM is granted  (fires precisely)
  ///   inexact → otherwise                            (fires within ~15 min)
  static Future<ScheduleResult> scheduleReminderAtTime({
    required int      id,
    required String   title,
    required String   body,
    required DateTime targetDate,
    required int      daysBefore,
    required int      hour,
    required int      minute,
  }) async {
    if (!_ready) return ScheduleResult.noPermission();

    try {
      // ── Build target datetime ─────────────────────────────────────
      final notifyDate = targetDate.subtract(Duration(days: daysBefore));
      final scheduleDt = DateTime(
        notifyDate.year,
        notifyDate.month,
        notifyDate.day,
        hour,
        minute,
      );

      // ── Past-time guard ──────────────────────────────────────────
      final now = DateTime.now();
      if (scheduleDt.isBefore(now)) {
        debugPrint('[LNH] id=$id  REJECTED — $scheduleDt is in the past '
            '(now=$now)');
        return ScheduleResult.inThePast(scheduleDt);
      }

      // ── Convert to tz-aware datetime ─────────────────────────────
      // tz.local is the real device timezone set in init() (Bug #1 fix).
      final tzDt = tz.TZDateTime.from(scheduleDt, tz.local);
      debugPrint('[LNH] id=$id  local=$scheduleDt  tzDt=$tzDt  '
          'tz.local=${tz.local.name}');

      // ── Resolve schedule mode (Bug #7 fix) ───────────────────────
      final mode = await _resolveScheduleMode(id);

      // ── Schedule ─────────────────────────────────────────────────
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        tzDt,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: _channelDesc,
            importance:         Importance.high,
            priority:           Priority.high,
            playSound:          true,
            enableVibration:    true,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentSound: true,
          ),
        ),
        androidScheduleMode: mode,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );

      debugPrint('[LNH] ✓ scheduleReminderAtTime  id=$id  '
          'scheduledAt=$scheduleDt  mode=$mode');
      return ScheduleResult.success(scheduleDt);
    } catch (e) {
      debugPrint('[LNH] scheduleReminderAtTime ERROR  id=$id: $e');
      return ScheduleResult.error(e);
    }
  }

  /// Schedules a test notification exactly 5 seconds from now.
  ///
  /// Use from the debug screen to verify the full pipeline without
  /// waiting for a real reminder.  Scheduling mode is resolved the
  /// same way as [scheduleReminderAtTime].
  static Future<ScheduleResult> scheduleTestIn5Seconds() async {
    if (!_ready) return ScheduleResult.noPermission();

    const testId = 999999;

    try {
      final fireAt   = DateTime.now().add(const Duration(seconds: 5));
      final tzFireAt = tz.TZDateTime.from(fireAt, tz.local);
      debugPrint('[LNH] TEST  local=$fireAt  tzDt=$tzFireAt  '
          'tz.local=${tz.local.name}');

      // ── Resolve schedule mode (Bug #7 fix) ───────────────────────
      final mode = await _resolveScheduleMode(testId);

      await _plugin.zonedSchedule(
        testId,
        '🔔 Test notification',
        'If you see this, notifications work! '
        'Fired at ${fireAt.hour.toString().padLeft(2, '0')}:'
        '${fireAt.minute.toString().padLeft(2, '0')}:'
        '${fireAt.second.toString().padLeft(2, '0')} local time.',
        tzFireAt,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: _channelDesc,
            importance:         Importance.max,
            priority:           Priority.max,
            playSound:          true,
            enableVibration:    true,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentSound: true,
            presentBadge: true,
          ),
        ),
        androidScheduleMode: mode,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );

      debugPrint('[LNH] ✓ scheduleTestIn5Seconds  scheduledAt=$fireAt  '
          'mode=$mode');
      return ScheduleResult.success(fireAt);
    } catch (e) {
      debugPrint('[LNH] scheduleTestIn5Seconds ERROR: $e');
      return ScheduleResult.error(e);
    }
  }

  // ── CANCELLATION ─────────────────────────────────────────────────

  /// Cancels a previously scheduled notification by [id].
  static Future<void> cancel(int id) async {
    if (!_ready) return;
    try {
      await _plugin.cancel(id);
      debugPrint('[LNH] Cancelled id=$id');
    } catch (e) {
      debugPrint('[LNH] cancel ERROR id=$id: $e');
    }
  }

  /// Cancels ALL pending notifications.
  static Future<void> cancelAll() async {
    if (!_ready) return;
    try {
      await _plugin.cancelAll();
      debugPrint('[LNH] cancelAll called');
    } catch (e) {
      debugPrint('[LNH] cancelAll ERROR: $e');
    }
  }

  // ── UTILITIES ────────────────────────────────────────────────────

  /// Generates a stable non-negative int notification ID from
  /// [overrideId] and [daysBefore].  Stays within Android's [0, 2³¹−1].
  static int reminderId(String overrideId, int daysBefore) =>
      (overrideId.hashCode ^ daysBefore.hashCode) & 0x7FFFFFFF;

  /// Returns IDs of all currently pending notifications (Android-only).
  static Future<List<int>> pendingIds() async {
    if (!_ready) return [];
    try {
      final p = await _plugin.pendingNotificationRequests();
      return p.map((n) => n.id).toList();
    } catch (_) {
      return [];
    }
  }

  /// Human-readable list of all currently scheduled notifications.
  static Future<String> debugDump() async {
    if (!_ready) return 'Plugin not ready';
    try {
      final p = await _plugin.pendingNotificationRequests();
      if (p.isEmpty) return 'No pending notifications';
      return p
          .map((n) => '  id=${n.id}  title="${n.title}"  body="${n.body}"')
          .join('\n');
    } catch (e) {
      return 'Error: $e';
    }
  }

  /// Returns true if the app is allowed to schedule exact alarms.
  ///
  /// • Android < 12  → always true (no permission required)
  /// • Android 12+   → requires SCHEDULE_EXACT_ALARM or USE_EXACT_ALARM
  /// • iOS           → always true
  static Future<bool> hasExactAlarmPermission() async {
    try {
      final androidImpl = _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      if (androidImpl == null) return true; // iOS
      return await androidImpl.canScheduleExactNotifications() ?? true;
    } catch (_) {
      return true;
    }
  }

  /// Returns true if the app has notification display permission.
  ///
  /// • Android < 13  → always true
  /// • Android 13+   → requires POST_NOTIFICATIONS grant
  /// • iOS           → depends on user grant at first launch
  static Future<bool> hasNotificationPermission() async {
    try {
      final androidImpl = _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      if (androidImpl == null) return true; // iOS
      return await androidImpl.areNotificationsEnabled() ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Runs a full diagnostics check and returns a structured report.
  /// Used by NotificationDebugScreen to display the current state.
  static Future<Map<String, dynamic>> fullDiagnostic() async {
    final notifPerm      = await hasNotificationPermission();
    final exactAlarmPerm = await hasExactAlarmPermission();
    final pending = await _plugin
        .pendingNotificationRequests()
        .then((l) => l.map((n) => {'id': n.id, 'title': n.title}).toList())
        .catchError((_) => <Map<String, dynamic>>[]);

    final nowLocal  = DateTime.now();
    final nowTz     = tz.TZDateTime.now(tz.local);
    final offset    = nowTz.timeZoneOffset;
    final sign      = offset.isNegative ? '-' : '+';
    final offsetStr = '$sign'
        '${offset.abs().inHours.toString().padLeft(2, '0')}:'
        '${(offset.abs().inMinutes % 60).toString().padLeft(2, '0')}';

    return {
      'plugin_ready':      _ready,
      'notification_perm': notifPerm,
      'exact_alarm_perm':  exactAlarmPerm,
      'tz_local':          tz.local.name,
      'utc_offset':        offsetStr,
      'device_time_local': nowLocal.toString(),
      'device_time_tz':    nowTz.toString(),
      'pending_count':     pending.length,
      'pending':           pending,
    };
  }
}