import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/back_nav.dart';
import '../../core/errors.dart';
import '../../core/format.dart';
import '../../data/owner_repo.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/pay_widgets.dart';
import 'hostel_scope.dart';

/// Payments to check (join payments and rent) and existing tenants to approve.
class RequestsScreen extends StatefulWidget {
  const RequestsScreen({super.key, required this.hostelId});
  final String hostelId;

  @override
  State<RequestsScreen> createState() => _RequestsScreenState();
}

class _RequestsScreenState extends State<RequestsScreen> {
  final _loader = GlobalKey<LoaderState<(List<Json>, List<Json>)>>();

  Future<(List<Json>, List<Json>)> _load() async {
    final r = await Future.wait([
      OwnerRepo.instance.pendingPayments(widget.hostelId),
      OwnerRepo.instance.existingTenantRequests(widget.hostelId),
    ]);
    return (r[0], r[1]);
  }

  Future<void> _after(String message) async {
    showSnack(context, message);
    await _loader.currentState?.reload();
    if (mounted) HostelScope.read(context).refresh();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(t.tabRequests), leading: const AppBackButton()),
      body: Loader<(List<Json>, List<Json>)>(
        key: _loader,
        load: _load,
        builder: (context, data, reload) {
          final (all, joins) = data;
          // cash the student told the owner about comes first (22 Oct 2026)
          final payments = [
            ...all.where((p) => p['cash_plan'] != null),
            ...all.where((p) => p['cash_plan'] == null),
          ];
          if (payments.isEmpty && joins.isEmpty) {
            return RefreshIndicator(
              onRefresh: reload,
              child: ListView(children: [
                EmptyView(
                  icon: Icons.inbox_rounded,
                  title: t.noRequestsTitle,
                  message: t.noRequestsMessage,
                  action: SizedBox(
                    width: 240,
                    child: OutlinedButton(
                      onPressed: () => context.go('/h/${widget.hostelId}/invite'),
                      child: Text(t.inviteStudents),
                    ),
                  ),
                ),
              ]),
            );
          }
          return PageList(
            onRefresh: reload,
            children: [
              if (payments.isNotEmpty) ...[
                _Heading(t.paymentsToCheckTitle, payments.length),
                for (final p in payments) _PaymentCard(payment: p, onDone: _after),
              ],
              if (joins.isNotEmpty) ...[
                _Heading(t.existingTenantsTitle, joins.length),
                for (final j in joins) _ExistingCard(tenant: j, onDone: _after),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text, this.count);
  final String text;
  final int count;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 10),
        child: Text('$text ($count)', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
      );
}

String _roomBedOf(Json? tenant) {
  final bed = tenant?['beds'] as Map?;
  final room = (bed?['rooms'] as Map?)?['room_no'];
  return roomBed(room, bed?['label']);
}

class _PaymentCard extends StatelessWidget {
  const _PaymentCard({required this.payment, required this.onDone});
  final Json payment;
  final Future<void> Function(String) onDone;

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    final tenant = payment['tenants'] as Map<String, dynamic>?;
    final joining = tenant?['status'] == 'pending_approval';
    final claimed = asInt(payment['amount_claimed']);
    final plan = payment['cash_plan'] as String?;
    final planLabel = switch (plan) {
      'today' => t.cashPlanToday,
      'tomorrow' => t.cashPlanTomorrow,
      'paid' => t.cashPlanPaid,
      _ => null,
    };
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(tenant?['full_name'] as String? ?? t.newStudent,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              ),
              planLabel != null
                  ? Chip2(planLabel, tone: Tone.warning)
                  : Chip2(joining ? t.newJoiner : t.rentPayment, tone: joining ? Tone.info : Tone.neutral),
            ],
          ),
          const SizedBox(height: 6),
          InfoRow(t.roomBed, _roomBedOf(tenant)),
          InfoRow(t.amount, money(claimed), bold: true),
          InfoRow(t.method, methodLabel(context, payment['method'] as String)),
          if (payment['utr'] != null) InfoRow(t.utrShort, payment['utr'] as String),
          if (payment['payment_note'] != null) InfoRow(t.paymentNote, payment['payment_note'] as String),
          InfoRow(t.paidOn, dateText(context, payment['paid_on'])),
          if (payment['checks_total'] != null) _ChecksLine(passed: asInt(payment['checks_passed']), total: asInt(payment['checks_total'])),
          const SizedBox(height: 6),
          Text(planLabel != null ? t.checkCashPlanHelp : payment['method'] == 'cash' ? t.checkCashHelp : t.checkBankHelp,
              style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
          const SizedBox(height: 12),
          if (joining)
            _JoinerButtons(payment: payment, tenant: tenant!, onDone: onDone)
          else
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
                  onPressed: () async {
                    final ok = await confirm(context,
                        title: t.rejectPaymentTitle, message: t.rejectPaymentMessage, okLabel: t.notReceived, danger: true);
                    if (!ok || !context.mounted) return;
                    try {
                      await OwnerRepo.instance.rejectPayment(payment['id'] as String);
                      await onDone(t.paymentRejected);
                    } catch (e) {
                      if (context.mounted) showSnack(context, errorText(context, e), error: true);
                    }
                  },
                  child: Text(t.notReceived),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: AppColors.success),
                  onPressed: () async {
                    final amount = await _askAmount(context, claimed);
                    if (amount == null || !context.mounted) return;
                    try {
                      final r = await OwnerRepo.instance.confirmPayment(payment['id'] as String, amount);
                      await onDone(r['part_payment'] == true ? t.partPaymentSaved : t.paymentConfirmed);
                    } catch (e) {
                      if (context.mounted) showSnack(context, errorText(context, e), error: true);
                    }
                  },
                  child: Text(payment['method'] == 'cash' ? t.cashReceived : t.received),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// "All 12 checks passed" / "3 of 12 checks failed" (the app's own checks on a UPI payment).
class _ChecksLine extends StatelessWidget {
  const _ChecksLine({required this.passed, required this.total});
  final int passed;
  final int total;

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    final failed = total - passed;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(children: [
        Icon(failed == 0 ? Icons.verified_rounded : Icons.warning_amber_rounded,
            size: 18, color: failed == 0 ? AppColors.success : AppColors.warning),
        const SizedBox(width: 6),
        Expanded(
          child: Text(failed == 0 ? t.checksAllPassed('$total') : t.checksSomeFailed('$failed', '$total'),
              style: TextStyle(
                  fontWeight: FontWeight.w800, fontSize: 12.5, color: failed == 0 ? AppColors.success : AppColors.warning)),
        ),
      ]),
    );
  }
}

