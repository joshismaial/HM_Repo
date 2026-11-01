import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/errors.dart';
import '../../core/locale_controller.dart';
import '../../core/format.dart';
import '../../data/student_api.dart';
import '../../theme.dart';
import '../../widgets/bill_widgets.dart';
import '../../widgets/common.dart';
import '../../widgets/pay_widgets.dart';
import '../owner/complaints_screen.dart' show issueCategories, issueIcon, issueLabel, issueStatusLabel, issueStatusTone;
import '../owner/more_screen.dart' show supportEmail;
import '../owner/notices_screen.dart' show noticeTypeOf;
import 'student_frame.dart' show rentDayText;

// Home tile colours ("Clean white" look, 20 Oct 2026): round solid icons on white tiles.
const _teal = Color(0xFF14B8A6); // Wi-Fi
const _rose = Color(0xFFF43F5E); // Leaving?
const _amberIcon = Color(0xFFF59E0B); // notices
const _violet = Color(0xFF8B5CF6); // ad space
const _amber = Color(0xFFB45309); // amber text (fee due, cash told, part paid)

/// The student's app after joining (private link /s/<token>).
/// Tabs (20 Oct 2026): Home · Fees · Report issue · Settings, in the lifted floating tab bar.
/// Room details and house rules are in Settings; Wi-Fi and leaving are on Home.
class StudentHome extends StatefulWidget {
  const StudentHome({super.key, required this.token});
  final String token;

  @override
  State<StudentHome> createState() => _StudentHomeState();
}

class _StudentHomeState extends State<StudentHome> {
  late Future<Json> _future = _load();
  Json? _last; // keeps the screen while reloading
  int _tab = 0;

  Future<Json> _load() async {
    await StudentApi.instance.useToken(widget.token);
    final me = await StudentApi.instance.me();
    _last = me;
    return me;
  }

  void _reload() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    return FutureBuilder<Json>(
      future: _future,
      builder: (context, snap) {
        final data = snap.connectionState == ConnectionState.done && snap.hasData ? snap.data : _last;
        if (data == null && snap.connectionState != ConnectionState.done) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snap.hasError) {
          final code = AppException.from(snap.error!).code;
          return Scaffold(
            appBar: AppBar(
              title: Text(t.appName),
              actions: const [Padding(padding: EdgeInsets.only(right: 8), child: LanguageButton())],
            ),
            body: code == 'SESSION_INVALID' || code == 'NO_BOOKING'
                ? ListView(children: [
                    EmptyView(icon: Icons.link_off_rounded, title: t.linkNotWorkingTitle, message: t.linkNotWorkingText),
                  ])
                : ErrorView(error: snap.error!, onRetry: _reload),
          );
        }
        final s = _Stay(data!);
        final pages = [
          _HomeTab(s: s, onReload: _reload, goFees: () => setState(() => _tab = 1)),
          _FeesTab(s: s, onReload: _reload),
          _IssuesTab(s: s, onReload: _reload),
          _SettingsTab(s: s),
        ];
        final feeCount = (s.toPay > 0 && s.canPay ? 1 : 0) + s.feeMessages.length;
        final issueCount = s.issues.where((i) => i['unread'] == true).length;
        Widget badge(Widget icon, int n) => n > 0 ? Badge(label: Text('$n'), child: icon) : icon;
        // phone back: other tabs go to Home first, then the app closes
        return BackButtonListener(
          onBackButtonPressed: () async {
            if (_tab == 0) return false;
            setState(() => _tab = 0);
            return true;
          },
          child: Scaffold(
            extendBody: true,
            body: IndexedStack(index: _tab, children: pages),
            bottomNavigationBar: FloatingTabBar(
              child: NavigationBar(
                selectedIndex: _tab,
                onDestinationSelected: (i) => setState(() => _tab = i),
                destinations: [
                  NavigationDestination(icon: const Icon(Icons.home_outlined), selectedIcon: const Icon(Icons.home_rounded), label: t.tabHome),
                  NavigationDestination(
                    icon: badge(const Icon(Icons.currency_rupee_rounded), feeCount),
                    selectedIcon: badge(const Icon(Icons.currency_rupee_rounded), feeCount),
                    label: t.tabFees,
                  ),
                  NavigationDestination(
                    icon: badge(const Icon(Icons.report_gmailerrorred_outlined), issueCount),
                    selectedIcon: badge(const Icon(Icons.report_gmailerrorred_rounded), issueCount),
                    label: t.stTabIssue,
                  ),
                  NavigationDestination(
                      icon: const Icon(Icons.settings_outlined), selectedIcon: const Icon(Icons.settings_rounded), label: t.settings),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Everything the tabs need, read once from student_me (+ student_me_extra merged into tenant).
class _Stay {
  _Stay(this.me)
      : hostel = Json.from(me['hostel'] as Map),
        tenant = Json.from(me['tenant'] as Map),
        balance = Json.from(me['balance'] as Map),
        bills = (me['bills'] as List).cast<Map>().map(Json.from).toList(),
        payments = (me['payments'] as List).cast<Map>().map(Json.from).toList();
  final Json me, hostel, tenant, balance;
  final List<Json> bills, payments;

  String? get status => tenant['status'] as String?;
  bool get canPay => status == 'active' || status == 'notice';
  bool get left => status == 'vacated';
  bool get waiting => status == 'pending_approval' || status == 'awaiting_payment';
  int get lateFee => asInt(tenant['late_fee']);
  int get lateDays => asInt(tenant['late_days']);
  int get perDay => asInt(tenant['late_fee_per_day']);
  int get due => asInt(balance['due_now']) + lateFee;
  int get noticeDays => asInt(tenant['notice_days'] ?? hostel['notice_days']);
  DateTime? get nextFeeDate => asDate(tenant['next_fee_date']);
  List<Json> _list(String k) => ((tenant[k] as List?) ?? const []).cast<Map>().map(Json.from).toList();
  List<Json> get wifi => _list('wifi');
  List<Json> get messages => _list('messages');
  List<Json> get notices => _list('notices');
  List<Json> get issues => _list('issues');
  Json? get cashPlan => tenant['cash_plan'] is Map ? Json.from(tenant['cash_plan'] as Map) : null;
  Json? get ad => tenant['ad'] is Map ? Json.from(tenant['ad'] as Map) : null;
  List<Json> get pendingPayments =>
      payments.where((p) => p['status'] == 'pending' && !(p['method'] == 'cash' && cashPlan != null && p['id'] == cashPlan!['id'])).toList();
  List<Json> get received => payments.where((p) => p['status'] == 'received').toList();

  static const _feeKinds = {'payment_not_received', 'cash_not_received', 'payment_received'};
  /// Payment messages: in Fees, until the student taps OK.
  List<Json> get feeMessages => messages.where((m) => _feeKinds.contains(m['kind'])).toList();
  /// Owner's change messages (sharing, fee date, notice period): in the Home "Notice" section.
  List<Json> get changeMessages => messages.where((m) => !_feeKinds.contains(m['kind']) && m['kind'] != 'issue_update').toList();

  /// Bills still open, oldest first.
  List<Json> get openBills {
    final open = bills.where((b) => b['status'] == 'unpaid' || b['status'] == 'partial').toList()
      ..sort((a, b) => '${a['due_date']}'.compareTo('${b['due_date']}'));
    return open;
  }

  Json? get nextBill => openBills.isEmpty ? null : openBills.first;
  static int remaining(Json b) => asInt(b['amount']) - asInt(b['paid_amount']);

  /// Bills that make up the amount to pay now: everything already due, or else the next bill.
  List<Json> get payBills {
    final now = today();
    final dueBills = openBills.where((b) => !(asDate(b['due_date']) ?? now).isAfter(now)).toList();
    if (dueBills.isNotEmpty) return dueBills;
    return nextBill == null ? const [] : [nextBill!];
  }

  /// What the student pays now (balance after part payments + late fee).
  int get toPay => payBills.fold<int>(0, (a, b) => a + remaining(b)) + lateFee;
  int get billTotal => payBills.fold<int>(0, (a, b) => a + asInt(b['amount'])) + lateFee;
  int get paidSoFar => payBills.fold<int>(0, (a, b) => a + asInt(b['paid_amount']));

  DateTime? get dueDate => payBills.isEmpty ? null : asDate(payBills.last['due_date']);
  int get daysToDue => dueDate == null ? 9999 : dueDate!.difference(today()).inDays;

  /// "paid" when nothing is due and the next fee is more than a week away.
  bool get showPaid {
    if (toPay <= 0) return true;
    final lastDue = bills.where((b) => !(asDate(b['due_date']) ?? today()).isAfter(today())).toList();
    return due <= 0 && daysToDue > 7 && lastDue.isNotEmpty && lastDue.every((b) => b['status'] == 'paid' || b['status'] == 'cancelled');
  }

  String get firstName => ((tenant['full_name'] as String?) ?? '').trim().split(RegExp(r'\s+')).first;
}

String _initials(String? name) {
  final parts = (name ?? '').trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  return (parts.first[0] + (parts.length > 1 ? parts.last[0] : '')).toUpperCase();
}

Widget _sectionTitle(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
      child: Text(text, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
    );

BoxDecoration _box({Color color = Colors.white}) => BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.line),
      boxShadow: appCardShadow,
    );

Widget _card({required Widget child, EdgeInsets padding = const EdgeInsets.all(14)}) =>
    Container(padding: padding, decoration: _box(), child: child);

Widget _roundIcon(IconData icon, Color color, {double size = 36}) => Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: Icon(icon, size: size * 0.5, color: Colors.white),
    );

String _shortWhen(BuildContext context, dynamic at) {
  final d = asDate(at);
  if (d == null) return '';
  final days = today().difference(DateTime(d.year, d.month, d.day)).inDays;
  if (days <= 0) return context.l10n.stToday;
  return shortDate(context, d);
}

/// The student's own photo, or initials.
Widget _avatar(_Stay s, double size, {Color ring = Colors.white, bool onBlue = false}) {
  final url = s.tenant['photo_url'] as String?;
  return Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      border: Border.all(color: ring, width: 3),
      color: onBlue ? Colors.white.withValues(alpha: 0.18) : AppColors.primary,
    ),
    clipBehavior: Clip.antiAlias,
    alignment: Alignment.center,
    child: url == null
        ? Text(_initials(s.tenant['full_name'] as String?),
            style: TextStyle(color: Colors.white, fontSize: size > 60 ? 20 : 16, fontWeight: FontWeight.w800))
        : Image.network(url, width: size, height: size, fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Text(_initials(s.tenant['full_name'] as String?),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800))),
  );
}

// =====================================================================================
// Home: name band → fee card → ad space (grows) → Notice → Wi-Fi + Leaving? tiles. Fits one screen.
// =====================================================================================
class _HomeTab extends StatelessWidget {
  const _HomeTab({required this.s, required this.onReload, required this.goFees});
  final _Stay s;
  final VoidCallback onReload, goFees;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async => onReload(),
        child: LayoutBuilder(
          builder: (context, box) => SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 96), // room for the floating tab bar
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: box.maxHeight - 96),
              child: IntrinsicHeight(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  _NameBand(s: s, top: top),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        if (s.waiting)
                          Banner2(tone: Tone.warning, icon: Icons.hourglass_top_rounded, text: context.l10n.waitingOwnerConfirm)
                        else if (!s.left && s.canPay)
                          _FeeCard(s: s, goFees: goFees),
                        const SizedBox(height: 12),
                        Expanded(child: _AdSpace(ad: s.ad)),
                        _NoticeSection(s: s),
                        const SizedBox(height: 12),
                        IntrinsicHeight(
                          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                            if (_wifiFor(s) != null) ...[
                              Expanded(child: _WifiTile(wifi: _wifiFor(s)!)),
                              if (!s.waiting) const SizedBox(width: 12),
                            ],
                            if (!s.waiting) Expanded(child: _LeavingTile(s: s, onReload: onReload)),
                          ]),
                        ),
                      ]),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Wi-Fi for the student's floor first, then the whole-hostel one.
