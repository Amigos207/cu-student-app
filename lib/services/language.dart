import 'package:flutter/material.dart';

class LanguageService {
  static final ValueNotifier<String> currentLang = ValueNotifier<String>('English');
  static final ValueNotifier<bool> showBothTimes = ValueNotifier<bool>(true);

  static String capitalize(String text) {
    if (text.isEmpty) return text;
    text = text.trim().replaceAll(RegExp(r'\s+'), ' ');
    final keepUppercase = ['I', 'II', 'III', 'IV', 'V', 'VI', 'VII', 'VIII', 'IX', 'X', 'IT', 'CU'];

    return text.split(' ').map((word) {
      if (word.isEmpty) return word;
      if (keepUppercase.contains(word.toUpperCase())) return word.toUpperCase();
      return word[0].toUpperCase() + word.substring(1).toLowerCase();
    }).join(' ');
  }

  /// Converts the CU portal name format "LASTNAME FIRSTNAME [...]" →
  /// "Firstname [Middlename] Lastname" for display in the UI.
  static String formatPortalName(String raw) {
    final words = raw.trim().split(RegExp(r'[\s,]+'))
        .where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return raw;
    if (words.length == 1) return capitalize(words[0].toLowerCase());
    // Portal stores surname first; move it to the end.
    final lastName  = capitalize(words[0].toLowerCase());
    final givenNames = words.skip(1).map((w) => capitalize(w.toLowerCase())).join(' ');
    return '$givenNames $lastName';
  }

  /// Extracts only the first given name from portal format "LASTNAME FIRSTNAME [...]".
  /// Used for personalised greetings.
  static String extractFirstName(String raw) {
    final words = raw.trim().split(RegExp(r'[\s,]+'))
        .where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return '';
    // Skip the first word (last name), take the second word (given name).
    final given = words.length > 1 ? words[1] : words[0];
    return capitalize(given.toLowerCase());
  }

  static const Map<String, Map<String, String>> _dayTranslations = {
    'English': {
      'Monday': 'Monday', 'Tuesday': 'Tuesday', 'Wednesday': 'Wednesday',
      'Thursday': 'Thursday', 'Friday': 'Friday', 'Saturday': 'Saturday', 'Sunday': 'Sunday'
    },
    'Русский': {
      'Monday': 'Понедельник', 'Tuesday': 'Вторник', 'Wednesday': 'Среда',
      'Thursday': 'Четверг', 'Friday': 'Пятница', 'Saturday': 'Суббота', 'Sunday': 'Воскресенье'
    },
    'ქართული': {
      'Monday': 'ორშაბათი', 'Tuesday': 'სამშაბათი', 'Wednesday': 'ოთხშაბათი',
      'Thursday': 'ხუთშაბათი', 'Friday': 'პარასკევი', 'Saturday': 'შაბათი', 'Sunday': 'კვირა'
    },
  };

  static String translateDay(String day) {
    return _dayTranslations[currentLang.value]?[day] ?? day;
  }

  static const Map<String, String> _geoToLat = {
      'ა': 'a', 'ბ': 'b', 'გ': 'g', 'დ': 'd', 'ე': 'e', 'ვ': 'v', 'ზ': 'z', 'თ': 't',
      'ი': 'i', 'კ': 'k', 'ლ': 'l', 'მ': 'm', 'ნ': 'n', 'ო': 'o', 'პ': 'p', 'ჟ': 'zh',
      'რ': 'r', 'ს': 's', 'ტ': 't', 'უ': 'u', 'ფ': 'p', 'ქ': 'k', 'ღ': 'gh', 'ყ': 'q',
      'შ': 'sh', 'ჩ': 'ch', 'ც': 'ts', 'ძ': 'dz', 'წ': 'ts', 'ჭ': 'ch', 'ხ': 'kh', 'ჯ': 'j', 'ჰ': 'h',
      ' ': ' ', '-': '-', '(': '(', ')': ')'
    };
    
  static const Map<String, String> _geoToRus = {
      'ა': 'а', 'ბ': 'б', 'გ': 'г', 'დ': 'д', 'ე': 'е', 'ვ': 'в', 'ზ': 'з', 'თ': 'т',
      'ი': 'и', 'კ': 'к', 'ლ': 'л', 'მ': 'м', 'ნ': 'н', 'ო': 'о', 'პ': 'п', 'ჟ': 'ж',
      'რ': 'р', 'ს': 'с', 'ტ': 'т', 'უ': 'у', 'ფ': 'п', 'ქ': 'к', 'ღ': 'г', 'ყ': 'к',
      'შ': 'ш', 'ჩ': 'ч', 'ც': 'ц', 'ძ': 'дз', 'წ': 'ц', 'ჭ': 'ч', 'ხ': 'х', 'ჯ': 'дж', 'ჰ': 'х',
      ' ': ' ', '-': '-', '(': '(', ')': ')'
  };

