// lib/services/data_service.dart
//
// Central data coordinator that prevents duplicate network calls when multiple
// screens need the same data (schedule, attendance) simultaneously.
//
// Problem solved:
//   Before: HomeScreen, ScheduleScreen, AttendanceScreen each called
//           Parser.parseSchedule() / Parser.parseAttendance() independently.
//           On first launch all three fired real HTTP requests in parallel.
//
//   After:  Every call to fetchSchedule() / fetchAttendance() joins the single
//           in-flight Future.  If the data is already cached it returns instantly.
//
// Usage:
//   final schedule   = await DataService.instance.fetchSchedule();
//   final attendance = await DataService.instance.fetchAttendance();
//   final dates      = DataService.instance.attendanceDates; // derived set

import 'package:flutter/foundation.dart';
import '../models/lesson.dart';
import '../models/attendance.dart';
import 'api.dart';
import 'parser.dart';

class DataService {
  DataService._();
  static final DataService instance = DataService._();

  // ── Schedule ────────────────────────────────────────────────────
  List<Lesson>?         _schedule;
  Future<List<Lesson>>? _scheduleFuture;

  // ── Attendance ──────────────────────────────────────────────────
  List<Attendance>?         _attendance;
  Future<List<Attendance>>? _attendanceFuture;

  // Derived: set of "dd/mm/yyyy" strings from attendance records.
  // Built once when attendance is loaded; used by ScheduleScreen for
  // vacation-day detection without an extra network call.
  Set<String> _attendanceDates = {};

  // ── Public read-only snapshots (safe to call synchronously) ─────
  List<Lesson>     get cachedSchedule   => _schedule   ?? const [];
  List<Attendance> get cachedAttendance => _attendance ?? const [];
  Set<String>      get attendanceDates  => _attendanceDates;

  // ── Schedule ─────────────────────────────────────────────────────

  /// Returns schedule lessons, fetching them exactly once even if called
  /// concurrently.  Pass [forceRefresh] to bypass both the DataService cache
  /// and the ApiService HTML cache.
  Future<List<Lesson>> fetchSchedule({bool forceRefresh = false}) {
    if (forceRefresh) _invalidateSchedule();
    if (_schedule != null) return Future.value(_schedule!);
    // Deduplication: all concurrent callers share the same in-flight future.
    _scheduleFuture ??= _doFetchSchedule();
    return _scheduleFuture!;
  }

  Future<List<Lesson>> _doFetchSchedule() async {
    try {
      final lessons = await Parser.parseSchedule();
      _schedule = lessons;
      return lessons;
    } catch (e) {
      debugPrint('DataService.fetchSchedule ERROR: $e');
      return [];
    } finally {
      // Always clear the in-flight reference so the next call after
      // completion (success or failure) works correctly.
      _scheduleFuture = null;
    }
  }

  // ── Attendance ────────────────────────────────────────────────────

  /// Returns attendance list, fetching it exactly once even if called
  /// concurrently.  Internally calls [fetchSchedule] first (deduplicated).
  Future<List<Attendance>> fetchAttendance({bool forceRefresh = false}) {
    if (forceRefresh) _invalidateAttendance();
    if (_attendance != null) return Future.value(_attendance!);
    _attendanceFuture ??= _doFetchAttendance();
    return _attendanceFuture!;
  }

  Future<List<Attendance>> _doFetchAttendance() async {
    try {
      // fetchSchedule() is deduplicated — if schedule is already loading,
      // this joins that same future rather than making a new request.
      final schedule   = await fetchSchedule();
      final attendance = await Parser.parseAttendance(schedule);
      _attendance      = attendance;
      _attendanceDates = _extractDates(attendance);
      return attendance;
    } catch (e) {
      debugPrint('DataService.fetchAttendance ERROR: $e');
      return [];
    } finally {
      _attendanceFuture = null;
    }
  }

  /// Extracts real date strings from attendance records for vacation detection.
  static Set<String> _extractDates(List<Attendance> attendance) {
    final dates = <String>{};
    for (final a in attendance) {
      for (final r in a.records) {
        if (r.isDateReal && r.date.isNotEmpty) dates.add(r.date);
      }
    }
    return dates;
  }

  // ── Invalidation ──────────────────────────────────────────────────

  void _invalidateSchedule() {
    _schedule       = null;
    _scheduleFuture = null;
    // Also clear API HTML cache so the next fetch hits the network.
    ApiService.clearHtmlCache();
    // Clear parser-level parse caches too.
    Parser.clearExamCache();
  }

  void _invalidateAttendance() {
    _attendance       = null;
    _attendanceFuture = null;
    _attendanceDates  = {};
  }

  /// Invalidates all cached data.  Call on pull-to-refresh or logout.
  void invalidateAll() {
    _invalidateSchedule();
    _invalidateAttendance();
  }
}
