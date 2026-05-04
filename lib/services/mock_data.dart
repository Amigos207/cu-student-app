// lib/services/mock_data.dart
//
// ════════════════════════════════════════════════════════════════════════════
//  ADMIN SANDBOX — полностью изолированные тестовые данные
//  Активируется ТОЛЬКО когда Storage.getUser() == 'admin'.
//  Реальные пользователи никогда не заходят в этот файл.
// ════════════════════════════════════════════════════════════════════════════
//
//  PUBLIC API
//  ──────────
//  MockDataService.isActive              → bool   — быстрая проверка
//  MockDataService.mockProfile           → Map    — данные профиля
//  MockDataService.mockSemesters         → List<Semester>
//  MockDataService.mockSchedule          → List<Lesson>
//  MockDataService.buildMockAttendance() → List<Attendance>
//  MockDataService.buildMockGrades()     → (List<GradeSubject>, GpaStats?)
//  MockDataService.buildMockSubjectDetail(cxrId) → SubjectDetail
//  MockDataService.buildMockExams({semId})
//       → (List<ExamSemester>, List<ExamEntry>)
//  MockDataService.buildMockPayment()
//       → (DebtStatus?, List<PaymentSemester>)
//  MockDataService.buildMockMaterialsList()
//       → ({List<Semester> semesters, List<CourseSubject> subjects})
//  MockDataService.buildMockMaterialDetails(payload)
//       → ({String courseTitle, List<LectureGroup> groups})
//  MockDataService.seedNotificationsIfNeeded() → Future<void>
//  MockDataService.resetSandbox()              → Future<void>

import 'package:flutter/foundation.dart';
import '../models/lesson.dart';
import '../models/attendance.dart';
import '../models/semester.dart';
import '../models/grade.dart';
import '../models/exam_entry.dart';
import '../models/payment.dart';
import '../models/course_material.dart';
import '../models/notification_item.dart';
import 'storage.dart';
import 'notification_service.dart';

class MockDataService {
  MockDataService._();

  // ── АКТИВАЦИЯ ─────────────────────────────────────────────────
  /// true → текущий пользователь — тестовый admin-аккаунт
  static bool get isActive => Storage.getUser() == 'admin';

  // ══════════════════════════════════════════════════════════════
  // 1. ПРОФИЛЬ
  // ══════════════════════════════════════════════════════════════

  static const Map<String, String> mockProfile = {
    'name':        'Sandbox Admin Testov',
    'faculty':     'School of Computer Science and Engineering',
    'program':     'BS in Computer Science',
    'year':        '3',
    'studentId':   'CU-2024-0042',
    'email':       'admin@cu.edu.ge',
    'phone':       '+995 555 000 001',
    'status':      'Active',
  };

  // ══════════════════════════════════════════════════════════════
  // 2. СЕМЕСТРЫ
  // ══════════════════════════════════════════════════════════════

  static final List<Semester> mockSemesters = const [
    Semester(id: 84, name: '2024 შემოდგომის სემესტრი'),
    Semester(id: 85, name: '2025 გაზაფხულის სემესტრი'),
    Semester(id: 86, name: '2025 შემოდგომის სემესტრი'),
    Semester(id: 87, name: '2026 გაზაფხულის სემესტრი'),
  ];

  // ══════════════════════════════════════════════════════════════
  // 3. РАСПИСАНИЕ
  // ══════════════════════════════════════════════════════════════