Json? _wifiFor(_Stay s) {
  if (!s.canPay || s.wifi.isEmpty) return null;
  final floor = s.tenant['room_floor'];
  return s.wifi.firstWhere((w) => w['floor'] == floor && floor != null,
      orElse: () => s.wifi.firstWhere((w) => w['floor'] == null, orElse: () => s.wifi.first));
}

class _NameBand extends StatelessWidget {
  const _NameBand({required this.s, required this.top});
  final _Stay s;
  final double top;

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    final tn = s.tenant;
    Widget chip(Widget child) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
            borderRadius: BorderRadius.circular(99),
          ),
          child: child,
        );
    return Container(
      padding: EdgeInsets.fromLTRB(18, top + 16, 18, 18),
      decoration: const BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(26)),
      ),
      child: Row(children: [
        _avatar(s, 64, onBlue: true),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tn['full_name'] as String? ?? '', maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
            Text(hostelTitle(context, s.hostel), maxLines: 2,
                style: const TextStyle(color: AppColors.onBlueMuted, fontSize: 12.5, fontWeight: FontWeight.w600)),
            if (tn['room_no'] != null) ...[
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 6, children: [
                chip(Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.bed_outlined, size: 13, color: Colors.white),
                  const SizedBox(width: 5),
                  Text(tn['bed_label'] == null ? '${tn['room_no']}' : '${tn['room_no']} · ${t.bed} ${tn['bed_label']}',
                      style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600)),
                ])),
                if (tn['sharing'] != null)
                  chip(Text(t.sharingN('${tn['sharing']}'),
                      style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600))),
              ]),
            ],
          ]),
        ),
      ]),
    );
  }
}

/// Compact fee card (half height), 4 states: before the date (blue) · late with late fee (red) ·
/// late, late fee off (amber) · paid (green). Date box | label + amount + one line | Pay, then a breakdown strip.
class _FeeCard extends StatelessWidget {
  const _FeeCard({required this.s, required this.goFees});
  final _Stay s;
  final VoidCallback goFees;

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    final lang = context.lang;
    final d = s.dueDate;
    final dd = d == null ? '' : '${d.day}';
    final mon = d == null ? '' : DateFormat('MMM', lang).format(d).toUpperCase();
    final dateLabel = d == null ? '' : shortDate(context, d);

    // one line: rent + extra charges + late fee (only when there is one)
    final parts = <String>[
      for (final b in s.payBills) b['kind'] == 'rent' ? t.stRentLine(money(asInt(b['amount']))) : '${b['label'] ?? ''} ${money(asInt(b['amount']))}',
      if (s.lateFee > 0) t.stLateFeeLine(money(s.lateFee)),
    ];
    final breakdown = parts.join(' + ');

