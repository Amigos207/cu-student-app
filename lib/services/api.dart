import 'dart:io' as io;
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import 'storage.dart';

class ApiService {
  static const String _baseUrl        = 'https://programs.cu.edu.ge/cu';
  static const String _scheduleUrl    = 'https://programs.cu.edu.ge/students/schedule.php';
  static const String _attendanceUrl  = 'https://programs.cu.edu.ge/students/agricxva_cxrili.php';
  static const String _gradesUrl      = 'https://programs.cu.edu.ge/students/gpa.php';
  static const String _gradeDetailUrl = 'https://programs.cu.edu.ge/cu/controllers/students/C_Grade.php';
  static const String _myAccountUrl   = 'https://programs.cu.edu.ge/students/myaccount.php';
  static const String _profileUrl            = 'https://programs.cu.edu.ge/students/studenti_piradi.php';
  static const String _paymentScheduleUrl    = 'https://programs.cu.edu.ge/cu/controllers/students/C_PaymentSchedule.php';
  static const String _paymentHistoryUrl     = 'https://programs.cu.edu.ge/students/gadaxda.php';

  // Endpoint смены семестра на странице экзаменов.
  // POST: sem_id, stud_id, lang=ka  +  заголовок X-CSRF-TOKEN
  // Ответ: JSON {"html": "<table>...</table>"}
  static const String _filterExamSemesterUrl =
      'https://net.cu.edu.ge/filterExamSemester';

  // ── programs.cu.edu.ge session ─────────────────────────────────
  static String _cookies = '';
  static final Map<String, String> _cookieMap = {};

  // ── net.cu.edu.ge session (отдельный домен) ────────────────────
  static String _netCookies = '';
  static final Map<String, String> _netCookieMap = {};

  // ── In-memory HTML cache (3 минуты TTL) ───────────────────────
  // Предотвращает дублирующиеся HTTP-запросы к одному URL
  // (например, schedule.php запрашивают и HomeScreen, и ScheduleScreen).
  static final Map<String, (String, DateTime)> _htmlCache = {};
  static const _htmlCacheTtl = Duration(minutes: 3);

  // ── In-flight request deduplication ───────────────────────────
  // If two callers request the same URL before the first response arrives,
  // the second caller receives the *same* Future instead of firing a new
  // HTTP request.  This eliminates the race condition that caused duplicate
  // network calls on app startup (HomeScreen + ScheduleScreen both fetching
  // schedule.php simultaneously).
  static final Map<String, Future<String?>> _inFlight = {};

  static String? _getCachedHtml(String url) {
    final entry = _htmlCache[url];
    if (entry == null) return null;
    if (DateTime.now().difference(entry.$2) > _htmlCacheTtl) {
      _htmlCache.remove(url);
      return null;
    }
    return entry.$1;
  }

  static void _setCachedHtml(String url, String html) {
    _htmlCache[url] = (html, DateTime.now());
  }

  /// Очищает HTML-кэш (вызывается при forceRefresh).
  static void clearHtmlCache() {
    _htmlCache.clear();
    _inFlight.clear(); // cancel any in-flight dedup references
  }

  /// Полностью сбрасывает состояние сессии.
  /// Вызывать при logout И в начале login, чтобы куки предыдущего
  /// аккаунта не мешали авторизации нового.
  static void clearSession() {
    _cookies      = '';
    _netCookies   = '';
    _cookieMap.clear();
    _netCookieMap.clear();
    _htmlCache.clear();
    _inFlight.clear();
  }

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
  static String get gradesUrl     => _gradesUrl;

  static Future<String?> fetchProfileHtml() => getHtmlWithRetry(_profileUrl);

  /// Загружает страницу статуса долга (C_PaymentSchedule.php).
  static Future<String?> fetchPaymentScheduleHtml() =>
      withSessionRetry(() => getHtml(_paymentScheduleUrl));

  /// Загружает страницу истории платежей (gadaxda.php).
  static Future<String?> fetchPaymentHistoryHtml() =>
      withSessionRetry(() => getHtml(_paymentHistoryUrl));

