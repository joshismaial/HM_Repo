import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/back_nav.dart';
import '../../core/errors.dart';
import '../../core/format.dart';
import '../../data/owner_repo.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/pay_widgets.dart' show methodLabel;
import 'hostel_scope.dart';

const _green = Color(0xFF15803D);
const _amber = Color(0xFFB25E09);
const _blue = AppColors.primary;
// Rent tab tidy (20 Oct 2026): month and Today boxes white with a thin border; the three tiles tinted
// green / amber / red; filter chips with colour dots (the picked chip fills with its colour).
const _boxBg = Colors.white;
const _boxLine = AppColors.line;

/// Rent tab:
///  - Month box (tap the month to change it): Collected · Still to pay · Late now
///  - Today box: Collected · Still to pay · Late now, with the Auto-remind switch
///  - Filters (All / Late / Due / Upcoming / Paid) and one list of every tenant;
///    tap a tenant to record a payment, send a WhatsApp reminder or open their details
///  - "Send reminder to all" after the list (SMS to everyone unpaid this month)
///  - Late fee is set in Hostel settings (moved there 20 Oct 2026)
class RentScreen extends StatefulWidget {
  const RentScreen({super.key, required this.hostelId});
  final String hostelId;

  @override
  State<RentScreen> createState() => _RentScreenState();
}

class _RentScreenState extends State<RentScreen> {
  DateTime _month = DateTime(today().year, today().month);
  String _filter = 'all';
  bool? _autoRemind; // local value while the switch is saving
  Map<String, String> _thumbs = const {}; // tenant id -> small photo link (lists load only thumbnails)

  @override
  void initState() {
    super.initState();
    OwnerRepo.instance.thumbUrls(widget.hostelId).then((m) {
      if (mounted) setState(() => _thumbs = m);
    }).catchError((_) {}); // no photos is fine: initials are shown
  }