  static final List<Lesson> mockSchedule = [
    // Monday — heavy day (5 lectures)
    Lesson(code: 'CSC 1101', name: 'Introduction to Programming',
        teacher: 'Giorgi Beridze', day: 'Monday', time: '09:00-10:50', room: 'A-101'),
    Lesson(code: 'MATH 2201', name: 'Calculus II',
        teacher: 'Nino Kvaratskhelia', day: 'Monday', time: '11:15-13:05', room: 'B-12'),
    Lesson(code: 'CSC 2305', name: 'Data Structures and Algorithms',
        teacher: 'Lasha Mchedlishvili', day: 'Monday', time: '13:30-15:20', room: 'A-203'),
    Lesson(code: 'ENGL 0009E', name: 'Academic Writing for Engineers',
        teacher: 'Sarah Johnson', day: 'Monday', time: '15:45-17:35', room: 'C-30'),
    Lesson(code: 'CSC 3401', name: 'Operating Systems',
        teacher: 'Davit Gogichaishvili', day: 'Monday', time: '18:00-19:50', room: 'B-07'),

    // Tuesday — light day (1 lecture)
    Lesson(code: 'PHYS 1102', name: 'Advanced Physics: Electromagnetism and Optics',
        teacher: 'Tamar Simonishvili', day: 'Tuesday', time: '10:00-11:50', room: 'C-12'),

    // Wednesday — medium day (3 lectures)
    Lesson(code: 'CSC 2305', name: 'Data Structures and Algorithms',
        teacher: 'Lasha Mchedlishvili', day: 'Wednesday', time: '09:00-10:50', room: 'A-104'),
    Lesson(code: 'MATH 2202', name: 'Linear Algebra',
        teacher: 'Nino Kvaratskhelia', day: 'Wednesday', time: '11:15-13:05', room: 'B-12'),
    Lesson(code: 'CSC 3501', name: 'Database Systems',
        teacher: 'Mariam Janelidze', day: 'Wednesday', time: '13:30-15:20', room: 'A-101'),

    // Thursday — medium day (3 lectures)
    Lesson(code: 'CSC 3401', name: 'Operating Systems',
        teacher: 'Davit Gogichaishvili', day: 'Thursday', time: '09:00-10:50', room: 'B-07'),
    Lesson(code: 'CSC 4601', name: 'Machine Learning',
        teacher: 'Giorgi Beridze', day: 'Thursday', time: '11:15-13:05', room: 'A-203'),
    Lesson(code: 'ENGL 0009E', name: 'Academic Writing for Engineers',
        teacher: 'Sarah Johnson', day: 'Thursday', time: '13:30-15:20', room: 'C-30'),

    // Friday — heavy day (6 lectures — UI stress test)
    Lesson(code: 'CSC 1101', name: 'Introduction to Programming',
        teacher: 'Giorgi Beridze', day: 'Friday', time: '08:00-09:50', room: 'A-101'),
    Lesson(code: 'PHYS 1102', name: 'Advanced Physics: Electromagnetism and Optics',
        teacher: 'Tamar Simonishvili', day: 'Friday', time: '10:00-11:50', room: 'C-12'),
    Lesson(code: 'CSC 3501', name: 'Database Systems',
        teacher: 'Mariam Janelidze', day: 'Friday', time: '12:00-13:50', room: 'A-101'),
    Lesson(code: 'MATH 2201', name: 'Calculus II',
        teacher: 'Nino Kvaratskhelia', day: 'Friday', time: '14:00-15:50', room: 'B-12'),
    Lesson(code: 'CSC 4601', name: 'Machine Learning',
        teacher: 'Giorgi Beridze', day: 'Friday', time: '16:00-17:50', room: 'A-203'),
    Lesson(code: 'CSC 4701',
        name: 'Advanced Topics in Distributed Systems and Cloud Architecture',
        teacher: 'Davit Gogichaishvili', day: 'Friday', time: '18:00-19:50', room: 'B-07'),

    // Saturday — 2 lectures
    Lesson(code: 'MATH 2202', name: 'Linear Algebra',
        teacher: 'Nino Kvaratskhelia', day: 'Saturday', time: '10:00-11:50', room: 'B-12'),
    Lesson(code: 'CSC 4601', name: 'Machine Learning',
        teacher: 'Giorgi Beridze', day: 'Saturday', time: '12:00-13:50', room: 'A-203'),
    // Sunday — empty (no lessons → tests empty-day UI)
  ];

  // ══════════════════════════════════════════════════════════════
  // 4. ПОСЕЩАЕМОСТЬ  (все граничные случаи)
  // ══════════════════════════════════════════════════════════════