    Widget box(Color fg, Color bg, {Widget? child}) => Container(
          width: 58,
          height: 58,
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
          alignment: Alignment.center,
          child: child ??
              Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(mon, style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w600)),
                Text(dd, style: TextStyle(color: fg, fontSize: 20, fontWeight: FontWeight.w800, height: 1.1)),
              ]),
        );
    Widget payBtn(Color bg) => SizedBox(
          height: 44,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: bg, padding: const EdgeInsets.symmetric(horizontal: 14)),
            onPressed: goFees,
            icon: const Icon(Icons.bolt_rounded, size: 16),
            label: Text(t.stPay),
          ),
        );

    late final Color fg, soft, labelColor, lineColor;
    late final Widget left, btn;
    late final String label, line, strip;
    late final int amount;
    final cash = s.cashPlan;

    if (s.showPaid) {
      final r = s.received.isEmpty ? null : s.received.first;
      fg = AppColors.success;
      soft = AppColors.successSoft;
      left = box(fg, fg, child: const Icon(Icons.check_rounded, size: 34, color: Colors.white));
      label = t.stFeePaidLabel;
      labelColor = fg;
      amount = r == null ? asInt(s.tenant['rent_month']) : asInt(r['amount_received']);
      line = r == null ? '' : t.paidOnVia(shortDate(context, r['paid_on']), methodLabel(context, '${r['method']}'));
      lineColor = AppColors.muted;
      strip = s.nextFeeDate == null ? '' : t.stNextFeeOnTime(shortDate(context, s.nextFeeDate));
      btn = SizedBox(
        height: 44,
        child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12)),
          onPressed: goFees,
          icon: const Icon(Icons.receipt_long_outlined, size: 16),
          label: Text(t.stReceipt),
        ),
      );
    } else if (s.daysToDue < 0 && s.perDay > 0) {
      fg = AppColors.danger;
      soft = AppColors.dangerSoft;
      left = box(fg, soft);
      label = t.stFeeOverdue(dateLabel);
      labelColor = fg;
      amount = s.toPay;
      line = t.stDaysLatePerDay('${s.lateDays}', money(s.perDay));
      lineColor = fg;
      strip = breakdown;
      btn = payBtn(fg);
    } else if (s.daysToDue < 0) {
      fg = _amber;
      soft = AppColors.warningSoft;
      left = box(fg, soft);
      label = t.stFeeDue(dateLabel);
      labelColor = fg;
      amount = s.toPay;
      line = t.stPleasePayNow;
      lineColor = fg;
      strip = breakdown;
      btn = payBtn(AppColors.success);
    } else {
      fg = AppColors.primary;
      soft = AppColors.primarySoft;
      left = box(fg, soft);
      final part = s.paidSoFar > 0;
      label = part ? t.stFeePartPaid(dateLabel) : (s.daysToDue == 0 ? t.stFeeNextToday : t.stFeeNext(dateLabel));
      labelColor = part ? _amber : AppColors.muted;
      amount = s.toPay;
      final pending = s.pendingPayments.fold<int>(0, (a, p) => a + asInt(p['amount_claimed']));
      if (cash != null) {
        line = switch (cash['plan']) { 'paid' => t.stCashPaidWaiting, 'tomorrow' => t.stCashTomorrowTold, _ => t.stCashTodayTold };
        lineColor = _amber;
      } else if (pending > 0) {
        line = t.stPaymentChecking(money(pending));
        lineColor = _amber;
      } else if (part) {
        line = t.paidOfTotal(money(s.paidSoFar), money(s.billTotal));
        lineColor = _amber;
      } else {
        line = s.daysToDue == 0
            ? t.stPayToday
            : (s.perDay > 0 ? t.stDaysLeftLate('${s.daysToDue}', money(s.perDay)) : t.stDaysLeft('${s.daysToDue}'));
        lineColor = AppColors.muted;
      }
      strip = breakdown;
      btn = payBtn(AppColors.success);
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
        boxShadow: appCardShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(border: Border(left: BorderSide(color: fg, width: 6))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              left,
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: labelColor, fontSize: 12.5, fontWeight: FontWeight.w600)),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(money(amount), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, height: 1.15)),
                  ),
                  if (line.isNotEmpty)
                    Text(line, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: lineColor, fontSize: 11, fontWeight: FontWeight.w600)),
                ]),
              ),
              const SizedBox(width: 8),
              btn,
            ]),
          ),
          if (strip.isNotEmpty)
            Container(
              color: soft,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              child: Text(strip, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
            ),
        ]),
      ),
    );
  }
}

/// Ad space: grows to fill the free space (min ~92 px). Sponsored card from `student_ads` (added by the app admin
/// only) or an empty "Ad space" box. Shown only on Home – never on payment or ID screens.
class _AdSpace extends StatefulWidget {
  const _AdSpace({required this.ad});
  final Json? ad;

  @override
  State<_AdSpace> createState() => _AdSpaceState();
}

class _AdSpaceState extends State<_AdSpace> {
  static final _seen = <String>{}; // count one view per ad per app run
  bool _hidden = false;

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    final ad = _hidden ? null : widget.ad;
    if (ad != null && _seen.add('${ad['id']}')) StudentApi.instance.adEvent('${ad['id']}', click: false);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 92),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: ad != null
            ? _box()
            : BoxDecoration(
                color: const Color(0xFFFAFAFF),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _violet.withValues(alpha: 0.5), width: 1.5),
              ),
        alignment: Alignment.center,
        child: ad == null
            ? Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.campaign_outlined, color: _violet, size: 22),
                Text(t.stAdSpace, style: const TextStyle(color: _violet, fontWeight: FontWeight.w600)),
                Text(t.stAdSpaceHelp, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
              ])
            : Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Expanded(
                    child: Text(t.stSponsored,
                        style: const TextStyle(color: AppColors.muted, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
                  ),
                  InkWell(onTap: () => setState(() => _hidden = true), child: const Icon(Icons.close_rounded, size: 16, color: AppColors.muted)),
                ]),
                const SizedBox(height: 6),
                Row(children: [
                  _roundIcon(Icons.storefront_outlined, _violet, size: 48),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${ad['shop'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                      Text('${ad['offer'] ?? ''}', style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                    ]),
                  ),
                  if ((ad['button_value'] as String?)?.isNotEmpty == true)
                    FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: _violet, minimumSize: const Size(0, 36), padding: const EdgeInsets.symmetric(horizontal: 14)),
                      onPressed: () {
                        StudentApi.instance.adEvent('${ad['id']}', click: true);
                        final v = ad['button_value'] as String;
                        launchUrl(Uri.parse(ad['button_kind'] == 'link' ? v : 'tel:$v'), mode: LaunchMode.externalApplication);
                      },
                      child: Text(ad['button_kind'] == 'link' ? t.stOpenOffer : t.stCallShop),
                    ),
                ]),
              ]),
      ),
    );
  }
}