  static String transliterate(String text) {
    if (currentLang.value == 'ქართული') return text;
    final map = currentLang.value == 'Русский' ? _geoToRus : _geoToLat;
    final sb = StringBuffer();
    for (final char in text.toLowerCase().split('')) {
      sb.write(map[char] ?? char);
    }
    return capitalize(sb.toString());
  }

  static String translateName(String text) {
    return transliterate(text);
  }

  // ─── SUBJECT-NAME CACHE (code → English name from schedule) ────────────────

  /// Internal cache: normalised course code → English subject name.
  /// Populated by [seedCodeMap] whenever any screen loads the schedule.
  static final Map<String, String> _codeToEn = {};

  /// Normalises a course code for fuzzy lookup:
  /// "ACWR 0007E" → "acwr7e",  "CSC 1242" → "csc1242"
  static String _normCode(String code) {
    var s = code.toLowerCase().replaceAll(RegExp(r'\s+'), '');
    s = s.replaceAllMapped(RegExp(r'0+(\d)'), (m) => m.group(1)!);
    return s;
  }

  /// Call this after parsing the schedule to fill the cache.
  /// [codeToEn] maps raw subject code → English name (Lesson.code → Lesson.name).
  /// Clears the subject name cache. Call on logout so the next user
  /// doesn't see the previous user's subjects.
  static void clearCodeMap() => _codeToEn.clear();

  static void seedCodeMap(Map<String, String> codeToEn) {
    for (final e in codeToEn.entries) {
      if (e.key.isNotEmpty && e.value.isNotEmpty) {
        _codeToEn[_normCode(e.key)] = e.value;
      }
    }
  }

  /// Returns the best display name for a subject.
  /// - Georgian UI  → [georgianFallback] (raw portal text)
  /// - English / Russian UI → English name from the schedule cache (keyed by
  ///   [code]), or [georgianFallback] when the cache has no entry yet.
  static String subjectDisplayName(String code, String georgianFallback) {
    if (currentLang.value == 'ქართული') return georgianFallback;

    final norm = _normCode(code);
    if (_codeToEn.containsKey(norm)) return _codeToEn[norm]!;

    // Fuzzy: same letter prefix + same numeric part
    final prefix  = RegExp(r'^[a-z]+').stringMatch(norm) ?? '';
    final numPart = norm.replaceAll(RegExp(r'^[a-z]+'), '');
    if (prefix.isNotEmpty) {
      for (final e in _codeToEn.entries) {
        final ep = RegExp(r'^[a-z]+').stringMatch(e.key) ?? '';
        final np = e.key.replaceAll(RegExp(r'^[a-z]+'), '');
        if (ep == prefix && np == numPart) return e.value;
      }
    }

    // Nothing found yet — return Georgian so user still sees something meaningful
    return georgianFallback;
  }

  // ─── LECTURE TITLE TRANSLATION ──────────────────────────────────────────────

  /// Translates lecture group headings of the form "ლექცია-N" / "ლექცია N"
  /// to the current UI language.
  ///   Georgian → ლექცია N
  ///   English  → Lecture N
  ///   Russian  → Лекция N
  /// Non-matching titles are returned unchanged.
  static String translateLectureTitle(String title) {
    final match =
        RegExp(r'ლექცია[\s\-]+(\d+)', caseSensitive: false).firstMatch(title);
    if (match == null) return title;
    final num = match.group(1)!;
    switch (currentLang.value) {
      case 'ქართული': return 'ლექცია $num';
      case 'Русский':  return 'Лекция $num';
      default:         return 'Lecture $num';
    }
  }

