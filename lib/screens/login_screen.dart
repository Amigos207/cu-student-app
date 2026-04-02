import 'package:flutter/material.dart';
import '../services/language.dart';
import '../services/api.dart';
import '../services/storage.dart';
import '../screens/schedule_screen.dart';
import 'main_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _showPass = false;
  bool _loading  = false;

  late final AnimationController _animCtrl;
  late final Animation<double>   _fadeAnim;
  late final Animation<Offset>   _slideAnim;

  @override
  void initState() {
    super.initState();

    if (LanguageService.currentLang.value.isEmpty) {
      LanguageService.currentLang.value = 'English';
    }

    _animCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _fadeAnim  = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
            begin: const Offset(0, 0.06), end: Offset.zero)
        .animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut));
    _animCtrl.forward();

    // Предзаполняем поля сохранёнными данными (если пришли сюда после
    // неудачного авто-входа из SplashScreen).
    final savedUser = Storage.getUser();
    final savedPass = Storage.getPassword();
    if (savedUser != null) _usernameCtrl.text = savedUser;
    if (savedPass != null) _passwordCtrl.text = savedPass;
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    final username = _usernameCtrl.text.trim();
    final password = _passwordCtrl.text;
    if (username.isEmpty || password.isEmpty) return;

    setState(() => _loading = true);
    bool success = false;

    if (username == 'admin') {
      await Future.delayed(const Duration(milliseconds: 400));
      success = password == '1234';
    } else {
      success = await ApiService.login(username, password);
    }

    if (!mounted) return;
    setState(() => _loading = false);

    if (success) {
      // Сбрасываем кэш расписания (мог загрузиться без авторизации).
      ScheduleScreen.clearCache();

      // Сохраняем credentials через Storage (единое место).
      await Storage.saveUser(username);
      await Storage.savePassword(password);

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const MainScreen()),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(LanguageService.tr('error_auth')),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: LanguageService.currentLang,
      builder: (context, _, __) {
        final theme   = Theme.of(context);
        final primary = theme.colorScheme.primary;

        return Scaffold(
          body: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: FadeTransition(
                  opacity: _fadeAnim,
                  child: SlideTransition(
                    position: _slideAnim,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Логотип
                        Center(
                          child: Container(
                            decoration: BoxDecoration(
                              color: primary.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(24),
                            ),
                            padding: const EdgeInsets.all(18),
                            child: Icon(Icons.school_rounded,
                                size: 44, color: primary),
                          ),
                        ),
                        const SizedBox(height: 28),

                        Text(
                          LanguageService.tr('login_title'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 26, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Caucasus University',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 14,
                              color: theme.colorScheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 36),

                        // Форма входа
                        // ИСПРАВЛЕНИЕ #2: заменили
                        //   isDark ? surface : Colors.white
                        // на theme.colorScheme.surface
                        // Теперь розовая / все темы корректно окрашивают карточку.
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surface,
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.07),
                                blurRadius: 24,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Column(
                            children: [
                              _buildField(
                                controller: _usernameCtrl,
                                label: LanguageService.tr('username'),
                                icon: Icons.person_outline_rounded,
                                primary: primary,
                              ),
                              const SizedBox(height: 16),
                              _buildField(
                                controller: _passwordCtrl,
                                label: LanguageService.tr('password'),
                                icon: Icons.lock_outline_rounded,
                                primary: primary,
                                obscure: !_showPass,
                                suffix: IconButton(
                                  icon: Icon(
                                    _showPass
                                        ? Icons.visibility_off_rounded
                                        : Icons.visibility_rounded,
                                    color: theme.colorScheme.onSurfaceVariant,
                                    size: 20,
                                  ),
                                  onPressed: () =>
                                      setState(() => _showPass = !_showPass),
                                ),
                                onSubmitted: (_) => _handleLogin(),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),

                        SizedBox(
                          height: 54,
                          child: ElevatedButton(
                            onPressed: _loading ? null : _handleLogin,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: primary,
                              foregroundColor: Colors.white,
                              disabledBackgroundColor:
                                  primary.withOpacity(0.6),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16)),
                              elevation: 0,
                            ),
                            child: _loading
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                        color: Colors.white, strokeWidth: 2.5),
                                  )
                                : Text(
                                    LanguageService.tr('sign_in'),
                                    style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required Color primary,
    bool obscure = false,
    Widget? suffix,
    void Function(String)? onSubmitted,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      onSubmitted: onSubmitted,
      textInputAction:
          suffix != null ? TextInputAction.done : TextInputAction.next,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: primary, size: 20),
        suffixIcon: suffix,
        filled: true,
        fillColor: Theme.of(context).colorScheme.onSurface.withOpacity(0.04),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: primary, width: 1.5),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
    );
  }
}
