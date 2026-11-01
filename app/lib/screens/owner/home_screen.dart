import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config.dart';
import '../../core/errors.dart';
import '../../core/format.dart';
import '../../theme.dart';
import '../../data/owner_repo.dart';
import '../../widgets/common.dart';
import 'hostel_scope.dart';
import 'invite_screen.dart' show downloadJoinQr;

/// Owner Home (22 Oct 2026):
///  - blue header: ‹ My hostels · Switch, "Name – Type" (2 lines at most, shrinks a little rather than a 3rd line), area
///  - Payments card: Month and Today side by side (received · of total · balance in red), eye hides amounts, Remind
///  - Needs your action: Confirm payments · Approve joins · Complaints · Leaving notices · Available beds
///  - Invite students (light blue card): QR + Download, "Scan this QR to join", Share link · Poster
/// The page fits one screen: the action rows share the free space (compact spacing below 860 px high,
/// extra compact below 800). Only a phone that still can't fit everything scrolls – nothing is cut off.
class _Hc {
  static const ink = Color(0xFF14213D);
  static const muted = Color(0xFF5C6782);
  static const blue = Color(0xFF1560BD);
  static const darkBlue = Color(0xFF0C447C);
  static const green = Color(0xFF15803D);
  static const red = Color(0xFFDC2626);
  static const sheet = AppColors.ground;
  static const chip = Color(0x29FFFFFF);
  static const chipLine = Color(0x66FFFFFF);
}

/// Amounts hidden / shown; remembered while the app is open.
bool _hideAmounts = false;

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.hostelId});
  final String hostelId;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  Widget build(BuildContext context) {
    final scope = HostelScope.of(context);
    final h = scope.hostel;
    final s = scope.summary;
    if (h == null || s == null) {
      return Scaffold(
        body: scope.error != null
            ? ErrorView(error: scope.error!, onRetry: scope.refresh)
            : const Center(child: CircularProgressIndicator()),
      );
    }
    final screenH = MediaQuery.sizeOf(context).height;
    final tight = screenH < 860;
    final xtight = screenH < 800;
    final gap = xtight ? 6.0 : tight ? 8.0 : 10.0;
    return Scaffold(
      backgroundColor: _Hc.sheet,
      body: RefreshIndicator(
        onRefresh: scope.refresh,
        child: LayoutBuilder(
          builder: (context, box) => SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: box.maxHeight),
              child: IntrinsicHeight(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Header(hostel: h, tight: tight),
                    Expanded(
                      child: Transform.translate(
                        offset: const Offset(0, -22),
                        child: Container(
                          decoration: const BoxDecoration(
                            color: _Hc.sheet,
                            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                          ),
                          padding: EdgeInsets.fromLTRB(16, tight ? 10 : 7, 16, 0),
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 640),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (!tight)
                                    Center(
                                      child: Container(
                                        width: 40,
                                        height: 4,
                                        margin: const EdgeInsets.only(bottom: 8),
                                        decoration: BoxDecoration(
                                            color: const Color(0xFFC5CEDB), borderRadius: BorderRadius.circular(2)),
                                      ),
                                    ),
                                  _SetupChecklist(hostel: h, summary: s),
                                  _PaymentsCard(
                                    hostelId: widget.hostelId,
                                    summary: s,
                                    hide: _hideAmounts,
                                    tight: tight,
                                    onToggle: () => setState(() => _hideAmounts = !_hideAmounts),
                                  ),
                                  SizedBox(height: gap),
                                  Expanded(child: _ActionsCard(hostelId: widget.hostelId, summary: s, tight: tight, xtight: xtight)),
                                  SizedBox(height: gap),
                                  _InviteCard(hostel: h, tight: tight),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.hostel, required this.tight});
  final Json hostel;
  final bool tight;

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    final area = hostelAreaLine(hostel);
    final title = hostelTitle(context, hostel);
    return Container(
      color: AppColors.primary,
      padding: EdgeInsets.only(bottom: tight ? 26 : 30),
      child: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ‹ My hostels · Switch (both go back to My hostels)
                  Row(children: [
                    Tooltip(
                      message: t.back,
                      child: Material(
                        color: _Hc.chip,
                        shape: const CircleBorder(side: BorderSide(color: _Hc.chipLine)),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: () => context.go('/hostels'),
                          child: const SizedBox(width: 38, height: 38, child: Icon(Icons.chevron_left_rounded, color: Colors.white)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(t.myHostels, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white)),
                    ),
                    Material(
                      color: _Hc.chip,
                      shape: const StadiumBorder(side: BorderSide(color: _Hc.chipLine)),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => context.go('/hostels'),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(Icons.swap_horiz_rounded, size: 16, color: Colors.white),
                            const SizedBox(width: 6),
                            Text(t.switchShort, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Colors.white)),
                          ]),
                        ),
                      ),
                    ),
                  ]),
                  SizedBox(height: tight ? 10 : 14),
                  // name and type: one line if it fits, otherwise 2 lines; very long names get a little smaller
                  _TwoLineTitle(text: title),
                  if (area.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Row(children: [
                      const Icon(Icons.location_on_outlined, size: 14, color: AppColors.onBlueMuted),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(area,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w400, color: AppColors.onBlueMuted)),
                      ),
                    ]),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Header title: 20 px, at most 2 lines. Very long names get a little smaller (down to 16 px) rather than
