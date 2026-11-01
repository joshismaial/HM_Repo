import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/back_nav.dart';
import '../../core/errors.dart';
import '../../core/format.dart';
import '../../data/owner_repo.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/bill_widgets.dart';
import 'hostel_scope.dart';
import 'tenants_screen.dart';

class TenantDetailsScreen extends StatefulWidget {
  const TenantDetailsScreen({super.key, required this.hostelId, required this.tenantId});
  final String hostelId;
  final String tenantId;

  @override
  State<TenantDetailsScreen> createState() => _TenantDetailsScreenState();
}

class _TenantDetailsScreenState extends State<TenantDetailsScreen> {
  final _loader = GlobalKey<LoaderState<Json>>();
  String? _revealed;

  Future<void> _reload() async {
    await _loader.currentState?.reload();
    if (mounted) HostelScope.read(context).refresh();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(t.tenantDetails),
        leading: const AppBackButton(),
      ),
      body: Loader<Json>(
        key: _loader,
        load: () => OwnerRepo.instance.tenant(widget.tenantId),
        builder: (context, x, reload) {
          final bed = x['beds'] as Map?;
          final room = bed?['rooms'] as Map?;
          final status = x['status'] as String?;
          final living = status == 'active' || status == 'notice';
          final bills = (x['bills'] as List).cast<Json>();
          final payments = (x['payments'] as List).cast<Json>();
          final due = dueNow(bills);
          final phone = x['phone'] as String;
          return PageList(
            onRefresh: reload,
            children: [
              _Header(tenant: x),
              if (status == 'notice')
                Banner2(
                  tone: Tone.warning,
                  icon: Icons.logout_rounded,
                  text: t.noticeBanner(dateText(context, x['leaving_date']), dateText(context, x['notice_given_at'])),
                ),
              if (status == 'vacated')
                Banner2(
                  text: t.vacatedBanner(dateText(context, x['vacated_at']), money(asInt(x['deposit_refund']))),
                ),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.call_rounded, size: 18),
                      label: Text(t.call),
                      onPressed: () => launchUrl(Uri.parse('tel:$phone')),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(foregroundColor: AppColors.whatsapp),
                      icon: const Icon(Icons.chat_rounded, size: 18),
                      label: Text(t.whatsapp),
                      onPressed: () => launchUrl(Uri.parse('https://wa.me/${phone.replaceAll('+', '')}'),
                          mode: LaunchMode.externalApplication),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SectionCard(
                title: t.stay,
                child: Column(children: [
                  InfoRow(t.roomBed, roomBed(room?['room_no'], bed?['label'])),
                  if (room?['sharing'] != null) InfoRow(t.sharing, t.sharingN('${room!['sharing']}')),
                  InfoRow(t.joiningDate, dateText(context, x['joining_date'])),
                  InfoRow(t.joinedAs, x['is_existing'] == true ? t.existingTenant : t.newJoiner),
                  InfoRow(t.rentPerMonth, money(asInt(x['rent_month']))),
                  InfoRow(t.deposit, money(asInt(x['deposit']))),
                ]),
              ),
              SectionCard(
                title: t.balance,
                trailing: living || status == 'vacated'
                    ? TextButton.icon(
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: Text(t.recordPayment),
                        onPressed: () async {
                          await context.push('/h/${widget.hostelId}/record/${widget.tenantId}');
                          _reload();
                        },
                      )
                    : null,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    InfoRow(t.dueNow, money(due), bold: true),
                    const Divider(),
                    if (bills.isEmpty) Text(t.noBills, style: const TextStyle(color: AppColors.muted)),
                    for (final b in bills.take(6)) BillRow(bill: b),
                  ],
                ),
              ),
              SectionCard(
                title: t.payments,
                child: payments.isEmpty
                    ? Text(t.noPayments, style: const TextStyle(color: AppColors.muted))
                    : Column(children: [for (final p in payments) PaymentRow(payment: p)]),
              ),
              SectionCard(
                title: t.contactAndAddress,
                child: Column(children: [
                  InfoRow(t.mobileNumber, phoneText(phone)),
                  if ((x['parent_name'] as String?)?.isNotEmpty == true) InfoRow(t.parentName, x['parent_name'] as String),
                  InfoRow(t.parentPhone, phoneText(x['parent_phone'] as String?)),
                  if ((x['reference_name'] as String?)?.isNotEmpty == true)
                    InfoRow(t.referenceName, x['reference_name'] as String),
                  InfoRow(t.referencePhone, phoneText(x['reference_phone'] as String?)),
                  InfoRow(t.homeAddress, x['home_address'] as String? ?? '—'),
                  InfoRow(t.orgShort, x['org_name'] as String? ?? '—'),
                  InfoRow(t.orgAddressShort, x['office_address'] as String? ?? '—'),
                ]),
              ),
              _IdCard(
                tenant: x,
                revealed: _revealed,
                onReveal: () async {
                  try {
                    final n = await OwnerRepo.instance.revealIdNumber(widget.tenantId);
                    if (!mounted) return;
                    setState(() => _revealed = n ?? '');
                  } catch (e) {
                    if (mounted) showSnack(this.context, errorText(this.context, e), error: true);
                  }
                },
              ),
              if (living || status == 'pending_approval') ...[
                const SizedBox(height: 4),
                OutlinedButton.icon(
                  icon: const Icon(Icons.link_rounded),
                  label: Text(t.resetStudentLink),
                  onPressed: () => _resetLink(context),
                ),
              ],
              if (living) ...[
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
                  icon: const Icon(Icons.logout_rounded),
                  label: Text(t.markVacated),
                  onPressed: () => _vacate(context, x, bills),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Future<void> _resetLink(BuildContext context) async {
    final t = context.l10n;
    final sendSms = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.resetStudentLink),
        content: Text(t.resetLinkMessage),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t.cancel)),
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t.resetOnly)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t.resetAndSms)),
        ],
      ),
    );
    if (sendSms == null || !context.mounted) return;
    try {
      final url = await OwnerRepo.instance.studentLink(widget.tenantId, reset: true, sms: sendSms);
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(t.newLinkTitle),
          content: SelectableText(url),
          actions: [
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: url));
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: Text(t.copyLink),
            ),
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t.done)),
          ],
        ),
      );
    } catch (e) {
      if (context.mounted) showSnack(context, errorText(context, e), error: true);
    }
  }

  Future<void> _vacate(BuildContext context, Json x, List<Json> bills) async {
    final t = context.l10n;
    final ctrl = TextEditingController(text: '0');
    final depositPaid = bills
        .where((b) => b['kind'] == 'deposit')
        .fold<int>(0, (sum, b) => sum + asInt(b['paid_amount']));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.markVacated),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t.vacateHelp),
            const SizedBox(height: 10),
            InfoRow(t.depositPaid, money(depositPaid)),
            if (x['status'] != 'notice') Text(t.noNoticeWarning, style: const TextStyle(color: AppColors.danger)),
            const SizedBox(height: 10),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(7)],
              decoration: InputDecoration(prefixText: '₹ ', labelText: t.deductions, helperText: t.deductionsHelp, helperMaxLines: 2),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t.cancel)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(t.markVacated),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      final r = await OwnerRepo.instance.markVacated(widget.tenantId, int.tryParse(ctrl.text) ?? 0);
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(t.vacatedTitle),
          content: Text(r['enough_notice'] == true
              ? t.refundToPay(money(asInt(r['refund'])))
              : t.depositForfeited(money(asInt(r['deposit_paid'])))),
          actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: Text(t.done))],
        ),
      );
      _reload();
    } catch (e) {
      if (context.mounted) showSnack(context, errorText(context, e), error: true);
    }
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.tenant});
  final Json tenant;

  @override
  Widget build(BuildContext context) {
    final status = tenant['status'] as String?;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          _Photo(tenant: tenant),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tenant['full_name'] as String? ?? '—',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(phoneText(tenant['phone'] as String?), style: const TextStyle(color: AppColors.muted)),
                const SizedBox(height: 6),
                Chip2(tenantStatusLabel(context, status), tone: tenantStatusTone(status)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Photo extends StatefulWidget {
  const _Photo({required this.tenant});
  final Json tenant;

  @override
  State<_Photo> createState() => _PhotoState();
}

class _PhotoState extends State<_Photo> {
  Future<String>? _url;

  @override
  void initState() {
    super.initState();
    if (widget.tenant['photo_key'] != null && widget.tenant['files_purged_at'] == null) {
      _url = OwnerRepo.instance.fileUrl(widget.tenant['id'] as String, 'photo');
    }
  }

  @override
  Widget build(BuildContext context) {
    const placeholder = CircleAvatar(radius: 34, child: Icon(Icons.person_rounded, size: 34));
    if (_url == null) return placeholder;
    return FutureBuilder<String>(
      future: _url,
      builder: (context, snap) {
        if (!snap.hasData) return placeholder;
        return GestureDetector(
          onTap: () => showImage(context, snap.data!),
          child: CircleAvatar(radius: 34, backgroundImage: NetworkImage(snap.data!)),
        );
      },
    );
  }
}

void showImage(BuildContext context, String url) {
  showDialog<void>(
    context: context,
    builder: (ctx) => Dialog(
      insetPadding: const EdgeInsets.all(12),
      child: Stack(
        children: [
          InteractiveViewer(
            child: Image.network(url,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(context.l10n.errGeneric),
                    )),
          ),
          Positioned(
            right: 4,
            top: 4,
            child: IconButton.filledTonal(
              tooltip: context.l10n.close,
              icon: const Icon(Icons.close_rounded),
              onPressed: () => Navigator.pop(ctx),
            ),
          ),
        ],
      ),
    ),
  );
}

String idTypeLabel(BuildContext context, String? type) {
  final t = context.l10n;
  return switch (type) {
    'aadhaar' => t.idAadhaar,
    'passport' => t.idPassport,
    'driving_licence' => t.idDrivingLicence,
    _ => '—',
  };
}

class _IdCard extends StatelessWidget {
  const _IdCard({required this.tenant, required this.revealed, required this.onReveal});
  final Json tenant;
  final String? revealed;
  final Future<void> Function() onReveal;

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    final last4 = tenant['id_last4'] as String?;
    final purged = tenant['files_purged_at'] != null;
    final masked = last4 == null ? '—' : 'XXXX XXXX $last4';
    String shown = masked;
    if (revealed != null) shown = revealed!.isEmpty ? t.onlyMaskedGiven : revealed!;
    return SectionCard(
      title: t.idProof,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InfoRow(t.idType, idTypeLabel(context, tenant['id_type'] as String?)),
          InfoRow(
            t.idNumber,
            shown,
            trailing: revealed == null && last4 != null
                ? TextButton(onPressed: onReveal, child: Text(t.reveal))
                : null,
          ),
          if (revealed == null && last4 != null)
            Text(t.revealLogged, style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
          const SizedBox(height: 8),
          if (purged)
            Text(t.filesDeleted, style: const TextStyle(color: AppColors.muted))
          else if (tenant['id_file_key'] != null)
            OutlinedButton.icon(
              icon: const Icon(Icons.badge_rounded),
              label: Text(t.viewIdCopy),
              onPressed: () async {
                try {
                  final url = await OwnerRepo.instance.fileUrl(tenant['id'] as String, 'id');
                  if (context.mounted) showImage(context, url);
                } catch (e) {
                  if (context.mounted) showSnack(context, errorText(context, e), error: true);
                }
              },
            ),
        ],
      ),
    );
  }
}

