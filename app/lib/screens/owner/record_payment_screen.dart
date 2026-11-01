import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/back_nav.dart';
import '../../core/format.dart';
import '../../data/owner_repo.dart';
import '../../theme.dart';
import '../../widgets/bill_widgets.dart';
import '../../widgets/common.dart';
import '../../widgets/pay_widgets.dart';

/// Cash and other payments the owner received directly. Applied to the oldest unpaid bill first;
/// less than the bill is saved as a part-payment and the rest stays pending.
class RecordPaymentScreen extends StatefulWidget {
  const RecordPaymentScreen({super.key, required this.hostelId, required this.tenantId});
  final String hostelId;
  final String tenantId;

  @override
  State<RecordPaymentScreen> createState() => _RecordPaymentScreenState();
}

class _RecordPaymentScreenState extends State<RecordPaymentScreen> {
  final _form = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _note = TextEditingController();
  String _method = 'cash';
  DateTime _paidOn = today();
  bool _waive = false;
  int? _lastTotal; // amount we filled in, so a date / waive change can update it

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  void _close() => goBack(context);

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(t.recordPayment), leading: BackButton(onPressed: _close)),
      body: Loader<List<Json>>(
        key: ValueKey(_paidOn),
        load: () => Future.wait([
          OwnerRepo.instance.tenant(widget.tenantId),
          OwnerRepo.instance.lateFeeQuote(widget.tenantId, _paidOn),
        ]),
        builder: (context, data, _) {
          final x = data[0];
          final q = data[1];
          final bills = (x['bills'] as List).cast<Json>();
          final rentDue = dueNow(bills);
          final fee = q['late_fee_on'] == true ? asInt(q['fee']) : 0;
          final due = rentDue + (_waive ? 0 : fee);
          // fill in the total payable (and keep it in step while the owner hasn't typed their own amount)
          final typed = int.tryParse(_amount.text);
          if (_lastTotal == null ? true : typed == _lastTotal) {
            if (due > 0) {
              _amount.text = '$due';
            } else if (_lastTotal != null) {
              _amount.clear();
            }
            _lastTotal = due;
          }
          final open = bills.where((b) => b['status'] == 'unpaid' || b['status'] == 'partial').toList().reversed;
          return Form(
            key: _form,
            child: PageList(
              children: [
                SectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(x['full_name'] as String? ?? phoneText(x['phone'] as String?),
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                      const SizedBox(height: 4),
                      if (fee > 0) ...[
                        InfoRow(t.rentDueLabel, money(rentDue)),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(children: [
                            Expanded(
                              child: Text(t.lateFeeDaysTimes('${asInt(q['days'])}', money(asInt(q['per_day']))),
                                  style: const TextStyle(color: AppColors.muted)),
                            ),
                            Text(money(fee),
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: _waive ? AppColors.muted : AppColors.danger,
                                  decoration: _waive ? TextDecoration.lineThrough : null,
                                )),
                          ]),
                        ),
                        const Divider(height: 14),
                        Row(children: [
                          Expanded(child: Text(t.totalPayable, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
                          Text(money(due),
                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20, color: Color(0xFF15803D))),
                        ]),
                        const SizedBox(height: 4),
                        Text(t.lateFeeStopsNote, style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                      ] else
                        InfoRow(t.dueNow, money(due), bold: true),
                      if (open.isNotEmpty) const Divider(),
                      for (final b in open) BillRow(bill: b),
                    ],
                  ),
                ),
                TextFormField(
                  controller: _amount,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(7)],
                  decoration: InputDecoration(labelText: t.amountReceived, prefixText: '₹ ', helperText: t.oldestFirstHelp, helperMaxLines: 3),
                  validator: (v) => (int.tryParse(v ?? '') ?? 0) <= 0 ? t.errAmount : null,
                ),
                if (fee > 0)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(t.waiveLateFee, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(t.waiveLateFeeHelp),
                    value: _waive,
                    onChanged: (v) => setState(() => _waive = v),
                  ),
                const SizedBox(height: 16),
                Text(t.method, style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final m in ['cash', 'upi', 'bank', 'cheque'])
                      ChoiceChip(
                        label: Text(methodLabel(context, m)),
                        selected: _method == m,
                        onSelected: (_) => setState(() => _method = m),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                DateField(
                  label: t.paidOn,
                  value: _paidOn,
                  first: today().subtract(const Duration(days: 1825)),
                  last: today(),
                  onChanged: (d) => setState(() => _paidOn = d),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _note,
                  maxLength: 200,
                  decoration: InputDecoration(labelText: t.noteOptional),
                ),
                const SizedBox(height: 8),
                Text(t.receiptOnStudentPage, style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                const SizedBox(height: 16),
                BusyButton(
                  label: t.save,
                  onPressed: () async {
                    if (!_form.currentState!.validate()) return;
                    final amount = int.parse(_amount.text);
                    await OwnerRepo.instance.recordPayment(
                      tenantId: widget.tenantId,
                      amount: amount,
                      method: _method,
                      paidOn: _paidOn,
                      note: _note.text,
                      waiveLateFee: _waive,
                    );
                    if (!mounted) return;
                    showSnack(context, amount < due ? t.partPaymentSaved : t.paymentRecorded);
                    _close();
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
