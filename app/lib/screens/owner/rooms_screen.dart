import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:url_launcher/url_launcher.dart';

import '../../config.dart';
import '../../core/back_nav.dart';
import '../../core/format.dart';
import '../../data/owner_repo.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import 'home_screen.dart' show hostelAreaLine;
import 'hostel_scope.dart';

/// Blue header colours (same as Home).
class _Or {
  static const bg = Color(0xFF1560BD);
  static const dark = Color(0xFFFFFFFF);
  static const mid = Color(0xFFD3E2F7);
  static const chip = Color(0x29FFFFFF);
  static const chipLine = Color(0x66FFFFFF);
}

const _green = Color(0xFF15803D);
const _greenSoft = Color(0xFFDDF3E8);
const _greenLine = Color(0xFFCDEEDC);
const _blue = Color(0xFF1560BD);
const _sheet = Color(0xFFF2F5F9);

/// Rooms tab: only the FREE beds, one card per bed ("201 A", "201 B"), grouped by floor
/// and filtered by sharing. Full rooms and beds on hold are not shown.
/// Book on a bed opens the QR screen to show the student. Rooms are added / edited in Hostel settings.
class RoomsScreen extends StatefulWidget {
  const RoomsScreen({super.key, required this.hostelId});
  final String hostelId;

  @override
  State<RoomsScreen> createState() => _RoomsScreenState();
}

