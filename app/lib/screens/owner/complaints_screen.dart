import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/back_nav.dart';
import '../../core/errors.dart';
import '../../core/format.dart';
import '../../data/owner_repo.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import 'hostel_scope.dart';

/// Complaints from students' "Report issue": Open / In progress / Resolved filters; each card shows the category,
/// the student's words, name and room, date, and the owner's reply. Start work · Reply · Mark resolved.
/// Every change shows on the student's Report issue tab (with a number until they open it).
class ComplaintsScreen extends StatefulWidget {
  const ComplaintsScreen({super.key, required this.hostelId});
  final String hostelId;

  @override
  State<ComplaintsScreen> createState() => _ComplaintsScreenState();
}

/// Issue categories (same list as the student app).
const issueCategories = ['water', 'electricity', 'wifi', 'cleaning', 'food', 'furniture', 'plumbing', 'security', 'other'];

IconData issueIcon(String? c) => switch (c) {
      'water' => Icons.water_drop_outlined,
      'electricity' => Icons.bolt_rounded,
      'wifi' => Icons.wifi_rounded,
      'cleaning' => Icons.cleaning_services_outlined,
      'food' => Icons.restaurant_outlined,
      'furniture' => Icons.chair_outlined,
      'plumbing' => Icons.plumbing_rounded,
      'security' => Icons.shield_outlined,
      _ => Icons.report_gmailerrorred_rounded,
    };

String issueLabel(BuildContext context, String? c) {
  final t = context.l10n;
  return switch (c) {
    'water' => t.issueWater,
    'electricity' => t.issueElectricity,
    'wifi' => t.issueWifi,
    'cleaning' => t.issueCleaning,
    'food' => t.issueFood,
    'furniture' => t.issueFurniture,
    'plumbing' => t.issuePlumbing,
    'security' => t.issueSecurity,
    _ => t.issueOther,
  };
}

String issueStatusLabel(BuildContext context, String? s) {
  final t = context.l10n;
  return switch (s) { 'in_progress' => t.filterInProgress, 'resolved' => t.filterResolved, _ => t.filterOpen };
}

Tone issueStatusTone(String? s) => switch (s) { 'in_progress' => Tone.warning, 'resolved' => Tone.success, _ => Tone.danger };

class _ComplaintsScreenState extends State<ComplaintsScreen> {
  final _loader = GlobalKey<LoaderState<List<Json>>>();
  String _filter = 'open';

  Future<void> _update(Json c, {String? status, String? reply}) async {
    final t = context.l10n;
    try {
      await OwnerRepo.instance.updateComplaint(c['id'] as String, status: status, reply: reply);
      if (!mounted) return;
      showSnack(context, reply != null ? t.replySent : t.complaintUpdated);
      await _loader.currentState?.reload();
      if (mounted) HostelScope.read(context).refresh();
    } catch (e) {
      if (mounted) showSnack(context, errorText(context, e), error: true);
    }
  }

  Future<void> _reply(Json c, String name) async {
    final t = context.l10n;
    final ctrl = TextEditingController(text: c['owner_reply'] as String?);
    final text = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.viewInsetsOf(ctx).bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(t.replyToName(name), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl,
            autofocus: true,
            minLines: 2,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            inputFormatters: [LengthLimitingTextInputFormatter(300)],
            decoration: InputDecoration(hintText: t.replyHint),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 50,
            child: FilledButton(
              onPressed: () {
                if (ctrl.text.trim().isNotEmpty) Navigator.pop(ctx, ctrl.text.trim());
              },
              child: Text(t.replyAction),
            ),
          ),
        ]),
      ),
    );
    ctrl.dispose();
    if (text != null) await _update(c, reply: text, status: c['status'] == 'open' ? 'in_progress' : null);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(t.complaints), leading: const AppBackButton()),
      body: Loader<List<Json>>(
        key: _loader,
        load: () => OwnerRepo.instance.complaints(widget.hostelId),
        builder: (context, all, reload) {
          int count(String s) => all.where((c) => c['status'] == s).length;
          final shown = all.where((c) => c['status'] == _filter).toList();
          return PageList(
            onRefresh: reload,
            children: [
              Wrap(spacing: 6, children: [
                for (final f in [
                  ('open', t.filterOpen, AppColors.danger),
                  ('in_progress', t.filterInProgress, const Color(0xFFB45309)),
                  ('resolved', t.filterResolved, AppColors.success),
                ])
                  ChoiceChip(
                    label: Text(t.filterCount(f.$2, '${count(f.$1)}')),
                    selected: _filter == f.$1,
                    showCheckmark: false,
                    selectedColor: f.$3,
                    labelStyle: TextStyle(fontWeight: FontWeight.w600, color: _filter == f.$1 ? Colors.white : AppColors.ink),
                    side: BorderSide(color: _filter == f.$1 ? f.$3 : AppColors.line),
                    backgroundColor: Colors.white,
                    shape: const StadiumBorder(),
                    onSelected: (_) => setState(() => _filter = f.$1),
                  ),
              ]),
              const SizedBox(height: 12),
              if (shown.isEmpty)
                EmptyView(icon: Icons.task_alt_rounded, title: t.noComplaintsTitle, message: t.noComplaintsText)
              else
                for (final c in shown) _card(context, c),
            ],
          );
        },
      ),
    );
  }

  Widget _card(BuildContext context, Json c) {
    final t = context.l10n;
    final tenant = c['tenants'] as Map?;
    final bed = tenant?['beds'] as Map?;
    final room = roomBed((bed?['rooms'] as Map?)?['room_no'], bed?['label']);
    final name = (tenant?['full_name'] as String?) ?? '—';
    final status = c['status'] as String?;
    return SectionCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(12)),
            child: Icon(issueIcon(c['category'] as String?), size: 18, color: AppColors.primary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(issueLabel(context, c['category'] as String?),
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
          ),
          Chip2(issueStatusLabel(context, status), tone: issueStatusTone(status)),
        ]),
        const SizedBox(height: 8),
        Text(c['body'] as String? ?? ''),
        const SizedBox(height: 4),
        Text('$name · ${t.room} $room · ${dateText(context, c['created_at'])}',
            style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
        if ((c['owner_reply'] as String?)?.isNotEmpty == true) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(12)),
            child: Text(t.yourReply(c['owner_reply'] as String),
                style: const TextStyle(color: AppColors.primaryDark, fontSize: 12.5)),
          ),
        ],
        if (status != 'resolved') ...[
          const SizedBox(height: 10),
          Row(children: [
            if (status == 'open') ...[
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                  onPressed: () => _update(c, status: 'in_progress'),
                  child: Text(t.startWork),
                ),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                onPressed: () => _reply(c, name),
                child: Text(t.replyAction),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size(0, 44), backgroundColor: AppColors.success),
                onPressed: () => _update(c, status: 'resolved'),
                child: Text(t.markResolved, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ),
          ]),
        ],
      ]),
    );
  }
}
