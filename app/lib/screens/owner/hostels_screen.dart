import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors.dart';
import '../../core/format.dart';
import '../../data/owner_repo.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

class _Loaded {
  _Loaded(this.items, this.removed);
  final List<(Json, Json?, int)> items; // shown hostels: hostel, summary, colour slot
  final int removed; // how many hostels the owner removed (see Removed hostels)
}

/// "My hostels": every hostel of this owner with beds filled and alerts.
class HostelsScreen extends StatelessWidget {
  const HostelsScreen({super.key});

  /// Shown hostels with their summary and colour slot. The colour slot is the
  /// hostel's place among ALL the owner's hostels (removed ones included), so
  /// removing one hostel never changes the colour of the others.
  Future<_Loaded> _load() async {
    final all = await OwnerRepo.instance.hostels();
    final shown = [
      for (var i = 0; i < all.length; i++)
        if (all[i]['archived_at'] == null) (all[i], i),
    ];
    final removedCount = all.length - shown.length;
    final summaries = await Future.wait(shown.map((e) async {
      try {
        return await OwnerRepo.instance.summary(e.$1['id'] as String);
      } catch (_) {
        return null;
      }
    }));
    return _Loaded([for (var i = 0; i < shown.length; i++) (shown[i].$1, summaries[i], shown[i].$2)], removedCount);
  }

