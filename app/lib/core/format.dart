import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

import '../l10n/gen/app_localizations.dart';

typedef Json = Map<String, dynamic>;

extension L10nX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
  String get lang => Localizations.localeOf(this).languageCode;
}

final _money = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

/// ₹12,500 (Indian digit grouping).
String money(num? value) => _money.format(value ?? 0);

int asInt(dynamic v) => v == null ? 0 : (v is num ? v.toInt() : int.tryParse('$v') ?? 0);

DateTime? asDate(dynamic v) => v == null ? null : DateTime.tryParse('$v')?.toLocal();

/// 11 Oct 2026
String dateText(BuildContext context, dynamic v) {
  final d = v is DateTime ? v : asDate(v);
  if (d == null) return '—';
  return DateFormat('d MMM yyyy', context.lang).format(d);
}

/// 11 Oct
String shortDate(BuildContext context, dynamic v) {
  final d = v is DateTime ? v : asDate(v);
  if (d == null) return '—';
  return DateFormat('d MMM', context.lang).format(d);
}

String monthText(BuildContext context, DateTime d) => DateFormat('MMMM yyyy', context.lang).format(d);

/// yyyy-MM-dd for the server.
String isoDate(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

DateTime today() {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day);
}

/// "+919876543210" -> "98765 43210"
String phoneText(String? phone) {
  if (phone == null) return '—';
  final d = phone.replaceAll(RegExp(r'\D'), '');
  final ten = d.length >= 10 ? d.substring(d.length - 10) : d;
  if (ten.length != 10) return phone;
  return '${ten.substring(0, 5)} ${ten.substring(5)}';
}

/// Accepts 10 digits / 91… / +91…; returns +91XXXXXXXXXX or null if invalid.
String? normalizePhone(String input) {
  final d = input.replaceAll(RegExp(r'\D'), '');
  final ten = d.length == 12 && d.startsWith('91') ? d.substring(2) : d;
  if (!RegExp(r'^[6-9]\d{9}$').hasMatch(ten)) return null;
  return '+91$ten';
}

/// Room / bed text, e.g. "204 · B".
String roomBed(dynamic room, dynamic bed) {
  if (room == null) return '—';
  return bed == null ? '$room' : '$room · $bed';
}
