import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/back_nav.dart';
import '../../core/errors.dart';
import '../../core/format.dart';
import '../../data/owner_repo.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import 'hostel_scope.dart';
import 'settings_screen.dart' show SavedCover;

/// Duties a staff member can be given (what they may do in the app), in this order.
const staffDutyCodes = ['rent', 'approve', 'rooms', 'complaints', 'leaving', 'reminders', 'reports', 'ids', 'checklist'];

/// Duties switched on when a job is picked (same as the database's staff_job_duties).
List<String> jobDuties(String job) => switch (job) {
      'manager' => ['rent', 'approve', 'rooms', 'complaints', 'leaving', 'checklist'],
      'cleaning' => ['complaints', 'checklist'],
      'security' => ['leaving', 'checklist'],
      _ => ['checklist'],
    };

/// More → Staff (owner only): every staff member is one line with a down arrow; opening it shows
/// their duties (switches), duties the owner typed ("+ Add duty"), daily jobs, Remove and Save.
/// "+ Add staff member" at the bottom.
class StaffScreen extends StatelessWidget {
  const StaffScreen({super.key, required this.hostelId});
  final String hostelId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.staffTitle), leading: const AppBackButton()),
      body: Loader<List<Json>>(
        load: () => OwnerRepo.instance.staffList(hostelId),
        builder: (context, list, reload) => _StaffList(hostelId: hostelId, staff: list, reload: reload),
      ),
    );
  }
}

class _StaffList extends StatefulWidget {
  const _StaffList({required this.hostelId, required this.staff, required this.reload});
  final String hostelId;
  final List<Json> staff;
  final Future<void> Function() reload;

  @override
  State<_StaffList> createState() => _StaffListState();
}

class _StaffListState extends State<_StaffList> {
  String? _openId; // only one staff member open at a time
  Json? _draft; // the open one's duties until Save
  String _snap = '';
  bool _busy = false;
  String? _savedId;
  String _savedSub = '';
  Timer? _savedTimer;

  @override
  void dispose() {
    _savedTimer?.cancel();
    super.dispose();
  }

  String _jobName(Json s) {
    final t = context.l10n;
    return switch (s['job']) {
      'manager' => t.jobManager,
      'cleaning' => t.jobCleaning,
      'security' => t.jobSecurity,
      'cook' => t.jobCook,
      _ => (s['job_other'] as String?)?.isNotEmpty == true ? s['job_other'] as String : t.jobOther,
    };
  }

  String _dutyName(String code) {
    final t = context.l10n;
    return switch (code) {
      'rent' => t.dutyRent,
      'approve' => t.dutyApprove,
      'rooms' => t.dutyRooms,
      'complaints' => t.dutyComplaints,
      'leaving' => t.dutyLeaving,
      'reminders' => t.dutyReminders,
      'reports' => t.dutyReports,
      'ids' => t.dutyIds,
      _ => t.dutyChecklist,
    };
  }

  IconData _dutyIcon(String code) => switch (code) {
        'rent' => Icons.payments_outlined,
        'approve' => Icons.how_to_reg_outlined,
        'rooms' => Icons.bed_outlined,
        'complaints' => Icons.build_outlined,
        'leaving' => Icons.logout_rounded,
        'reminders' => Icons.notifications_none_rounded,
        'reports' => Icons.bar_chart_rounded,
        'ids' => Icons.badge_outlined,
        _ => Icons.checklist_rounded,
      };

  Json _copy(Json s) => {
        'duties': [...((s['duties'] as List?) ?? const []).cast<String>()],
        'custom_duties': [for (final c in ((s['custom_duties'] as List?) ?? const [])) Json.from(c as Map)],
        'checklist': (s['checklist'] as String?) ?? '',
      };

  bool get _dirty => _draft != null && jsonEncode(_draft) != _snap;