/// "Notice": owner's notices + automatic change messages (NEW), or the default "Keep the hostel clean".
class _NoticeSection extends StatelessWidget {
  const _NoticeSection({required this.s});
  final _Stay s;

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    final rows = <(IconData, String, String, String)>[
      for (final m in s.changeMessages)
        (_changeIcon(m['kind']), _changeText(context, m).$1, _changeText(context, m).$2, _shortWhen(context, m['at'])),
      for (final n in s.notices) (noticeTypeOf(n['icon'] as String?).icon, '${n['title'] ?? ''}', '${n['body'] ?? ''}', _shortWhen(context, n['at'])),
    ];
    final posted = rows.isNotEmpty;
    final list = posted ? rows.take(3).toList() : [(Icons.cleaning_services_outlined, t.stDefaultNoticeTitle, t.stDefaultNoticeBody, '')];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
        child: Row(children: [
          Text(t.stNoticeHeading, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          if (posted) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(color: AppColors.danger, borderRadius: BorderRadius.circular(8)),
              child: Text(t.stNewTag, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
            ),
          ],
        ]),
      ),
      Container(
        decoration: _box(),
        child: Column(children: [
          for (var i = 0; i < list.length; i++)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                border: i < list.length - 1 ? const Border(bottom: BorderSide(color: AppColors.line)) : null,
              ),
              child: Row(children: [
                _roundIcon(list[i].$1, _amberIcon, size: 38),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(list[i].$2, style: const TextStyle(fontWeight: FontWeight.w600)),
                    if (list[i].$3.isNotEmpty) Text(list[i].$3, style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                  ]),
                ),
                if (list[i].$4.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Text(list[i].$4, style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                ],
              ]),
            ),
        ]),
      ),
    ]);
  }
}

IconData _changeIcon(dynamic kind) => switch (kind) {
      'sharing_change' => Icons.bed_outlined,
      'rent_date_change' => Icons.event_rounded,
      'price_change' => Icons.sell_outlined,
      _ => Icons.hourglass_bottom_rounded,
    };

String _ordinal(BuildContext context, int d) {
  if (context.lang != 'en') return '$d';
  final suffix = (d % 100 >= 11 && d % 100 <= 13) ? 'th' : const {1: 'st', 2: 'nd', 3: 'rd'}[d % 10] ?? 'th';
  return '$d$suffix';
}

/// Title + text of an owner's change message (room sharing, fee date, notice period).
(String, String) _changeText(BuildContext context, Json m) {
  final t = context.l10n;
  final p = Json.from((m['params'] as Map?) ?? const {});
  return switch (m['kind']) {
    'sharing_change' => (
        t.msgSharingTitle('${p['to']}'),
        t.msgSharingBody('${p['room']}', shortDate(context, p['from_date']), money(asInt(p['new_rent'])), money(asInt(p['old_rent']))),
      ),
    'rent_date_change' => (
        p['mode'] == 'joining_date' ? t.msgFeeDateJoiningTitle : t.msgFeeDateTitle(_ordinal(context, asInt(p['day']))),
        asInt(p['days']) > 0
            ? t.msgFeeDateMore(shortDate(context, p['next_due']), money(asInt(p['rent'])), money(asInt(p['adjust'])), '${p['days']}', money(asInt(p['amount'])))
            : t.msgFeeDateLess(shortDate(context, p['next_due']), money(asInt(p['rent'])), money(-asInt(p['adjust'])), '${-asInt(p['days'])}', money(asInt(p['amount']))),
      ),
    _ => (t.msgNoticeTitle('${p['days']}'), t.msgNoticeBody('${p['days']}')),
  };
}

Widget _tileButton(String label, Color fg, Color bg, VoidCallback onTap, {IconData? icon}) => Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: SizedBox(
            height: 40,
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              if (icon != null) ...[Icon(icon, size: 17, color: fg), const SizedBox(width: 6)],
              Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
      ),
    );

class _WifiTile extends StatelessWidget {
  const _WifiTile({required this.wifi});
  final Json wifi;

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    final pass = '${wifi['password'] ?? ''}';
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: _box(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _roundIcon(Icons.wifi_rounded, _teal),
          const SizedBox(width: 10),
          Text(t.amenWifi, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        ]),
        const SizedBox(height: 8),
        Text('${wifi['name'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        Text(t.stPasswordLine(pass), maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
        const Spacer(),
        _tileButton(t.copy, const Color(0xFF0F766E), const Color(0xFFF0FDFA), () async {
          await Clipboard.setData(ClipboardData(text: pass));
          if (context.mounted) showSnack(context, t.stWifiCopied);
        }, icon: Icons.copy_rounded),
      ]),
    );
  }
}

/// Leaving? The leaving date is always the next fee date (no date picker). Notice at least
/// notice_days before it = deposit back. After notice: leaving date, deposit line, Cancel notice.
class _LeavingTile extends StatelessWidget {
  const _LeavingTile({required this.s, required this.onReload});
  final _Stay s;
  final VoidCallback onReload;

  Future<void> _give(BuildContext context) async {
    final t = context.l10n;
    final fee = s.nextFeeDate;
    if (fee == null) return;
    final days = fee.difference(today()).inDays;
    final onTime = days >= s.noticeDays;
    final deadline = fee.subtract(Duration(days: s.noticeDays));
    final ok = await confirm(
      context,
      title: t.stLeaveOnQ(dateText(context, fee)),
      message: onTime ? t.stOnTimeNoticeText : t.stLateNoticeText(shortDate(context, deadline), dateText(context, fee)),
      okLabel: onTime ? t.sendNotice : t.stGiveNoticeNoRefund,
      danger: !onTime,
    );
    if (!ok || !context.mounted) return;
    try {
      await StudentApi.instance.giveNotice();
      if (context.mounted) showSnack(context, t.noticeSent);
      onReload();
    } catch (e) {
      if (context.mounted) showSnack(context, errorText(context, e), error: true);
    }
  }