  // ─── ЭКЗАМЕНЫ ───────────────────────────────────────────────────

  /// Загружает главную страницу портала — источник токен-ссылки.
  static Future<String?> fetchMyAccountHtml() => getHtml(_myAccountUrl);

  /// Извлекает токен-ссылку вида:
  /// https://net.cu.edu.ge/student_exam/STUD_ID/TYPE/TOKEN/SEM
  static String? extractStudentExamUrl(String html) {
    final m = RegExp(
      r'https://net\.cu\.edu\.ge/student_exam/\d+/\d+/[a-z0-9]+/\d+',
    ).firstMatch(html);
    return m?.group(0);
  }

  /// Извлекает stud_id из токен-URL:
  /// https://net.cu.edu.ge/student_exam/10019392/... → "10019392"
  static String extractStudId(String tokenUrl) {
    final m = RegExp(r'student_exam/(\d+)/').firstMatch(tokenUrl);
    return m?.group(1) ?? '';
  }

  /// Загружает страницу student_exam_recovery по токен-ссылке.
  ///
  /// Сервер всегда делает 302 → student_exam_recovery — это ожидаемое
  /// и единственно правильное поведение. Метод следует за редиректом
  /// и возвращает HTML страницы recovery (status 200).
  static Future<String?> fetchExamRecoveryPage(String tokenUrl) async {
    try {
      return await _ioGetFollowRedirects(tokenUrl, referer: _myAccountUrl);
    } catch (e) {
      print('fetchExamRecoveryPage error: $e');
      return null;
    }
  }

