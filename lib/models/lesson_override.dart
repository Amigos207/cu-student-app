// lib/models/lesson_override.dart

class LessonOverride {
  final String   id;
  final DateTime date;
  final String   lessonName;
  final String   lessonTeacher;
  final String   lessonTime;
  final String   lessonRoom;
  final String   lessonCode;
  final bool     isCancelled;
  final bool     isAdded;

  const LessonOverride({
    required this.id,
    required this.date,
    required this.lessonName,
    this.lessonTeacher = '',
    this.lessonTime    = '',
    this.lessonRoom    = '',
    this.lessonCode    = '',
    this.isCancelled   = false,
    this.isAdded       = false,
  });

  Map<String, dynamic> toJson() => {
    'id':            id,
    'date':          date.millisecondsSinceEpoch,
    'lessonName':    lessonName,
    'lessonTeacher': lessonTeacher,
    'lessonTime':    lessonTime,
    'lessonRoom':    lessonRoom,
    'lessonCode':    lessonCode,
    'isCancelled':   isCancelled,
    'isAdded':       isAdded,
  };

  factory LessonOverride.fromJson(Map<String, dynamic> j) => LessonOverride(
    id:            j['id']            as String? ?? '',
    date:          DateTime.fromMillisecondsSinceEpoch((j['date'] as int?) ?? 0),
    lessonName:    j['lessonName']    as String? ?? '',
    lessonTeacher: j['lessonTeacher'] as String? ?? '',
    lessonTime:    j['lessonTime']    as String? ?? '',
    lessonRoom:    j['lessonRoom']    as String? ?? '',
    lessonCode:    j['lessonCode']    as String? ?? '',
    isCancelled:   (j['isCancelled']  as bool?)  ?? false,
    isAdded:       (j['isAdded']      as bool?)  ?? false,
    // Legacy reminder fields from older JSON are intentionally ignored.
  );

  LessonOverride copyWith({
    bool? isCancelled,
    bool? isAdded,
  }) => LessonOverride(
    id:            id,
    date:          date,
    lessonName:    lessonName,
    lessonTeacher: lessonTeacher,
    lessonTime:    lessonTime,
    lessonRoom:    lessonRoom,
    lessonCode:    lessonCode,
    isCancelled:   isCancelled ?? this.isCancelled,
    isAdded:       isAdded     ?? this.isAdded,
  );
}