/// New joiner: Reject (needs a reason) and one Confirm booking button.
class _JoinerButtons extends StatelessWidget {
  const _JoinerButtons({required this.payment, required this.tenant, required this.onDone});
  final Json payment;
  final Map<String, dynamic> tenant;
  final Future<void> Function(String) onDone;

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    final tenantId = (payment['tenant_id'] ?? tenant['id']) as String;
    final name = tenant['full_name'] as String? ?? t.newStudent;
    final bed = tenant['beds'] as Map?;
    final room = '${(bed?['rooms'] as Map?)?['room_no'] ?? ''}';
    final label = '${bed?['label'] ?? ''}';
    return Row(
      children: [
        Expanded(
          flex: 10,
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger, side: const BorderSide(color: AppColors.danger)),
            onPressed: () async {
              final reason = await showModalBottomSheet<String>(
                context: context,
                isScrollControlled: true,
                showDragHandle: true,
                builder: (_) => _RejectSheet(name: name, room: room, bed: label, amount: money(asInt(payment['amount_claimed']))),
              );
              if (reason == null || !context.mounted) return;
              try {
                await OwnerRepo.instance.rejectBooking(tenantId, reason);
                await onDone(t.bookingRejectedToast(name));
              } catch (e) {
                if (context.mounted) showSnack(context, errorText(context, e), error: true);
              }
            },
            child: Text(t.reject),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 22,
          child: BusyButton(
            label: t.confirmBooking,
            onPressed: () async {
              await OwnerRepo.instance.confirmBooking(tenantId);
              if (context.mounted) await onDone(t.bookingConfirmedToast(name, room, label));
            },
          ),
        ),
      ],
    );
  }
}

/// "Reject <name>?" with one reason to pick. The student sees the reason.
class _RejectSheet extends StatefulWidget {
  const _RejectSheet({required this.name, required this.room, required this.bed, required this.amount});
  final String name;
  final String room;
  final String bed;
  final String amount;