  Future<void> _pickMonth() async {
    final t = context.l10n;
    final now = DateTime(today().year, today().month);
    final months = [for (var i = 0; i < 12; i++) DateTime(now.year, now.month - i)];
    final picked = await showModalBottomSheet<DateTime>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(t.chooseMonth, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          ),
          Flexible(
            child: ListView(shrinkWrap: true, children: [
              for (final m in months)
                ListTile(
                  title: Text(monthText(ctx, m),
                      style: TextStyle(fontWeight: m == _month ? FontWeight.w600 : FontWeight.w400)),
                  trailing: m == _month ? const Icon(Icons.check_rounded, color: _blue) : null,
                  onTap: () => Navigator.of(ctx).pop(m),
                ),
            ]),
          ),
        ]),
      ),
    );
    if (picked != null && picked != _month) setState(() => _month = picked);
  }

  Future<void> _setAuto(bool on) async {
    setState(() => _autoRemind = on);
    try {
      await OwnerRepo.instance.setAutoRemind(widget.hostelId, on);
    } catch (e) {
      if (!mounted) return;
      setState(() => _autoRemind = !on);
      showSnack(context, errorText(context, e), error: true);
    }
  }

  Future<void> _remindAll(int unpaid) async {
    final t = context.l10n;
    final ok = await confirm(context,
        title: t.remindAllTitle('$unpaid'), message: t.remindAllMessage, okLabel: t.sendReminders);
    if (!ok || !mounted) return;
    try {
      final sent = await OwnerRepo.instance.remindAll(widget.hostelId);
      if (!mounted) return;
      showSnack(context, sent == 0 ? t.remindersNone : t.remindersSent('$sent'));
    } catch (e) {
      if (mounted) showSnack(context, errorText(context, e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    final hostelName = HostelScope.of(context).hostel?['name'] as String? ?? '';
    return Scaffold(
      appBar: AppBar(
        title: Text(t.tabRent),
        leading: const AppBackButton(),
        actions: [
          IconButton(
            tooltip: t.reports,
            icon: const Icon(Icons.bar_chart_rounded),
            onPressed: () => context.push('/h/${widget.hostelId}/reports'),
          ),
          IconButton(
            tooltip: t.hostelSettings,
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push('/h/${widget.hostelId}/settings'),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Loader<Json>(
        key: ValueKey(_month),
        load: () => OwnerRepo.instance.rentOverview(widget.hostelId, _month),
        builder: (context, r, reload) {
          final rows = (r['rows'] as List? ?? const []).cast<Json>();
          int count(String s) => rows.where((x) => x['status'] == s).length;
          // "All" = due today, late and paid; future rent only under "Upcoming"
          final allRows = rows.where((x) => x['status'] != 'upcoming').toList();
          final shown = _filter == 'all' ? allRows : rows.where((x) => x['status'] == _filter).toList();
          final toRemind = count('late') + count('due');
          final billed = asInt(r['billed']);
          final collected = asInt(r['collected']);
          final pct = billed == 0 ? 0 : (collected * 100 / billed).round().clamp(0, 100);
          final auto = _autoRemind ?? (r['auto_remind'] != false);
          final toCheck = asInt(r['to_check']);
          final monthName = monthText(context, _month).split(' ').first;

          final header = <Widget>[
            // ---- month
            _MetricsBox(
              title: InkWell(
                onTap: _pickMonth,
                borderRadius: BorderRadius.circular(8),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(_month.year == today().year ? monthName : monthText(context, _month),
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  const Icon(Icons.arrow_drop_down_rounded, size: 22),
                ]),
              ),
              right: t.rentOfTotal(money(collected), money(billed), '$pct'),
              tiles: [
                _Tile(t.collected, money(collected), _green, t.nPaid('${asInt(r['paid_count'])}'), _greenTint),
                _Tile(t.stillToPayLabel, money(asInt(r['to_pay'])), _amber, t.tenantsCount('${asInt(r['to_pay_count'])}'), _amberTint),
                _Tile(t.lateNowLabel, money(asInt(r['late_amount'])), AppColors.danger, t.tenantsCount('${asInt(r['late_count'])}'),
                    _redTint),
              ],
            ),
            const SizedBox(height: 8),
            // ---- today
            _MetricsBox(
              title: Text(t.todayDate(shortDate(context, today())),
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              right: t.tenantsDueToday('${asInt(r['today_due_count'])}'),
              tiles: [
                _Tile(t.collected, money(asInt(r['today_collected'])), _green, t.nPaid('${asInt(r['today_paid_count'])}'),
                    _greenTint),
                _Tile(t.stillToPayLabel, money(asInt(r['today_to_pay'])), _amber,
                    t.tenantsCount('${asInt(r['today_to_pay_count'])}'), _amberTint),
                _Tile(t.lateNowLabel, money(asInt(r['late_now'])), AppColors.danger,
                    t.tenantsCount('${asInt(r['late_now_count'])}'), _redTint),
              ],
              footer: Semantics(
                toggled: auto,
                label: '${t.autoRemindTitle}, ${t.autoRemindHelp}',
                excludeSemantics: true,
                child: InkWell(
                  onTap: () => _setAuto(!auto),
                  child: Row(children: [
                    const Icon(Icons.notifications_active_outlined, size: 17, color: _blue),
                    const SizedBox(width: 5),
                    Text(t.autoRemindTitle,
                        style: const TextStyle(fontWeight: FontWeight.w600, color: _blue, fontSize: 12.5)),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(t.autoRemindHelp,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                    ),
                    Transform.scale(scale: 0.8, child: Switch(value: auto, onChanged: _setAuto)),
                  ]),
                ),
              ),
            ),
            if (toCheck > 0) ...[
              const SizedBox(height: 8),
              Material(
                color: AppColors.primarySoft,
                borderRadius: BorderRadius.circular(12),
                child: ListTile(
                  dense: true,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  leading: const Icon(Icons.receipt_long_rounded, color: AppColors.primary),
                  title: Text(t.paymentsToCheck('$toCheck'), style: const TextStyle(fontWeight: FontWeight.w600)),
                  trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.primary),
                  onTap: () => context.go('/h/${widget.hostelId}/requests'),
                ),
              ),
            ],
            const SizedBox(height: 8),
            // ---- filters
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                for (final f in [
                  ('all', t.all, allRows.length, AppColors.ink),
                  ('late', t.filterLate, count('late'), AppColors.danger),
                  ('due', t.filterDue, count('due'), _amber),
                  ('upcoming', t.filterUpcoming, count('upcoming'), _blue),
                  ('paid', t.paidLabel, count('paid'), _green),
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      avatar: _filter == f.$1
                          ? null
                          : Container(width: 8, height: 8, decoration: BoxDecoration(color: f.$4, shape: BoxShape.circle)),
                      label: Text(t.filterCount(f.$2, '${f.$3}')),
                      selected: _filter == f.$1,
                      showCheckmark: false,
                      visualDensity: VisualDensity.compact,
                      selectedColor: f.$4,
                      backgroundColor: Colors.white,
                      labelStyle: TextStyle(
                          fontWeight: FontWeight.w600, color: _filter == f.$1 ? Colors.white : AppColors.ink),
                      side: BorderSide(color: _filter == f.$1 ? f.$4 : AppColors.line),
                      shape: const StadiumBorder(),
                      onSelected: (_) => setState(() => _filter = f.$1),
                    ),
                  ),
              ]),
            ),
            const SizedBox(height: 8),
          ];

          final listItems = <Widget>[
            if (shown.isEmpty)
              SectionCard(
                child: rows.isEmpty
                    ? EmptyView(icon: Icons.receipt_long_outlined, title: t.noRentRows, message: '')
                    : EmptyView(icon: Icons.verified_rounded, title: t.noPendingTitle, message: t.noPendingMessage),
              )
            else
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.line),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(children: [
                  for (var i = 0; i < shown.length; i++)
                    _TenantRow(
                      row: shown[i],
                      photo: _thumbs['${shown[i]['tenant_id']}'],
                      last: i == shown.length - 1,
                      onTap: () => _openTenant(shown[i], hostelName),
                    ),
                ]),
              ),
            if (rows.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(t.tapTenantHint,
                    textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
              ),
          ];

          // fixed reminder button at the bottom
          final Widget? dock = (toRemind > 0 && r['is_current'] == true)
              ? Container(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                  decoration: const BoxDecoration(
                    color: AppColors.ground,
                    border: Border(top: BorderSide(color: AppColors.line)),
                  ),
                  child: SizedBox(
                    height: 50,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                          backgroundColor: _blue, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                      icon: const Icon(Icons.campaign_rounded),
                      label: Text(t.sendReminderAll('$toRemind'),
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                      onPressed: () => _remindAll(toRemind),
                    ),
                  ),
                )
              : null;

          return Column(children: [
            // the whole page scrolls; only the reminder button stays at the bottom
            Expanded(
              child: RefreshIndicator(
                onRefresh: reload,
                child: Scrollbar(
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    children: [
                      Narrow(
                        maxWidth: 640,
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [...header, ...listItems]),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (dock != null) dock,
          ]);
        },
      ),
    );
  }

  Future<void> _openTenant(Json row, String hostelName) async {
    final t = context.l10n;
    final hid = widget.hostelId;
    final tid = row['tenant_id'];
    final paid = row['status'] == 'paid';
    if (paid) {
      context.go('/h/$hid/tenants/$tid');
      return;
    }
    final name = row['full_name'] as String? ?? phoneText(row['phone'] as String?);
    final phone = (row['phone'] as String? ?? '').replaceAll('+', '');
    final due = asInt(row['amount']);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            Text('${t.room} ${roomBed(row['room_no'], row['bed_label'])} · ${money(due)}',
                style: const TextStyle(color: AppColors.muted)),
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.add_card_rounded, color: _blue),
              title: Text(t.recordPayment, style: const TextStyle(fontWeight: FontWeight.w600)),
              onTap: () {
                Navigator.of(ctx).pop();
                context.push('/h/$hid/record/$tid');
              },
            ),
            ListTile(
              leading: const Icon(Icons.chat_rounded, color: AppColors.whatsapp),
              title: Text(t.sendReminder, style: const TextStyle(fontWeight: FontWeight.w600)),
              onTap: () {
                Navigator.of(ctx).pop();
                launchUrl(
                  Uri.parse('https://wa.me/$phone?text=${Uri.encodeComponent(t.reminderMessage(name, money(due), hostelName))}'),
                  mode: LaunchMode.externalApplication,
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.person_outline_rounded),
              title: Text(t.openTenant, style: const TextStyle(fontWeight: FontWeight.w600)),
              onTap: () {
                Navigator.of(ctx).pop();
                context.go('/h/$hid/tenants/$tid');
              },
            ),
          ]),
        ),
      ),
    );
  }
}