  static List<Attendance> buildMockAttendance() {
    final now = DateTime.now();

    Attendance _make({
      required String subject,
      required String teacher,
      required int total,
      required int attended,
      required int absent,
    }) {
      final records = <LectureRecord>[];
      for (int i = 0; i < total; i++) {
        final date = now.subtract(Duration(days: (total - i) * 7));
        final isAbsent    = i < absent;
        final isConfirmed = !isAbsent;
        records.add(LectureRecord(
          date:        '${date.day.toString().padLeft(2,'0')}/'
                       '${date.month.toString().padLeft(2,'0')}/${date.year}',
          isDateReal:  true,
          isPast:      true,
          isAbsent:    isAbsent,
          isConfirmed: isConfirmed,
          isPending:   false,
          checks:      [isConfirmed],
        ));
      }
      return Attendance(
        subject:          subject,
        teacher:          teacher,
        totalLectures:    total,
        passedLectures:   total,
        attendedLectures: attended,
        pendingLectures:  0,
        records:          records,
      );
    }

    return [
      // 100%
      _make(subject: 'Introduction to Programming',
            teacher: 'Giorgi Beridze',    total: 14, attended: 14, absent: 0),
      // ~95%
      _make(subject: 'Calculus II',
            teacher: 'Nino Kvaratskhelia', total: 20, attended: 19, absent: 1),
      // ~78%
      _make(subject: 'Data Structures and Algorithms',
            teacher: 'Lasha Mchedlishvili', total: 18, attended: 14, absent: 4),
      // ~61%
      _make(subject: 'Academic Writing for Engineers',
            teacher: 'Sarah Johnson',       total: 18, attended: 11, absent: 7),
      // ~43%  ← warning zone
      _make(subject: 'Operating Systems',
            teacher: 'Davit Gogichaishvili', total: 14, attended: 6, absent: 8),
      // ~12%  ← critical / fail
      _make(subject: 'Advanced Physics: Electromagnetism and Optics',
            teacher: 'Tamar Simonishvili',  total: 16, attended: 2, absent: 14),
      // 0%    ← edge case
      _make(subject: 'Linear Algebra',
            teacher: 'Nino Kvaratskhelia', total: 12, attended: 0, absent: 12),
      // 100% but only 1 lecture total
      _make(subject: 'Database Systems',
            teacher: 'Mariam Janelidze',   total: 1,  attended: 1, absent: 0),
    ];
  }

  // ══════════════════════════════════════════════════════════════
  // 5. ОЦЕНКИ / GPA
  // ══════════════════════════════════════════════════════════════

  static (List<GradeSubject>, GpaStats?) buildMockGrades() {
    final subjects = <GradeSubject>[
      // Excellent — A+
      GradeSubject(cxrId: 'mock_001', code: 'CSC 1101',
          name: 'შესავალი პროგრამირებაში',
          credits: 6, percentage: 97.0, letter: 'A+', qualityPoints: 4.0),
      // Excellent — A
      GradeSubject(cxrId: 'mock_002', code: 'MATH 2202',
          name: 'წრფივი ალგებრა',
          credits: 5, percentage: 92.5, letter: 'A',  qualityPoints: 4.0),
      // B+
      GradeSubject(cxrId: 'mock_003', code: 'CSC 2305',
          name: 'მონაცემთა სტრუქტურები და ალგორითმები',
          credits: 6, percentage: 88.0, letter: 'B+', qualityPoints: 3.5),
      // B
      GradeSubject(cxrId: 'mock_004', code: 'MATH 2201',
          name: 'მათემატიკური ანალიზი II',
          credits: 5, percentage: 83.0, letter: 'B',  qualityPoints: 3.0),
      // C
      GradeSubject(cxrId: 'mock_005', code: 'ENGL 0009E',
          name: 'აკადემიური წერა ინჟინრებისთვის',
          credits: 4, percentage: 76.0, letter: 'C',  qualityPoints: 2.0),
      // C–
      GradeSubject(cxrId: 'mock_006', code: 'PHYS 1102',
          name: 'მოწინავე ფიზიკა: ელექტრომაგნეტიზმი და ოპტიკა',
          credits: 5, percentage: 71.5, letter: 'C-', qualityPoints: 1.7),
      // D
      GradeSubject(cxrId: 'mock_007', code: 'CSC 3401',
          name: 'ოპერაციული სისტემები',
          credits: 6, percentage: 62.0, letter: 'D',  qualityPoints: 1.0),
      // F — failed
      GradeSubject(cxrId: 'mock_008', code: 'CSC 4601',
          name: 'მანქანური სწავლება',
          credits: 6, percentage: 44.0, letter: 'F',  qualityPoints: 0.0),
      // FX — retake needed
      GradeSubject(cxrId: 'mock_009', code: 'CSC 3501',
          name: 'მონაცემთა ბაზების სისტემები',
          credits: 5, percentage: 38.0, letter: 'FX', qualityPoints: 0.0),
      // No grade yet — edge case
      GradeSubject(cxrId: 'mock_010', code: 'CSC 4701',
          name: 'Advanced Topics in Distributed Systems and Cloud Architecture',
          credits: 6, percentage: 0.0,  letter: '',   qualityPoints: 0.0),
    ];

    final gradedSubjects = subjects.where((s) => s.letter.isNotEmpty).toList();
    final totalCredits = gradedSubjects.fold(0.0, (a, s) => a + s.credits);
    final totalQp      = gradedSubjects.fold(0.0,
        (a, s) => a + s.qualityPoints * s.credits);
    final annualGpa    = totalCredits > 0 ? totalQp / totalCredits : 0.0;
    final annualPct    = gradedSubjects.isEmpty
        ? 0.0
        : gradedSubjects.fold(0.0, (a, s) => a + s.percentage) /
          gradedSubjects.length;

    final stats = GpaStats(
      annualSubjects:      gradedSubjects.length,
      annualCredits:       totalCredits,
      annualPercentage:    double.parse(annualPct.toStringAsFixed(2)),
      annualGpa:           double.parse(annualGpa.toStringAsFixed(2)),
      cumulativeSubjects:  gradedSubjects.length + 12,
      cumulativeCredits:   totalCredits + 60,
      cumulativePercentage: 79.40,
      cumulativeGpa:       2.89,
    );

    return (List<GradeSubject>.from(subjects), stats);
  }