/// a 3rd line. (Sized by length, not measured, so the page can still work out its own height.)
class _TwoLineTitle extends StatelessWidget {
  const _TwoLineTitle({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final n = text.length;
    final size = n > 52 ? 16.0 : n > 46 ? 17.0 : n > 40 ? 18.5 : 20.0;
    return Text(text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: size, fontWeight: FontWeight.w800, color: Colors.white, height: 1.25));
  }
}

/// White card with a thin border and a very light shadow; the whole card can be tappable.
class _HomeCard extends StatelessWidget {
  const _HomeCard({required this.child, this.onTap, required this.semantics, this.padding, this.color, this.borderColor});
  final Widget child;
  final VoidCallback? onTap;
  final String semantics;
  final EdgeInsets? padding;
  final Color? color;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final pad = padding ?? const EdgeInsets.fromLTRB(12, 10, 12, 10);
    return Semantics(
      button: onTap != null,
      label: semantics,
      child: Container(
        decoration: BoxDecoration(
          color: color ?? Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor ?? AppColors.line),
          boxShadow: appCardShadow,
        ),
        child: Material(
          color: Colors.transparent,
          child: onTap == null
              ? Padding(padding: pad, child: child)
              : InkWell(borderRadius: BorderRadius.circular(16), onTap: onTap, child: Padding(padding: pad, child: child)),
        ),
      ),
    );
  }
}

/// Payments: Month · October and Today · 20 Oct side by side. Each half: received (green, big), "of <total>",
/// "<balance> left" in red ("All paid" in green). The eye hides the amounts. Bottom: who hasn't paid today + Remind.
class _PaymentsCard extends StatelessWidget {
  const _PaymentsCard({required this.hostelId, required this.summary, required this.hide, required this.tight, required this.onToggle});
  final String hostelId;
  final Json summary;
  final bool hide;
  final bool tight;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    String m(int v) => hide ? '₹ ••••' : money(v);
    final got = asInt(summary['collected_month']);
    final billed = asInt(summary['billed_month']);
    final dueTotal = asInt(summary['due_today_total']);
    final duePaid = asInt(summary['due_today_paid']);
    final count = asInt(summary['due_today_tenants']);
    final names = [for (final n in (summary['due_today_names'] as List? ?? const [])) '$n'.trim().split(RegExp(r'\s+')).first];
    final extra = math0(count - names.length);
    final who = [...names, if (extra > 0) '+$extra'].join(', ');
    final month = DateFormat('MMMM', context.lang).format(DateTime.now());
    final date = DateFormat('d MMM', context.lang).format(DateTime.now());

    Widget half(String label, int received, int total) {
      final left = math0(total - received);
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 2, 12, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _Hc.muted)),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(m(received),
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: hide ? _Hc.ink : _Hc.green, height: 1.3,
                      letterSpacing: hide ? 2 : 0)),
            ),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(t.ofAmount(m(total)), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w400, color: _Hc.muted)),
            ),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: left > 0 || hide
                  ? Text(t.amountLeft(m(left)), style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: _Hc.red))
                  : Text(t.allPaid, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: _Hc.green)),
            ),
          ]),
        ),
      );
    }

    return _HomeCard(
      semantics: t.homePayments,
      padding: EdgeInsets.zero,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: EdgeInsets.fromLTRB(12, tight ? 6 : 8, 8, 0),
          child: Row(children: [
            Expanded(child: Text(t.homePayments, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: _Hc.muted))),
            Tooltip(
              message: hide ? t.showAmounts : t.hideAmounts,
              child: Material(
                color: AppColors.primarySoft,
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: onToggle,
                  child: SizedBox(
                    width: tight ? 28 : 32,
                    height: tight ? 28 : 32,
                    child: Icon(hide ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 18, color: _Hc.blue),
                  ),
                ),
              ),
            ),
          ]),
        ),
        InkWell(
          onTap: () => context.go('/h/$hostelId/rent'),
          child: IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              half(t.homeMonthLabel(month), got, billed),
              Container(width: 1, margin: const EdgeInsets.only(bottom: 8), color: const Color(0xFFEEF2F6)),
              half(t.todayDate(date), duePaid, dueTotal),
            ]),
          ),
        ),
        Container(
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFFEEF2F6)))),
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
          child: Row(children: [
            Expanded(
              child: Text(count > 0 ? t.notPaidTodayNames(who) : t.everyonePaidToday,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w400, color: _Hc.muted)),
            ),
            if (count > 0)
              SizedBox(
                height: 32,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 32),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                  ),
                  onPressed: () => _remind(context, count),
                  child: Text(t.remind),
                ),
              ),
          ]),
        ),
      ]),
    );
  }

  Future<void> _remind(BuildContext context, int count) async {
    final t = context.l10n;
    final ok = await confirm(context, title: t.remindAllTitle('$count'), message: t.remindAllMessage, okLabel: t.sendReminders);
    if (!ok || !context.mounted) return;
    try {
      final sent = await OwnerRepo.instance.remindAll(hostelId);
      if (context.mounted) showSnack(context, sent == 0 ? t.remindersNone : t.remindersSent('$sent'));
    } catch (e) {
      if (context.mounted) showSnack(context, errorText(context, e), error: true);
    }
  }
}

