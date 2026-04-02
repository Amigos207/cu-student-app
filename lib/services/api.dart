import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;

class ApiService {
  static const String _baseUrl       = 'https://programs.cu.edu.ge/cu';
  static const String _scheduleUrl   = 'https://programs.cu.edu.ge/students/schedule.php';
  static const String _attendanceUrl = 'https://programs.cu.edu.ge/students/agricxva_cxrili.php';

  static String _cookies = '';
  static final Map<String, String> _cookieMap = {};

  // Браузерный User-Agent — без него портал CU отклоняет запросы
  // на реальном устройстве (в debug/эмуляторе проходило, на APK — нет).
  static const _ua =
      'Mozilla/5.0 (Linux; Android 14; Pixel 7) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/124.0.0.0 Mobile Safari/537.36';

  static const _baseHeaders = <String, String>{
    'User-Agent':      _ua,
    'Accept':          'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    'Accept-Language': 'ka,en-US;q=0.9,en;q=0.8,ru;q=0.7',
  };

  static String get scheduleUrl   => _scheduleUrl;
  static String get attendanceUrl => _attendanceUrl;

  // ─── АВТОРИЗАЦИЯ ────────────────────────────────────────────────

  static Future<bool> login(String username, String password) async {
    try {
      print('=== START LOGIN ===');
      _cookies = '';
      _cookieMap.clear();

      final loginUri = Uri.parse('$_baseUrl/loginStud');

      // Шаг 1: GET страницы входа
      print('[1] GET $loginUri');
      final getResp = await _get(loginUri);
      print('[1] status=${getResp.statusCode} cookies=$_cookies');
      _storeCookies(getResp.headers);

      final doc = html_parser.parse(getResp.body);
      final formData = <String, String>{};
      for (final input in doc.querySelectorAll('input')) {
        final name  = input.attributes['name'];
        final value = input.attributes['value'] ?? '';
        final type  = input.attributes['type']?.toLowerCase();
        if (name != null && type != 'submit' && type != 'button') {
          formData[name] = value;
        }
      }
      formData['username'] = username;
      formData['password'] = password;
      formData['submit']   = 'Login';
      print('[1] form fields: ${formData.keys.toList()}');

      // Шаг 2: POST
      print('[2] POST $loginUri');
      final body = await _postFollowRedirects(loginUri, formData);
      print('[2] body contains logout=${body.contains('logout.php')} '
            'cxrili=${body.contains('cxrili')} '
            'kodi=${body.contains('საგნის კოდი')} '
            'bodyLen=${body.length}');

      if (_isLoggedIn(body)) {
        print('LOGIN SUCCESS (post)');
        return true;
      }

      // Шаг 3: верификация
      print('[3] GET $_scheduleUrl');
      try {
        final verifyResp = await _get(Uri.parse(_scheduleUrl));
        _storeCookies(verifyResp.headers);
        print('[3] status=${verifyResp.statusCode} '
              'logout=${verifyResp.body.contains('logout.php')} '
              'bodyLen=${verifyResp.body.length}');
        if (_isLoggedIn(verifyResp.body)) {
          print('LOGIN SUCCESS (verified)');
          return true;
        }
      } catch (e) {
        print('[3] FAILED: $e');
      }

      print('LOGIN FAILED — no success markers found');
      return false;
    } catch (e) {
      print('LOGIN ERROR: $e');
      return false;
    }
  }

  // ─── GET HTML ───────────────────────────────────────────────────

  static Future<String?> getHtml(String url) async {
    try {
      final resp = await _get(Uri.parse(url));
      if (resp.statusCode == 200) return resp.body;
    } catch (e) {
      print('GET error ($url): $e');
    }
    return null;
  }

  // ─── РАСПИСАНИЕ КОНКРЕТНОГО СЕМЕСТРА ────────────────────────────