class _RoomsScreenState extends State<RoomsScreen> {
  final _loader = GlobalKey<LoaderState<List<Json>>>();
  int? _sharing; // null = all

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    final scope = HostelScope.of(context);
    final h = scope.hostel;
    return Scaffold(
      backgroundColor: _sheet,
      body: Loader<List<Json>>(
        key: _loader,
        load: () => OwnerRepo.instance.roomsWithBeds(widget.hostelId),
        builder: (context, rooms, reload) {
          // every bed, as (room, bed)
          final free = <(Json, Json)>[];
          var total = 0, taken = 0;
          for (final r in rooms) {
            final beds = (r['beds'] as List).cast<Json>()..sort((a, b) => '${a['label']}'.compareTo('${b['label']}'));
            for (final b in beds) {
              total++;
              final v = bedView(b);
              if (v == BedView.free) free.add((r, b));
              if (v == BedView.living || v == BedView.offline) taken++;
            }
          }
          final sharings = {for (final r in rooms) asInt(r['sharing'])}.toList()..sort();
          int freeIn(int n) => free.where((e) => asInt(e.$1['sharing']) == n).length;
          if (_sharing != null && !sharings.contains(_sharing)) _sharing = null;
          final shown = free.where((e) => _sharing == null || asInt(e.$1['sharing']) == _sharing).toList();
          final roomsShown = {for (final e in shown) e.$1['id']}.length;
          final floors = {for (final e in shown) asInt(e.$1['floor'])}.toList()..sort();
          final pct = total == 0 ? 0 : (taken * 100 / total).round();
          String floorName(int f) => f == 0 ? t.groundFloor : t.floorN('$f');
          final line = t.freeBedsInRooms('${shown.length}', '$roomsShown') +
              (_sharing == null ? '' : ' · ${t.sharingN('$_sharing')}');

          return RefreshIndicator(
            onRefresh: () async {
              await reload();
              await scope.refresh();
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              children: [
                // whole-hostel numbers: they don't change with the sharing filter
                _RoomsHeader(
                  hostel: h,
                  occupied: taken,
                  available: free.length,
                  pct: pct,
                ),
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Sharing filter: All, 1, 2, 3 … with the free-bed count on each chip
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(children: [
                              Text(t.sharingLabel,
                                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w400, color: AppColors.muted)),
                              const SizedBox(width: 8),
                              _CountChip(
                                label: t.all,
                                count: free.length,
                                selected: _sharing == null,
                                onTap: () => setState(() => _sharing = null),
                              ),
                              for (final n in sharings) ...[
                                const SizedBox(width: 6),
                                _CountChip(
                                  label: '$n',
                                  semantics: t.sharingN('$n'),
                                  count: freeIn(n),
                                  selected: _sharing == n,
                                  onTap: () => setState(() => _sharing = n),
                                ),
                              ],
                            ]),
                          ),
                          const SizedBox(height: 14),
                          Row(children: [
                            Expanded(
                              child: Text(line, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.ink)),
                            ),
                            if (shown.isNotEmpty)
                              Text(t.tapBookToShareQr,
                                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w400, color: AppColors.muted)),
                          ]),
                          if (rooms.isEmpty)
                            EmptyView(icon: Icons.bed_rounded, title: t.noRoomsTitle, message: t.noRoomsMessage)
                          else if (shown.isEmpty)
                            EmptyView(icon: Icons.bed_rounded, title: t.noFreeBedsTitle, message: t.noFreeBedsMessage),
                          for (final f in floors) ...[
                            Padding(
                              padding: const EdgeInsets.fromLTRB(2, 14, 2, 8),
                              child: Row(children: [
                                Expanded(
                                  child: Text(floorName(f).toUpperCase(),
                                      style: const TextStyle(
                                          fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.muted, letterSpacing: 0.3)),
                                ),
                                Text(t.bedsFreeN('${shown.where((e) => asInt(e.$1['floor']) == f).length}'),
                                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: _green)),
                              ]),
                            ),
                            LayoutBuilder(builder: (context, c) {
                              const gap = 6.0;
                              final cols = c.maxWidth >= 520 ? 6 : 4;
                              final w = (c.maxWidth - gap * (cols - 1)) / cols;
                              return Wrap(
                                spacing: gap,
                                runSpacing: gap,
                                children: [
                                  for (final e in shown.where((e) => asInt(e.$1['floor']) == f))
                                    SizedBox(
                                      width: w,
                                      child: _FreeBedCard(
                                        room: e.$1,
                                        bed: e.$2,
                                        onBook: () async {
                                          await context.push('/h/${widget.hostelId}/share-bed/${e.$2['id']}');
                                          _loader.currentState?.reload();
                                        },
                                      ),
                                    ),
                                ],
                              );
                            }),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Peach header: back, hostel type, Switch; hostel name and area; occupied / available / occupied %
/// for the whole hostel (not affected by the sharing filter).
class _RoomsHeader extends StatelessWidget {
  const _RoomsHeader({required this.hostel, required this.occupied, required this.available, required this.pct});
  final Json? hostel;
  final int occupied, available, pct;

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    final h = hostel;
    final area = h == null ? '' : hostelAreaLine(h);
    Widget stat(String value, String label, Color color) => Expanded(
          child: Column(children: [
            Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: color)),
            Text(label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w400, color: AppColors.muted)),
          ]),
        );
    Widget divider() => Container(width: 1, height: 28, color: AppColors.line);
    return Container(
      decoration: const BoxDecoration(
        color: _Or.bg,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(26)),
      ),
      padding: const EdgeInsets.only(bottom: 16),
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
                  Row(children: [
                    Tooltip(
                      message: t.back,
                      child: Material(
                        color: _Or.chip,
                        shape: const CircleBorder(side: BorderSide(color: _Or.chipLine)),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: () => goBack(context),
                          child: const SizedBox(width: 38, height: 38, child: Icon(Icons.chevron_left_rounded, color: _Or.dark)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: _Or.chip,
                        border: Border.all(color: _Or.chipLine),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(t.tabRooms,
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _Or.dark)),
                    ),
                    const Spacer(),
                    Material(
                      color: _Or.chip,
                      shape: const StadiumBorder(side: BorderSide(color: _Or.chipLine)),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => context.go('/hostels'),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(Icons.swap_horiz_rounded, size: 16, color: _Or.dark),
                            const SizedBox(width: 6),
                            Text(t.switchShort, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: _Or.dark)),
                          ]),
                        ),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 10),
                  Text(hostelTitle(context, h),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: _Or.dark, height: 1.25)),
                  if (area.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Row(children: [
                      const Icon(Icons.location_on_outlined, size: 15, color: _Or.mid),
                      const SizedBox(width: 3),
                      Flexible(
                        child: Text(area,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w400, color: _Or.mid)),
                      ),
                    ]),
                  ],
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                    child: Row(children: [
                      stat('$occupied', t.occupiedBeds, _blue),
                      divider(),
                      stat('$available', t.availableBeds, _green),
                      divider(),
                      stat('$pct%', t.occupiedPctLabel, _blue),
                    ]),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Sharing filter chip with the number of free beds.
class _CountChip extends StatelessWidget {
  const _CountChip({required this.label, required this.count, required this.selected, required this.onTap, this.semantics});
  final String label;
  final String? semantics;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: '${semantics ?? label}: $count',
      excludeSemantics: true,
      child: Material(
        color: selected ? _green : Colors.white,
        shape: StadiumBorder(side: BorderSide(color: selected ? _green : AppColors.line)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 7, 7, 7),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(label,
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: selected ? Colors.white : AppColors.ink)),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                decoration: BoxDecoration(color: selected ? Colors.white : _greenSoft, borderRadius: BorderRadius.circular(8)),
                child: Text('$count', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _green)),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// One free bed, as small as possible: "201 A", sharing · rent, and a Book button inside the card.
