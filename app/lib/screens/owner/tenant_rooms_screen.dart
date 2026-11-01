import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/back_nav.dart';
import '../../core/format.dart';
import '../../data/owner_repo.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/room_pickers.dart';
import 'hostel_scope.dart';

// Phase 1 only: rooms entered by tenants.
// Students type floor, room number, sharing, price and deposit in "Your details". The owner checks the
// table here, corrects wrong rooms himself (students are not told) and confirms them. Confirmed rooms
// become normal rooms in Rooms & beds. Remove (or switch off in Hostel settings) in Phase 2/3.

String floorShortText(BuildContext context, int floor) => floor == 0 ? context.l10n.groundFloor : context.l10n.floorN('$floor');

Widget _statusChip(BuildContext context, String status) {
  final t = context.l10n;
  return switch (status) {
    'confirmed' => Chip2(t.statusConfirmed, tone: Tone.success),
    'fix' => Chip2(t.statusFix, tone: Tone.warning),
    _ => Chip2(t.statusOk, tone: Tone.info),
  };
}

List<int> _distinct(List entries, String key) =>
    {for (final e in entries) asInt((e as Map)[key])}.toList()..sort();

/// More → Rooms from tenants: a table grouped by floor. Tap a room to correct and confirm it.
class TenantRoomsScreen extends StatefulWidget {
  const TenantRoomsScreen({super.key, required this.hostelId});
  final String hostelId;

  @override
  State<TenantRoomsScreen> createState() => _TenantRoomsScreenState();
}

class _TenantRoomsScreenState extends State<TenantRoomsScreen> {
  final _loader = GlobalKey<LoaderState<List<Json>>>();
  String? _open; // room id being corrected

  Future<void> _reload() async {
    await _loader.currentState?.reload();
    if (mounted) HostelScope.read(context).refresh();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(t.tenantRoomsTitle), leading: const AppBackButton()),
      body: Loader<List<Json>>(
        key: _loader,
        load: () => OwnerRepo.instance.tenantRooms(widget.hostelId),
        builder: (context, rows, reload) {
          if (rows.isEmpty) {
            return PageList(children: [
              EmptyView(
                icon: Icons.bed_outlined,
                title: t.tenantRoomsEmptyTitle,
                message: t.tenantRoomsEmptyMessage,
                action: FilledButton.icon(
                  icon: const Icon(Icons.qr_code_2_rounded),
                  label: Text(t.joinQrTitle),
                  onPressed: () => context.go('/h/${widget.hostelId}/invite'),
                ),
              ),
            ]);
          }
          final floors = {for (final r in rows) asInt(r['floor'])}.toList()..sort();
          final confirmed = rows.where((r) => r['status'] == 'confirmed').length;
          final ok = rows.where((r) => r['status'] == 'ok').length;
          final fix = rows.where((r) => r['status'] == 'fix').length;
          final tenants = rows.fold<int>(0, (n, r) => n + ((r['entries'] as List?)?.length ?? 0));
          return Column(children: [
            Expanded(
              child: PageList(onRefresh: reload, children: [
                Text(t.tenantRoomsSummary('${floors.length}', '${rows.length}', '$tenants'),
                    style: const TextStyle(color: AppColors.muted)),
                const SizedBox(height: 8),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  Chip2(t.countConfirmed('$confirmed'), tone: Tone.success),
                  if (ok > 0) Chip2(t.countToConfirm('$ok'), tone: Tone.info),
                  if (fix > 0) Chip2(t.countToFix('$fix'), tone: Tone.warning),
                ]),
                const SizedBox(height: 12),
                Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.line),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    _TableRow(
                      header: true,
                      cells: [t.room, t.sharing, t.colPrice, t.colFilled],
                      trailing: const SizedBox.shrink(),
                    ),
                    for (final f in floors) ...[
                      Container(
                        color: const Color(0xFFFAFBFD),
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
                        child: Text(floorShortText(context, f).toUpperCase(),
                            style: const TextStyle(color: AppColors.muted, fontWeight: FontWeight.w600, fontSize: 11, letterSpacing: 0.5)),
                      ),
                      for (final r in rows.where((r) => asInt(r['floor']) == f)) ...[
                        _roomRow(context, r),
                        if (_open == r['room_id'])
                          _FixPanel(
                            row: r,
                            onCancel: () => setState(() => _open = null),
                            onSaved: () async {
                              setState(() => _open = null);
                              showSnack(context, t.roomConfirmedN('${r['room_no']}'));
                              await _reload();
                            },
                          ),
                      ],
                    ],
                  ]),
                ),
                const SizedBox(height: 8),
                Text(t.tenantRoomsHelp, style: const TextStyle(color: AppColors.muted, fontSize: 12.5, height: 1.4)),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  icon: const Icon(Icons.sell_outlined),
                  label: Text(t.priceBySharing),
                  onPressed: () => context.push('/h/${widget.hostelId}/sharing-prices'),
                ),
              ]),
            ),
            if (ok > 0)
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Narrow(
                    maxWidth: 640,
                    child: SizedBox(
                      height: 52,
                      width: double.infinity,
                      child: BusyButton(
                        icon: Icons.done_all_rounded,
                        label: t.confirmCorrectRooms('$ok'),
                        onPressed: () async {
                          final n = await OwnerRepo.instance.confirmCorrectTenantRooms(widget.hostelId);
                          if (!context.mounted) return;
                          showSnack(context, t.roomsConfirmedN('$n'));
                          await _reload();
                        },
                      ),
                    ),
                  ),
                ),
              ),
          ]);
        },
      ),
    );
  }

  Widget _roomRow(BuildContext context, Json r) {
    final entries = (r['entries'] as List?) ?? const [];
    final fix = r['status'] == 'fix';
    final sharings = _distinct(entries, 'sharing');
    final prices = _distinct(entries, 'rent_month');
    final clashS = fix && sharings.length > 1;
    final clashP = fix && prices.length > 1;
    final sharing = asInt(r['sharing']);
    return InkWell(
      onTap: () => setState(() => _open = _open == r['room_id'] ? null : r['room_id'] as String),
      child: _TableRow(
        cells: [
          '${r['room_no']}',
          clashS ? '${sharings.join(' / ')}?' : '$sharing',
          clashP ? '${prices.map(money).join(' / ')}?' : money(asInt(r['rent_month'])),
          '${asInt(r['filled'])}/${asInt(r['beds'])}',
        ],
        bold: const [true, false, false, false],
        warn: [false, clashS, clashP, false],
        trailing: _statusChip(context, r['status'] as String? ?? 'ok'),
      ),
    );
  }
}