  static Future<String?> fetchScheduleForSemester(
      int semId, String semName) async {
    try {
      final body = await _postFollowRedirects(
        Uri.parse(_scheduleUrl),
        {
          'sem_id1':  semId.toString(),
          'semestri': semName,
          'Submit':   'Go',
        },
        referer: _scheduleUrl,
      );
      if (body.isNotEmpty) return body;
    } catch (e) {
      print('fetchScheduleForSemester error: $e');
    }
    return null;
  }

  // ─── УТИЛИТЫ ────────────────────────────────────────────────────

  static String? extractExamUrl(String htmlBody) {
    final doc = html_parser.parse(htmlBody);
    for (final a in doc.querySelectorAll('a')) {
      final href = a.attributes['href'] ?? '';
      if (href.contains('student_exam')) return href;
    }
    return null;
  }

  static bool _isLoggedIn(String body) =>
      body.contains('logout.php') ||
      body.contains('cxrili') ||
      body.contains('საგნის კოდი');

  // ─── ВНУТРЕННИЕ HTTP-УТИЛИТЫ ────────────────────────────────────

  /// GET с браузерными заголовками и текущими куки.
  static Future<http.Response> _get(Uri uri, {String? referer}) {
    return http.get(uri, headers: {
      ..._baseHeaders,
      'Cookie': _cookies,
      if (referer != null) 'Referer': referer,
    });
  }

  /// POST + ручная обработка 301/302/303/307/308 редиректов.
  /// Сохраняет куки на каждом шаге — именно это фиксит потерю
  /// сессии на Android release APK.
  static Future<String> _postFollowRedirects(
    Uri uri,
    Map<String, String> body, {
    String? referer,
    int maxRedirects = 8,
  }) async {
    Uri current = uri;
    bool isPost = true;

    for (int i = 0; i < maxRedirects; i++) {
      final http.Response resp;

      if (isPost) {
        print('[redirect] POST $current');
        resp = await http.post(current, headers: {
          ..._baseHeaders,
          'Cookie':       _cookies,
          'Content-Type': 'application/x-www-form-urlencoded',
          if (referer != null) 'Referer': referer,
        }, body: body);
        isPost = false;
      } else {
        print('[redirect] GET $current');
        resp = await _get(current, referer: referer);
      }

      _storeCookies(resp.headers);
      print('[redirect] → status=${resp.statusCode} cookies=$_cookies');

      final sc = resp.statusCode;
      if (sc == 301 || sc == 302 || sc == 303 ||
          sc == 307 || sc == 308) {
        // Используем строку 'location' напрямую — без dart:io
        final location = resp.headers['location'];
        if (location == null || location.isEmpty) return resp.body;
        current = current.resolve(location);
        continue;
      }

      return resp.body;
    }
    return '';
  }

  /// Разбирает set-cookie и сохраняет в _cookieMap.
  /// Корректно обрабатывает объединённые Set-Cookie через ', '
  /// (поведение пакета http на Android).
  static void _storeCookies(Map<String, String> headers) {
    final raw = headers['set-cookie'];
    if (raw == null || raw.isEmpty) return;

    // Разбиваем по запятой перед новым именем куки,
    // но не внутри значений типа Expires (там тоже есть запятые).
    final entries = raw.split(RegExp(r',\s*(?=[A-Za-z0-9_\-]+=)'));

    for (final entry in entries) {
      final parts = entry.split(';');
      if (parts.isEmpty) continue;
      final kv  = parts.first.trim();
      final eq  = kv.indexOf('=');
      if (eq <= 0) continue;
      final key = kv.substring(0, eq).trim();
      final val = kv.substring(eq + 1).trim();
      if (!_isServiceAttr(key)) {
        _cookieMap[key] = val;
      }
    }

    _cookies = _cookieMap.entries
        .map((e) => '${e.key}=${e.value}')
        .join('; ');
  }

  static bool _isServiceAttr(String key) {
    const attrs = {
      'path', 'domain', 'expires', 'max-age',
      'httponly', 'secure', 'samesite',
    };
    return attrs.contains(key.toLowerCase());
  }
}