/// Book opens the "Share with student" QR screen for this bed.
class _FreeBedCard extends StatelessWidget {
  const _FreeBedCard({required this.room, required this.bed, required this.onBook});
  final Json room, bed;
  final VoidCallback onBook;

  /// ₹6,500 → ₹6.5k (keeps the small card on one line)
  static String _short(int v) {
    if (v < 1000) return money(v);
    final k = v / 1000;
    final txt = k == k.roundToDouble() ? k.toStringAsFixed(0) : k.toStringAsFixed(1);
    return '₹${txt}k';
  }

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    final ac = (room['features'] as List? ?? const []).contains('ac');
    return Container(
      padding: const EdgeInsets.fromLTRB(7, 6, 7, 7),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _greenLine, width: 1.2),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Flexible(
            child: Text('${room['room_no']}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.ink)),
          ),
          const SizedBox(width: 3),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(color: _greenSoft, borderRadius: BorderRadius.circular(8)),
            child: Text('${bed['label']}', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: _green)),
          ),
          const Spacer(),
          if (ac)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
              decoration: BoxDecoration(color: AppColors.primaryTint, borderRadius: BorderRadius.circular(4)),
              child: Text(t.featAc, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _blue)),
            ),
        ]),
        const SizedBox(height: 1),
        Text('${t.sharingShortN('${room['sharing']}')} · ${_short(asInt(room['rent_month']))}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, color: AppColors.muted)),
        const SizedBox(height: 5),
        Semantics(
          button: true,
          label: '${t.bookShort} ${t.bookBedTitle('${room['room_no']}', '${bed['label']}')}',
          excludeSemantics: true,
          child: Material(
            color: _green,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: onBook,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Text(t.bookShort,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600)),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

/// Opens the "Book bed" sheet for a free bed (used by Rooms and Rooms & beds).
Future<void> showBookBedSheet(BuildContext context, String hostelId, Json room, Json bed) async {
  final hostel = HostelScope.read(context).hostel ?? await OwnerRepo.instance.hostel(hostelId);
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Colors.white,
    builder: (_) => _BookBedSheet(hostel: hostel, room: room, bed: bed),
  );
}

enum BedView { free, held, living, offline }

BedView bedView(Json b) {
  final status = b['status'];
  final heldUntil = asDate(b['held_until']);
  final heldNow = heldUntil != null && heldUntil.isAfter(DateTime.now());
  if (status == 'occupied') return BedView.living;
  if (status == 'offline_occupied') return heldNow ? BedView.held : BedView.offline;
  if (status == 'held' && heldNow) return BedView.held;
  return BedView.free;
}

(Color, Color) bedColors(BedView v) => switch (v) {
      BedView.free => (AppColors.successSoft, AppColors.success),
      BedView.held => (AppColors.warningSoft, AppColors.warning),
      BedView.living => (AppColors.primarySoft, AppColors.primary),
      BedView.offline => (const Color(0xFFECEFF3), AppColors.muted),
    };

class _BedBadge extends StatelessWidget {
  const _BedBadge({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(color: AppColors.successSoft, borderRadius: BorderRadius.circular(12)),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text(t.bed.toUpperCase(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.success)),
        Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.success, height: 1)),
      ]),
    );
  }
}

/// Book a free bed: student name + mobile, first month's rent, deposit, total, how they'll pay.
/// "Proceed to payment" sends the student a WhatsApp message with the join link and amount;
/// they finish joining (ID, consent) and pay in the normal student flow.
class _BookBedSheet extends StatefulWidget {
  const _BookBedSheet({required this.hostel, required this.room, required this.bed});
  final Json hostel, room, bed;

  @override
  State<_BookBedSheet> createState() => _BookBedSheetState();
}