  /// Owner's first name from the sign-up details (no extra server call), or null.
  String? _ownerFirstName() {
    final meta = supa.auth.currentUser?.userMetadata;
    final full = (meta?['full_name'] ?? '').toString().trim();
    if (full.isEmpty) return null;
    return full.split(RegExp(r'\s+')).first;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    final firstName = _ownerFirstName();
    return Scaffold(
      backgroundColor: AppColors.ground,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ---------- header ----------
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (firstName != null)
                          Text(
                            t.greetingHi(firstName),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 14, color: AppColors.muted, fontWeight: FontWeight.w400),
                          ),
                        Text(
                          t.myHostels,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.ink, height: 1.2),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Tooltip(
                    message: t.logout,
                    child: SizedBox(
                      width: 44,
                      height: 44,
                      child: Material(
                        color: Colors.white,
                        shape: const CircleBorder(side: BorderSide(color: Color(0xFFDDE3EC))),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () => OwnerRepo.instance.logout(),
                          child: const Center(
                            child: Icon(Icons.logout_rounded, size: 20, color: AppColors.ink),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // ---------- hostel cards ----------
            Expanded(
              child: Loader<_Loaded>(
                load: _load,
                builder: (context, loaded, reload) {
                  final items = loaded.items;
                  if (items.isEmpty) {
                    // First-time owner: go straight to "Register hostel".
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (context.mounted) context.go('/hostels/new');
                    });
                    return const SizedBox.shrink();
                  }
                  return _HostelList(
                    onRefresh: reload,
                    removedCount: loaded.removed,
                    cards: [
                      for (var i = 0; i < items.length; i++)
                        _HostelCard(
                          hostel: items[i].$1,
                          summary: items[i].$2,
                          palette: _CardPalette.forIndex(items[i].$3),
                          onRemoved: reload,
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Hostel cards plus a way to add another hostel:
/// - 1-2 hostels: big "Run another hostel?" card under the list.
/// - 3+ hostels: small one-row "Another hostel?" card under the list, while it fits.
/// - Screen full: the card goes, an "Add another hostel" button stays fixed at
///   the bottom and the cards scroll above it.
class _HostelList extends StatefulWidget {
  const _HostelList({required this.cards, required this.onRefresh, this.removedCount = 0});
  final List<Widget> cards;
  final Future<void> Function() onRefresh;
  final int removedCount;

  @override
  State<_HostelList> createState() => _HostelListState();
}

class _HostelListState extends State<_HostelList> {
  static const _gap = 12.0, _pad = 16.0;
  final _cardsKey = GlobalKey();
  final _extraKey = GlobalKey();
  double _cardsH = 0;
  double _extraH = 0; // last measured height of the add card (kept while it is hidden)

  double? _heightOf(GlobalKey k) {
    final box = k.currentContext?.findRenderObject() as RenderBox?;
    return (box != null && box.hasSize) ? box.size.height : null;
  }

  void _measure() {
    if (!mounted) return;
    final c = _heightOf(_cardsKey) ?? _cardsH;
    final e = _heightOf(_extraKey) ?? _extraH;
    if ((c - _cardsH).abs() > 0.5 || (e - _extraH).abs() > 0.5) {
      setState(() {
        _cardsH = c;
        _extraH = e;
      });
    }
  }

  void _add(BuildContext context) => context.push('/hostels/new');

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    final few = widget.cards.length <= 2;
    return LayoutBuilder(builder: (context, c) {
      final areaH = c.maxHeight;
      final measured = _cardsH > 0;
      final cardH = _extraH > 0 ? _extraH : 76.0;
      final overflow = !few && measured && _pad + _cardsH + _gap + cardH + _pad > areaH;

      final list = RefreshIndicator(
        onRefresh: widget.onRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 4, 16, _pad),
          children: [
            Narrow(
              maxWidth: 640,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Column(
                    key: _cardsKey,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < widget.cards.length; i++) ...[
                        if (i > 0) const SizedBox(height: 10),
                        widget.cards[i],
                      ],
                    ],
                  ),
                  if (!overflow) ...[
                    const SizedBox(height: _gap),
                    Opacity(
                      // hidden for the first frame, until the layout is measured
                      opacity: measured ? 1 : 0,
                      child: KeyedSubtree(
                        key: _extraKey,
                        child: few
                            ? _AddHostelCardBig(onAdd: () => _add(context))
                            : _AddHostelCardSmall(onAdd: () => _add(context)),
                      ),
                    ),
                  ],
                  if (widget.removedCount > 0) ...[
                    const SizedBox(height: 8),
                    TextButton.icon(
                      icon: const Icon(Icons.inventory_2_outlined, size: 18),
                      label: Text(context.l10n.removedHostelsCount('${widget.removedCount}')),
                      onPressed: () => context.push('/hostels/removed'),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      );

      if (!overflow) return list;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: list),
          Container(
            decoration: const BoxDecoration(
              color: AppColors.ground,
              border: Border(top: BorderSide(color: Color(0xFFDDE3EC))),
            ),
            child: SafeArea(
              top: false,
              minimum: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: Center(
                heightFactor: 1,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.add_rounded),
                      label: Text(context.l10n.addAnotherHostel),
                      onPressed: () => _add(context),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    });
  }
}

const _dashColor = Color(0xFFB9D0EF);
const _dashFill = Color(0xFFFBFCFE);

/// Rounded box with a dashed border (used by both add-hostel cards).
class _DashedBox extends StatelessWidget {
  const _DashedBox({required this.child, required this.padding});
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      foregroundPainter: _DashedRRectPainter(color: _dashColor, radius: 18, stroke: 2),
      child: Container(
        decoration: BoxDecoration(color: _dashFill, borderRadius: BorderRadius.circular(16)),
        padding: padding,
        child: child,
      ),
    );
  }
}

class _DashedRRectPainter extends CustomPainter {
  const _DashedRRectPainter({required this.color, required this.radius, required this.stroke});
  final Color color;
  final double radius, stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    final r = RRect.fromRectAndRadius(
        (Offset.zero & size).deflate(stroke / 2), Radius.circular(radius));
    final path = Path()..addRRect(r);
    for (final m in path.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        canvas.drawPath(m.extractPath(d, math.min(d + 6, m.length)), paint);
        d += 10;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedRRectPainter old) => old.color != color;
}

/// Three small buildings with a blue "+" badge.
class _MiniTown extends StatelessWidget {
  const _MiniTown({this.scale = 1});
  final double scale;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 60 * scale,
      height: 40 * scale,
      child: CustomPaint(painter: _MiniTownPainter()),
    );
  }
}

class _MiniTownPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 60;
    final white = Paint()..color = Colors.white;
    void block(double x, double w, double h, Color c, int cols, int rows) {
      final top = 38 - h;
      canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(x * k, top * k, w * k, h * k), Radius.circular(1.5 * k)),
          Paint()..color = c);
      for (var r = 0; r < rows; r++) {
        for (var col = 0; col < cols; col++) {
          canvas.drawRect(Rect.fromLTWH((x + 3 + col * 6) * k, (top + 4 + r * 6) * k, 3 * k, 3 * k), white);
        }
      }
    }

    block(4, 17, 26, const Color(0xFFE4EDFA), 2, 3);
    block(24, 20, 33, const Color(0xFFFAE5EE), 3, 4);
    block(47, 11, 22, const Color(0xFFE1F3E9), 0, 0);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(0, 38 * k, 60 * k, 2 * k), Radius.circular(k)),
        Paint()..color = const Color(0xFFDDE3EC));
    final centre = Offset(53.5 * k, 6.5 * k);
    canvas.drawCircle(centre, 6.5 * k, Paint()..color = AppColors.primary);
    final plus = Paint()
      ..color = Colors.white
      ..strokeWidth = 1.6 * k
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(centre.translate(0, -3 * k), centre.translate(0, 3 * k), plus);
    canvas.drawLine(centre.translate(-3 * k, 0), centre.translate(3 * k, 0), plus);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 1-2 hostels: big card with drawing, short text and a full-width button.
class _AddHostelCardBig extends StatelessWidget {
  const _AddHostelCardBig({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    return _DashedBox(
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 20),
      child: Column(
        children: [
          const _MiniTown(scale: 2),
          const SizedBox(height: 10),
          Text(t.runAnotherHostelTitle,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.ink)),
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 280),
            child: Text(t.runAnotherHostelBody,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12.5, height: 1.45, color: AppColors.muted)),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
              icon: const Icon(Icons.add_rounded),
              label: Text(t.addAnotherHostel),
              onPressed: onAdd,
            ),
          ),
        ],
      ),
    );
  }
}