const _greenTint = Color(0xFFEAF6EE);
const _amberTint = Color(0xFFFFF4E2);
const _redTint = Color(0xFFFDECEC);

class _Tile {
  const _Tile(this.label, this.value, this.color, this.sub, this.tint);
  final String label, value, sub;
  final Color color, tint;
}

/// Light blue box with a title row and three white tiles (same look for month and today).
class _MetricsBox extends StatelessWidget {
  const _MetricsBox({required this.title, required this.right, required this.tiles, this.footer});
  final Widget title;
  final String right;
  final List<_Tile> tiles;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: _boxBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _boxLine),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          title,
          const SizedBox(width: 8),
          Expanded(
            child: Text(right,
                textAlign: TextAlign.end,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.muted, fontSize: 11, fontWeight: FontWeight.w400)),
          ),
        ]),
        const SizedBox(height: 6),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (var i = 0; i < tiles.length; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            Expanded(
              child: Container(
                padding: const EdgeInsets.fromLTRB(8, 6, 6, 6),
                decoration: BoxDecoration(color: tiles[i].tint, borderRadius: BorderRadius.circular(12)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(tiles[i].label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.muted, fontSize: 11, fontWeight: FontWeight.w400)),
                  const SizedBox(height: 1),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(tiles[i].value,
                        style: TextStyle(color: tiles[i].color, fontSize: 16, fontWeight: FontWeight.w800)),
                  ),
                  Text(tiles[i].sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                ]),
              ),
            ),
          ],
        ]),
        if (footer != null) Padding(padding: const EdgeInsets.only(top: 2), child: footer!),
      ]),
    );
  }
}