  Future<void> _cancel(BuildContext context) async {
    final t = context.l10n;
    final ok = await confirm(context, title: t.stCancelNoticeQ, message: t.stCancelNoticeText, okLabel: t.stYesStaying);
    if (!ok || !context.mounted) return;
    try {
      await StudentApi.instance.cancelNotice();
      if (context.mounted) showSnack(context, t.stNoticeCancelled);
      onReload();
    } catch (e) {
      if (context.mounted) showSnack(context, errorText(context, e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    const muted = TextStyle(color: AppColors.muted, fontSize: 12.5);
    const strong = TextStyle(color: AppColors.ink, fontSize: 12.5, fontWeight: FontWeight.w600);
    Widget head(IconData icon, Color color, String title) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(children: [
            _roundIcon(icon, color),
            const SizedBox(width: 10),
            Expanded(child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
          ]),
        );
    final children = <Widget>[];
    if (s.left) {
      children.addAll([
        head(Icons.done_all_rounded, AppColors.success, t.stYouHaveLeft),
        Text(t.stLeftOn(dateText(context, s.tenant['leaving_date'])), style: muted),
        const Spacer(),
        Text(t.stThanksStaying, style: muted),
      ]);
    } else if (s.status == 'notice') {
      final leave = asDate(s.tenant['leaving_date']);
      final given = asDate(s.tenant['notice_given_at']);
      final onTime = leave == null || given == null ||
          leave.difference(DateTime(given.year, given.month, given.day)).inDays >= s.noticeDays;
      children.addAll([
        head(Icons.event_outlined, _rose, t.noticeGiven),
        Text(t.leavingOn(shortDate(context, leave)), style: muted),
        Text(onTime ? t.stDepositBackAmount(money(asInt(s.tenant['deposit']))) : t.stShortNoticeNoRefund,
            style: TextStyle(color: onTime ? AppColors.success : AppColors.danger, fontSize: 12.5, fontWeight: FontWeight.w800)),
        const Spacer(),
        _tileButton(t.stCancelNotice, const Color(0xFFE11D48), const Color(0xFFFFF1F2), () => _cancel(context)),
      ]);
    } else {
      final fee = s.nextFeeDate;
      final onTime = fee == null || fee.difference(today()).inDays >= s.noticeDays;
      final deadline = fee?.subtract(Duration(days: s.noticeDays));
      children.addAll([
        head(Icons.logout_rounded, _rose, t.stLeaving),
        if (deadline != null)
          Text.rich(TextSpan(style: muted, children: [
            TextSpan(text: onTime ? t.stGiveNoticeBy(shortDate(context, deadline)) : t.stNoticeDatePassed(shortDate(context, deadline))),
            const TextSpan(text: ' '),
            TextSpan(
              text: onTime ? t.stDepositBackArrow : t.stNoRefundArrow,
              style: strong.copyWith(color: onTime ? AppColors.success : AppColors.danger),
            ),
          ])),
        const Spacer(),
        if (s.canPay && fee != null)
          _tileButton(t.giveNotice, const Color(0xFFE11D48), const Color(0xFFFFF1F2), () => _give(context)),
      ]);
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: _box(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }
}

// =====================================================================================
// Fees: bill (total · paid so far · still due), messages with OK, Pay online / Pay by cash, history
// =====================================================================================
class _FeesTab extends StatelessWidget {
  const _FeesTab({required this.s, required this.onReload});
  final _Stay s;
  final VoidCallback onReload;

  bool get _online => s.tenant['accept_online'] == true || s.hostel['upi'] != null || (s.hostel['bank'] != null && '${s.hostel['bank']}'.trim().isNotEmpty);
  bool get _cash => s.hostel['cash'] != null;

  void _sheet(BuildContext context, Widget Function(BuildContext ctx) builder) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(ctx).bottom),
        child: SingleChildScrollView(child: builder(ctx)),
      ),
    );
  }

  Future<void> _ack(BuildContext context, Json m) async {
    try {
      await StudentApi.instance.ackMessage('${m['id']}');
      onReload();
    } catch (e) {
      if (context.mounted) showSnack(context, errorText(context, e), error: true);
    }
  }

  Future<void> _cancelCash(BuildContext context) async {
    final t = context.l10n;
    try {
      await StudentApi.instance.cancelCashPlan();
      if (context.mounted) showSnack(context, t.stCashCancelled);
      onReload();
    } catch (e) {
      if (context.mounted) showSnack(context, errorText(context, e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    final cash = s.cashPlan;
    final nothing = s.toPay <= 0;
    final pending = s.pendingPayments.fold<int>(0, (a, p) => a + asInt(p['amount_claimed']));
    return Scaffold(
      appBar: AppBar(title: Text(t.tabFees), automaticallyImplyLeading: false),
      body: RefreshIndicator(
        onRefresh: () async => onReload(),
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 110), children: [
          _card(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(child: Text(t.yourBill, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
                if (nothing)
                  Chip2(t.billPaid, tone: Tone.success)
                else if (s.dueDate != null)
                  Chip2(t.dueOn(shortDate(context, s.dueDate)), tone: s.daysToDue < 0 ? Tone.danger : Tone.warning),
              ]),
              const SizedBox(height: 8),
              if (nothing)
                Text(t.stNothingToPay, style: const TextStyle(color: AppColors.muted))
              else ...[
                for (final b in s.payBills) InfoRow(billLabel(context, b), money(asInt(b['amount']))),
                if (s.lateFee > 0)
                  InfoRow(t.lateFeeDaysTimes('${s.lateDays}', money(s.perDay)), money(s.lateFee)),
                const Divider(height: 18),
                InfoRow(t.stTotal, money(s.billTotal), bold: true),
                if (s.paidSoFar > 0) ...[
                  InfoRow(t.stPaidSoFar, '− ${money(s.paidSoFar)}'),
                  InfoRow(t.stStillDue, money(s.toPay), bold: true),
                ],
              ],
              if (pending > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(t.paymentsBeingChecked(money(pending)), style: const TextStyle(color: AppColors.primary, fontSize: 12.5)),
                ),
            ]),
          ),
          // messages from the owner about payments: stay until OK
          for (final m in s.feeMessages) _FeeMessage(m: m, onOk: () => _ack(context, m)),
          const SizedBox(height: 14),
          if (!s.canPay)
            Banner2(icon: Icons.hourglass_top_rounded, text: t.payAfterConfirm)
          else if (!nothing) ...[
            if (_online)
              SizedBox(
                height: 50,
                child: FilledButton.icon(
                  icon: const Icon(Icons.bolt_rounded),
                  label: Text(t.stPayOnline(money(s.toPay))),
                  onPressed: () => _sheet(context, (ctx) => _OnlinePaySheet(s: s, onPaid: onReload)),
                ),
              ),
            if (_cash) ...[
              const SizedBox(height: 10),
              if (cash != null)
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFBF3),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFF6DDB8), width: 1.5),
                  ),
                  child: Column(children: [
                    Row(children: [
                      _roundIcon(Icons.hourglass_top_rounded, _amberIcon, size: 42),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(
                            switch (cash['plan']) { 'paid' => t.stCashPaidTold, 'tomorrow' => t.stCashTomorrowPlan, _ => t.stCashTodayPlan },
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          Text(t.stWaitingConfirm(money(asInt(cash['amount']))), style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                        ]),
                      ),
                    ]),
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => _sheet(context, (ctx) => _CashSheet(s: s, onDone: onReload)),
                          child: Text(t.stChange),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: TextButton(onPressed: () => _cancelCash(context), child: Text(t.cancel))),
                    ]),
                  ]),
                )
              else
                SizedBox(
                  height: 50,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.payments_outlined),
                    label: Text(t.stPayByCash),
                    onPressed: () => _sheet(context, (ctx) => _CashSheet(s: s, onDone: onReload)),
                  ),
                ),
            ],
            if (!_online && !_cash) Banner2(tone: Tone.danger, text: t.noPaymentMethods),
          ],
          _sectionTitle(t.paymentHistory),
          _card(
            child: s.payments.isEmpty
                ? Text(t.noPayments, style: const TextStyle(color: AppColors.muted))
                : Column(children: [for (final p in s.payments) PaymentRow(payment: p)]),
          ),
        ]),
      ),
    );
  }
}

class _FeeMessage extends StatelessWidget {
  const _FeeMessage({required this.m, required this.onOk});
  final Json m;
  final VoidCallback onOk;

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    final p = Json.from((m['params'] as Map?) ?? const {});
    final good = m['kind'] == 'payment_received';
    final amount = money(asInt(p['amount']));
    final text = switch (m['kind']) {
      'payment_received' => t.stMsgPaymentReceived(amount),
      'cash_not_received' => t.stMsgCashNotReceived(amount),
      _ => t.stMsgPaymentNotReceived(methodLabel(context, '${p['method'] ?? 'upi'}'), amount),
    };
    final fg = good ? AppColors.success : AppColors.danger;
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: good ? AppColors.successSoft : AppColors.dangerSoft, borderRadius: BorderRadius.circular(12)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(good ? Icons.check_circle_rounded : Icons.error_rounded, size: 20, color: fg),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: TextStyle(color: fg, fontWeight: FontWeight.w600))),
        const SizedBox(width: 8),
        Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onOk,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              child: Text(t.ok, style: TextStyle(color: fg, fontSize: 12.5, fontWeight: FontWeight.w600)),
            ),
          ),
        ),
      ]),
    );
  }
}