  /// Before opening another staff member: if something changed, ask "Save changes?". False = stay.
  Future<bool> _leave() async {
    if (!_dirty) return true;
    final t = context.l10n;
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(t.saveChangesQ, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),
            SizedBox(height: 50, child: FilledButton(onPressed: () => Navigator.pop(ctx, 'save'), child: Text(t.save))),
            TextButton(onPressed: () => Navigator.pop(ctx, 'drop'), child: Text(t.dontSave)),
          ]),
        ),
      ),
    );
    if (!mounted || choice == null) return false;
    if (choice == 'save') return _save();
    return true;
  }

  Future<void> _toggle(Json s) async {
    final id = s['id'] as String;
    if (!await _leave()) return;
    setState(() {
      if (_openId == id) {
        _openId = null;
        _draft = null;
      } else {
        _openId = id;
        _draft = _copy(s);
        _snap = jsonEncode(_draft);
      }
    });
  }

  Future<bool> _save() async {
    final id = _openId;
    final d = _draft;
    if (id == null || d == null || _busy) return false;
    final s = widget.staff.firstWhere((x) => x['id'] == id);
    setState(() => _busy = true);
    try {
      await OwnerRepo.instance.saveStaff(widget.hostelId,
          id: id,
          name: s['name'] as String,
          phone: s['phone'] as String,
          job: s['job'] as String,
          jobOther: s['job_other'] as String?,
          duties: (d['duties'] as List).cast<String>(),
          custom: (d['custom_duties'] as List).cast<Json>(),
          checklist: d['checklist'] as String);
    } catch (e) {
      if (mounted) showSnack(context, errorText(context, e), error: true);
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return false;
    setState(() {
      _snap = jsonEncode(d);
      _savedId = id;
      _savedSub = s['name'] as String;
    });
    _savedTimer?.cancel();
    _savedTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _savedId = null);
    });
    await widget.reload();
    return true;
  }

  Future<void> _remove(Json s) async {
    final t = context.l10n;
    final ok = await confirm(context,
        title: t.removeStaffQ(s['name'] as String), message: t.removeStaffText, okLabel: t.removeStaff, danger: true);
    if (!ok) return;
    try {
      await OwnerRepo.instance.removeStaff(s['id'] as String);
    } catch (e) {
      if (mounted) showSnack(context, errorText(context, e), error: true);
      return;
    }
    if (!mounted) return;
    setState(() {
      _openId = null;
      _draft = null;
    });
    showSnack(context, t.staffRemoved(s['name'] as String));
    await widget.reload();
  }

  /// "+ Add duty": a duty the owner types himself.
  Future<void> _addDuty() async {
    final t = context.l10n;
    final c = TextEditingController();
    final name = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(t.addDuty, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          Text(t.addDutyHelp, style: const TextStyle(color: AppColors.muted)),
          const SizedBox(height: 12),
          TextField(
            controller: c,
            autofocus: true,
            inputFormatters: [LengthLimitingTextInputFormatter(60)],
            decoration: InputDecoration(hintText: t.addDutyHint),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 50,
            child: FilledButton(
              onPressed: () {
                if (c.text.trim().isEmpty) {
                  showSnack(ctx, t.cantBeEmpty, error: true);
                } else {
                  Navigator.pop(ctx, c.text.trim());
                }
              },
              child: Text(t.addLine),
            ),
          ),
        ]),
      ),
    ).whenComplete(c.dispose);
    if (name == null || _draft == null) return;
    setState(() => (_draft!['custom_duties'] as List).add({'name': name, 'on': true}));
  }

  Future<void> _editChecklist() async {
    final t = context.l10n;
    final c = TextEditingController(text: _draft!['checklist'] as String);
    final v = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(t.dailyJobs, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          Text(t.dailyJobsHelp, style: const TextStyle(color: AppColors.muted)),
          const SizedBox(height: 12),
          TextField(controller: c, autofocus: true, minLines: 2, maxLines: 5, maxLength: 500),
          SizedBox(height: 50, child: FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: Text(t.save))),
        ]),
      ),
    ).whenComplete(c.dispose);
    if (v != null) setState(() => _draft!['checklist'] = v);
  }

  /// "+ Add staff member": name, mobile number, job → added with the job's duties, then an SMS invite.
  Future<void> _addStaff() async {
    final t = context.l10n;
    if (!await _leave()) return;
    if (!mounted) return;
    final name = TextEditingController();
    final phone = TextEditingController();
    final other = TextEditingController();
    String job = 'manager';
    final added = await showModalBottomSheet<Json>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(t.addStaffMember, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              TextField(
                controller: name,
                textCapitalization: TextCapitalization.words,
                inputFormatters: [LengthLimitingTextInputFormatter(80)],
                decoration: InputDecoration(labelText: t.fullName),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: phone,
                keyboardType: TextInputType.phone,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)],
                decoration: InputDecoration(labelText: t.mobileNumber, prefixText: '+91 '),
              ),
              const SizedBox(height: 12),
              Text(t.jobLabel, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Wrap(spacing: 8, runSpacing: 6, children: [
                for (final (code, label) in [
                  ('manager', t.jobManager),
                  ('cleaning', t.jobCleaning),
                  ('security', t.jobSecurity),
                  ('cook', t.jobCook),
                  ('other', t.jobOther),
                ])
                  ChoiceChip(label: Text(label), selected: job == code, onSelected: (_) => setSheet(() => job = code)),
              ]),
              if (job == 'other') ...[
                const SizedBox(height: 8),
                TextField(
                  controller: other,
                  inputFormatters: [LengthLimitingTextInputFormatter(40)],
                  decoration: InputDecoration(labelText: t.jobOtherLabel),
                ),
              ],
              const SizedBox(height: 8),
              Text(t.jobDutiesNote, style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
              const SizedBox(height: 14),
              SizedBox(
                height: 50,
                child: FilledButton(
                  onPressed: () {
                    if (name.text.trim().length < 2) {
                      showSnack(ctx, t.errName, error: true);
                    } else if (!RegExp(r'^[6-9][0-9]{9}$').hasMatch(phone.text)) {
                      showSnack(ctx, t.errBadPhone, error: true);
                    } else {
                      Navigator.pop(ctx, {'name': name.text.trim(), 'phone': '+91${phone.text}', 'job': job, 'other': other.text.trim()});
                    }
                  },
                  child: Text(t.addAndInvite),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
    name.dispose();
    phone.dispose();
    other.dispose();
    if (added == null || !mounted) return;
    try {
      await OwnerRepo.instance.saveStaff(widget.hostelId,
          name: added['name'] as String,
          phone: added['phone'] as String,
          job: added['job'] as String,
          jobOther: added['job'] == 'other' ? added['other'] as String : null,
          duties: jobDuties(added['job'] as String));
    } catch (e) {
      if (mounted) showSnack(context, errorText(context, e), error: true);
      return;
    }
    if (!mounted) return;
    showSnack(context, t.staffAdded(added['name'] as String));
    // SMS invite from the owner's phone
    final hostel = HostelScope.of(context).hostel?['name'] as String? ?? '';
    final body = t.staffInviteSms(added['name'] as String, hostel);
    await launchUrl(Uri.parse('sms:${added['phone']}?body=${Uri.encodeComponent(body)}')).catchError((_) => false);
    await widget.reload();
  }

  Widget _switchLine(IconData icon, String label, bool value, ValueChanged<bool> onChanged, {Widget? trailing}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          Icon(icon, color: AppColors.primary, size: 21),
          const SizedBox(width: 10),
          Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600))),
          if (trailing != null) trailing,
          Switch(value: value, onChanged: onChanged),
        ]),
      );

  Widget _details(Json s) {
    final t = context.l10n;
    final d = _draft!;
    final duties = (d['duties'] as List).cast<String>();
    final custom = (d['custom_duties'] as List).cast<Json>();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SizedBox(height: 4),
      Text(t.dutiesInApp, style: const TextStyle(fontWeight: FontWeight.w600)),
      const SizedBox(height: 4),
      for (final code in staffDutyCodes)
        _switchLine(_dutyIcon(code), _dutyName(code), duties.contains(code), (on) => setState(() {
              if (on) {
                duties.add(code);
              } else {
                duties.remove(code);
              }
            })),
      // duties the owner typed
      for (final c in custom)
        _switchLine(Icons.star_border_rounded, c['name'] as String, c['on'] == true, (on) => setState(() => c['on'] = on),
            trailing: IconButton(
              tooltip: t.delete,
              icon: const Icon(Icons.close_rounded, color: AppColors.danger, size: 20),
              onPressed: () => setState(() => custom.remove(c)),
            )),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(onPressed: _addDuty, icon: const Icon(Icons.add_circle_outline_rounded), label: Text(t.addDutyButton)),
      ),
      const SizedBox(height: 6),
      Text(t.dailyJobs, style: const TextStyle(fontWeight: FontWeight.w600)),
      const SizedBox(height: 6),
      Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: AppColors.field)),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: _editChecklist,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Expanded(
                child: Text((d['checklist'] as String).isEmpty ? t.dailyJobsHint : d['checklist'] as String,
                    style: TextStyle(fontWeight: FontWeight.w600, color: (d['checklist'] as String).isEmpty ? AppColors.muted : null)),
              ),
              const Icon(Icons.edit_rounded, size: 18, color: AppColors.primary),
            ]),
          ),
        ),
      ),
      const SizedBox(height: 10),
      Row(children: [
        TextButton(
          onPressed: () => _remove(s),
          child: Text(t.removeStaff, style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600)),
        ),
        const Spacer(),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(0, 44), padding: const EdgeInsets.symmetric(horizontal: 26)),
          onPressed: _busy ? null : _save,
          child: Text(t.save, style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
      ]),
    ]);
  }

  Widget _card(Json s) {
    final open = _openId == s['id'];
    final name = s['name'] as String;
    final initials = name.trim().split(RegExp(r'\s+')).take(2).map((w) => w.isEmpty ? '' : w[0]).join().toUpperCase();
    final card = Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: open ? AppColors.primary : AppColors.line, width: open ? 1.5 : 1),
      ),
      child: Material(
        color: Colors.white,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          InkWell(
            onTap: () => _toggle(s),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
              child: Row(children: [
                CircleAvatar(
                  radius: 21,
                  backgroundColor: AppColors.primarySoft,
                  child: Text(initials, style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                    Text('${_jobName(s)} · ${phoneText(s['phone'] as String?)}',
                        style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                  ]),
                ),
                Icon(open ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded, color: AppColors.primary, size: 28),
              ]),
            ),
          ),
          if (open) Padding(padding: const EdgeInsets.fromLTRB(14, 0, 14, 14), child: _details(s)),
        ]),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: _savedId == s['id'] ? Stack(children: [card, Positioned.fill(child: SavedCover(sub: _savedSub))]) : card,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    return PageList(children: [
      Text(t.staffHelp, style: const TextStyle(color: AppColors.muted)),
      const SizedBox(height: 10),
      if (widget.staff.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Text(t.noStaffYet, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted)),
        ),
      for (final s in widget.staff) _card(s),
      const SizedBox(height: 4),
      OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          side: const BorderSide(color: AppColors.primary, width: 1.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        onPressed: _addStaff,
        icon: const Icon(Icons.add_rounded),
        label: Text(t.addStaffMember, style: const TextStyle(fontWeight: FontWeight.w600)),
      ),
      const SizedBox(height: 12),
      Text(t.staffLoginNote, style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
    ]);
  }
}