  // ══════════════════════════════════════════════════════════════
  // 6. ДЕТАЛИ ПРЕДМЕТА (для модального окна оценок)
  // ══════════════════════════════════════════════════════════════

  static SubjectDetail buildMockSubjectDetail(String cxrId) {
    switch (cxrId) {
      case 'mock_001': // A+ subject — all scores
        return SubjectDetail(
          code: 'CSC 1101', teacher: 'Giorgi Beridze',
          exams: [
            SubjectExam(date: '2026-01-20', type: 'Written work (Drop method)', maxScore: 10, score: 9.5),
            SubjectExam(date: '2026-02-14', type: 'Written work (Drop method)', maxScore: 10, score: 10.0),
            SubjectExam(date: '2026-03-05', type: 'Midterm Examination', maxScore: 30, score: 28.5),
            SubjectExam(date: '2026-04-18', type: 'Written work (Drop method)', maxScore: 10, score: 9.8),
            SubjectExam(date: '2026-05-10', type: 'Final Examination', maxScore: 40, score: 39.2),
          ],
          interimTotal: 59.8, maxEntered: 100, studentTotal: 97.0,
          finalPercentage: 97.0, finalGrade: 'A+',
        );
      case 'mock_008': // F — failed subject
        return SubjectDetail(
          code: 'CSC 4601', teacher: 'Giorgi Beridze',
          exams: [
            SubjectExam(date: '2026-01-28', type: 'Quiz', maxScore: 10, score: 3.0),
            SubjectExam(date: '2026-03-10', type: 'Midterm Examination', maxScore: 30, score: 11.0),
            SubjectExam(date: '2026-05-15', type: 'Final Examination', maxScore: 40, score: null),
          ],
          interimTotal: 14.0, maxEntered: 60, studentTotal: 14.0,
          finalPercentage: 44.0, finalGrade: 'F',
        );
      case 'mock_009': // FX — retake
        return SubjectDetail(
          code: 'CSC 3501', teacher: 'Mariam Janelidze',
          exams: [
            SubjectExam(date: '2026-02-03', type: 'Written work (Drop method)', maxScore: 10, score: 2.0),
            SubjectExam(date: '2026-03-17', type: 'Midterm Examination', maxScore: 30, score: 9.0),
            SubjectExam(date: '2026-05-20', type: 'Final Examination (FX)', maxScore: 40, score: null),
          ],
          interimTotal: 11.0, maxEntered: 60, studentTotal: 11.0,
          finalPercentage: 38.0, finalGrade: 'FX',
        );
      case 'mock_010': // No grade yet
        return SubjectDetail(
          code: 'CSC 4701', teacher: 'Davit Gogichaishvili',
          exams: [
            SubjectExam(date: '2026-03-01', type: 'Written work (Drop method)', maxScore: 10, score: null),
            SubjectExam(date: '2026-04-12', type: 'Midterm Examination', maxScore: 30, score: null),
            SubjectExam(date: '2026-06-01', type: 'Final Examination', maxScore: 40, score: null),
          ],
          interimTotal: 0, maxEntered: 0, studentTotal: 0,
          finalPercentage: 0.0, finalGrade: '',
        );
      default: // Generic mid-range subject
        final pct = {'mock_003': 88.0, 'mock_004': 83.0,
                     'mock_005': 76.0, 'mock_006': 71.5, 'mock_007': 62.0}
            [cxrId] ?? 80.0;
        final letter = pct >= 91 ? 'A' : pct >= 81 ? 'B+' : pct >= 71
            ? 'B' : pct >= 61 ? 'C' : 'D';
        return SubjectDetail(
          code: cxrId, teacher: 'Mock Teacher',
          exams: [
            SubjectExam(date: '2026-02-10', type: 'Written work (Drop method)', maxScore: 10, score: pct * 0.10),
            SubjectExam(date: '2026-03-20', type: 'Midterm Examination', maxScore: 30, score: pct * 0.30),
            SubjectExam(date: '2026-05-12', type: 'Final Examination', maxScore: 40, score: pct * 0.40),
          ],
          interimTotal: pct * 0.60, maxEntered: 100, studentTotal: pct,
          finalPercentage: pct, finalGrade: letter,
        );
    }
  }

