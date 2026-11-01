import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/format.dart';
import '../theme.dart';
import 'common.dart';

/// UPI payment link with amount and payment note already filled in.
String upiLink({required String upiId, required String payee, required int amount, required String note}) {
  final q = {
    'pa': upiId,
    'pn': payee,
    'am': '$amount.00',
    'cu': 'INR',
    'tn': note,
  }.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&');
  return 'upi://pay?$q';
}

/// UPI apps the owner can switch on in Hostel settings (opened with the same UPI details).
const _upiAppSchemes = {'gpay': 'tez://upi/pay', 'phonepe': 'phonepe://pay', 'paytm': 'paytmmp://pay'};

String _upiAppName(BuildContext context, String app) {
  final t = context.l10n;
  return switch (app) { 'gpay' => t.payGpay, 'phonepe' => t.payPhonepe, 'paytm' => t.payPaytm, _ => app };
}

/// Methods the hostel accepts, from the "upi" / "bank" / "cash" fields the server sends.
List<String> acceptedMethods(Json options) => [
      if (options['upi'] != null) 'upi',
      if (options['bank'] != null) 'bank',
      if (options['cash'] != null) 'cash',
    ];

String methodLabel(BuildContext context, String m) {
  final t = context.l10n;
  return switch (m) {
    'upi' => t.methodUpi,
    'bank' => t.methodBank,
    'cash' => t.methodCash,
    'cheque' => t.methodCheque,
    'online' => t.methodOnline,
    _ => m,
  };
}

class MethodPicker extends StatelessWidget {
  const MethodPicker({super.key, required this.methods, required this.value, required this.onChanged});
  final List<String> methods;
  final String? value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final icons = {'upi': Icons.qr_code_2_rounded, 'bank': Icons.account_balance_rounded, 'cash': Icons.payments_rounded};
    return Column(
      children: [
        for (final m in methods)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: value == m ? AppColors.primarySoft : Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: value == m ? AppColors.primary : AppColors.line, width: value == m ? 2 : 1),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => onChanged(m),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  child: Row(
                    children: [
                      Icon(icons[m] ?? Icons.payments_rounded, color: AppColors.primary),
                      const SizedBox(width: 12),
                      Expanded(child: Text(methodLabel(context, m), style: const TextStyle(fontWeight: FontWeight.w600))),
                      Icon(value == m ? Icons.radio_button_checked : Icons.radio_button_off,
                          color: value == m ? AppColors.primary : AppColors.field),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// How to pay with the chosen method: UPI app button + QR, bank details, or cash note.
class PayInstructions extends StatelessWidget {
  const PayInstructions({super.key, required this.method, required this.options, required this.amount, required this.note});
  final String method;
  final Json options;
  final int amount;
  final String note;

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    if (method == 'upi') {
      final upi = Json.from(options['upi'] as Map);
      final link = upiLink(upiId: upi['id'] as String, payee: upi['name'] as String, amount: amount, note: note);
      return SectionCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton.icon(
              icon: const Icon(Icons.open_in_new_rounded),
              label: Text(t.payInUpiApp(money(amount))),
              onPressed: () async {
                final ok = await launchUrl(Uri.parse(link), mode: LaunchMode.externalApplication);
                if (!ok && context.mounted) showSnack(context, t.noUpiApp, error: true);
              },
            ),
            // Google Pay / PhonePe / Paytm buttons the owner switched on (same UPI ID, amount and note)
            for (final app in ((upi['apps'] as List?) ?? const []).cast<String>())
              if (_upiAppSchemes.containsKey(app))
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: OutlinedButton(
                    onPressed: () async {
                      final uri = Uri.parse('${_upiAppSchemes[app]}?${link.substring(link.indexOf('?') + 1)}');
                      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
                      if (!ok && context.mounted) showSnack(context, t.noUpiApp, error: true);
                    },
                    child: Text(t.payWithApp(_upiAppName(context, app))),
                  ),
                ),
            const SizedBox(height: 12),
            Text(t.orScanQr, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted)),
            const SizedBox(height: 8),
            Center(child: QrImageView(data: link, size: 180, backgroundColor: Colors.white)),
            const SizedBox(height: 8),
            InfoRow(t.upiId, upi['id'] as String,
                trailing: _CopyButton(text: upi['id'] as String)),
            InfoRow(t.paymentNote, note, trailing: _CopyButton(text: note)),
            const SizedBox(height: 4),
            Text(t.upiNoteHelp, style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
          ],
        ),
      );
    }
    if (method == 'bank') {
      final bank = '${options['bank'] ?? ''}';
      return SectionCard(
        title: t.bankDetails,
        trailing: _CopyButton(text: bank),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SelectableText(bank, style: const TextStyle(fontWeight: FontWeight.w600, height: 1.5)),
            const Divider(height: 20),
            InfoRow(t.amount, money(amount), bold: true),
            InfoRow(t.paymentNote, note, trailing: _CopyButton(text: note)),
            Text(t.bankNoteHelp, style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
          ],
        ),
      );
    }
    final cashNote = '${options['cash'] ?? ''}'.trim();
    return Banner2(
      icon: Icons.payments_rounded,
      text: cashNote.isEmpty ? t.cashHelp(money(amount)) : '${t.cashHelp(money(amount))}\n$cashNote',
    );
  }
}

class _CopyButton extends StatelessWidget {
  const _CopyButton({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      visualDensity: VisualDensity.compact,
      tooltip: context.l10n.copy,
      icon: const Icon(Icons.copy_rounded, size: 18),
      onPressed: () => copyText(context, text),
    );
  }
}

/// UTR / transaction ID box (UPI and bank only).
class UtrField extends StatelessWidget {
  const UtrField({super.key, required this.controller});
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    return TextFormField(
      controller: controller,
      textCapitalization: TextCapitalization.characters,
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
        LengthLimitingTextInputFormatter(30),
      ],
      decoration: InputDecoration(labelText: t.utrLabel, helperText: t.utrHelp, helperMaxLines: 3),
      validator: (v) {
        final s = (v ?? '').trim();
        if (s.isEmpty) return t.errUtrRequired;
        if (s.length < 6) return t.errUtrRequired;
        return null;
      },
    );
  }
}

/// Date field opening a date picker.
class DateField extends StatelessWidget {
  const DateField({super.key, required this.label, required this.value, required this.onChanged, required this.first, required this.last});
  final String label;
  final DateTime? value;
  final ValueChanged<DateTime> onChanged;
  final DateTime first;
  final DateTime last;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () async {
        var initial = value ?? today();
        if (initial.isBefore(first)) initial = first;
        if (initial.isAfter(last)) initial = last;
        final d = await showDatePicker(
          context: context,
          initialDate: initial,
          firstDate: first,
          lastDate: last,
        );
        if (d != null) onChanged(d);
      },
      child: InputDecorator(
        decoration: InputDecoration(labelText: label, suffixIcon: const Icon(Icons.calendar_month_rounded)),
        child: Text(value == null ? context.l10n.chooseDate : dateText(context, value)),
      ),
    );
  }
}
