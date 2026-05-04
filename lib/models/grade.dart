/// Один предмет в таблице оценок (главная страница GPA).
class GradeSubject {
  final String cxrId;        // ID для запроса деталей (скрытое поле cxr_id)
  final String code;         // "ACWR 0007E"
  final String name;         // Georgian name
  final double credits;      // 5.00
  final double percentage;   // 76.00
  final String letter;       // "C", "B+", "" если ещё нет
  final double qualityPoints;// 2.00

  const GradeSubject({
    required this.cxrId,
    required this.code,
    required this.name,
    required this.credits,
    required this.percentage,
    required this.letter,
    required this.qualityPoints,
  });
}

/// Итоговые показатели GPA (внизу страницы).
class GpaStats {
  final int    annualSubjects;
  final double annualCredits;
  final double annualPercentage;
  final double annualGpa;
  final int    cumulativeSubjects;
  final double cumulativeCredits;
  final double cumulativePercentage;
  final double cumulativeGpa;

  const GpaStats({
    required this.annualSubjects,
    required this.annualCredits,
    required this.annualPercentage,
    required this.annualGpa,
    required this.cumulativeSubjects,
    required this.cumulativeCredits,
    required this.cumulativePercentage,
    required this.cumulativeGpa,
  });
}

/// Одна строка экзаменационной таблицы внутри предмета.
class SubjectExam {
  final String  date;     // "2026-03-07" или "" если ещё не назначено
  final String  type;     // "Written work(Drop method)", "Midterm Examination" ...
  final double  maxScore;
  final double? score;    // null — результат ещё не выставлен

  const SubjectExam({
    required this.date,
    required this.type,
    required this.maxScore,
    this.score,
  });

  bool get isScored   => score != null;
  bool get isFuture   => !isScored && date.isNotEmpty &&
      DateTime.tryParse(date)?.isAfter(DateTime.now()) == true;
  bool get isFinalType =>
      type.toLowerCase().contains('final') ||
      type.toLowerCase().contains('fx');
}

/// Полные данные страницы внутри предмета.
class SubjectDetail {
  final String           code;
  final String           teacher;
  final List<SubjectExam> exams;
  final double           interimTotal;
  final double           maxEntered;
  final double           studentTotal;
  final double           finalPercentage;
  final String           finalGrade;

  const SubjectDetail({
    required this.code,
    required this.teacher,
    required this.exams,
    required this.interimTotal,
    required this.maxEntered,
    required this.studentTotal,
    required this.finalPercentage,
    required this.finalGrade,
  });

  bool get hasData => maxEntered > 0;
}