class _BookBedSheetState extends State<_BookBedSheet> {
  final _name = TextEditingController();
  final _mobile = TextEditingController();
  String _method = 'upi';
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _mobile.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    final h = widget.hostel;
    final methods = <(String, String)>[
      if (h['accept_upi'] == true) ('upi', t.methodUpi),
      if (h['accept_cash'] == true) ('cash', t.methodCash),
      if (h['accept_bank'] == true) ('bank', t.methodBank),
    ];
    if (methods.isNotEmpty && !methods.any((m) => m.$1 == _method)) _method = methods.first.$1;
    final rent = asInt(widget.room['rent_month']);
    final deposit = asInt(widget.room['deposit_month']);
    final total = rent + deposit;
    Widget row(String l, String v, {bool strong = false}) => Container(
          padding: EdgeInsets.only(top: strong ? 10 : 6, bottom: 6),
          margin: EdgeInsets.only(top: strong ? 4 : 0),
          decoration: strong ? const BoxDecoration(border: Border(top: BorderSide(color: AppColors.line, width: 1.5))) : null,
          child: Row(children: [
            Expanded(
              child: Text(l, style: TextStyle(fontSize: strong ? 15 : 14, fontWeight: strong ? FontWeight.w600 : FontWeight.w600,
                  color: strong ? AppColors.ink : AppColors.muted)),
            ),
            Text(v, style: TextStyle(fontSize: strong ? 18 : 14, fontWeight: FontWeight.w600, color: strong ? AppColors.success : AppColors.ink)),
          ]),
        );
    return Padding(
      padding: EdgeInsets.fromLTRB(18, 0, 18, 18 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            _BedBadge(label: '${widget.bed['label']}'),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t.bookBedTitle('${widget.room['room_no']}', '${widget.bed['label']}'),
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                Text(t.sharingN('${widget.room['sharing']}'), style: const TextStyle(color: AppColors.muted)),
              ]),
            ),
          ]),
          const SizedBox(height: 14),
          TextField(controller: _name, textCapitalization: TextCapitalization.words, decoration: InputDecoration(labelText: t.fullName)),
          const SizedBox(height: 10),
          TextField(
            controller: _mobile,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(labelText: t.mobileNumber, prefixText: '+91 '),
          ),
          const SizedBox(height: 8),
          row(t.firstMonthRent, money(rent)),
          row(t.securityDeposit, money(deposit)),
          row(t.totalToPay, money(total), strong: true),
          if (methods.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(t.paymentMethod, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.muted)),
            const SizedBox(height: 6),
            SegmentedButton<String>(
              showSelectedIcon: false,
              segments: [for (final m in methods) ButtonSegment(value: m.$1, label: Text(m.$2))],
              selected: {_method},
              onSelectionChanged: (v) => setState(() => _method = v.first),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600)),
          ],
          const SizedBox(height: 14),
          SizedBox(
            height: 52,
            child: FilledButton(onPressed: () => _proceed(total, methods), child: Text(t.proceedToPayment(money(total)))),
          ),
          const SizedBox(height: 8),
          Text(t.bookingNote, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12.5, color: AppColors.muted)),
        ]),
      ),
    );
  }

  Future<void> _proceed(int total, List<(String, String)> methods) async {
    final t = context.l10n;
    final name = _name.text.trim();
    final phone = normalizePhone(_mobile.text);
    if (name.length < 2) return setState(() => _error = t.errStudentName);
    if (phone == null) return setState(() => _error = t.errBadPhone);
    final h = widget.hostel;
    final link = AppConfig.joinLink(h['join_code'] as String);
    final method = methods.firstWhere((m) => m.$1 == _method, orElse: () => ('', '')).$2;
    final text = t.bookMessage(name, hostelTitle(context, h), '${widget.room['room_no']}', '${widget.bed['label']}', money(total), method, link);
    final ok = await launchUrl(
      Uri.parse('https://wa.me/${phone.substring(1)}?text=${Uri.encodeComponent(text)}'),
      mode: LaunchMode.externalApplication,
    );
    if (!mounted) return;
    if (!ok) {
      await copyText(context, text);
    }
    if (mounted) Navigator.pop(context);
  }
}

/// Room features and hostel amenities (stored as codes, shown in the user's language).
const roomFeatureCodes = ['ac', 'geyser', 'attached_bath', 'balcony', 'cupboard', 'study_table', 'tv', 'wifi'];
const amenityCodes = ['wifi', 'food', 'laundry', 'housekeeping', 'power_backup', 'cctv', 'parking', 'ro_water', 'gym', 'tv'];

String featureLabel(BuildContext context, String code) {
  final t = context.l10n;
  return switch (code) {
    'ac' => t.featAc,
    'attached_bath' => t.featAttachedBath,
    'balcony' => t.featBalcony,
    'geyser' => t.featGeyser,
    'cupboard' => t.featCupboard,
    'study_table' => t.featStudyTable,
    'wifi' => t.amenWifi,
    'food' => t.amenFood,
    'laundry' => t.amenLaundry,
    'housekeeping' => t.amenHousekeeping,
    'power_backup' => t.amenPowerBackup,
    'cctv' => t.amenCctv,
    'parking' => t.amenParking,
    'ro_water' => t.amenRoWater,
    'gym' => t.amenGym,
    'tv' => t.amenTv,
    _ => code,
  };
}