  // ══════════════════════════════════════════════════════════════
  // 7. РАСПИСАНИЕ ЭКЗАМЕНОВ
  // ══════════════════════════════════════════════════════════════

  static (List<ExamSemester>, List<ExamEntry>) buildMockExams({int? semId}) {
    final now      = DateTime.now();
    final tomorrow = now.add(const Duration(days: 1));

    const semesters = [
      ExamSemester(id: 85, name: '2025 გაზაფხულის სემესტრი'),
      ExamSemester(id: 86, name: '2025 შემოდგომის სემესტრი'),
      ExamSemester(id: 87, name: '2026 გაზაფხულის სემესტრი'),
    ];

    final targetSem = semId ?? 87;

    final exams = <ExamEntry>[];

    if (targetSem == 87) {
      exams.addAll([
        // Exam tomorrow — countdown test
        ExamEntry(
          code: 'ENGL 0009E', nameKa: 'აკადემიური წერა', nameEn: 'Academic Writing for Engineers',
          teacher: 'Sarah Johnson', semId: 87,
          date: DateTime(tomorrow.year, tomorrow.month, tomorrow.day),
          time: '09:00', room: 'C-12',
        ),
        // In 3 days — Quiz
        ExamEntry(
          code: 'CSC 1101', nameKa: 'შესავალი პროგრამირებაში', nameEn: 'Introduction to Programming',
          teacher: 'Giorgi Beridze', semId: 87,
          date: now.add(const Duration(days: 3)),
          time: '11:00', room: 'A-101',
        ),
        // Midterm in 7 days
        ExamEntry(
          code: 'MATH 2201', nameKa: 'მათემატიკური ანალიზი II', nameEn: 'Calculus II',
          teacher: 'Nino Kvaratskhelia', semId: 87,
          date: now.add(const Duration(days: 7)),
          time: '14:00', room: 'B-12',
        ),
        // Final in 15 days
        ExamEntry(
          code: 'CSC 3501', nameKa: 'მონაცემთა ბაზების სისტემები', nameEn: 'Database Systems',
          teacher: 'Mariam Janelidze', semId: 87,
          date: now.add(const Duration(days: 15)),
          time: '15:00', room: 'A-101',
        ),
        // Oral exam in 10 days
        ExamEntry(
          code: 'PHYS 1102', nameKa: 'მოწინავე ფიზიკა', nameEn: 'Advanced Physics: Electromagnetism and Optics',
          teacher: 'Tamar Simonishvili', semId: 87,
          date: now.add(const Duration(days: 10)),
          time: '10:00', room: 'C-30',
        ),
        // FX Retake in 21 days
        ExamEntry(
          code: 'CSC 4601', nameKa: 'მანქანური სწავლება', nameEn: 'Machine Learning',
          teacher: 'Giorgi Beridze', semId: 87,
          date: now.add(const Duration(days: 21)),
          time: '13:00', room: 'B-07',
        ),
        // Practical exam in 12 days — long name for UI stress
        ExamEntry(
          code: 'CSC 4701',
          nameKa: 'განაწილებული სისტემები',
          nameEn: 'Advanced Topics in Distributed Systems and Cloud Architecture',
          teacher: 'Davit Gogichaishvili', semId: 87,
          date: now.add(const Duration(days: 12)),
          time: '16:00', room: 'A-203',
        ),
        // Past exam — 5 days ago
        ExamEntry(
          code: 'CSC 2305', nameKa: 'მონაცემთა სტრუქტურები', nameEn: 'Data Structures and Algorithms',
          teacher: 'Lasha Mchedlishvili', semId: 87,
          date: now.subtract(const Duration(days: 5)),
          time: '09:00', room: 'A-104',
        ),
        // Past exam — 14 days ago
        ExamEntry(
          code: 'MATH 2202', nameKa: 'წრფივი ალგებრა', nameEn: 'Linear Algebra',
          teacher: 'Nino Kvaratskhelia', semId: 87,
          date: now.subtract(const Duration(days: 14)),
          time: '11:00', room: 'B-12',
        ),
      ]);
    } else if (targetSem == 86) {
      exams.addAll([
        ExamEntry(
          code: 'CSC 1101', nameKa: 'შესავალი პროგრამირებაში', nameEn: 'Introduction to Programming',
          teacher: 'Giorgi Beridze', semId: 86,
          date: DateTime(2025, 12, 10), time: '10:00', room: 'A-101',
        ),
        ExamEntry(
          code: 'MATH 2201', nameKa: 'მათემატიკური ანალიზი II', nameEn: 'Calculus II',
          teacher: 'Nino Kvaratskhelia', semId: 86,
          date: DateTime(2025, 12, 15), time: '14:00', room: 'B-12',
        ),
      ]);
    }

    return (List<ExamSemester>.from(semesters), exams);
  }