/// "How much now?" Full ₹due or Part now (type the amount; no minimum).
class _AmountPicker extends StatefulWidget {
  const _AmountPicker({required this.due, required this.onChanged});
  final int due;
  final ValueChanged<int> onChanged;

  @override
  State<_AmountPicker> createState() => _AmountPickerState();
}

class _AmountPickerState extends State<_AmountPicker> {
  bool _part = false;
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  int get _typed => int.tryParse(_text.text) ?? 0;

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    Widget box(bool on, String title, String sub, VoidCallback onTap) => Expanded(
          child: Material(
            color: on ? AppColors.primarySoft : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: on ? AppColors.primary : AppColors.line, width: 1.5),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(on ? Icons.radio_button_checked : Icons.radio_button_off, size: 18, color: on ? AppColors.primary : AppColors.muted),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(title, style: TextStyle(fontWeight: FontWeight.w600, color: on ? AppColors.primary : AppColors.ink)),
                    ),
                  ]),
                  Padding(
                    padding: const EdgeInsets.only(left: 24, top: 2),
                    child: Text(sub, style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                  ),
                ]),
              ),
            ),
          ),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(t.stHowMuchNow, style: const TextStyle(fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      Row(children: [
        box(!_part, t.stFullAmount(money(widget.due)), t.stClearBill, () {
          setState(() => _part = false);
          widget.onChanged(widget.due);
        }),
        const SizedBox(width: 8),
        box(_part, t.stPartNow, t.stPayRestLater, () {
          setState(() => _part = true);
          widget.onChanged(_typed.clamp(0, widget.due));
        }),
      ]),
      if (_part) ...[
        const SizedBox(height: 10),
        TextField(
          controller: _text,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(7)],
          decoration: InputDecoration(labelText: t.stAmountNow, prefixText: '₹ ', hintText: '4000'),
          onChanged: (_) {
            setState(() {});
            widget.onChanged(_typed.clamp(0, widget.due));
          },
        ),
        if (_typed > 0 && _typed < widget.due)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(t.stStillDueAfter(money(widget.due - _typed)),
                style: const TextStyle(color: _amber, fontSize: 12.5, fontWeight: FontWeight.w800)),
          ),
      ],
    ]);
  }
}

/// Pay online: only the options the owner turned on (instant online · UPI apps · any UPI app · bank).
/// UPI app / bank → "Done – I have paid" (no UTR for now) → the owner checks it in Requests.
class _OnlinePaySheet extends StatefulWidget {
  const _OnlinePaySheet({required this.s, required this.onPaid});
  final _Stay s;
  final VoidCallback onPaid;

  @override
  State<_OnlinePaySheet> createState() => _OnlinePaySheetState();
}

class _OnlinePaySheetState extends State<_OnlinePaySheet> {
  late int _amount = widget.s.toPay;
  (String, String?)? _step; // ('upi', app) or ('bank', null)

  bool _okAmount() {
    if (_amount > 0) return true;
    showSnack(context, context.l10n.stEnterAmountNow, error: true);
    return false;
  }

  Widget _opt(IconData icon, String title, String sub, VoidCallback onTap, {String? badge}) => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Material(
          color: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: AppColors.line, width: 1.2)),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(12)),
                  child: Icon(icon, color: AppColors.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Flexible(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14))),
                      if (badge != null) ...[const SizedBox(width: 6), Chip2(badge, tone: Tone.success)],
                    ]),
                    Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                  ]),
                ),
                const Icon(Icons.chevron_right_rounded, color: AppColors.primary),
              ]),
            ),
          ),
        ),
      );

  static const _schemes = {'gpay': 'tez://upi/pay', 'phonepe': 'phonepe://pay', 'paytm': 'paytmmp://pay'};

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    final h = widget.s.hostel;
    final upi = h['upi'] is Map ? Json.from(h['upi'] as Map) : null;
    final bank = '${h['bank'] ?? ''}'.trim();
    final note = '${widget.s.me['payment_note'] ?? ''}';
    final step = _step;
    if (step != null) {
      final isUpi = step.$1 == 'upi';
      final appName = switch (step.$2) { 'gpay' => t.payGpay, 'phonepe' => t.payPhonepe, 'paytm' => t.payPaytm, _ => t.stAnyUpiApp };
      final link = isUpi ? upiLink(upiId: upi!['id'] as String, payee: '${upi['name']}', amount: _amount, note: note) : '';
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(isUpi ? t.payWithApp(appName) : t.methodBank, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: AppColors.ground, borderRadius: BorderRadius.circular(12)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (isUpi)
              InfoRow(t.upiId, '${upi!['id']}', bold: true, trailing: IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.copy_rounded, size: 18),
                onPressed: () => copyText(context, '${upi['id']}'),
              ))
            else
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: SelectableText(bank, style: const TextStyle(fontWeight: FontWeight.w600, height: 1.5))),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    onPressed: () => copyText(context, bank),
                  ),
                ]),
              ),
            InfoRow(t.amount, money(_amount), bold: true),
            InfoRow(t.paymentNote, note, trailing: IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.copy_rounded, size: 18),
              onPressed: () => copyText(context, note),
            )),
          ]),
        ),
        const SizedBox(height: 12),
        if (isUpi) ...[
          SizedBox(
            height: 50,
            child: FilledButton.icon(
              icon: const Icon(Icons.open_in_new_rounded),
              label: Text(t.stOpenAppFilled(appName)),
              onPressed: () async {
                final scheme = _schemes[step.$2];
                final uri = Uri.parse(scheme == null ? link : '$scheme?${link.substring(link.indexOf('?') + 1)}');
                final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
                if (!ok && context.mounted) showSnack(context, t.noUpiApp, error: true);
              },
            ),
          ),
          const SizedBox(height: 10),
        ],
        BusyButton(
          label: t.stDonePaid,
          icon: Icons.check_circle_outline_rounded,
          outlined: isUpi,
          onPressed: () async {
            await StudentApi.instance.payBill(method: step.$1, amount: _amount, paidOn: today());
            if (!context.mounted) return;
            Navigator.of(context).pop();
            showSnack(context, t.stPaidToldOwner);
            widget.onPaid();
          },
        ),
        TextButton(onPressed: () => setState(() => _step = null), child: Text(t.back)),
      ]);
    }

    final apps = ((upi?['apps'] as List?) ?? const []).cast<String>().where(_schemes.containsKey).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(t.stPayOnline(money(_amount)), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
      Text(t.stOptionsAccepted, style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
      const SizedBox(height: 12),
      _AmountPicker(due: widget.s.toPay, onChanged: (v) => setState(() => _amount = v)),
      const SizedBox(height: 4),
      // Instant online pay (Razorpay) – shown only when the owner turned it on; the gateway is not connected yet
      if (widget.s.tenant['accept_online'] == true)
        _opt(Icons.bolt_rounded, t.stInstantTitle, t.stReceiptAtOnce, () => showSnack(context, t.stOnlineSoon), badge: t.stInstant),
      if (upi != null) ...[
        for (final a in apps)
          _opt(
            a == 'gpay' ? Icons.g_mobiledata_rounded : (a == 'phonepe' ? Icons.phone_android_rounded : Icons.account_balance_wallet_outlined),
            switch (a) { 'gpay' => t.payGpay, 'phonepe' => t.payPhonepe, _ => t.payPaytm },
            t.stToUpi('${upi['id']}'),
            () {
              if (_okAmount()) setState(() => _step = ('upi', a));
            },
          ),
        _opt(Icons.qr_code_2_rounded, t.stAnyUpiApp, '${t.upiId} ${upi['id']}', () {
          if (_okAmount()) setState(() => _step = ('upi', null));
        }),
      ],
      if (bank.isNotEmpty)
        _opt(Icons.account_balance_outlined, t.methodBank, bank.split('\n').first, () {
          if (_okAmount()) setState(() => _step = ('bank', null));
        }),
      TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(t.close)),
    ]);
  }
}

