/// Одна транзакция (дата + сумма) из <select> в gadaxda.php
class PaymentTransaction {
  final String dateTime; // "2025-09-05 15:13:27"
  final double amount;   // 3050.00

  const PaymentTransaction({required this.dateTime, required this.amount});

  /// Форматирует дату: "2025-09-05 15:13:27" → "05.09.2025  15:13"
  String get formattedDate {
    try {
      final parts = dateTime.trim().split(' ');
      if (parts.isEmpty) return dateTime;
      final dateParts = parts[0].split('-');
      if (dateParts.length < 3) return dateTime;
      final formatted = '${dateParts[2]}.${dateParts[1]}.${dateParts[0]}';
      if (parts.length > 1) {
        final timeParts = parts[1].split(':');
        if (timeParts.length >= 2) {
          return '$formatted  ${timeParts[0]}:${timeParts[1]}';
        }
      }
      return formatted;
    } catch (_) {
      return dateTime;
    }
  }

  /// "3050.00" → "3,050.00 ₾"
  String get formattedAmount => '${_fmt(amount)} ₾';

  static String _fmt(double v) {
    final s = v.toStringAsFixed(2);
    final parts = s.split('.');
    final intPart = parts[0];
    final decPart = parts.length > 1 ? parts[1] : '00';
    final buf = StringBuffer();
    for (var i = 0; i < intPart.length; i++) {
      if (i > 0 && (intPart.length - i) % 3 == 0) buf.write(',');
      buf.write(intPart[i]);
    }
    return '$buf.$decPart';
  }
}

/// Один семестр из таблицы gadaxda.php
class PaymentSemester {
  final String name;
  final double totalAmount;
  final double examFee;
  final double penalty;
  final double paidAmount;
  final double debtAmount;
  final List<PaymentTransaction> transactions;

  const PaymentSemester({
    required this.name,
    required this.totalAmount,
    required this.examFee,
    required this.penalty,
    required this.paidAmount,
    required this.debtAmount,
    required this.transactions,
  });

  bool get hasDebt => debtAmount > 0.005;

  String get formattedDebt => '${PaymentTransaction._fmt(debtAmount)} ₾';
  String get formattedPaid => '${PaymentTransaction._fmt(paidAmount)} ₾';
  String get formattedTotal => '${PaymentTransaction._fmt(totalAmount)} ₾';
}

/// Результат парсинга C_PaymentSchedule.php
class DebtStatus {
  /// true — у студента НЕТ долга ("ვალი არ გაქვთ")
  final bool noDebt;

  /// Исходный текст со страницы (если долг есть — может содержать сумму/пояснение)
  final String rawText;

  const DebtStatus({required this.noDebt, required this.rawText});
}