  // ══════════════════════════════════════════════════════════════
  // 8. ФИНАНСЫ / ОПЛАТА
  // ══════════════════════════════════════════════════════════════

  static (DebtStatus?, List<PaymentSemester>) buildMockPayment() {
    const debtStatus = DebtStatus(noDebt: false, rawText: 'ვალი: 1,250.00 ₾');

    final semesters = [
      // Current — partial payment / overdue debt
      PaymentSemester(
        name: '2026 გაზაფხულის სემესტრი',
        totalAmount: 5000.00,
        examFee: 0.00,
        penalty: 75.00,
        paidAmount: 3750.00,
        debtAmount: 1250.00,
        transactions: [
          PaymentTransaction(dateTime: '2026-01-15 10:22:00', amount: 2500.00),
          PaymentTransaction(dateTime: '2026-03-01 14:05:00', amount: 1250.00),
        ],
      ),
      // Previous — fully paid
      PaymentSemester(
        name: '2025 შემოდგომის სემესტრი',
        totalAmount: 5000.00,
        examFee: 150.00,
        penalty: 0.00,
        paidAmount: 5150.00,
        debtAmount: 0.00,
        transactions: [
          PaymentTransaction(dateTime: '2025-09-05 15:13:27', amount: 3050.00),
          PaymentTransaction(dateTime: '2025-10-20 09:44:12', amount: 2100.00),
        ],
      ),
      // Older — fully paid
      PaymentSemester(
        name: '2025 გაზაფხულის სემესტრი',
        totalAmount: 4500.00,
        examFee: 100.00,
        penalty: 0.00,
        paidAmount: 4600.00,
        debtAmount: 0.00,
        transactions: [
          PaymentTransaction(dateTime: '2025-01-10 11:00:00', amount: 4600.00),
        ],
      ),
      // Very old — misc fee edge case
      PaymentSemester(
        name: '2024 შემოდგომის სემესტრი',
        totalAmount: 4500.00,
        examFee: 50.00,
        penalty: 25.00,
        paidAmount: 4575.00,
        debtAmount: 0.00,
        transactions: [
          PaymentTransaction(dateTime: '2024-09-02 12:30:00', amount: 2000.00),
          PaymentTransaction(dateTime: '2024-11-11 16:15:00', amount: 2575.00),
        ],
      ),
    ];

    return (debtStatus, List<PaymentSemester>.from(semesters));
  }

  // ══════════════════════════════════════════════════════════════
  // 9. МАТЕРИАЛЫ — список предметов
  // ══════════════════════════════════════════════════════════════

  static ({List<Semester> semesters, List<CourseSubject> subjects})
      buildMockMaterialsList() {
    final subjects = [
      CourseSubject(
        code: 'CSC 1101', name: 'Introduction to Programming',
        teacher: 'Giorgi Beridze',
        payloadForDetails: {'subjectId': 'mock_mat_001'},
      ),
      CourseSubject(
        code: 'CSC 2305', name: 'Data Structures and Algorithms',
        teacher: 'Lasha Mchedlishvili',
        payloadForDetails: {'subjectId': 'mock_mat_002'},
      ),
      CourseSubject(
        code: 'MATH 2201', name: 'Calculus II',
        teacher: 'Nino Kvaratskhelia',
        payloadForDetails: {'subjectId': 'mock_mat_003'},
      ),
      CourseSubject(
        code: 'CSC 3501', name: 'Database Systems',
        teacher: 'Mariam Janelidze',
        payloadForDetails: {'subjectId': 'mock_mat_004'},
      ),
      CourseSubject(
        code: 'CSC 4601',
        name: 'Machine Learning',
        teacher: 'Giorgi Beridze',
        payloadForDetails: {'subjectId': 'mock_mat_005'},
      ),
      // No materials edge case
      CourseSubject(
        code: 'ENGL 0009E', name: 'Academic Writing for Engineers',
        teacher: 'Sarah Johnson',
        payloadForDetails: {'subjectId': 'mock_mat_006'},
      ),
    ];
    return (semesters: List<Semester>.from(mockSemesters), subjects: subjects);
  }