/// Pay by cash: owner's cash note, How much now?, When will you pay? Today / Tomorrow / Already paid → Tell owner.
class _CashSheet extends StatefulWidget {
  const _CashSheet({required this.s, required this.onDone});
  final _Stay s;
  final VoidCallback onDone;

  @override
  State<_CashSheet> createState() => _CashSheetState();
}

class _CashSheetState extends State<_CashSheet> {
  late String _when = (widget.s.cashPlan?['plan'] as String?) ?? 'today';
  late int _amount = widget.s.toPay;

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    final note = '${widget.s.hostel['cash'] ?? ''}'.trim();
    final opts = [
      ('today', Icons.wb_sunny_outlined, t.stToday),
      ('tomorrow', Icons.calendar_today_outlined, t.stTomorrow),
      ('paid', Icons.done_all_rounded, t.stAlreadyPaid),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Center(
        child: Container(
          width: 64,
          height: 64,
          decoration: const BoxDecoration(color: AppColors.successSoft, shape: BoxShape.circle),
          child: const Icon(Icons.payments_outlined, size: 32, color: AppColors.success),
        ),
      ),
      const SizedBox(height: 8),
      Text(t.stPayInCash, textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: AppColors.warningSoft, borderRadius: BorderRadius.circular(12)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.schedule_rounded, color: _amber),
          const SizedBox(width: 10),
          Expanded(child: Text(note.isEmpty ? t.stCashDefault : note, style: const TextStyle(fontWeight: FontWeight.w600, height: 1.4))),
        ]),
      ),
      const SizedBox(height: 12),
      _AmountPicker(due: widget.s.toPay, onChanged: (v) => setState(() => _amount = v)),
      const SizedBox(height: 12),
      Text(t.stWhenPay, style: const TextStyle(fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      Row(children: [
        for (final o in opts) ...[
          if (o != opts.first) const SizedBox(width: 8),
          Expanded(
            child: Material(
              color: _when == o.$1 ? AppColors.primarySoft : Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: _when == o.$1 ? AppColors.primary : AppColors.line, width: 1.5),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => setState(() => _when = o.$1),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Column(children: [
                    Icon(o.$2, size: 20, color: _when == o.$1 ? AppColors.primary : AppColors.muted),
                    const SizedBox(height: 4),
                    Text(o.$3,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: _when == o.$1 ? AppColors.primary : AppColors.ink)),
                  ]),
                ),
              ),
            ),
          ),
        ],
      ]),
      const SizedBox(height: 14),
      BusyButton(
        label: _when == 'paid' ? t.stTellOwnerPaid : t.stTellOwner,
        icon: Icons.notifications_active_outlined,
        onPressed: () async {
          if (_amount <= 0) {
            showSnack(context, t.stEnterAmountNow, error: true);
            return;
          }
          await StudentApi.instance.cashPlan(plan: _when, amount: _amount);
          if (!context.mounted) return;
          Navigator.of(context).pop();
          showSnack(context, t.stOwnerToldCash);
          widget.onDone();
        },
      ),
      const SizedBox(height: 6),
      Text(t.stCashSheetFoot, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
    ]);
  }
}

// =====================================================================================
// Report issue: category chips, description, Send to owner; My issues with status and owner's reply
// =====================================================================================
class _IssuesTab extends StatefulWidget {
  const _IssuesTab({required this.s, required this.onReload});
  final _Stay s;
  final VoidCallback onReload;

  @override
  State<_IssuesTab> createState() => _IssuesTabState();
}

class _IssuesTabState extends State<_IssuesTab> {
  String _cat = issueCategories.first;
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final t = context.l10n;
    if (_text.text.trim().isEmpty) {
      showSnack(context, t.stDescribeProblem, error: true);
      return;
    }
    await StudentApi.instance.reportIssue(category: _cat, body: _text.text.trim());
    if (!mounted) return;
    _text.clear();
    FocusScope.of(context).unfocus();
    showSnack(context, t.stIssueSent);
    widget.onReload();
  }

  Future<void> _read(Json i) async {
    if (i['unread'] != true) return;
    try {
      await StudentApi.instance.readIssue('${i['id']}');
      widget.onReload();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    final issues = widget.s.issues;
    return Scaffold(
      appBar: AppBar(title: Text(t.stReportTitle), automaticallyImplyLeading: false),
      body: RefreshIndicator(
        onRefresh: () async => widget.onReload(),
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 110), children: [
          Text(t.stReportHelp, style: const TextStyle(color: AppColors.muted)),
          const SizedBox(height: 12),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final c in issueCategories)
              ChoiceChip(
                avatar: Icon(issueIcon(c), size: 16, color: _cat == c ? Colors.white : AppColors.primary),
                label: Text(issueLabel(context, c)),
                selected: _cat == c,
                showCheckmark: false,
                selectedColor: AppColors.primary,
                backgroundColor: Colors.white,
                labelStyle: TextStyle(fontWeight: FontWeight.w600, color: _cat == c ? Colors.white : AppColors.ink),
                side: BorderSide(color: _cat == c ? AppColors.primary : AppColors.line),
                shape: const StadiumBorder(),
                onSelected: (_) => setState(() => _cat = c),
              ),
          ]),
          const SizedBox(height: 14),
          TextField(
            controller: _text,
            minLines: 3,
            maxLines: 5,
            maxLength: 500,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(hintText: t.stIssueHint),
          ),
          const SizedBox(height: 6),
          BusyButton(label: t.stSendToOwner, icon: Icons.send_rounded, onPressed: _send),
          _sectionTitle(t.stMyIssues),
          if (issues.isEmpty)
            EmptyView(icon: Icons.check_circle_outline_rounded, title: t.stNoIssuesTitle, message: t.stNoIssuesText)
          else
            for (final i in issues)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: i['unread'] == true ? AppColors.primary : AppColors.line, width: i['unread'] == true ? 1.5 : 1),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => _read(i),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        if (i['unread'] == true)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(t.stNewUpdate,
                                style: const TextStyle(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.w600)),
                          ),
                        Row(children: [
                          Chip2(issueLabel(context, i['category'] as String?)),
                          const Spacer(),
                          Chip2(issueStatusLabel(context, i['status'] as String?), tone: issueStatusTone(i['status'] as String?)),
                        ]),
                        const SizedBox(height: 8),
                        Text('${i['body'] ?? ''}'),
                        if ((i['owner_reply'] as String?)?.isNotEmpty == true) ...[
                          const SizedBox(height: 8),
                          Text(t.stOwnerReply(i['owner_reply'] as String),
                              style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600)),
                        ],
                        const SizedBox(height: 4),
                        Text(dateText(context, i['at']), style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                      ]),
                    ),
                  ),
                ),
              ),
        ]),
      ),
    );
  }
}