  @override
  State<_RejectSheet> createState() => _RejectSheetState();
}

class _RejectSheetState extends State<_RejectSheet> {
  String? _reason;

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    final reasons = {
      'wrong_details': t.rejectReasonWrongDetails,
      'aadhaar_unclear': t.rejectReasonAadhaar,
      'payment_not_received': t.rejectReasonPayment,
      'bed_not_available': t.rejectReasonBed,
      'other': t.rejectReasonOther,
    };
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: Narrow(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(t.rejectBookingTitle(widget.name),
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(t.rejectBedFree(widget.room, widget.bed), style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
            const SizedBox(height: 16),
            Text(t.rejectReasonLabel,
                style: const TextStyle(color: AppColors.muted, fontWeight: FontWeight.w600, fontSize: 12.5)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final e in reasons.entries)
                ChoiceChip(
                  label: Text(e.value),
                  selected: _reason == e.key,
                  selectedColor: AppColors.dangerSoft,
                  labelStyle: TextStyle(
                      fontWeight: FontWeight.w600, color: _reason == e.key ? AppColors.danger : AppColors.ink, fontSize: 12.5),
                  side: BorderSide(color: _reason == e.key ? AppColors.danger : AppColors.line),
                  showCheckmark: false,
                  onSelected: (_) => setState(() => _reason = e.key),
                ),
            ]),
            const SizedBox(height: 14),
            Text(t.rejectReasonHelp(widget.amount), style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
            const SizedBox(height: 14),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
              onPressed: _reason == null ? null : () => Navigator.pop(context, _reason),
              child: Text(t.reject),
            ),
          ],
        ),
      ),
    );
  }
}

/// "How much did you receive?" – less than the claim is saved as a part-payment.
Future<int?> _askAmount(BuildContext context, int claimed) {
  final t = context.l10n;
  final ctrl = TextEditingController(text: '$claimed');
  return showDialog<int>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(t.amountReceivedTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: ctrl,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(7)],
            decoration: InputDecoration(prefixText: '₹ ', labelText: t.amountReceived),
          ),
          const SizedBox(height: 8),
          Text(t.partPaymentHelp, style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t.cancel)),
        FilledButton(
          onPressed: () {
            final v = int.tryParse(ctrl.text);
            if (v != null && v > 0) Navigator.pop(ctx, v);
          },
          child: Text(t.confirm),
        ),
      ],
    ),
  );
}

class _ExistingCard extends StatelessWidget {
  const _ExistingCard({required this.tenant, required this.onDone});
  final Json tenant;
  final Future<void> Function(String) onDone;

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    final hid = HostelScope.read(context).hostelId;
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(tenant['full_name'] as String? ?? '—',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              ),
              Chip2(t.existingTenant, tone: Tone.warning),
            ],
          ),
          const SizedBox(height: 6),
          Text(t.existingSummary(dateText(context, tenant['joining_date']), _roomBedOf(tenant)),
              style: const TextStyle(fontWeight: FontWeight.w600)),
          InfoRow(t.mobileNumber, phoneText(tenant['phone'] as String?)),
          InfoRow(t.rentPerMonth, money(asInt(tenant['rent_month']))),
          const SizedBox(height: 6),
          Text(t.existingHelp, style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
          TextButton(
            onPressed: () => context.go('/h/$hid/tenants/${tenant['id']}'),
            child: Text(t.viewDetailsAndId),
          ),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
                  onPressed: () async {
                    final ok = await confirm(context,
                        title: t.rejectJoinTitle, message: t.rejectJoinMessage, okLabel: t.reject, danger: true);
                    if (!ok || !context.mounted) return;
                    try {
                      await OwnerRepo.instance.rejectTenant(tenant['id'] as String);
                      await onDone(t.requestRejected);
                    } catch (e) {
                      if (context.mounted) showSnack(context, errorText(context, e), error: true);
                    }
                  },
                  child: Text(t.reject),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: AppColors.success),
                  onPressed: () async {
                    try {
                      await OwnerRepo.instance.approveTenant(tenant['id'] as String);
                      await onDone(t.tenantApproved);
                    } catch (e) {
                      if (context.mounted) showSnack(context, errorText(context, e), error: true);
                    }
                  },
                  child: Text(t.approve),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
