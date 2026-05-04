/// Model for one subject row on the Syllabus page (sylab.php).
class SyllabusSubject {
  final String code;
  final String name;
  final String teacher;
  /// The hidden `id` field value (student's schedule-registration ID).
  final String studentId;
  /// The hidden `cxr_id` field value (unique per course in this semester).
  final String cxrId;

  const SyllabusSubject({
    required this.code,
    required this.name,
    required this.teacher,
    required this.studentId,
    required this.cxrId,
  });
}