// =====================================================================================
// Settings: name card, MY STAY (My room · House rules · My details), APP (Language · Privacy & terms · Delete my data)
// =====================================================================================
class _SettingsTab extends StatelessWidget {
  const _SettingsTab({required this.s});
  final _Stay s;

  List<String> get _rules => '${s.tenant['house_rules'] ?? s.hostel['house_rules'] ?? ''}'
      .split('\n')
      .map((l) => l.replaceFirst(RegExp(r'^\s*[-•*\d.)]+\s*'), '').trim())
      .where((l) => l.isNotEmpty)
      .toList();

  void _sheet(BuildContext context, String title, List<Widget> children) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
              Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              ...children,
            ]),
          ),
        ),
      ),
    );
  }

  void _room(BuildContext context) {
    final t = context.l10n;
    final tn = s.tenant;
    _sheet(context, t.tabMyRoom, [
      InfoRow(t.roomBed, roomBed(tn['room_no'], tn['bed_label']), bold: true),
      if (tn['sharing'] != null) InfoRow(t.sharing, t.sharingN('${tn['sharing']}')),
      if (tn['room_floor'] != null) InfoRow(t.floor, asInt(tn['room_floor']) == 0 ? t.groundFloor : t.floorN('${tn['room_floor']}')),
      InfoRow(t.joiningDate, dateText(context, tn['joining_date'])),
      InfoRow(t.rentPerMonth, money(asInt(tn['rent_month']))),
      InfoRow(t.deposit, money(asInt(tn['deposit']))),
      InfoRow(t.yourRentDay, rentDayText(context, s.hostel)),
    ]);
  }

  void _rulesSheet(BuildContext context) {
    final t = context.l10n;
    final rules = _rules;
    _sheet(context, t.houseRules, [
      if (rules.isEmpty) Text(t.noRulesYet, style: const TextStyle(color: AppColors.muted)),
      for (final r in rules)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.check_circle_rounded, size: 18, color: AppColors.primary),
            const SizedBox(width: 10),
            Expanded(child: Text(r, style: const TextStyle(height: 1.4))),
          ]),
        ),
      const SizedBox(height: 8),
      Text(t.noticeRule('${s.noticeDays}'), style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
    ]);
  }

  void _details(BuildContext context) {
    final t = context.l10n;
    final tn = s.tenant;
    InfoRow? kv(String k, String? v) => (v == null || v.trim().isEmpty) ? null : InfoRow(k, v);
    _sheet(context, t.myDetailsTitle, [
      ...[
        kv(t.stMobile, phoneText(tn['phone'] as String?)),
        kv(t.idProof, tn['id_last4'] == null ? null : '•••• ${tn['id_last4']}'),
        kv(t.parentName, tn['parent_name'] as String?),
        kv(t.parentPhone, tn['parent_phone'] == null ? null : phoneText(tn['parent_phone'] as String?)),
        kv(t.referenceName, tn['reference_name'] as String?),
        kv(t.referencePhoneShort, tn['reference_phone'] == null ? null : phoneText(tn['reference_phone'] as String?)),
        kv(t.orgShort, tn['org_name'] as String?),
        kv(t.homeAddress, tn['home_address'] as String?),
      ].whereType<InfoRow>(),
      const SizedBox(height: 8),
      Text(t.detailsLocked, style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
    ]);
  }

  void _language(BuildContext context) {
    final ctrl = LocaleScope.of(context);
    _sheet(context, context.l10n.language, [
      for (final e in appLanguages.entries)
        Builder(
          builder: (ctx) => ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(e.value, style: const TextStyle(fontWeight: FontWeight.w600)),
            trailing: Icon(ctrl.locale.languageCode == e.key ? Icons.radio_button_checked : Icons.radio_button_off,
                color: ctrl.locale.languageCode == e.key ? AppColors.primary : AppColors.muted),
            onTap: () {
              ctrl.setLanguage(e.key);
              Navigator.of(ctx).pop();
            },
          ),
        ),
    ]);
  }

  Future<void> _delete(BuildContext context) async {
    final t = context.l10n;
    final ok = await confirm(context, title: t.requestDataDeletion, message: t.stDeleteText, okLabel: t.stSendRequest, danger: true);
    if (!ok) return;
    await launchUrl(Uri.parse(
        'mailto:$supportEmail?subject=${Uri.encodeComponent(t.dataDeletionSubject)}&body=${Uri.encodeComponent('${s.hostel['name']} · ${s.tenant['phone']}')}'));
  }

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    final tn = s.tenant;
    Widget row(IconData icon, Color color, String title, String sub, VoidCallback onTap, {bool last = false}) => InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(border: last ? null : const Border(bottom: BorderSide(color: AppColors.line))),
            child: Row(children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, size: 21, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: color == AppColors.danger ? AppColors.danger : AppColors.ink)),
                  Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                ]),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.primary),
            ]),
          ),
        );
    Widget group(String title) => Padding(
          padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
          child: Text(title, style: const TextStyle(color: AppColors.muted, fontSize: 12.5, fontWeight: FontWeight.w600)),
        );
    final roomLine = [
      if (tn['room_no'] != null) '${t.room} ${tn['room_no']}',
      if (tn['bed_label'] != null) '${t.bed} ${tn['bed_label']}',
      if (tn['sharing'] != null) t.sharingN('${tn['sharing']}'),
    ].join(' · ');
    return Scaffold(
      appBar: AppBar(title: Text(t.settings), automaticallyImplyLeading: false),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 110), children: [
        _card(
          child: Row(children: [
            _avatar(s, 56, ring: AppColors.primarySoft),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tn['full_name'] as String? ?? '', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                if (roomLine.isNotEmpty) Text(roomLine, style: const TextStyle(color: AppColors.muted)),
              ]),
            ),
          ]),
        ),
        group(t.stMyStay),
        Container(
          decoration: _box(),
          clipBehavior: Clip.antiAlias,
          child: Material(
            color: Colors.white,
            child: Column(children: [
              row(Icons.bed_outlined, AppColors.primary, t.tabMyRoom, t.stMyRoomSub, () => _room(context)),
              row(Icons.description_outlined, AppColors.primary, t.houseRules, t.stRulesCount('${_rules.length}'), () => _rulesSheet(context)),
              row(Icons.person_outline_rounded, AppColors.primary, t.myDetailsTitle, t.stMyDetailsSub, () => _details(context), last: true),
            ]),
          ),
        ),
        group(t.stAppGroup),
        Container(
          decoration: _box(),
          clipBehavior: Clip.antiAlias,
          child: Material(
            color: Colors.white,
            child: Column(children: [
              row(Icons.translate_rounded, AppColors.primary, t.language, appLanguages[LocaleScope.of(context).locale.languageCode] ?? 'English', () => _language(context)),
              row(Icons.verified_user_outlined, AppColors.success, t.stPrivacyTerms, t.stPrivacySub, () => context.push('/privacy')),
              row(Icons.delete_outline_rounded, AppColors.danger, t.stDeleteMyData, t.stDeleteSub, () => _delete(context), last: true),
            ]),
          ),
        ),
      ]),
    );
  }
}