  static const Map<String, Map<String, String>> _translations = {
      'English': {
        'app_name': 'CU Student App',
        'login_title': 'CU Student Portal',
        'username': 'Username',
        'password': 'Password',
        'sign_in': 'Sign In',
        'error_auth': 'Invalid credentials',
        'demo_hint': 'Demo: admin / 1234',
        'schedule': 'Schedule',
        'attendance': 'Attendance',
        'profile': 'Profile',
        'settings': 'Settings',
        'logout': 'Logout',
        'nav_home': 'Home',
        'nav_academic': 'Academic',
        'nav_progress': 'Progress',
        'nav_resources': 'Resources',
        'nav_more': 'More',
        'next_class': 'Next Class',
        'current_gpa': 'Current GPA',
        'payment_status': 'Payment Status',
        'paid': 'Paid',
        'unpaid': 'Unpaid',
        'calendar': 'Calendar',
        'welcome': 'Welcome',
        'greeting_morning':   'Good morning',
        'greeting_afternoon': 'Good afternoon',
        'greeting_evening':   'Good evening',
        'greeting_night':     'Good night',
        'today_schedule':     'Today',
        'no_classes_today':   'No classes today',
        'and_more':           '+{n} more',
        'class_ongoing':      'Now',
        'upcoming_exam':      'Upcoming exam',
        'exam_today':         'Today',
        'exam_tomorrow':      'Tomorrow',
        'exam_in_days':       'in {n} days',
        'language': 'Language',
        'theme': 'Theme',
        'light': 'Light',
        'dark': 'Dark',
        'teacher': 'Teacher',
        'room': 'Room',
        'time': 'Time',
        'no_data': 'No data found',
        'present': 'Present',
        'absent': 'Absent',
        'current_lesson': 'Current Lesson',
        'time_remaining': 'remaining',
        'next_lesson': 'Next Lesson',
        'starts_in': 'starts in',
        'minutes': 'min',
        'time_format': 'Lesson Time',
        'show_both_times': 'Show end time',
        'haptic_feedback': 'Haptic Feedback',
        'haptic_feedback_sub': 'Vibration on taps and interactions',
        'show_start_only': 'Display full duration',
        'today': 'TODAY',
        'upcoming': 'Upcoming',
        'missed': 'Missed',
        'attended_status': 'Attended',
        'pending': 'Pending', // <--- НОВОЕ
        'passed_lectures': 'Passed lectures',
        'out_of': 'out of',
        'attended_count': 'Attended',
        'details': 'Attendance details:',
        'lecture': 'Lecture',
        'now': 'Now',
        'soon': 'Soon',
        'done': 'Done',
        'upcoming_exams': 'Upcoming',
        'past_exams': 'Past',
        'exam_in': 'In',
        'exam_days': 'days',
        'exam_past': 'Past',
        'break': 'Break',
        'part': 'Part',
        'left': 'left',
        'min': 'min',
        'ending': 'Ending',
        // Theme labels
        'theme_light': 'Light',
        'theme_dark': 'Dark',
        'theme_pink': 'Pink',
        'theme_hacker': 'Hacker',
        'theme_ocean': 'Ocean',
        // Profile
        'status': 'Status',
        'student_active': 'Active',
        'university': 'University',
        'academic_info': 'Academic Info',
        'personal_info': 'Personal Info',
        'personal_id': 'Personal ID',
        'email': 'University Email',
        'personal_email': 'Personal Email',
        'mobile': 'Mobile',
        'phone': 'Phone',
        'grant': 'Grant',
        'course': 'Year / Course',
        'enrollment_year': 'Enrollment Year',
        'concentration': 'Concentration',
        'rating': 'Rating',
        // Schedule
        'loading': 'Loading...',
        'vacation_today': 'No classes today — enjoy your day off!',
        // Bug report
        'feedback': 'Feedback',
        'bug_report': 'Bug Report',
        'bug_report_sub': 'Found a problem? Let us know',
        'bug_intro': 'Help us improve the app by reporting any issues you encounter.',
        'bug_category': 'Category',
        'bug_cat_ui': 'UI',
        'bug_cat_schedule': 'Schedule',
        'bug_cat_attendance': 'Attendance',
        'bug_cat_login': 'Login',
        'bug_cat_other': 'Other',
        'bug_desc_label': 'Description',
        'bug_desc_hint': 'Describe the issue...',
        'bug_steps_label': 'Steps to reproduce',
        'bug_steps_hint': '1. Open the app\n2. Go to...\n3. ...',
        'bug_screenshot_hint': 'You can attach a screenshot after sending.',
        'send_report': 'Send Report',
        'bug_copied': 'Report copied to clipboard',
        'bug_fill_required': 'Please fill in the description',
        'bug_thanks': 'Thank you!',
        'bug_thanks_sub': 'Your report has been sent. We will look into it.',
        'back': 'Back',
        // Update
        'grades': 'Grades',
        'exams': 'Exam Schedule',
        'syllabi': 'Syllabi',
        'materials': 'Course Materials',
        'payments': 'Payments',
        'student_info': 'Student Info',
        'coming_soon': 'Coming soon...',
        'menu': 'Menu',
        'go_home': 'Go to Home',
        'course_materials': 'Course Materials',
        'syllabus': 'Syllabi',
        'payment_schedule': 'Payment Schedule',
        // Semester season localization
        'sem_spring':  'Spring',
        'sem_summer':  'Summer',
        'sem_autumn':  'Autumn',
        'sem_winter':  'Winter',
        'sem_semester':'Semester',
        'section_study': 'Academics',
        'section_personal': 'Personal',
        'section_other': 'More',
        // Grades screen
        'credits': 'credits',
        'subjects': 'subjects',
        'annual': 'Annual',
        'cumulative': 'Cumulative',
        'exam_type': 'Exam',
        'score': 'Score',
        'interim_total': 'Interim total',
        'student_total': 'Points earned',
        'final_percentage': 'Final %',
        'final_grade': 'Final grade',
        'retry': 'Retry',
        'update_required': 'Update Required',
        'update_message': 'A new version is available. Please update to continue.',
        'update_btn': 'Download Update',
        'whats_new': "What's new",
        'follow_installer': 'Follow the installer instructions',
        'update_error_unknown': 'Unknown error',
        'update_retry': 'Try again',
        'update_open_error': 'Could not open installer',
        'update_download_error': 'Download error',
        'update_permission_denied': 'Installation permission required',
        'update_file_corrupted': 'File corrupted, please try again',
        'open': 'Open',
        'connecting': 'Connecting...',
        'syllabus_open': 'Open Syllabus',
        'syllabus_downloading': 'Downloading...',
        'syllabus_opening': 'Opening...',
        'syllabus_error': 'Failed to open syllabus',
        'syllabus_no_viewer': 'No PDF viewer found. Install one and try again.',
        // ── Notifications ──────────────────────────────────────────
        'notifications':                'Notifications',
        'notif_empty':                  'No notifications yet',
        'notif_clear_all':              'Clear all',
        'notif_just_now':               'Just now',
        'notif_ago':                    'ago',
        'notif_hours':                  'h',
        'open_in_schedule':             'Open in schedule',
        'notif_days':                   'd',
        'notif_lesson_added_title':     'Lecture added',
        'notif_lesson_cancelled_title': 'Lecture cancelled',
        'notif_lesson_restored_title':  'Lecture restored',
        'notif_lesson_removed_title':   'Lecture removed',
        'notif_reminder_title':         'Reminder',
        'notif_in_3_days':              'in 3 days',
        'notif_in_1_day':               'tomorrow',
        // ── Schedule overrides ─────────────────────────────────────
        'add_lecture':          'Add',
        'add_new_lecture':      'Add new lecture',
        'added_lecture':        'Added',
        'lesson_cancelled':     'Cancelled',
        'cancel_lecture':       'Cancel lecture',
        'restore_lecture':      'Restore',
        'restore_cancelled':    'Restore cancelled',
        'restore':              'Restore',
        'pick_subject':         'Choose subject',
        'enter_manually':       'Enter manually',
        'lesson_name':          'Lesson name',
        'reminders':            'Reminders',
        'remind_3_days':        'Remind 3 days before',
        'remind_1_day':         'Remind 1 day before',
        'save_lecture':         'Save lecture',
        // ── Add-lecture sheet (2-step) ─────────────────────────
        'step_pick_subject':    'Choose subject',
        'step_set_time':        'Time & reminder',
        'btn_next':             'Next',
        'lecture_start_time':   'Lecture time',
        'remind_me':            'Remind me',
        'remind_days_before':   'Days before',
        'remind_same_day':      'Same day',
        'remind_1d':            '1 day before',
        'remind_2d':            '2 days before',
        'remind_3d':            '3 days before',
        'remind_at_time':       'Reminder time',
        'remind_optional_hint': 'Reminder is optional',
        'hours_label':          'h',
        'minutes_label':        'min',
        // ── Payments ──────────────────────────────────────────────
        'no_debt':             'No Debt',
        'has_debt':            'You Have a Debt',
        'debt_status':         'Debt Status',
        'payment_history':     'Payment History',
        'paid_label':          'Paid',
        'debt_label':          'Debt',
        'total_label':         'Total',
        'transactions_label':  'TRANSACTIONS',
        'session_expired_hint':'Session expired. Pull down to retry.',
      },
      'Русский': {
        'app_name': 'CU Студент',
        'login_title': 'Портал CU',
        'username': 'Логин',
        'password': 'Пароль',
        'sign_in': 'Войти',
        'error_auth': 'Неверный логин или пароль',
        'demo_hint': 'Демо: admin / 1234',
        'schedule': 'Расписание',
        'attendance': 'Посещаемость',
        'nav_home': 'Главная',
        'nav_academic': 'Учёба',
        'nav_progress': 'Успехи',
        'nav_resources': 'Материалы',
        'nav_more': 'Ещё',
        'next_class': 'Следующее занятие',
        'current_gpa': 'Текущий GPA',
        'payment_status': 'Статус оплаты',
        'paid': 'Оплачено',
        'unpaid': 'Не оплачено',
        'calendar': 'Календарь',
        'profile': 'Профиль',
        'settings': 'Настройки',
        'logout': 'Выйти',
        'welcome': 'Добро пожаловать',
        'greeting_morning':   'Доброе утро',
        'greeting_afternoon': 'Добрый день',
        'greeting_evening':   'Добрый вечер',
        'greeting_night':     'Доброй ночи',
        'today_schedule':     'Сегодня',
        'no_classes_today':   'Сегодня пар нет',
        'and_more':           'ещё {n}',
        'class_ongoing':      'Сейчас',
        'upcoming_exam':      'Ближайший экзамен',
        'exam_today':         'Сегодня',
        'exam_tomorrow':      'Завтра',
        'exam_in_days':       'через {n} дн.',
        'language': 'Язык',
        'theme': 'Тема',
        'light': 'Светлая',
        'dark': 'Тёмная',
        'teacher': 'Преподаватель',
        'room': 'Аудитория',
        'time': 'Время',
        'no_data': 'Нет данных',
        'present': 'Присутствий',
        'absent': 'Отсутствий',
        'current_lesson': 'Текущая пара',
        'time_remaining': 'осталось',
        'next_lesson': 'Следующая пара',
        'starts_in': 'через',
        'minutes': 'мин',
        'time_format': 'Время занятий',
        'show_both_times': 'Время окончания пар',
        'haptic_feedback': 'Тактильная отдача',
        'haptic_feedback_sub': 'Вибрация при нажатиях',
        'show_start_only': 'Показывать и начало, и конец',
        'today': 'СЕГОДНЯ',
        'upcoming': 'Предстоит',
        'missed': 'Пропуск',
        'attended_status': 'Был',
        'pending': 'В ожидании', // <--- НОВОЕ
        'passed_lectures': 'Прошло лекций',
        'out_of': 'из',
        'attended_count': 'Присутствовал',
        'details': 'Детализация посещений:',
        'lecture': 'Лекция',
        'now': 'Сейчас',
        'soon': 'Скоро',
        'done': 'Прошла',
        'upcoming_exams': 'Предстоящие',
        'past_exams': 'Прошедшие',
        'exam_in': 'Через',
        'exam_days': 'дн.',
        'exam_past': 'Прошёл',
        'break': 'Перерыв',
        'part': 'Часть',
        'left': 'осталось',
        'min': 'мин',
        'ending': 'Завершение',
        // Theme labels
        'theme_light': 'Светлая',
        'theme_dark': 'Тёмная',
        'theme_pink': 'Розовая',
        'theme_hacker': 'Хакер',
        'theme_ocean': 'Океан',
        // Profile
        'status': 'Статус',
        'student_active': 'Активный',
        'university': 'Университет',
        'academic_info': 'Учебная информация',
        'personal_info': 'Личные данные',
        'personal_id': 'Личный номер',
        'email': 'Университетский email',
        'personal_email': 'Личный email',
        'mobile': 'Мобильный',
        'phone': 'Телефон',
        'grant': 'Грант',
        'course': 'Курс',
        'enrollment_year': 'Год поступления',
        'concentration': 'Концентрация',
        'rating': 'Рейтинг',
        // Schedule
        'loading': 'Загрузка...',
        'vacation_today': 'Сегодня нет пар — отдыхай!',
        // Bug report
        'feedback': 'Обратная связь',
        'bug_report': 'Сообщить о баге',
        'bug_report_sub': 'Нашли проблему? Сообщите нам',
        'bug_intro': 'Помогите улучшить приложение, сообщив о найденных проблемах.',
        'bug_category': 'Категория',
        'bug_cat_ui': 'Интерфейс',
        'bug_cat_schedule': 'Расписание',
        'bug_cat_attendance': 'Посещаемость',
        'bug_cat_login': 'Вход',
        'bug_cat_other': 'Другое',
        'bug_desc_label': 'Описание',
        'bug_desc_hint': 'Опишите проблему...',
        'bug_steps_label': 'Шаги воспроизведения',
        'bug_steps_hint': '1. Открыть приложение\n2. Перейти в...\n3. ...',
        'bug_screenshot_hint': 'Вы можете прикрепить скриншот после отправки.',
        'send_report': 'Отправить',
        'bug_copied': 'Отчёт скопирован в буфер обмена',
        'bug_fill_required': 'Пожалуйста, заполните описание',
        'bug_thanks': 'Спасибо!',
        'bug_thanks_sub': 'Ваш отчёт отправлен. Мы разберёмся.',
        'back': 'Назад',
        // Update
        'grades': 'Оценки',
        'exams': 'Расписание экзаменов',
        'syllabi': 'Силлабусы',
        'materials': 'Материалы курсов',
        'payments': 'Оплата',
        'student_info': 'Данные студента',
        'coming_soon': 'Скоро...',
        'menu': 'Меню',
        'go_home': 'На главный экран',
        'course_materials': 'Материалы курсов',
        'syllabus': 'Силлабусы',
        'payment_schedule': 'График оплаты',
        'sem_spring':  'Весна',
        'sem_summer':  'Лето',
        'sem_autumn':  'Осень',
        'sem_winter':  'Зима',
        'sem_semester':'Семестр',
        'section_study': 'Учёба',
        'section_personal': 'Личное',
        'section_other': 'Прочее',
        // Grades screen
        'credits': 'кредит',
        'subjects': 'предметов',
        'annual': 'Годовой',
        'cumulative': 'Кумулятивный',
        'exam_type': 'Экзамен',
        'score': 'Баллы',
        'interim_total': 'Промежуточный итог',
        'student_total': 'Набранные баллы',
        'final_percentage': 'Итоговый %',
        'final_grade': 'Итоговая оценка',
        'retry': 'Повторить',
        'update_required': 'Требуется обновление',
        'update_message': 'Доступна новая версия. Обновите для продолжения.',
        'update_btn': 'Скачать обновление',
        'whats_new': 'Что нового',
        'follow_installer': 'Следуйте инструкциям установщика',
        'update_error_unknown': 'Неизвестная ошибка',
        'update_retry': 'Попробовать снова',
        'update_open_error': 'Не удалось открыть установщик',
        'update_download_error': 'Ошибка загрузки',
        'update_permission_denied': 'Необходимо разрешение на установку приложений',
        'update_file_corrupted': 'Файл повреждён, попробуйте ещё раз',
        'open': 'Открыть',
        'connecting': 'Подключение...',
        'syllabus_open': 'Открыть силлабус',
        'syllabus_downloading': 'Загрузка...',
        'syllabus_opening': 'Открытие...',
        'syllabus_error': 'Не удалось открыть силлабус',
        'syllabus_no_viewer': 'Нет приложения для PDF. Установите его и попробуйте снова.',
        // ── Уведомления ───────────────────────────────────────────
        'notifications':                'Уведомления',
        'notif_empty':                  'Уведомлений пока нет',
        'notif_clear_all':              'Очистить всё',
        'notif_just_now':               'Только что',
        'notif_ago':                    'назад',
        'notif_hours':                  'ч',
        'open_in_schedule':             'Открыть в расписании',
        'notif_days':                   'дн.',
        'notif_lesson_added_title':     'Лекция добавлена',
        'notif_lesson_cancelled_title': 'Лекция отменена',
        'notif_lesson_restored_title':  'Лекция восстановлена',
        'notif_lesson_removed_title':   'Лекция удалена',
        'notif_reminder_title':         'Напоминание',
        'notif_in_3_days':              'через 3 дня',
        'notif_in_1_day':               'завтра',
        // ── Расписание ────────────────────────────────────────────
        'add_lecture':          'Добавить',
        'add_new_lecture':      'Добавить новую лекцию',
        'added_lecture':        'Доп.',
        'lesson_cancelled':     'Отменена',
        'cancel_lecture':       'Отменить лекцию',
        'restore_lecture':      'Восстановить',
        'restore_cancelled':    'Восстановить отменённую',
        'restore':              'Восстановить',
        'pick_subject':         'Выбрать предмет',
        'enter_manually':       'Ввести вручную',
        'lesson_name':          'Название лекции',
        'reminders':            'Напоминания',
        'remind_3_days':        'Напомнить за 3 дня',
        'remind_1_day':         'Напомнить за 1 день',
        'save_lecture':         'Сохранить',
        // ── Добавление лекции (2 шага) ────────────────────────
        'step_pick_subject':    'Выберите предмет',
        'step_set_time':        'Время и напоминание',
        'btn_next':             'Далее',
        'lecture_start_time':   'Время лекции',
        'remind_me':            'Напомнить',
        'remind_days_before':   'За сколько дней',
        'remind_same_day':      'В день лекции',
        'remind_1d':            'За 1 день',
        'remind_2d':            'За 2 дня',
        'remind_3d':            'За 3 дня',
        'remind_at_time':       'Время напоминания',
        'remind_optional_hint': 'Напоминание необязательно',
        'hours_label':          'ч',
        'minutes_label':        'мин',
        // ── Платежи ───────────────────────────────────────────────
        'no_debt':             'Долга нет',
        'has_debt':            'Есть задолженность',
        'debt_status':         'Статус задолженности',
        'payment_history':     'История платежей',
        'paid_label':          'Оплачено',
        'debt_label':          'Долг',
        'total_label':         'Итого',
        'transactions_label':  'ТРАНЗАКЦИИ',
        'session_expired_hint':'Сессия истекла. Потяните вниз для повтора.',
      },
      'ქართული': {
        'app_name': 'CU სტუდენტი',
        'login_title': 'CU პორტალი',
        'username': 'მომხმარებელი',
        'password': 'პაროლი',
        'sign_in': 'შესვლა',
        'error_auth': 'არასწორი მონაცემები',
        'demo_hint': 'დემო: admin / 1234',
        'schedule': 'განრიგი',
        'attendance': 'დასწრება',
        'nav_home': 'მთავარი',
        'nav_academic': 'სასწავლო',
        'nav_progress': 'პროგრესი',
        'nav_resources': 'მასალები',
        'nav_more': 'მეტი',
        'next_class': 'შემდეგი გაკვეთილი',
        'current_gpa': 'მიმდინარე GPA',
        'payment_status': 'გადახდის სტატუსი',
        'paid': 'გადახდილია',
        'unpaid': 'გადაუხდელია',
        'calendar': 'კალენდარი',
        'profile': 'პროფილი',
        'settings': 'პარამეტრები',
        'logout': 'გასვლა',
        'welcome': 'მოგესალმებით',
        'greeting_morning':   'დილა მშვიდობისა',
        'greeting_afternoon': 'შუადღე მშვიდობისა',
        'greeting_evening':   'საღამო მშვიდობისა',
        'greeting_night':     'ღამე მშვიდობისა',
        'today_schedule':     'დღეს',
        'no_classes_today':   'დღეს წყვეტილი არ არის',
        'and_more':           'კიდევ {n}',
        'class_ongoing':      'ახლა',
        'upcoming_exam':      'მომავალი გამოცდა',
        'exam_today':         'დღეს',
        'exam_tomorrow':      'ხვალ',
        'exam_in_days':       '{n} დღეში',
        'language': 'ენა',
        'theme': 'თემა',
        'light': 'ნათელი',
        'dark': 'ბნელი',
        'teacher': 'მასწავლებელი',
        'room': 'აუდიტორია',
        'time': 'დრო',
        'no_data': 'მონაცემები არ არის',
        'present': 'დასწრება',
        'absent': 'აკლება',
        'current_lesson': 'მიმდინარე გაკვეთილი',
        'time_remaining': 'დარჩა',
        'next_lesson': 'შემდეგი გაკვეთილი',
        'starts_in': 'დაიწყება',
        'minutes': 'წუთში',
        'time_format': 'დრო',
        'show_both_times': 'დასრულების დროის ჩვენება',
        'haptic_feedback': 'ვიბრაცია',
        'haptic_feedback_sub': 'ვიბრაცია ღილაკებზე დაჭერისას',
        'show_start_only': 'სრული დროის ჩვენება',
        'today': 'დღეს',
        'upcoming': 'მომავალი',
        'missed': 'გაცდენა',
        'attended_status': 'დასწრება',
        'pending': 'მოლოდინში', // <--- НОВОЕ
        'passed_lectures': 'ჩატარებული ლექციები',
        'out_of': '/',
        'attended_count': 'დასწრება',
        'details': 'დასწრების დეტალები:',
        'lecture': 'ლექცია',
        'now': 'ახლა',
        'soon': 'მალე',
        'done': 'დასრულდა',
        'upcoming_exams': 'მომავალი',
        'past_exams': 'გასული',
        'exam_in': '',
        'exam_days': 'დღეში',
        'exam_past': 'გასული',
        'break': 'შესვენება',
        'part': 'ნაწილი',
        'left': 'დარჩა',
        'min': 'წთ',
        'ending': 'დასრულება',
        // Theme labels
        'theme_light': 'ნათელი',
        'theme_dark': 'ბნელი',
        'theme_pink': 'ვარდისფერი',
        'theme_hacker': 'ჰაკერი',
        'theme_ocean': 'ოკეანე',
        // Profile
        'status': 'სტატუსი',
        'student_active': 'აქტიური',
        'university': 'უნივერსიტეტი',
        'academic_info': 'სასწავლო ინფორმაცია',
        'personal_info': 'პირადი მონაცემები',
        'personal_id': 'პირადი ნომერი',
        'email': 'უნივერსიტეტის email',
        'personal_email': 'პირადი email',
        'mobile': 'მობილური',
        'phone': 'ტელეფონი',
        'grant': 'გრანტი',
        'course': 'კურსი',
        'enrollment_year': 'ჩარიცხვის წელი',
        'concentration': 'კონცენტრაცია',
        'rating': 'რეიტინგი',
        // Schedule
        'loading': 'იტვირთება...',
        'vacation_today': 'დღეს გაკვეთილები არ არის — ისიამოვნე!',
        // Bug report
        'feedback': 'უკუკავშირი',
        'bug_report': 'შეცდომის შეტყობინება',
        'bug_report_sub': 'პრობლემა აღმოაჩინეთ? შეგვატყობინეთ',
        'bug_intro': 'დაგვეხმარეთ აპლიკაციის გაუმჯობესებაში.',
        'bug_category': 'კატეგორია',
        'bug_cat_ui': 'ინტერფეისი',
        'bug_cat_schedule': 'განრიგი',
        'bug_cat_attendance': 'დასწრება',
        'bug_cat_login': 'შესვლა',
        'bug_cat_other': 'სხვა',
        'bug_desc_label': 'აღწერა',
        'bug_desc_hint': 'აღწერეთ პრობლემა...',
        'bug_steps_label': 'გამეორების ნაბიჯები',
        'bug_steps_hint': '1. გახსენი აპლიკაცია\n2. გადი...\n3. ...',
        'bug_screenshot_hint': 'შეგიძლიათ სკრინშოტი მიამაგროთ გაგზავნის შემდეგ.',
        'send_report': 'გაგზავნა',
        'bug_copied': 'შეტყობინება კოპირებულია',
        'bug_fill_required': 'გთხოვთ შეავსოთ აღწერა',
        'bug_thanks': 'მადლობა!',
        'bug_thanks_sub': 'თქვენი შეტყობინება გაგზავნილია.',
        'back': 'უკან',
        // Update
        'grades': 'შეფასებები',
        'exams': 'გამოცდების განრიგი',
        'syllabi': 'სილაბუსები',
        'materials': 'კურსის მასალები',
        'payments': 'გადახდა',
        'student_info': 'სტუდენტის ინფო',
        'coming_soon': 'მალე...',
        'menu': 'მენიუ',
        'go_home': 'მთავარ გვერდზე',
        'course_materials': 'კურსის მასალები',
        'syllabus': 'სილაბუსები',
        'payment_schedule': 'გადახდის განრიგი',
        'sem_spring':  'გაზაფხული',
        'sem_summer':  'ზაფხული',
        'sem_autumn':  'შემოდგომა',
        'sem_winter':  'ზამთარი',
        'sem_semester':'სემესტრი',
        'section_study': 'სწავლა',
        'section_personal': 'პირადი',
        'section_other': 'სხვა',
        'whats_new': 'სიახლეები',
        // Grades screen
        'credits': 'კრედიტი',
        'subjects': 'საგანი',
        'annual': 'წლიური',
        'cumulative': 'კუმულაციური',
        'exam_type': 'გამოცდა',
        'score': 'ქულა',
        'interim_total': 'შუალედური ჯამი',
        'student_total': 'მიღებული ქულები',
        'final_percentage': 'საბოლოო %',
        'final_grade': 'საბოლოო ნიშანი',
        'retry': 'თავიდან',
        'update_required': 'განახლება საჭიროა',
        'update_message': 'ახალი ვერსია ხელმისაწვდომია. გთხოვთ განაახლოთ.',
        'update_btn': 'განახლების ჩამოტვირთვა',
        'follow_installer': 'მიჰყევით ინსტალერის მითითებებს',
        'update_error_unknown': 'უცნობი შეცდომა',
        'update_retry': 'სცადეთ ისევ',
        'update_open_error': 'ინსტალერის გახსნა ვერ მოხერხდა',
        'update_download_error': 'ჩამოტვირთვის შეცდომა',
        'update_permission_denied': 'საჭიროა ინსტალაციის ნებართვა',
        'update_file_corrupted': 'ფაილი დაზიანებულია, სცადეთ ისევ',
        'open': 'გახსნა',
        'connecting': 'დაკავშირება...',
        'syllabus_open': 'სილაბუსის გახსნა',
        'syllabus_downloading': 'იტვირთება...',
        'syllabus_opening': 'იხსნება...',
        'syllabus_error': 'სილაბუსის გახსნა ვერ მოხერხდა',
        'syllabus_no_viewer': 'PDF-ის პროგრამა არ არის. დააინსტალირეთ და სცადეთ ისევ.',
        // ── შეტყობინებები ─────────────────────────────────────────
        'notifications':                'შეტყობინებები',
        'notif_empty':                  'შეტყობინებები არ არის',
        'notif_clear_all':              'ყველას გასუფთავება',
        'notif_just_now':               'ახლახან',
        'notif_ago':                    'წინ',
        'notif_hours':                  'სთ',
        'open_in_schedule':             'განრიგში გახსნა',
        'notif_days':                   'დღ',
        'notif_lesson_added_title':     'ლექცია დამატებულია',
        'notif_lesson_cancelled_title': 'ლექცია გაუქმებულია',
        'notif_lesson_restored_title':  'ლექცია აღდგენილია',
        'notif_lesson_removed_title':   'ლექცია წაიშალა',
        'notif_reminder_title':         'შეხსენება',
        'notif_in_3_days':              '3 დღეში',
        'notif_in_1_day':               'ხვალ',
        // ── განრიგი ───────────────────────────────────────────────
        'add_lecture':          'დამატება',
        'add_new_lecture':      'ახალი ლექციის დამატება',
        'added_lecture':        'დამატ.',
        'lesson_cancelled':     'გაუქმდა',
        'cancel_lecture':       'ლექციის გაუქმება',
        'restore_lecture':      'აღდგენა',
        'restore_cancelled':    'გაუქმებულის აღდგენა',
        'restore':              'აღდგენა',
        'pick_subject':         'საგნის არჩევა',
        'enter_manually':       'ხელით შეყვანა',
        'lesson_name':          'ლექციის სახელი',
        'reminders':            'შეხსენებები',
        'remind_3_days':        '3 დღით ადრე შეხსენება',
        'remind_1_day':         '1 დღით ადრე შეხსენება',
        'save_lecture':         'შენახვა',
        // ── ლექციის დამატება (2 ნაბიჯი) ──────────────────────
        'step_pick_subject':    'აირჩიე საგანი',
        'step_set_time':        'დრო და შეხსენება',
        'btn_next':             'შემდეგი',
        'lecture_start_time':   'ლექციის დრო',
        'remind_me':            'შეხსენება',
        'remind_days_before':   'რამდენი დღით ადრე',
        'remind_same_day':      'იმავე დღეს',
        'remind_1d':            '1 დღით ადრე',
        'remind_2d':            '2 დღით ადრე',
        'remind_3d':            '3 დღით ადრე',
        'remind_at_time':       'შეხსენების დრო',
        'remind_optional_hint': 'შეხსენება არჩევითია',
        'hours_label':          'სთ',
        'minutes_label':        'წთ',
        // ── გადახდა ───────────────────────────────────────────────
        'no_debt':             'ვალი არ გაქვთ',
        'has_debt':            'გაქვთ დავალიანება',
        'debt_status':         'ვალის სტატუსი',
        'payment_history':     'გადახდების ისტორია',
        'paid_label':          'გადახდილი',
        'debt_label':          'ვალი',
        'total_label':         'ჯამი',
        'transactions_label':  'ტრანზაქციები',
        'session_expired_hint':'სესია ამოიწურა. ჩამოიწიეთ განახლებისთვის.',
      },
  };

  static String tr(String key) {
    return _translations[currentLang.value]?[key] ?? key;
  }
}