/// Needs your action: one card, each row icon · title · count · ›. Rows share the card's height.
class _ActionsCard extends StatelessWidget {
  const _ActionsCard({required this.hostelId, required this.summary, required this.tight, required this.xtight});
  final String hostelId;
  final Json summary;
  final bool tight;
  final bool xtight;

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    final base = '/h/$hostelId';
    final total = asInt(summary['beds_total']);
    final free = math0(total - asInt(summary['beds_filled']) - asInt(summary['beds_held']));
    final freeRooms = summary['rooms_with_free'];
    final rows = <Widget>[
      _row(context, Icons.payments_outlined, _Hc.blue, AppColors.primarySoft, t.confirmPayments,
          asInt(summary['payments_to_check']), () => context.go('$base/requests')),
      _row(context, Icons.person_add_alt_outlined, const Color(0xFF0F6E56), const Color(0xFFE1F5EE), t.approveJoins,
          asInt(summary['joins_to_approve']), () => context.go('$base/requests')),
      if (summary.containsKey('open_complaints'))
        _row(context, Icons.build_outlined, const Color(0xFFA32D2D), const Color(0xFFFCEBEB), t.complaints,
            asInt(summary['open_complaints']), () => context.go('$base/complaints')),
      _row(context, Icons.logout_rounded, const Color(0xFF534AB7), const Color(0xFFEEEDFE), t.leavingNotices,
          asInt(summary['leaving']), () => context.go('$base/tenants?filter=notice')),
      _row(context, Icons.bed_outlined, const Color(0xFF3B6D11), const Color(0xFFEAF3DE), t.availableBeds, free,
          () => context.go('$base/rooms?status=available'),
          sub: freeRooms == null ? t.bedsTotalCount('$total') : t.inRoomsTotal('${asInt(freeRooms)}', '$total')),
    ];
    return _HomeCard(
      semantics: t.needsYourAction,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 2),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(t.needsYourAction, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: _Hc.muted)),
        for (var i = 0; i < rows.length; i++)
          Expanded(
            child: Container(
              constraints: BoxConstraints(minHeight: xtight ? 32 : tight ? 36 : 40),
              decoration: BoxDecoration(
                border: i == rows.length - 1 ? null : const Border(bottom: BorderSide(color: Color(0xFFEEF2F6))),
              ),
              child: rows[i],
            ),
          ),
      ]),
    );
  }

  Widget _row(BuildContext context, IconData icon, Color color, Color bg, String title, int count, VoidCallback onTap,
      {String? sub}) {
    final box = tight ? 30.0 : 34.0;
    return Semantics(
      button: true,
      label: '$title: $count',
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: tight ? 2 : 3),
          child: Row(children: [
            Container(
              width: box,
              height: box,
              decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, size: tight ? 16 : 18, color: color),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _Hc.ink)),
                if (sub != null)
                  Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w400, color: _Hc.muted)),
              ]),
            ),
            Container(
              constraints: const BoxConstraints(minWidth: 24),
              height: 24,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              alignment: Alignment.center,
              decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
              child: Text('$count', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: color)),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right_rounded, size: 20, color: _Hc.blue),
          ]),
        ),
      ),
    );
  }
}

int math0(int v) => v < 0 ? 0 : v;