  // ══════════════════════════════════════════════════════════════
  // 10. МАТЕРИАЛЫ — детали предмета
  // ══════════════════════════════════════════════════════════════

  static ({String courseTitle, List<LectureGroup> groups})
      buildMockMaterialDetails(Map<String, String> payload) {
    final id = payload['subjectId'] ?? '';

    switch (id) {
      case 'mock_mat_001':
        return (
          courseTitle: 'Introduction to Programming — CSC 1101',
          groups: [
            LectureGroup(title: 'ლექცია-1', date: '12/02/2026', files: [
              MaterialFile(name: 'Lecture1_Intro_to_CS.pdf',
                  url: 'https://example.com/mock/lec1.pdf'),
              MaterialFile(name: 'Lab1_HelloWorld.zip',
                  url: 'https://example.com/mock/lab1.zip'),
            ]),
            LectureGroup(title: 'ლექცია-2', date: '19/02/2026', files: [
              MaterialFile(name: 'Lecture2_Variables_and_Types.pdf',
                  url: 'https://example.com/mock/lec2.pdf'),
              MaterialFile(name: 'Slides2.pptx',
                  url: 'https://example.com/mock/slides2.pptx'),
            ]),
            LectureGroup(title: 'ლექცია-3', date: '26/02/2026', files: [
              MaterialFile(name: 'Lecture3_Control_Flow.pdf',
                  url: 'https://example.com/mock/lec3.pdf'),
            ]),
            LectureGroup(title: 'ლექცია-4', date: '05/03/2026', files: [
              MaterialFile(name: 'DSA_Lecture2_Arrays_and_LinkedLists.pdf',
                  url: 'https://example.com/mock/dsa_lec2.pdf'),
              MaterialFile(name: 'Google_Drive_Resource',
                  url: 'https://drive.google.com/file/d/mock_id/view'),
            ]),
            // Empty lecture — edge case
            LectureGroup(title: 'ლექცია-5', date: '12/03/2026', files: []),
          ],
        );

      case 'mock_mat_002':
        return (
          courseTitle: 'Data Structures and Algorithms — CSC 2305',
          groups: [
            LectureGroup(title: 'ლექცია-1', date: '10/02/2026', files: [
              MaterialFile(name: 'DSA_Overview.pdf',
                  url: 'https://example.com/mock/dsa1.pdf'),
            ]),
            LectureGroup(title: 'ლექცია-2', date: '17/02/2026', files: [
              MaterialFile(name: 'Arrays_LinkedLists.pdf',
                  url: 'https://example.com/mock/dsa2.pdf'),
              MaterialFile(name: 'Practice_Problems.pdf',
                  url: 'https://example.com/mock/dsa2_practice.pdf'),
              MaterialFile(name: 'Reference_Implementation.zip',
                  url: 'https://example.com/mock/dsa2_code.zip'),
            ]),
            LectureGroup(title: 'ლექცია-3', date: '24/02/2026', files: [
              MaterialFile(name: 'Trees_and_Graphs.pdf',
                  url: 'https://example.com/mock/dsa3.pdf'),
            ]),
          ],
        );

      case 'mock_mat_006':
        // No materials — edge case
        return (
          courseTitle: 'Academic Writing for Engineers — ENGL 0009E',
          groups: [],
        );

      default:
        return (
          courseTitle: 'Course Materials',
          groups: [
            LectureGroup(title: 'ლექცია-1', date: '15/02/2026', files: [
              MaterialFile(name: 'Lecture_Notes_Week1.pdf',
                  url: 'https://example.com/mock/week1.pdf'),
            ]),
            LectureGroup(title: 'ლექცია-2', date: '22/02/2026', files: [
              MaterialFile(name: 'Lecture_Notes_Week2.pdf',
                  url: 'https://example.com/mock/week2.pdf'),
              MaterialFile(name: 'Supplementary_Reading.pdf',
                  url: 'https://example.com/mock/supp.pdf'),
            ]),
          ],
        );
    }
  }