/// One table line: Room · Sharing · Price · Filled · status.
class _TableRow extends StatelessWidget {
  const _TableRow({required this.cells, required this.trailing, this.header = false, this.bold, this.warn});
  final List<String> cells;
  final Widget trailing;
  final bool header;
  final List<bool>? bold;
  final List<bool>? warn;

  static const _flex = [2, 3, 4, 2];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: header ? AppColors.line : const Color(0xFFEEF1F5))),
      ),
      child: Row(children: [
        for (var i = 0; i < cells.length; i++)
          Expanded(
            flex: _flex[i],
            child: Text(
              cells[i],
              maxLines: 2,
              style: TextStyle(
                fontSize: header ? 11.5 : 13,
                fontWeight: header ? FontWeight.w600 : ((bold?[i] ?? false) ? FontWeight.w800 : FontWeight.w600),
                color: header ? AppColors.muted : ((warn?[i] ?? false) ? AppColors.warning : AppColors.ink),
              ),
            ),
          ),
        SizedBox(width: 92, child: Align(alignment: Alignment.centerRight, child: trailing)),
      ]),
    );
  }
}

/// Inline editor under a room: what each tenant entered, then the correct floor / sharing / price / deposit.
class _FixPanel extends StatefulWidget {
  const _FixPanel({required this.row, required this.onCancel, required this.onSaved});
  final Json row;
  final VoidCallback onCancel;
  final Future<void> Function() onSaved;

  @override
  State<_FixPanel> createState() => _FixPanelState();
}

class _FixPanelState extends State<_FixPanel> {
  late int _floor = asInt(widget.row['floor']);
  late int _sharing = asInt(widget.row['sharing']).clamp(1, maxSharing);
  late final _price = TextEditingController(text: '${asInt(widget.row['rent_month'])}');
  late final _deposit = TextEditingController(text: asInt(widget.row['deposit']) > 0 ? '${asInt(widget.row['deposit'])}' : '');