class _TenantRow extends StatelessWidget {
  const _TenantRow({required this.row, required this.last, required this.onTap, this.photo});
  final Json row;
  final String? photo; // small photo link; initials when there is none
  final bool last;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    final name = row['full_name'] as String? ?? phoneText(row['phone'] as String?);
    final status = row['status'] as String? ?? '';
    final (Color fg, Color bg) = switch (status) {
      'late' => (AppColors.danger, AppColors.dangerSoft),
      'due' => (_amber, const Color(0xFFFEF0D7)),
      'upcoming' => (_blue, const Color(0xFFE3EDFC)),
      _ => (_green, const Color(0xFFDDF3E8)),
    };
    final statusText = switch (status) {
      'late' => t.daysLate('${asInt(row['days_late'])}'),
      'due' => t.dueToday,
      'upcoming' => t.dueOn(shortDate(context, row['next_due'])),
      _ => row['paid_on'] == null
          ? t.paidPlain
          : t.paidOnVia(shortDate(context, row['paid_on']), methodLabel(context, '${row['method'] ?? ''}')),
    };
    final room = roomBed(row['room_no'], row['bed_label']);
    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            border: last ? null : const Border(bottom: BorderSide(color: Color(0xFFEEF1F5))),
          ),
          child: Row(children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: bg,
              foregroundImage: photo == null ? null : NetworkImage(photo!),
              onForegroundImageError: photo == null ? null : (_, __) {},
              child: Text(_initials(name), style: TextStyle(color: fg, fontWeight: FontWeight.w600, fontSize: 12.5)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                if (asInt(row['late_fee']) > 0)
                  Text.rich(
                    TextSpan(children: [
                      TextSpan(text: '${t.room} $room · '),
                      TextSpan(
                        text: t.rentPlusFee(money(asInt(row['due'])), money(asInt(row['late_fee']))),
                        style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w800),
                      ),
                    ]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.muted, fontSize: 12.5),
                  )
                else
                  Text('${t.room} $room', style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
              ]),
            ),
            const SizedBox(width: 8),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(money(asInt(row['amount'])), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
              Text(statusText, style: TextStyle(color: fg, fontWeight: FontWeight.w600, fontSize: 12.5)),
            ]),
          ]),
        ),
      ),
    );
  }
}

String _initials(String name) {
  final p = name.trim().split(RegExp(r'\s+')).where((x) => x.isNotEmpty).toList();
  if (p.isEmpty) return '?';
  return (p.first[0] + (p.length > 1 ? p.last[0] : '')).toUpperCase();
}