  /// POST на /filterExamSemester для получения таблицы нужного семестра.
  ///
  /// Сервер возвращает JSON: {"html": "<table>...</table>"}
  /// Метод парсит JSON и возвращает содержимое поля "html".
  ///
  /// [csrfToken] — значение <meta name="csrf-token"> со страницы recovery.
  /// [studId]    — ID студента из токен-URL.
  static Future<String?> fetchExamSemesterHtml({
    required int    semId,
    required String studId,
    required String csrfToken,
  }) async {
    try {
      final uri = Uri.parse(_filterExamSemesterUrl);

      // Браузер отправляет multipart/form-data через new FormData()
      final request = http.MultipartRequest('POST', uri);
      request.headers.addAll({
        'User-Agent':        _ua,
        'X-CSRF-TOKEN':      csrfToken,
        'Cookie':            _netCookies,
        'Accept':            'application/json, text/javascript, */*; q=0.01',
        'X-Requested-With':  'XMLHttpRequest',
        'Referer':           'https://net.cu.edu.ge/student_exam_recovery',
      });
      request.fields['sem_id']  = semId.toString();
      request.fields['stud_id'] = studId;
      request.fields['lang']    = 'ka';

      final streamed = await request.send();
      _storeCookiesFromMap(streamed.headers, isNet: true);

      final body = await streamed.stream.bytesToString();
      print('filterExamSemester: status=${streamed.statusCode} '
            'bodyLen=${body.length}');

      // Всегда печатаем начало ответа — главный инструмент диагностики
      final preview = body.length > 1500 ? body.substring(0, 1500) : body;
      print('filterExamSemester: body_preview=[$preview]');

      if (streamed.statusCode != 200) {
        print('filterExamSemester: unexpected status=${streamed.statusCode}');
        return null;
      }

      // ── Попытка 1: тело — JSON {"html": "..."}  (штатный режим) ──
      final trimmed = body.trimLeft();
      if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
        try {
          final decoded = jsonDecode(body) as Map<String, dynamic>;
          final fragment = decoded['html'] as String?;
          if (fragment != null && fragment.isNotEmpty) {
            print('filterExamSemester: JSON ok, html len=${fragment.length}');
            return fragment;
          }
          // JSON есть, но поля "html" нет — логируем ключи
          print('filterExamSemester: JSON parsed but no "html" key. '
                'keys=${decoded.keys.toList()}');
        } catch (jsonErr) {
          print('filterExamSemester: jsonDecode failed: $jsonErr');
        }
      }

      // ── Попытка 2: тело — сырой HTML (сервер иногда отдаёт text/html) ──
      if (trimmed.startsWith('<') ||
          body.contains('<table') ||
          body.contains('<tr')) {
        print('filterExamSemester: treating body as raw HTML');
        return body;
      }

      print('filterExamSemester: could not extract HTML from response');
    } catch (e, st) {
      print('fetchExamSemesterHtml error: $e\n$st');
    }
    return null;
  }

  // ─── dart:io GET с ручным следованием редиректам ───────────────

  static Future<String?> _ioGetFollowRedirects(
    String startUrl, {
    String? referer,
    int maxHops = 10,
  }) async {
    Uri current = Uri.parse(startUrl);

    for (int hop = 0; hop < maxHops; hop++) {
      final isNet            = current.host.contains('net.cu.edu.ge');
      final cookiesForDomain = isNet ? _netCookies : _cookies;

      final client = io.HttpClient()..userAgent = null;
      try {
        final req = await client.getUrl(current);
        req.followRedirects = false;
        req.headers.set('User-Agent',      _ua);
        req.headers.set('Accept',
            'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8');
        req.headers.set('Accept-Language', 'ka,en-US;q=0.9,en;q=0.8,ru;q=0.7');
        if (referer != null) req.headers.set('Referer', referer);
        if (cookiesForDomain.isNotEmpty)
          req.headers.set('Cookie', cookiesForDomain);

        final resp = await req.close();
        final sc   = resp.statusCode;
        print('ioGet[hop=$hop isNet=$isNet]: $sc $current');

        _storeCookiesIo(resp.headers, isNet: isNet);

        if (sc >= 300 && sc < 400) {
          final location = resp.headers.value('location');
          print('  → redirect: $location');
          await resp.drain<void>();
          if (location != null && location.isNotEmpty) {
            referer = current.toString();
            current = current.resolve(location);
            continue;
          }
        }

        if (sc == 200) {
          final bytes = await resp.fold<List<int>>(
              [], (buf, chunk) => buf..addAll(chunk));
          return utf8.decode(bytes, allowMalformed: true);
        }

        print('ioGet: unexpected status=$sc');
        await resp.drain<void>();
        return null;
      } finally {
        client.close();
      }
    }
    print('ioGet: exceeded maxHops');
    return null;
  }

  // ─── АВТОРИЗАЦИЯ ────────────────────────────────────────────────

  static Future<bool> login(String username, String password) async {
    try {
      print('=== START LOGIN ===');
      clearSession(); // Сбрасываем любую предыдущую сессию перед входом

      final loginUri = Uri.parse('$_baseUrl/loginStud');

      print('[1] GET $loginUri');
      final getResp = await _get(loginUri);
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

      print('[2] POST $loginUri');
      final body = await _postFollowRedirects(loginUri, formData);
      if (_isLoggedIn(body)) { print('LOGIN SUCCESS (post)'); return true; }

      print('[3] GET $_scheduleUrl');
      try {
        final verifyResp = await _get(Uri.parse(_scheduleUrl));
        _storeCookies(verifyResp.headers);
        if (_isLoggedIn(verifyResp.body)) {
          print('LOGIN SUCCESS (verified)');
          return true;
        }
      } catch (e) { print('[3] FAILED: $e'); }

      print('LOGIN FAILED');
      return false;
    } catch (e) {
      print('LOGIN ERROR: $e');
      return false;
    }
  }

  // ─── GET HTML ───────────────────────────────────────────────────

  static Future<String?> getHtml(String url) {
    // 1. Check the TTL cache first — cheapest path.
    final cached = _getCachedHtml(url);
    if (cached != null) {
      print('[ApiService] cache hit: $url');
      return Future.value(cached);
    }

    // 2. If a request for this URL is already in flight, join it instead of
    //    firing a second HTTP request.  This is the key fix for the startup
    //    race condition where HomeScreen and ScheduleScreen both requested
    //    schedule.php before the first response arrived.
    if (_inFlight.containsKey(url)) {
      print('[ApiService] dedup hit (in-flight): $url');
      return _inFlight[url]!;
    }

    // 3. No cache and no in-flight request — start one and register it.
    final future = _doGetHtml(url);
    _inFlight[url] = future;
    return future;
  }

  static Future<String?> _doGetHtml(String url) async {
    try {
      final resp = await _get(Uri.parse(url));
      if (resp.statusCode == 200) {
        _setCachedHtml(url, resp.body);
        return resp.body;
      }
    } catch (e) {
      print('GET error ($url): $e');
    } finally {
      _inFlight.remove(url);
    }
    return null;
  }

  // ─── ПЕРЕРАСЧЕТ GPA ─────────────────────────────────────────────

  static Future<String> fetchCalculatedGradesHtml() async {
    const calculateUrl = 'https://programs.cu.edu.ge/students/gpa_datvla.php';
    try {
      await _postFollowRedirects(
        Uri.parse(calculateUrl),
        {'submit': 'GPA-ის გამოთვლა'},
        referer: _gradesUrl,
      );
      return await getHtml(_gradesUrl) ?? '';
    } catch (e) {
      return await getHtml(_gradesUrl) ?? '';
    }
  }

  // ─── ДЕТАЛИ ПРЕДМЕТА ────────────────────────────────────────────

  static Future<String?> getSubjectDetailHtml(String cxrId) async {
    try {
      final body = await _postFollowRedirects(
        Uri.parse(_gradeDetailUrl),
        {'cxr_id': cxrId, 'submit': 'Go'},
        referer: _gradesUrl,
      );
      return body.isNotEmpty ? body : null;
    } catch (e) {
      print('getSubjectDetailHtml error ($cxrId): $e');
      return null;
    }
  }

  static const String _syllabusListUrl =
      'https://programs.cu.edu.ge/students/sylab.php';
  static const String _syllabusPdfUrl =
      'https://programs.cu.edu.ge/cu/models/Syllabus_pdfENG_students';

  /// GET the syllabus list for the current semester, or POST to switch semester.
  static Future<String?> fetchSyllabusList({
    String? semesterId,
    String? semesterName,
  }) =>
      withSessionRetry(() async {
        if (semesterId != null && semesterName != null) {
          final body = await _postFollowRedirects(
            Uri.parse(_syllabusListUrl),
            {
              'sem_id1':  semesterId,
              'semestri': semesterName,
              'Submit':   'Go',
            },
            referer: _syllabusListUrl,
          );
          return body.isNotEmpty ? body : null;
        }
        return getHtml(_syllabusListUrl);
      });

  /// POST to Syllabus_pdfENG_students and return raw PDF bytes.
  /// Returns null on failure.
  static Future<List<int>?> downloadSyllabusPdf({
    required String studentId,
    required String cxrId,
  }) =>
      withSessionRetry(() async {
        try {
          final uri = Uri.parse(_syllabusPdfUrl);
          final resp = await http.post(
            uri,
            headers: {
              ..._baseHeaders,
              'Cookie':       _cookies,
              'Content-Type': 'application/x-www-form-urlencoded',
              'Referer':      _syllabusListUrl,
            },
            body: {'id': studentId, 'cxr_id': cxrId, 'submit5': 'სილაბუსები'},
          );
          _storeCookies(resp.headers);
          if (resp.statusCode == 200 && resp.bodyBytes.length > 500) {
            return resp.bodyBytes.toList();
          }
        } catch (e) {
          print('downloadSyllabusPdf error: $e');
        }
        return null;
      });

  // ─── МАТЕРИАЛЫ ──────────────────────────────────────────────────

  static const String _materialsListUrl   =
      'https://programs.cu.edu.ge/students/masalebi_1.php';
  static const String _materialsDetailUrl =
      'https://programs.cu.edu.ge/students/masalebi.php';

  /// GET the materials list (default semester), or POST to switch semester.
  static Future<String?> fetchMaterialsList({
    String? semesterId,
    String? semesterName,
  }) =>
      withSessionRetry(() async {
        if (semesterId != null && semesterName != null) {
          final body = await _postFollowRedirects(
            Uri.parse(_materialsListUrl),
            {
              'sem_id1':  semesterId,
              'semestri': semesterName,
              'Submit':   'Go',
            },
            referer: _materialsListUrl,
          );
          return body.isNotEmpty ? body : null;
        }
        return getHtml(_materialsListUrl);
      });

  /// POST to masalebi.php with the payload from the subject form.
  static Future<String?> fetchMaterialDetails(
          Map<String, String> payload) =>
      withSessionRetry(() async {
        final body = await _postFollowRedirects(
          Uri.parse(_materialsDetailUrl),
          payload,
          referer: _materialsListUrl,
        );
        return body.isNotEmpty ? body : null;
      });

  // ─── РАСПИСАНИЕ КОНКРЕТНОГО СЕМЕСТРА ────────────────────────────

  static Future<String?> fetchScheduleForSemester(
      int semId, String semName) async {
    try {
      final body = await _postFollowRedirects(
        Uri.parse(_scheduleUrl),
        {'sem_id1': semId.toString(), 'semestri': semName, 'Submit': 'Go'},
        referer: _scheduleUrl,
      );
      if (body.isNotEmpty) return body;
    } catch (e) { print('fetchScheduleForSemester error: $e'); }
    return null;
  }

  // ─── УТИЛИТЫ ────────────────────────────────────────────────────

  static bool _isLoggedIn(String body) =>
      body.contains('logout.php') ||
      body.contains('cxrili') ||
      body.contains('საგნის კოდი');

  /// Returns true when the HTML looks like a login/redirect page
  /// (session expired or was never established).
  static bool _isSessionExpired(String? body) {
    if (body == null || body.isEmpty) return true;
    // Login page contains a username/password form and NO user-specific content
    final hasLoginForm = body.contains('loginStud') ||
        body.contains('type="password"') ||
        body.contains('name="username"');
    final hasUserContent = _isLoggedIn(body);
    return hasLoginForm && !hasUserContent;
  }

  /// Silently re-authenticates using stored credentials, then retries [action].
  ///
  /// Call this whenever a network fetch returns suspicious empty/login HTML.
  /// Returns the result of [action] after re-login, or null if re-login fails.
  static Future<T?> withSessionRetry<T>(Future<T?> Function() action) async {
    // First attempt
    final result = await action();
    if (result != null) return result;

    // Try to detect if the session is dead by pinging schedule page
    try {
      final probe = await _get(Uri.parse(_scheduleUrl));
      if (!_isSessionExpired(probe.body)) {
        // Session alive, just empty data
        return result;
      }
    } catch (_) {
      // Network error (SocketException etc.) — NOT a session problem.
      // Do NOT attempt re-login: login() calls clearSession() which would
      // wipe valid cookies, breaking all subsequent requests once network
      // comes back.
      print('[ApiService] withSessionRetry: network error during probe — '
            'keeping session intact, returning null');
      return result;
    }

    // Session appears dead — attempt silent re-login
    print('[ApiService] Session expired. Attempting silent re-login...');
    final username = Storage.getUser();
    final password = Storage.getPassword();
    if (username == null || password == null) {
      print('[ApiService] No stored credentials — cannot re-login');
      return null;
    }

    final ok = await login(username, password);
    if (!ok) {
      print('[ApiService] Silent re-login FAILED');
      return null;
    }
    print('[ApiService] Silent re-login OK — retrying action');
    return action();
  }

  /// Like [getHtml] but transparently re-logs in if the session is expired.
  static Future<String?> getHtmlWithRetry(String url) =>
      withSessionRetry(() => getHtml(url));

  // ─── ВНУТРЕННИЕ HTTP-УТИЛИТЫ ────────────────────────────────────

  static Future<http.Response> _get(Uri uri, {String? referer}) =>
      http.get(uri, headers: {
        ..._baseHeaders,
        'Cookie': _cookies,
        if (referer != null) 'Referer': referer,
      });

  static Future<String> _postFollowRedirects(
    Uri uri,
    Map<String, String> body, {
    String? referer,
    int maxRedirects = 8,
  }) async {
    Uri  current = uri;
    bool isPost  = true;
    for (int i = 0; i < maxRedirects; i++) {
      final http.Response resp;
      if (isPost) {
        resp = await http.post(current, headers: {
          ..._baseHeaders,
          'Cookie':       _cookies,
          'Content-Type': 'application/x-www-form-urlencoded',
          if (referer != null) 'Referer': referer,
        }, body: body);
        isPost = false;
      } else {
        resp = await _get(current, referer: referer);
      }
      _storeCookies(resp.headers);
      final sc = resp.statusCode;
      if (sc == 301 || sc == 302 || sc == 303 || sc == 307 || sc == 308) {
        final location = resp.headers['location'];
        if (location == null || location.isEmpty) return resp.body;
        current = current.resolve(location);
        continue;
      }
      return resp.body;
    }
    return '';
  }

  static void _storeCookies(Map<String, String> headers) {
    final raw = headers['set-cookie'];
    if (raw == null || raw.isEmpty) return;
    for (final entry in raw.split(RegExp(r',\s*(?=[A-Za-z0-9_\-]+=)'))) {
      final parts = entry.split(';');
      if (parts.isEmpty) continue;
      final kv  = parts.first.trim();
      final eq  = kv.indexOf('=');
      if (eq <= 0) continue;
      final key = kv.substring(0, eq).trim();
      final val = kv.substring(eq + 1).trim();
      if (!_isServiceAttr(key)) _cookieMap[key] = val;
    }
    _cookies = _cookieMap.entries.map((e) => '${e.key}=${e.value}').join('; ');
  }

  static void _storeCookiesIo(io.HttpHeaders headers, {required bool isNet}) {
    final targetMap = isNet ? _netCookieMap : _cookieMap;
    headers.forEach((name, values) {
      if (name.toLowerCase() != 'set-cookie') return;
      for (final raw in values) {
        final parts = raw.split(';');
        if (parts.isEmpty) continue;
        final kv  = parts.first.trim();
        final eq  = kv.indexOf('=');
        if (eq <= 0) continue;
        final key = kv.substring(0, eq).trim();
        final val = kv.substring(eq + 1).trim();
        if (!_isServiceAttr(key)) targetMap[key] = val;
      }
    });
    final joined =
        targetMap.entries.map((e) => '${e.key}=${e.value}').join('; ');
    if (isNet) { _netCookies = joined; } else { _cookies = joined; }
  }

  static void _storeCookiesFromMap(Map<String, String> headers,
      {required bool isNet}) {
    final raw = headers['set-cookie'];
    if (raw == null || raw.isEmpty) return;
    final targetMap = isNet ? _netCookieMap : _cookieMap;
    for (final entry in raw.split(RegExp(r',\s*(?=[A-Za-z0-9_\-]+=)'))) {
      final parts = entry.split(';');
      if (parts.isEmpty) continue;
      final kv  = parts.first.trim();
      final eq  = kv.indexOf('=');
      if (eq <= 0) continue;
      final key = kv.substring(0, eq).trim();
      final val = kv.substring(eq + 1).trim();
      if (!_isServiceAttr(key)) targetMap[key] = val;
    }
    final joined =
        targetMap.entries.map((e) => '${e.key}=${e.value}').join('; ');
    if (isNet) { _netCookies = joined; } else { _cookies = joined; }
  }

  static bool _isServiceAttr(String key) {
    const attrs = {
      'path', 'domain', 'expires', 'max-age',
      'httponly', 'secure', 'samesite',
    };
    return attrs.contains(key.toLowerCase());
  }
}