  @override
  void dispose() {
    _price.dispose();
    _deposit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    final entries = (widget.row['entries'] as List?) ?? const [];
    final digits = [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)];
    return Container(
      color: AppColors.warningSoft,
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(t.whatTenantsEntered, style: const TextStyle(color: AppColors.warning, fontWeight: FontWeight.w600, fontSize: 12.5)),
        const SizedBox(height: 4),
        for (final e in entries.cast<Map>())
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              '${(e['name'] as String?)?.isNotEmpty == true ? e['name'] : '—'}: '
              '${t.sharingN('${e['sharing']}')} · ${money(asInt(e['rent_month']))} · '
              '${asInt(e['deposit']) > 0 ? money(asInt(e['deposit'])) : t.noneText}',
              style: const TextStyle(fontSize: 12.5),
            ),
          ),
        const SizedBox(height: 10),
        Text(t.correctDetails, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5)),
        const SizedBox(height: 6),
        Text(t.floor, style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
        const SizedBox(height: 4),
        FloorPicker(
          value: _floor,
          // G rooms stay on the ground floor; other rooms can't be moved to it
          allowGround: isGroundRoom('${widget.row['room_no']}'),
          onlyGround: isGroundRoom('${widget.row['room_no']}'),
          onChanged: (f) => setState(() => _floor = f),
        ),
        const SizedBox(height: 8),
        Text(t.sharing, style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
        const SizedBox(height: 4),
        SharingPicker(value: _sharing, onChanged: (n) => setState(() => _sharing = n)),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _price,
              keyboardType: TextInputType.number,
              inputFormatters: digits,
              decoration: InputDecoration(labelText: t.monthlyPrice, prefixText: '₹ '),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _deposit,
              keyboardType: TextInputType.number,
              inputFormatters: digits,
              decoration: InputDecoration(labelText: t.deposit, prefixText: '₹ ', hintText: t.noneText),
            ),
          ),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: OutlinedButton(onPressed: widget.onCancel, child: Text(t.cancel))),
          const SizedBox(width: 8),
          Expanded(
            child: BusyButton(
              label: t.saveRoomN('${widget.row['room_no']}'),
              onPressed: () async {
                final price = int.tryParse(_price.text) ?? 0;
                if (price <= 0) {
                  showSnack(context, t.errAmount, error: true);
                  return;
                }
                await OwnerRepo.instance.confirmTenantRoom(
                  widget.row['room_id'] as String,
                  floor: _floor,
                  sharing: _sharing,
                  rent: price,
                  deposit: int.tryParse(_deposit.text) ?? 0,
                );
                await widget.onSaved();
              },
            ),
          ),
        ]),
      ]),
    );
  }
}

/// Hostel settings → Price by sharing: price and deposit per sharing, built from the tenants' rooms.
class SharingPricesScreen extends StatefulWidget {
  const SharingPricesScreen({super.key, required this.hostelId});
  final String hostelId;

  @override
  State<SharingPricesScreen> createState() => _SharingPricesScreenState();
}

class _SharingPricesScreenState extends State<SharingPricesScreen> {
  final _loader = GlobalKey<LoaderState<(List<Json>, Json)>>();

  /// Rows: sharing, rooms, prices[], deposits[] (rooms still to fix count every value their tenants typed).
  List<Json> _bySharing(List<Json> rooms) {
    final out = <int, Json>{};
    for (final r in rooms) {
      final s = asInt(r['sharing']);
      final row = out.putIfAbsent(s, () => {'sharing': s, 'rooms': 0, 'prices': <int>{}, 'deposits': <int>{}});
      row['rooms'] = asInt(row['rooms']) + 1;
      final entries = (r['entries'] as List?) ?? const [];
      if (r['status'] == 'fix' && entries.isNotEmpty) {
        (row['prices'] as Set<int>).addAll(_distinct(entries, 'rent_month'));
        (row['deposits'] as Set<int>).addAll(_distinct(entries, 'deposit'));
      } else {
        (row['prices'] as Set<int>).add(asInt(r['rent_month']));
        (row['deposits'] as Set<int>).add(asInt(r['deposit']));
      }
    }
    return (out.keys.toList()..sort()).map((k) => out[k]!).toList();
  }

