import 'package:flutter/material.dart';
import '../models/payment.dart';
import '../services/parser.dart';
import '../services/language.dart';
import 'main_screen.dart'; // для buildPushedAppBar

// ─────────────────────────────────────────────────────────────────────────────
// PAYMENT SCHEDULE SCREEN
// ─────────────────────────────────────────────────────────────────────────────

class PaymentScheduleScreen extends StatefulWidget {
  final VoidCallback? onMenuTap;
  const PaymentScheduleScreen({super.key, this.onMenuTap});

  @override
  State<PaymentScheduleScreen> createState() => _PaymentScheduleScreenState();
}

class _PaymentScheduleScreenState extends State<PaymentScheduleScreen> {
  DebtStatus?           _debtStatus;
  List<PaymentSemester> _semesters = [];
  bool                  _loading   = true;
  String?               _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error   = null;
    });

    final results = await Future.wait([
      Parser.fetchDebtStatus(),
      Parser.fetchPaymentHistory(),
    ]);

    if (!mounted) return;

    final debt      = results[0] as DebtStatus?;
    final semesters = results[1] as List<PaymentSemester>;

    // Если оба запроса вернули пустые данные — скорее всего сессия истекла
    if (debt == null && semesters.isEmpty) {
      setState(() {
        _loading = false;
        _error   = LanguageService.tr('session_expired_hint');
      });
      return;
    }

    setState(() {
      _debtStatus = debt;
      _semesters  = semesters;
      _loading    = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: LanguageService.currentLang,
      builder: (_, __, ___) {
        final theme   = Theme.of(context);
        final primary = theme.colorScheme.primary;

        return Scaffold(
          appBar: buildPushedAppBar(
            context,
            title:     LanguageService.tr('payment_schedule'),
            onMenuTap: widget.onMenuTap,
          ),
          body: _loading
              ? _buildSkeleton(theme)
              : _error != null
                  ? _buildError(theme, primary)
                  : RefreshIndicator(
                      color:    primary,
                      onRefresh: _load,
                      child: _buildContent(theme, primary),
                    ),
        );
      },
    );
  }

  // ── Контент ─────────────────────────────────────────────────────────────

  Widget _buildContent(ThemeData theme, Color primary) {
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        // Отступ сверху
        const SliverToBoxAdapter(child: SizedBox(height: 12)),

        // ── Карточка статуса долга ───────────────────────────────
        if (_debtStatus != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _DebtStatusCard(status: _debtStatus!),
            ),
          ),

        const SliverToBoxAdapter(child: SizedBox(height: 20)),

        // ── Заголовок истории ────────────────────────────────────
        if (_semesters.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                LanguageService.tr('payment_history'),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  fontSize:   17,
                  letterSpacing: -0.2,
                ),
              ),
            ),
          ),

        const SliverToBoxAdapter(child: SizedBox(height: 10)),

        // ── Список семестров ─────────────────────────────────────
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (_, i) => Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: _SemesterCard(semester: _semesters[i]),
            ),
            childCount: _semesters.length,
          ),
        ),

        // Нижний отступ (навбар)
        const SliverToBoxAdapter(child: SizedBox(height: 110)),
      ],
    );
  }

  // ── Скелетон загрузки ──────────────────────────────────────────────────

  Widget _buildSkeleton(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    final base   = isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.06);
    final shine  = isDark ? Colors.white.withOpacity(0.10) : Colors.black.withOpacity(0.10);

    Widget shimmer(double w, double h, {double radius = 10}) =>
        _ShimmerBox(width: w, height: h, radius: radius, base: base, shine: shine);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Карточка долга
          shimmer(double.infinity, 100, radius: 18),
          const SizedBox(height: 20),
          shimmer(160, 22, radius: 8),
          const SizedBox(height: 12),
          // Семестры
          for (var i = 0; i < 2; i++) ...[
            shimmer(double.infinity, 180, radius: 16),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }

  // ── Ошибка / истёкшая сессия ───────────────────────────────────────────

  Widget _buildError(ThemeData theme, Color primary) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, size: 56,
                color: theme.colorScheme.onSurfaceVariant.withOpacity(0.4)),
            const SizedBox(height: 16),
            Text(
              LanguageService.tr('no_data'),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              _error ?? '',
              style: TextStyle(
                  color: theme.colorScheme.onSurfaceVariant, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text(LanguageService.tr('retry')),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _DebtStatusCard — карточка статуса задолженности
// ─────────────────────────────────────────────────────────────────────────────

class _DebtStatusCard extends StatelessWidget {
  final DebtStatus status;
  const _DebtStatusCard({required this.status});

  @override
  Widget build(BuildContext context) {
    final theme  = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Цвет карточки зависит от наличия долга
    final Color accent =
        status.noDebt ? const Color(0xFF16A34A) : const Color(0xFFDC2626);
    final Color bg = status.noDebt
        ? (isDark
            ? const Color(0xFF052E16).withOpacity(0.85)
            : const Color(0xFFF0FDF4))
        : (isDark
            ? const Color(0xFF450A0A).withOpacity(0.85)
            : const Color(0xFFFEF2F2));

    final IconData icon =
        status.noDebt ? Icons.check_circle_rounded : Icons.warning_amber_rounded;

    final String label = status.noDebt
        ? LanguageService.tr('no_debt')
        : LanguageService.tr('has_debt');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        color:        bg,
        borderRadius: BorderRadius.circular(18),
        border:       Border.all(color: accent.withOpacity(0.35), width: 1.5),
        boxShadow: [
          BoxShadow(
            color:      accent.withOpacity(isDark ? 0.18 : 0.12),
            blurRadius: 20,
            offset:     const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 52, height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accent.withOpacity(0.15),
            ),
            child: Icon(icon, size: 28, color: accent),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  LanguageService.tr('debt_status'),
                  style: TextStyle(
                    fontSize:   12,
                    fontWeight: FontWeight.w600,
                    color:      accent.withOpacity(0.8),
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  label,
                  style: TextStyle(
                    fontSize:   17,
                    fontWeight: FontWeight.w800,
                    color:      accent,
                  ),
                ),
                if (!status.noDebt && status.rawText.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    status.rawText,
                    style: TextStyle(
                      fontSize: 12,
                      color:    accent.withOpacity(0.75),
                    ),
                    maxLines:  3,
                    overflow:  TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _SemesterCard — карточка одного семестра с транзакциями
// ─────────────────────────────────────────────────────────────────────────────

class _SemesterCard extends StatefulWidget {
  final PaymentSemester semester;
  const _SemesterCard({required this.semester});

  @override
  State<_SemesterCard> createState() => _SemesterCardState();
}

class _SemesterCardState extends State<_SemesterCard>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;
  late final AnimationController _ctrl;
  late final Animation<double>   _rotate;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 250));
    _rotate = Tween<double>(begin: 0, end: 0.5).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    _expanded ? _ctrl.forward() : _ctrl.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final theme   = Theme.of(context);
    final isDark  = theme.brightness == Brightness.dark;
    final primary = theme.colorScheme.primary;
    final sem     = widget.semester;

    final Color debtColor = sem.hasDebt
        ? const Color(0xFFDC2626)
        : const Color(0xFF16A34A);

    return Container(
      decoration: BoxDecoration(
        color:        theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outline.withOpacity(0.12),
        ),
        boxShadow: [
          BoxShadow(
            color:      Colors.black.withOpacity(isDark ? 0.25 : 0.06),
            blurRadius: 16,
            offset:     const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // ── Заголовок семестра ────────────────────────────────
          InkWell(
            onTap:        sem.transactions.isNotEmpty ? _toggle : null,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _localizeSemesterName(sem.name),
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            fontSize:   14,
                          ),
                        ),
                        const SizedBox(height: 6),
                        _buildSummaryRow(theme, debtColor, sem),
                      ],
                    ),
                  ),
                  if (sem.transactions.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    RotationTransition(
                      turns: _rotate,
                      child: Icon(
                        Icons.expand_more_rounded,
                        color: theme.colorScheme.onSurfaceVariant,
                        size: 22,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          // ── Развёртка с транзакциями ──────────────────────────
          AnimatedCrossFade(
            firstChild:  const SizedBox.shrink(),
            secondChild: _buildTransactions(theme, primary),
            crossFadeState: _expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 240),
            sizeCurve: Curves.easeOutCubic,
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(
      ThemeData theme, Color debtColor, PaymentSemester sem) {
    final muted = theme.colorScheme.onSurfaceVariant;
    return Wrap(
      spacing: 12,
      runSpacing: 4,
      children: [
        _Chip(
          label: LanguageService.tr('paid_label'),
          value: sem.formattedPaid,
          color: const Color(0xFF16A34A),
        ),
        _Chip(
          label: LanguageService.tr('debt_label'),
          value: sem.formattedDebt,
          color: debtColor,
        ),
        _Chip(
          label: LanguageService.tr('total_label'),
          value: sem.formattedTotal,
          color: muted,
        ),
      ],
    );
  }

  Widget _buildTransactions(ThemeData theme, Color primary) {
    final muted = theme.colorScheme.onSurfaceVariant;
    return Column(
      children: [
        Divider(
          height: 1,
          thickness: 1,
          color: theme.colorScheme.outline.withOpacity(0.10),
          indent: 16, endIndent: 16,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                LanguageService.tr('transactions_label'),
                style: TextStyle(
                  fontSize:   11,
                  fontWeight: FontWeight.w700,
                  color:      muted,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 8),
              ...widget.semester.transactions.asMap().entries.map((e) {
                final isLast =
                    e.key == widget.semester.transactions.length - 1;
                final tx = e.value;
                return Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 8, height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: primary.withOpacity(0.7),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            tx.formattedDate,
                            style: TextStyle(
                                fontSize: 13,
                                color: theme.colorScheme.onSurface),
                          ),
                        ),
                        Text(
                          tx.formattedAmount,
                          style: const TextStyle(
                            fontSize:   14,
                            fontWeight: FontWeight.w700,
                            color:      Color(0xFF16A34A),
                          ),
                        ),
                      ],
                    ),
                    if (!isLast) ...[
                      const SizedBox(height: 2),
                      Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: SizedBox(
                          width: 1, height: 10,
                          child: VerticalDivider(
                            color: primary.withOpacity(0.25), thickness: 1),
                        ),
                      ),
                      const SizedBox(height: 2),
                    ] else
                      const SizedBox(height: 4),
                  ],
                );
              }),
            ],
          ),
        ),
      ],
    );
  }

  /// Локализует названия семестров.
  ///
  /// Пример: "2025 შემოდგომის სემესტრი" →
  ///   EN: "2025 Autumn Semester"
  ///   RU: "2025 Осенний семестр"
  ///   KA: исходное
  String _localizeSemesterName(String name) {
    final lang = LanguageService.currentLang.value;
    if (lang == 'ქართული') return name;

    final Map<String, String> seasonMap = {
      'გაზაფხულის': LanguageService.tr('sem_spring'),
      'შემოდგომის': LanguageService.tr('sem_autumn'),
      'ზაფხულის':   LanguageService.tr('sem_summer'),
      'ზამთრის':    LanguageService.tr('sem_winter'),
    };
    final semWord = LanguageService.tr('sem_semester');

    var result = name;
    seasonMap.forEach((ka, loc) {
      if (result.contains(ka)) {
        result = result
            .replaceAll(ka, loc)
            .replaceAll('სემესტრი', semWord);
      }
    });
    return result;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Вспомогательные виджеты
// ─────────────────────────────────────────────────────────────────────────────

class _Chip extends StatelessWidget {
  final String label;
  final String value;
  final Color  color;
  const _Chip({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        children: [
          TextSpan(
            text: '$label: ',
            style: TextStyle(
              fontSize: 11,
              color:    color.withOpacity(0.7),
              fontWeight: FontWeight.w500,
            ),
          ),
          TextSpan(
            text: value,
            style: TextStyle(
              fontSize:   13,
              color:      color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// Простой шиммер-прямоугольник для скелетона.
class _ShimmerBox extends StatefulWidget {
  final double width;
  final double height;
  final double radius;
  final Color  base;
  final Color  shine;
  const _ShimmerBox({
    required this.width,
    required this.height,
    required this.radius,
    required this.base,
    required this.shine,
  });

  @override
  State<_ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<_ShimmerBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double>   _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1100))
      ..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Container(
        width:  widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.radius),
          color: Color.lerp(widget.base, widget.shine, _anim.value),
        ),
      ),
    );
  }
}