  // ══════════════════════════════════════════════════════════════
  // 11. УВЕДОМЛЕНИЯ — посев / сброс
  // ══════════════════════════════════════════════════════════════

  static const _seedFlagKey = 'admin_sandbox_notif_seeded_v3';

  static Future<void> seedNotificationsIfNeeded() async {
    try {
      final prefs = Storage.prefs;
      if (prefs.getBool(_seedFlagKey) == true) return;

      final now      = DateTime.now();
      final tomorrow = now.add(const Duration(days: 1));

      final items = [
        NotificationItem(
          id: 'adm_001', title: 'Lecture Added',
          body: 'Machine Learning: extra session on ${_fmtDate(now.add(const Duration(days: 3)))}',
          timestamp: now.subtract(const Duration(minutes: 25)),
          type: NotificationType.lessonAdded, isRead: false),
        NotificationItem(
          id: 'adm_002', title: 'Exam Tomorrow!',
          body: 'Academic Writing exam is tomorrow at 09:00 in room C-12',
          timestamp: now.subtract(const Duration(hours: 1, minutes: 40)),
          type: NotificationType.examReminder, isRead: false),
        NotificationItem(
          id: 'adm_003', title: 'Grade Posted',
          body: 'Calculus II midterm result: 28.0 / 30.0',
          timestamp: now.subtract(const Duration(hours: 4)),
          type: NotificationType.info, isRead: false),
        NotificationItem(
          id: 'adm_004', title: 'Lecture Cancelled',
          body: 'Advanced Physics lecture on ${_fmtDate(now.subtract(const Duration(days: 2)))} cancelled',
          timestamp: now.subtract(const Duration(days: 1, hours: 2)),
          type: NotificationType.lessonCancelled,
          date: now.subtract(const Duration(days: 2)), isRead: true),
        NotificationItem(
          id: 'adm_005', title: 'Exam Scheduled',
          body: 'Database Systems final: ${_fmtDate(now.add(const Duration(days: 15)))} at 15:00 · A-101',
          timestamp: now.subtract(const Duration(days: 1, hours: 5)),
          type: NotificationType.examReminder, isRead: true),
        NotificationItem(
          id: 'adm_006', title: 'Lecture Restored',
          body: 'Operating Systems lecture rescheduled — restored to calendar',
          timestamp: now.subtract(const Duration(days: 2, hours: 1)),
          type: NotificationType.lessonRestored, isRead: true),
        NotificationItem(
          id: 'adm_007', title: 'Payment Reminder',
          body: 'Tuition balance: 1,250.00 ₾ outstanding — deadline approaching',
          timestamp: now.subtract(const Duration(days: 3)),
          type: NotificationType.info, isRead: true),
        NotificationItem(
          id: 'adm_008', title: 'Grade Updated',
          body: 'Linear Algebra final grade: A (93.0%)',
          timestamp: now.subtract(const Duration(days: 3, hours: 3)),
          type: NotificationType.info, isRead: true),
        NotificationItem(
          id: 'adm_009', title: 'Lecture Added',
          body: 'Data Structures: extra lab session added for Thursday',
          timestamp: now.subtract(const Duration(days: 4)),
          type: NotificationType.lessonAdded, isRead: true),
        NotificationItem(
          id: 'adm_010', title: 'Retake Exam Scheduled',
          body: 'Machine Learning FX retake: ${_fmtDate(now.add(const Duration(days: 21)))} · B-07',
          timestamp: now.subtract(const Duration(days: 5)),
          type: NotificationType.examReminder, isRead: true),
      ];

      await NotificationService.clearAll();
      for (final item in items.reversed) {
        await NotificationService.add(item);
      }
      await prefs.setBool(_seedFlagKey, true);
      debugPrint('[MockDataService] notifications seeded (${items.length} items)');
    } catch (e) {
      debugPrint('[MockDataService] seedNotifications ERROR: $e');
    }
  }

  /// Сбрасывает sandbox: пересеивает уведомления.
  /// Вызывающий код (settings_screen) сам сбрасывает LessonOverrides.
  static Future<void> resetSandbox() async {
    await Storage.prefs.remove(_seedFlagKey);
    await seedNotificationsIfNeeded();
    debugPrint('[MockDataService] sandbox reset complete');
  }

  // ── HELPERS ──────────────────────────────────────────────────

  static String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2,'0')}/${d.month.toString().padLeft(2,'0')}/${d.year}';
}