  Future<void> _edit(Json row) async {
    final t = context.l10n;
    final prices = (row['prices'] as Set<int>).toList();
    final deposits = (row['deposits'] as Set<int>).toList();
    final price = TextEditingController(text: prices.isEmpty ? '' : '${prices.first}');
    final deposit = TextEditingController(text: deposits.isEmpty || deposits.first == 0 ? '' : '${deposits.first}');
    final digits = [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)];
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(t.sharingN('${row['sharing']}'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(t.setsPriceForSharing('${row['sharing']}'), style: const TextStyle(color: AppColors.muted)),
          const SizedBox(height: 14),
          TextField(
            controller: price,
            keyboardType: TextInputType.number,
            inputFormatters: digits,
            decoration: InputDecoration(labelText: t.rentPerBed, prefixText: '₹ '),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: deposit,
            keyboardType: TextInputType.number,
            inputFormatters: digits,
            decoration: InputDecoration(labelText: t.deposit, prefixText: '₹ ', hintText: t.noneText),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 50,
            child: BusyButton(
              label: t.save,
              onPressed: () async {
                final p = int.tryParse(price.text) ?? 0;
                if (p <= 0) {
                  showSnack(ctx, t.errAmount, error: true);
                  return;
                }
                await OwnerRepo.instance.setSharingPrice(widget.hostelId,
                    sharing: asInt(row['sharing']), rent: p, deposit: int.tryParse(deposit.text) ?? 0);
                if (ctx.mounted) Navigator.of(ctx).pop(true);
              },
            ),
          ),
        ]),
      ),
    );
    price.dispose();
    deposit.dispose();
    if (saved == true && mounted) {
      showSnack(context, t.priceSaved);
      await _loader.currentState?.reload();
    }
  }

  Future<void> _setFlag(String key, bool value) async {
    await OwnerRepo.instance.updateHostel(widget.hostelId, {key: value});
    if (!mounted) return;
    HostelScope.read(context).refresh();
    await _loader.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(t.priceBySharing), leading: const AppBackButton()),
      body: Loader<(List<Json>, Json)>(
        key: _loader,
        load: () async => (
          await OwnerRepo.instance.tenantRooms(widget.hostelId),
          await OwnerRepo.instance.hostel(widget.hostelId),
        ),
        builder: (context, data, reload) {
          final rows = _bySharing(data.$1);
          final h = data.$2;
          Widget cell(String s, int flex, {bool head = false, bool bold = false}) => Expanded(
                flex: flex,
                child: Text(s,
                    style: TextStyle(
                      fontSize: head ? 11.5 : 13,
                      color: head ? AppColors.muted : AppColors.ink,
                      fontWeight: bold ? FontWeight.w600 : FontWeight.w600,
                    )),
              );
          Widget many(Set<int> values, String Function(String) label) => values.length > 1
              ? Align(alignment: Alignment.centerLeft, child: Chip2(label('${values.length}'), tone: Tone.warning))
              : Text(values.isEmpty || values.first == 0 ? t.noneText : money(values.first),
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600));
          return PageList(onRefresh: reload, children: [
            Text(t.priceBySharingHelp, style: const TextStyle(color: AppColors.muted)),
            const SizedBox(height: 12),
            if (rows.isEmpty)
              EmptyView(icon: Icons.sell_outlined, title: t.tenantRoomsEmptyTitle, message: t.tenantRoomsEmptyMessage)
            else
              Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.line),
                ),
                child: Column(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.line))),
                    child: Row(children: [
                      cell(t.sharing, 3, head: true),
                      cell(t.colRooms, 2, head: true),
                      cell(t.colPricePerBed, 3, head: true),
                      cell(t.deposit, 3, head: true),
                    ]),
                  ),
                  for (final r in rows)
                    InkWell(
                      onTap: () => _edit(r),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFEEF1F5)))),
                        child: Row(children: [
                          cell(t.sharingN('${r['sharing']}'), 3, bold: true),
                          cell('${r['rooms']}', 2),
                          Expanded(flex: 3, child: many(r['prices'] as Set<int>, t.nPrices)),
                          Expanded(flex: 3, child: many(r['deposits'] as Set<int>, t.nDeposits)),
                        ]),
                      ),
                    ),
                ]),
              ),
            const SizedBox(height: 14),
            SectionCard(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Column(children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: h['use_tenant_prices'] != false,
                  onChanged: (v) => _setFlag('use_tenant_prices', v).catchError((Object e) {
                    if (context.mounted) showSnack(context, t.errGeneric, error: true);
                  }),
                  title: Text(t.useTenantPrices, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(t.useTenantPricesHelp),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: h['tenant_room_entry'] != false,
                  onChanged: (v) => _setFlag('tenant_room_entry', v).catchError((Object e) {
                    if (context.mounted) showSnack(context, t.errGeneric, error: true);
                  }),
                  title: Text(t.tenantRoomEntry, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(t.tenantRoomEntryHelp),
                ),
              ]),
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.people_outline_rounded),
              label: Text(t.tenantRoomsTitle),
              onPressed: () => context.go('/h/${widget.hostelId}/tenant-rooms'),
            ),
          ]);
        },
      ),
    );
  }
}