/// "Madhapur, Hyderabad": last useful part of the address, then the city.
String hostelAreaLine(Json hostel) {
  final city = (hostel['city'] ?? '').toString().trim();
  final pin = (hostel['pincode'] ?? '').toString().trim();
  final parts = (hostel['address'] ?? '')
      .toString()
      .split(RegExp(r'[,\n]'))
      .map((p) => p.trim())
      .where((p) => p.isNotEmpty)
      .where((p) => city.isEmpty || !p.toLowerCase().contains(city.toLowerCase()))
      .where((p) => pin.isEmpty || !p.contains(pin))
      .where((p) => !RegExp(r'^\d+$').hasMatch(p))
      .toList();
  return [if (parts.isNotEmpty) parts.last, if (city.isNotEmpty) city].join(', ');
}


/// Invite students (light blue card, 22 Oct 2026): white QR box + Download, "Invite students" (16) and
/// "Scan this QR to join" (14) in dark blue, Share link and Poster side by side as white pills.
class _InviteCard extends StatelessWidget {
  const _InviteCard({required this.hostel, required this.tight});
  final Json hostel;
  final bool tight;

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    final link = AppConfig.joinLink(hostel['join_code'] as String);
    final invite = '/h/${hostel['id']}/invite';
    Widget pill(IconData icon, String text, VoidCallback onTap) => Expanded(
          child: Material(
            color: Colors.white,
            shape: const StadiumBorder(side: BorderSide(color: AppColors.primaryLine)),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: SizedBox(
                height: 32,
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(icon, size: 15, color: _Hc.blue),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: _Hc.blue)),
                  ),
                ]),
              ),
            ),
          ),
        );
    final qr = tight ? 48.0 : 60.0;
    return _HomeCard(
      onTap: () => context.go(invite),
      semantics: t.inviteStudents,
      color: AppColors.primarySoft,
      borderColor: AppColors.primaryLine,
      padding: const EdgeInsets.all(10),
      child: Row(children: [
        Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: qr,
            height: qr,
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
            child: QrImageView(data: link, padding: EdgeInsets.zero, backgroundColor: Colors.transparent),
          ),
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => downloadJoinQr(context, hostel),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.download_rounded, size: 14, color: _Hc.blue),
                const SizedBox(width: 3),
                Text(t.downloadShort, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _Hc.blue)),
              ]),
            ),
          ),
        ]),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t.inviteStudents, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _Hc.darkBlue)),
            Text(t.scanToJoin, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _Hc.darkBlue)),
            const SizedBox(height: 8),
            Row(children: [
              pill(Icons.share_outlined, t.shareLink, () => launchUrl(
                    Uri.parse('https://wa.me/?text=${Uri.encodeComponent(t.inviteMessage(hostelTitle(context, hostel), link))}'),
                    mode: LaunchMode.externalApplication,
                  )),
              const SizedBox(width: 8),
              // Poster: the big QR screen, ready to print or screenshot.
              pill(Icons.print_outlined, t.poster, () => context.go(invite)),
            ]),
          ]),
        ),
      ]),
    );
  }
}

/// New hostel: Hostel details ✓ → Add rooms → Payment options → Rent day & rules → Invite students.
class _SetupChecklist extends StatelessWidget {
  const _SetupChecklist({required this.hostel, required this.summary});
  final Json hostel;
  final Json summary;

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    final id = hostel['id'];
    final rooms = asInt(summary['rooms']) > 0;
    final payment = (hostel['accept_upi'] == true && hostel['upi_id'] != null) ||
        (hostel['accept_bank'] == true && (hostel['bank_details'] ?? '').toString().isNotEmpty) ||
        (hostel['accept_cash'] == true && hostel['accept_upi'] != true);
    final rules = (hostel['house_rules'] ?? '').toString().trim().isNotEmpty;
    final invited = asInt(summary['tenants']) > 0;
    final steps = [
      (t.setupDetails, true, null),
      (t.setupRooms, rooms, '/h/$id/add-room'),
      (t.setupPayment, payment, '/h/$id/settings'),
      (t.setupRules, rules, '/h/$id/settings'),
      (t.setupInvite, invited, '/h/$id/invite'),
    ];
    final done = steps.where((s) => s.$2).length;
    if (done == steps.length) return const SizedBox.shrink();
    return SectionCard(
      title: t.setupTitle,
      trailing: Text('$done/${steps.length}', style: const TextStyle(fontWeight: FontWeight.w600)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LinearProgressIndicator(value: done / steps.length, minHeight: 6, borderRadius: BorderRadius.circular(4)),
          const SizedBox(height: 8),
          for (final (label, ok, route) in steps)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: Icon(ok ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                  color: ok ? AppColors.success : AppColors.field),
              title: Text(label,
                  style: TextStyle(
                      fontWeight: FontWeight.w600, decoration: ok ? TextDecoration.lineThrough : null)),
              trailing: ok || route == null ? null : const Icon(Icons.chevron_right_rounded, color: AppColors.primary),
              onTap: ok || route == null ? null : () => context.push(route),
            ),
        ],
      ),
    );
  }
}
