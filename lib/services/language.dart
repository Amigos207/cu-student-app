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

  static String translateDay(String day) {
    final Map<String, Map<String, String>> dayTranslations = {
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
    return dayTranslations[currentLang.value]?[day] ?? day;
  }

  static String transliterate(String text) {
    if (currentLang.value == 'ქართული') return text;
    
    final Map<String, String> geoToLat = {
      'ა': 'a', 'ბ': 'b', 'გ': 'g', 'დ': 'd', 'ე': 'e', 'ვ': 'v', 'ზ': 'z', 'თ': 't',
      'ი': 'i', 'კ': 'k', 'ლ': 'l', 'მ': 'm', 'ნ': 'n', 'ო': 'o', 'პ': 'p', 'ჟ': 'zh',
      'რ': 'r', 'ს': 's', 'ტ': 't', 'უ': 'u', 'ფ': 'p', 'ქ': 'k', 'ღ': 'gh', 'ყ': 'q',
      'შ': 'sh', 'ჩ': 'ch', 'ც': 'ts', 'ძ': 'dz', 'წ': 'ts', 'ჭ': 'ch', 'ხ': 'kh', 'ჯ': 'j', 'ჰ': 'h',
      ' ': ' ', '-': '-', '(': '(', ')': ')'
    };
    
    final Map<String, String> geoToRus = {
      'ა': 'а', 'ბ': 'б', 'გ': 'г', 'დ': 'д', 'ე': 'е', 'ვ': 'в', 'ზ': 'з', 'თ': 'т',
      'ი': 'и', 'კ': 'к', 'ლ': 'л', 'მ': 'м', 'ნ': 'н', 'ო': 'о', 'პ': 'п', 'ჟ': 'ж',
      'რ': 'р', 'ს': 'с', 'ტ': 'т', 'უ': 'у', 'ფ': 'п', 'ქ': 'к', 'ღ': 'г', 'ყ': 'к',
      'შ': 'ш', 'ჩ': 'ч', 'ც': 'ц', 'ძ': 'дз', 'წ': 'ц', 'ჭ': 'ч', 'ხ': 'х', 'ჯ': 'дж', 'ჰ': 'х',
      ' ': ' ', '-': '-', '(': '(', ')': ')'
    };
    
    final map = currentLang.value == 'Русский' ? geoToRus : geoToLat;
    
    String result = '';
    for (var char in text.toLowerCase().split('')) {
      result += map[char] ?? char;
    }
    
    return capitalize(result);
  }

  static String translateName(String text) {
    return transliterate(text);
  }

  static String tr(String key) {
    final Map<String, Map<String, String>> translations = {
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
        'welcome': 'Welcome',
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
        'university': 'University',
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
        'update_required': 'Update Required',
        'update_message': 'A new version is available. Please update to continue.',
        'update_btn': 'Download Update',
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
        'profile': 'Профиль',
        'settings': 'Настройки',
        'logout': 'Выйти',
        'welcome': 'Добро пожаловать',
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
        'university': 'Университет',
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
        'update_required': 'Требуется обновление',
        'update_message': 'Доступна новая версия. Обновите для продолжения.',
        'update_btn': 'Скачать обновление',
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
        'profile': 'პროფილი',
        'settings': 'პარამეტრები',
        'logout': 'გასვლა',
        'welcome': 'მოგესალმებით',
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
        'show_start_only': 'სრული დროის ჩვენება',
        'today': 'დღეს',
        'upcoming': 'მომავალი',
        'missed': 'გაცდენა',
        'attended_status': 'დაესწრო',
        'pending': 'მოლოდინში', // <--- НОВОЕ
        'passed_lectures': 'ჩატარებული ლექციები',
        'out_of': '/',
        'attended_count': 'დაესწრო',
        'details': 'დასწრების დეტალები:',
        'lecture': 'ლექცია',
        'now': 'ახლა',
        'soon': 'მალე',
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
        'university': 'უნივერსიტეტი',
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
        'update_required': 'განახლება საჭიროა',
        'update_message': 'ახალი ვერსია ხელმისაწვდომია. გთხოვთ განაახლოთ.',
        'update_btn': 'განახლების ჩამოტვირთვა',
      },
    };
    
    return translations[currentLang.value]?[key] ?? key;
  }
}