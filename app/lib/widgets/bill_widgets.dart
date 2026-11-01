import 'package:flutter/material.dart';

import '../core/format.dart';
import '../theme.dart';
import 'common.dart';
import 'pay_widgets.dart';

String billStatusLabel(BuildContext context, String? s) {
  final t = context.l10n;
  return switch (s) {
    'paid' => t.billPaid,
    'partial' => t.billPartial,
    'cancelled' => t.billCancelled,
    _ => t.billUnpaid,
  };
}

Tone billTone(String? s) => switch (s) {
      'paid' => Tone.success,
      'partial' => Tone.warning,
      'unpaid' => Tone.danger,
      _ => Tone.neutral,
    };

class BillRow extends StatelessWidget {
  const BillRow({super.key, required this.bill});
  final Json bill;

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    final status = bill['status'] as String?;
    final amount = asInt(bill['amount']);
    final paid = asInt(bill['paid_amount']);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(billLabel(context, bill), style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(t.dueOn(dateText(context, bill['due_date'])),
                    style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(money(amount), style: const TextStyle(fontWeight: FontWeight.w800)),
              if (status == 'partial') Text(t.paidAmount(money(paid)), style: const TextStyle(fontSize: 12.5)),
            ],
          ),
          const SizedBox(width: 8),
          Chip2(billStatusLabel(context, status), tone: billTone(status)),
        ],
      ),
    );
  }
}

/// Bill names in the user's language (the server label is the English fallback).
String billLabel(BuildContext context, Json bill) {
  final t = context.l10n;
  switch (bill['kind']) {
    case 'deposit':
      return t.securityDeposit;
    case 'rent':
      if (bill['period_start'] != null && bill['period_end'] != null) {
        return t.rentPeriod(shortDate(context, bill['period_start']), shortDate(context, bill['period_end']));
      }
      return t.rent;
    default:
      return '${bill['label'] ?? ''}';
  }
}

class PaymentRow extends StatelessWidget {
  const PaymentRow({super.key, required this.payment});
  final Json payment;

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    final status = payment['status'] as String?;
    final amount = status == 'received' ? asInt(payment['amount_received']) : asInt(payment['amount_claimed']);
    final (label, tone) = switch (status) {
      'received' => (t.payReceived, Tone.success),
      'rejected' => (t.payRejected, Tone.danger),
      _ => (t.payPending, Tone.info),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${methodLabel(context, payment['method'] as String)} · ${dateText(context, payment['paid_on'])}',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                if (payment['utr'] != null)
                  Text('${t.utrShort} ${payment['utr']}', style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                if (payment['note'] != null)
                  Text('${payment['note']}', style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
              ],
            ),
          ),
          Text(money(amount), style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(width: 8),
          Chip2(label, tone: tone),
        ],
      ),
    );
  }
}