/// 3+ hostels: one row - drawing, short text, "Add hostel" button.
class _AddHostelCardSmall extends StatelessWidget {
  const _AddHostelCardSmall({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    return _DashedBox(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      child: Row(
        children: [
          const _MiniTown(),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(t.anotherHostelTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.ink)),
                Text(t.anotherHostelBody,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5, color: AppColors.muted)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 44,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 14),
              ),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: Text(t.addHostelShort),
              onPressed: onAdd,
            ),
          ),
        ],
      ),
    );
  }
}

/// Confirm sheet shown after tapping × on a hostel card. Pops true to remove.
class _RemoveHostelSheet extends StatelessWidget {
  const _RemoveHostelSheet({required this.name, this.tenants = 0});
  final String name;
  final int tenants;

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    Widget bullet(String text) => Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('•  ', style: TextStyle(color: AppColors.muted)),
            Expanded(child: Text(text, style: const TextStyle(fontSize: 14, height: 1.4, color: AppColors.muted))),
          ]),
        );
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(color: AppColors.dangerSoft, shape: BoxShape.circle),
                child: const Icon(Icons.close_rounded, color: AppColors.danger, size: 22),
              ),
            ),
            const SizedBox(height: 12),
            Text(t.removeHostelTitle(name),
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.ink)),
            const SizedBox(height: 8),
            bullet(t.removeB1),
            bullet(t.removeB2),
            bullet(t.removeB3),
            bullet(t.removeB4),
            if (tenants > 0) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: AppColors.warningSoft, borderRadius: BorderRadius.circular(10)),
                child: Text(t.removeTenantsWarn('$tenants'),
                    style: const TextStyle(fontSize: 12.5, height: 1.4, color: AppColors.warning)),
              ),
            ],
            const SizedBox(height: 18),
            SizedBox(
              height: 52,
              child: FilledButton(
                style: FilledButton.styleFrom(backgroundColor: AppColors.danger, foregroundColor: Colors.white),
                onPressed: () => Navigator.pop(context, true),
                child: Text(t.removeHostel),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 48,
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(t.keepIt),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String hostelTypeLabel(BuildContext context, String? type) {
  final t = context.l10n;
  return switch (type) {
    'mens' => t.typeMens,
    'womens' => t.typeWomens,
    _ => t.typeColiving,
  };
}

/// Light colour set for one card, picked by the card's position in the list.
class _CardPalette {
  const _CardPalette({
    required this.tint,
    required this.band,
    required this.border,
    required this.dark,
    required this.strong,
    required this.door,
  });

  final Color tint; // card background
  final Color band; // top strip
  final Color border; // card border and building
  final Color dark; // % text
  final Color strong; // % ring
  final Color door; // building door

  // Trust blue: every hostel card has the same solid blue strip.
  static const List<_CardPalette> all = [
    _CardPalette(
      tint: Color(0xFFFFFFFF),
      band: Color(0xFF1560BD),
      border: Color(0xFFB9D0EF),
      dark: Color(0xFF14213D),
      strong: Color(0xFF1560BD),
      door: Color(0xFF8DB0E0),
    ),
  ];

  static _CardPalette forIndex(int i) => all[i % all.length];
}

const _blue = Color(0xFF1560BD);
const _green = Color(0xFF15803D);
const _amber = Color(0xFFB45309);
const _red = Color(0xFFDC2626);
const _amberArc = Color(0xFFF2B35B);

/// First part of the locality from the address, e.g. "Plot 12, Road 5, Madhapur, Hyderabad 500081" -> "Madhapur".
/// Falls back to the city.
String _areaText(Json hostel) {
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
  if (parts.isNotEmpty) return parts.last;
  return city;
}

/// Same steps as the setup checklist on Owner home:
/// Hostel details ✓ → Add rooms → Payment options → Rent day & rules → Invite students.
double _setupProgress(Json hostel, Json summary) {
  final rooms = asInt(summary['rooms']) > 0;
  final payment = (hostel['accept_upi'] == true && hostel['upi_id'] != null) ||
      (hostel['accept_bank'] == true && (hostel['bank_details'] ?? '').toString().isNotEmpty) ||
      (hostel['accept_cash'] == true && hostel['accept_upi'] != true);
  final rules = (hostel['house_rules'] ?? '').toString().trim().isNotEmpty;
  final invited = asInt(summary['tenants']) > 0;
  final done = [true, rooms, payment, rules, invited].where((ok) => ok).length;
  return done / 5;
}

class _HostelCard extends StatelessWidget {
  const _HostelCard({required this.hostel, required this.summary, required this.palette, required this.onRemoved});
  final Json hostel;
  final Json? summary;
  final _CardPalette palette;
  final Future<void> Function() onRemoved;

  Future<void> _askRemove(BuildContext context) async {
    final name = hostelTitle(context, hostel);
    // How many tenants still live here (shown as a warning); 0 if it can't be read.
    final counts = await OwnerRepo.instance
        .tenantCounts([hostel['id'] as String]).catchError((_) => <String, int>{});
    if (!context.mounted) return;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      builder: (ctx) => _RemoveHostelSheet(name: name, tenants: counts[hostel['id']] ?? 0),
    );
    if (ok != true || !context.mounted) return;
    try {
      await OwnerRepo.instance.removeHostel(hostel['id'] as String);
      if (!context.mounted) return;
      showSnack(context, context.l10n.hostelRemoved(name));
      await onRemoved(); // reload; with no hostels left the screen opens "Register hostel"
    } catch (e) {
      if (context.mounted) showSnack(context, errorText(context, e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final s = summary ?? const <String, dynamic>{};
    final rooms = asInt(s['rooms']);
    final needsSetup = summary != null && rooms == 0;
    final area = _areaText(hostel);
    final radius = BorderRadius.circular(16);

    return Material(
      color: p.tint,
      shape: RoundedRectangleBorder(borderRadius: radius, side: const BorderSide(color: Color(0xFFE3EAF5))),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.go('/h/${hostel['id']}/home'),
        child: Padding(
          // keep content clear of the 1px border, which is painted on top
          padding: const EdgeInsets.all(1),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ---------- top band ----------
              Container(
                color: p.band,
                padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
                child: Row(
                  children: [
                    // "Name – Type" (up to 2 lines), area below
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(hostelTitle(context, hostel),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Colors.white)),
                        if (area.isNotEmpty)
                          Text(area,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w400, fontSize: 12.5, color: AppColors.onBlueMuted)),
                      ]),
                    ),
                    const SizedBox(width: 6),
                    // ---------- remove (×) ----------
                    Semantics(
                      button: true,
                      label: '${context.l10n.removeHostel}: ${hostelTitle(context, hostel)}',
                      excludeSemantics: true,
                      child: Tooltip(
                        message: context.l10n.removeHostel,
                        child: Material(
                          color: Colors.white,
                          shape: const CircleBorder(),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: () => _askRemove(context),
                            // 24px white circle
                            child: Padding(
                              padding: const EdgeInsets.all(5),
                              child: Icon(Icons.close_rounded, size: 14, color: p.strong),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // ---------- body ----------
              Padding(
                padding: const EdgeInsets.all(10),
                child: needsSetup ? _setupBody(context) : _statsBody(context, s),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statsBody(BuildContext context, Json s) {
    final t = context.l10n;
    final p = palette;
    final total = asInt(s['beds_total']);
    final filled = asInt(s['beds_filled']);
    final held = asInt(s['beds_held']);
    final free = math.max(0, total - filled - held);
    // Alerts = payments to confirm + existing-tenant join requests + tenants with rent pending.
    final alerts = asInt(s['payments_to_check']) + asInt(s['joins_to_approve']) + asInt(s['pending_tenants']) +
        asInt(s['open_complaints']);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // hostel photo, or the short name until one is added (📷 / ✏️ to change)
        HostelPhotoBox(hostel: hostel, height: 66, editable: true),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(children: [
                Expanded(child: _StatBox(value: filled, label: t.statFilled, color: AppColors.ink)),
                const SizedBox(width: 5),
                Expanded(child: _StatBox(value: free, label: t.bedFree, color: _green)),
              ]),
              const SizedBox(height: 5),
              Row(children: [
                Expanded(child: _StatBox(value: held, label: t.bedHeld, color: _amber)),
                const SizedBox(width: 5),
                Expanded(
                  child: _StatBox(value: alerts, label: t.statAlerts, color: alerts > 0 ? _red : _green),
                ),
              ]),
            ],
          ),
        ),
        const SizedBox(width: 10),
        _PercentRing(total: total, filled: filled, held: held, palette: p),
      ],
    );
  }

  Widget _setupBody(BuildContext context) {
    final t = context.l10n;
    final progress = _setupProgress(hostel, summary ?? const <String, dynamic>{});
    return Row(
      children: [
        HostelPhotoBox(hostel: hostel, height: 66, editable: true),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  height: 8,
                  color: Colors.white,
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: math.max(0.0, math.min(1.0, progress)),
                    heightFactor: 1,
                    child: const ColoredBox(color: _blue),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${t.finishSetup} →',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: _blue, fontWeight: FontWeight.w600, fontSize: 14),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatBox extends StatelessWidget {
  const _StatBox({required this.value, required this.label, required this.color});
  final int value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
      decoration: BoxDecoration(color: AppColors.ground, borderRadius: BorderRadius.circular(8)),
      child: Text.rich(
        TextSpan(children: [
          TextSpan(
            text: '$value',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5, color: color),
          ),
          TextSpan(
            text: ' $label',
            style: const TextStyle(fontWeight: FontWeight.w400, fontSize: 11, color: AppColors.muted),
          ),
        ]),
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

/// 60px ring: white track, filled beds in the card colour, beds on hold in amber after it.
class _PercentRing extends StatelessWidget {
  const _PercentRing({required this.total, required this.filled, required this.held, required this.palette});
  final int total;
  final int filled;
  final int held;
  final _CardPalette palette;

  @override
  Widget build(BuildContext context) {
    final double filledFrac = total <= 0 ? 0.0 : math.max(0.0, math.min(1.0, filled / total));
    final double heldFrac = total <= 0 ? 0.0 : math.max(0.0, math.min(1.0 - filledFrac, held / total));
    final pct = (filledFrac * 100).round();
    return SizedBox(
      width: 60,
      height: 60,
      child: CustomPaint(
        painter: _RingPainter(filled: filledFrac, held: heldFrac, color: palette.strong),
        child: Center(
          child: Text(
            '$pct%',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: palette.dark),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.filled, required this.held, required this.color});
  final double filled;
  final double held;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 6.0;
    final rect = Rect.fromLTWH(stroke / 2, stroke / 2, size.width - stroke, size.height - stroke);
    Paint arc(Color c) => Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    canvas.drawArc(rect, 0, 2 * math.pi, false, arc(const Color(0xFFE8F0FA)));
    const start = -math.pi / 2;
    if (filled > 0) canvas.drawArc(rect, start, 2 * math.pi * filled, false, arc(color));
    if (held > 0) canvas.drawArc(rect, start + 2 * math.pi * filled, 2 * math.pi * held, false, arc(_amberArc));
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.filled != filled || old.held != held || old.color != color;
}

/// Hostel photo (back in Phase 1, 20 Oct 2026): the photo, or the short name until one is added.
/// [editable]: small 📷 / ✏️ button that opens Take a photo / Choose from gallery / Remove photo.
/// Photos are compressed on the phone (~200 KB) and kept in private storage; the app gets 1-hour links.
class HostelPhotoBox extends StatefulWidget {
  const HostelPhotoBox({super.key, required this.hostel, this.width = 56, this.height = 56, this.editable = false});
  final Json hostel;
  final double width;
  final double height;
  final bool editable;

  @override
  State<HostelPhotoBox> createState() => _HostelPhotoBoxState();
}

class _HostelPhotoBoxState extends State<HostelPhotoBox> {
  static final Map<String, String> _cache = {}; // hostel id -> link shown this session
  String? _url;
  bool _hasPhoto = false;

  String get _id => widget.hostel['id'] as String;

  @override
  void initState() {
    super.initState();
    _hasPhoto = widget.hostel['photo_key'] != null;
    _url = _cache[_id];
    if (_hasPhoto && _url == null) {
      OwnerRepo.instance.hostelPhotoUrl(_id).then((u) {
        if (u != null) _cache[_id] = u;
        if (mounted) setState(() => _url = u);
      }).catchError((_) {});
    }
  }

  Future<void> _edit() async {
    final t = context.l10n;
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
            child: Text(_hasPhoto ? t.changeHostelPhoto : t.addHostelPhoto,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(t.hostelPhotoHelp, style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
          ),
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined, color: AppColors.primary),
            title: Text(t.takePhoto),
            onTap: () => Navigator.pop(ctx, 'camera'),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined, color: AppColors.primary),
            title: Text(t.chooseFromGallery),
            onTap: () => Navigator.pop(ctx, 'gallery'),
          ),
          if (_hasPhoto)
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded, color: AppColors.danger),
              title: Text(t.removePhoto, style: const TextStyle(color: AppColors.danger)),
              onTap: () => Navigator.pop(ctx, 'remove'),
            ),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (choice == null || !mounted) return;
    try {
      if (choice == 'remove') {
        await OwnerRepo.instance.removeHostelPhoto(_id);
        _cache.remove(_id);
        if (!mounted) return;
        setState(() {
          _hasPhoto = false;
          _url = null;
        });
        showSnack(context, t.photoRemovedMsg);
        return;
      }
      final file = await ImagePicker().pickImage(
        source: choice == 'camera' ? ImageSource.camera : ImageSource.gallery,
        maxWidth: 1080,
        maxHeight: 1080,
        imageQuality: 70, // ~200 KB
      );
      if (file == null) return;
      final url = await OwnerRepo.instance.setHostelPhoto(_id, await file.readAsBytes());
      if (url != null) _cache[_id] = url;
      if (!mounted) return;
      setState(() {
        _hasPhoto = true;
        _url = url;
      });
      showSnack(context, t.photoSavedMsg);
    } catch (e) {
      if (mounted) showSnack(context, errorText(context, e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final box = _url != null
        ? ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(_url!, width: widget.width, height: widget.height, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    HostelShortNameBox(name: '${widget.hostel['name']}', width: widget.width, height: widget.height)),
          )
        : HostelShortNameBox(name: '${widget.hostel['name']}', width: widget.width, height: widget.height);
    if (!widget.editable) return box;
    return SizedBox(
      width: widget.width + 6,
      height: widget.height + 6,
      child: Stack(children: [
        box,
        Positioned(
          right: 0,
          bottom: 0,
          child: Material(
            color: Colors.white,
            shape: const CircleBorder(side: BorderSide(color: AppColors.line)),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: _edit,
              child: Padding(
                padding: const EdgeInsets.all(5),
                child: Icon(_hasPhoto ? Icons.edit_rounded : Icons.photo_camera_outlined, size: 14, color: AppColors.primary),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}
