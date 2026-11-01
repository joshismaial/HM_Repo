import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/back_nav.dart';
import '../../core/errors.dart';
import '../../core/format.dart';
import '../../data/student_api.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/pay_widgets.dart';
import '../../widgets/room_pickers.dart';
import '../owner/hostels_screen.dart' show hostelTypeLabel;
import '../owner/rooms_screen.dart' show featureLabel;
import '../owner/tenant_details_screen.dart' show idTypeLabel;
import 'student_frame.dart';

StudentApi get _api => StudentApi.instance;

/// Makes sure we have this student's token (from memory or the phone); otherwise verify again.
Future<void> _ensureToken(String joinCode) async {
  if (_api.token != null) return;
  final t = await _api.savedToken(joinCode: joinCode);
  if (t == null) throw AppException('SESSION_INVALID');
}

/// Error states for the joining flow.
class _StudentError extends StatelessWidget {
  const _StudentError({required this.joinCode, required this.error, required this.onRetry});
  final String joinCode;
  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    final code = AppException.from(error).code;
    if (code == 'SESSION_INVALID') {
      return ListView(children: [
        EmptyView(
          icon: Icons.phonelink_lock_rounded,
          title: t.verifyAgainTitle,
          message: t.errSessionInvalid,
          action: SizedBox(
            width: 240,
            child: FilledButton(onPressed: () => context.go('/j/$joinCode'), child: Text(t.verifyMobileTitle)),
          ),
        ),
      ]);
    }
    if (code == 'HOLD_EXPIRED' || code == 'NO_BED_HELD' || code == 'BED_TAKEN') return BedLostView(joinCode: joinCode);
    if (code == 'ALREADY_JOINED' || code == 'NOT_READY_FOR_PAYMENT') {
      return ListView(children: [
        EmptyView(
          icon: Icons.check_circle_outline_rounded,
          title: t.alreadyJoinedTitle,
          message: t.errAlreadyJoined,
          action: SizedBox(
            width: 240,
            child: FilledButton(onPressed: () => context.go('/s/${_api.token}'), child: Text(t.openMyStay)),
          ),
        ),
      ]);
    }
    return ErrorView(error: error, onRetry: onRetry);
  }
}

/// Loader for student pages with the error states above.
class _StudentLoader<T> extends StatefulWidget {
  const _StudentLoader({super.key, required this.joinCode, required this.load, required this.builder});
  final String joinCode;
  final Future<T> Function() load;
  final Widget Function(BuildContext context, T data, VoidCallback reload) builder;

  @override
  State<_StudentLoader<T>> createState() => _StudentLoaderState<T>();
}

class _StudentLoaderState<T> extends State<_StudentLoader<T>> {
  late Future<T> _future = _run();

  Future<T> _run() async {
    await _ensureToken(widget.joinCode);
    return widget.load();
  }

  void _reload() => setState(() => _future = _run());

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
        if (snap.hasError) return _StudentError(joinCode: widget.joinCode, error: snap.error!, onRetry: _reload);
        return widget.builder(context, snap.data as T, _reload);
      },
    );
  }
}

// =====================================================================================
// Hostel details (after verification)
// =====================================================================================
class HostelDetailsScreen extends StatelessWidget {
  const HostelDetailsScreen({super.key, required this.joinCode});
  final String joinCode;

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    return _StudentLoader<Json>(
      joinCode: joinCode,
      load: _api.hostel,
      builder: (context, h, _) {
        final status = h['tenant_status'] as String?;
        if (['pending_approval', 'active', 'notice'].contains(status)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) context.go('/s/${_api.token}');
          });
        }
        final amenities = ((h['amenities'] as List?) ?? const []).cast<String>();
        final rules = (h['house_rules'] as String? ?? '').trim();
        final open = h['is_open'] == true;
        final sMin = h['sharing_min'];
        final sMax = h['sharing_max'];
        return StudentFrame(
          title: t.hostelDetails,
          bottom: FilledButton(
            onPressed: open ? () => context.go('/j/$joinCode/rooms') : null,
            child: Text(open ? t.viewAvailableRooms : t.hostelClosedShort),
          ),
          body: PageList(
            children: [
              // hostel photo (short-lived private link), when the owner added one
              if (h['photo_url'] is String) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Image.network(h['photo_url'] as String, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const ColoredBox(color: AppColors.primarySoft)),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Text(hostelTitle(context, h),
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text('${hostelTypeLabel(context, h['type'] as String?)} · ${h['address']}, ${h['city']}',
                  style: const TextStyle(color: AppColors.muted)),
              const SizedBox(height: 12),
              if (!open) Banner2(tone: Tone.warning, text: t.hostelClosedStudent),
              SectionCard(
                child: Column(children: [
                  if (h['min_rent'] != null) InfoRow(t.rentFrom, '${money(asInt(h['min_rent']))}${t.perMonthShort}', bold: true),
                  if (sMin != null)
                    InfoRow(t.sharing, sMin == sMax ? t.sharingN('$sMin') : t.sharingRange('$sMin', '$sMax')),
                  InfoRow(t.freeBeds, '${asInt(h['free_beds'])}'),
                  InfoRow(t.rentDay, rentDayText(context, h)),
                  InfoRow(t.noticePeriod, asInt(h['notice_days']) == 0 ? t.noNotice : t.daysN('${h['notice_days']}')),
                ]),
              ),
              if (amenities.isNotEmpty)
                SectionCard(
                  title: t.amenities,
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [for (final a in amenities) Chip2(featureLabel(context, a), tone: Tone.info)],
                  ),
                ),
              if (rules.isNotEmpty)
                SectionCard(title: t.houseRules, child: Text(rules, style: const TextStyle(height: 1.5))),
              SectionCard(
                title: t.contactOwner,
                child: Row(
                  children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(h['owner_name'] as String? ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
                        Text(phoneText(h['contact_phone'] as String?), style: const TextStyle(color: AppColors.muted)),
                      ]),
                    ),
                    IconButton.filledTonal(
                      tooltip: t.call,
                      icon: const Icon(Icons.call_rounded),
                      onPressed: () => launchUrl(Uri.parse('tel:${h['contact_phone']}')),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// =====================================================================================
// Student registration (one draft kept in memory while the student moves between steps):
//   owner booked the bed:  Verify → Details → Profile → Payment
//   student scanned the hostel QR: Verify → Details → Profile → Room selection → Payment
//   Phase 1, hostel lets tenants type their room: Verify → Details (+ Your room) → Profile → Payment
// =====================================================================================

/// Steps for the progress bar.
bool get _shortFlow => _api.isBookedFlow || _api.typedRoomFlow;
int get _totalSteps => _shortFlow ? 4 : 5;
int get _payStep => _shortFlow ? 3 : 4;

/// What the student typed / picked. Kept until the details are sent (after the bed is held).
class StudentDraft {
  StudentDraft._();
  static final instance = StudentDraft._();

  String name = '';
  String parentName = '';
  String parent = '';
  String referenceName = '';
  String reference = '';
  String idType = 'aadhaar';
  String idNumber = '';
  String home = '';
  String org = '';
  String office = '';
  bool existing = false;
  DateTime? joinedOn;
  bool acceptRules = false;
  bool consent = false;
  XFile? idFile;
  Uint8List? idBytes;
  XFile? photo;
  Uint8List? photoBytes;
  String? idKey;
  String? photoKey;
  // Phase 1 "Your room" (typed by the student)
  String roomNo = '';
  int? roomFloor;
  int? roomSharing;
  String roomPrice = '';
  String roomDeposit = '';
  bool roomLocked = false; // the owner already set this room → filled in and locked

  static const _key = 'student_details_draft';

  bool get roomOk =>
      roomNo.trim().isNotEmpty &&
      roomFloor != null &&
      roomMatchesFloor(roomNo, roomFloor) &&
      roomSharing != null &&
      (int.tryParse(roomPrice) ?? 0) > 0;

  String get idDigits => idNumber.replaceAll(' ', '').toUpperCase();
  bool get idOk => idType == 'aadhaar'
      ? RegExp(r'^[0-9X]{8}[0-9]{4}$').hasMatch(idDigits)
      : RegExp(r'^[A-Z0-9-]{6,20}$').hasMatch(idDigits);

  bool get ready =>
      name.trim().length >= 2 &&
      idOk &&
      home.trim().length >= 5 &&
      parentName.trim().length >= 2 &&
      normalizePhone(parent) != null &&
      (reference.trim().isEmpty || normalizePhone(reference) != null) &&
      org.trim().length >= 2 &&
      idFile != null &&
      acceptRules &&
      consent &&
      (!existing || joinedOn != null) &&
      (!_api.typedRoomFlow || _api.isBookedFlow || roomOk);

  /// Typed text is kept on the phone (not the ID number or photos) in case the app is closed.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return;
      final d = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      if (name.isEmpty) name = d['name'] ?? '';
      if (parentName.isEmpty) parentName = d['parent_name'] ?? '';
      if (parent.isEmpty) parent = d['parent'] ?? '';
      if (referenceName.isEmpty) referenceName = d['reference_name'] ?? '';
      if (reference.isEmpty) reference = d['reference'] ?? '';
      if (home.isEmpty) home = d['home'] ?? '';
      if (org.isEmpty) org = d['org'] ?? '';
      if (office.isEmpty) office = d['office'] ?? '';
      if (roomNo.isEmpty) {
        roomNo = d['room_no'] ?? '';
        roomFloor = d['room_floor'] as int?;
        roomSharing = d['room_sharing'] as int?;
        roomPrice = d['room_price'] ?? '';
        roomDeposit = d['room_deposit'] ?? '';
        roomLocked = d['room_locked'] == true;
      }
    } catch (_) {}
  }

  Future<void> save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode({
        'name': name, 'parent_name': parentName, 'parent': parent, 'reference_name': referenceName,
        'reference': reference, 'home': home, 'org': org, 'office': office,
        'room_no': roomNo, 'room_floor': roomFloor, 'room_sharing': roomSharing,
        'room_price': roomPrice, 'room_deposit': roomDeposit, 'room_locked': roomLocked,
      }));
    } catch (_) {}
  }

  Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (_) {}
    idFile = null;
    idBytes = null;
    photo = null;
    photoBytes = null;
    idKey = null;
    photoKey = null;
    roomNo = '';
    roomFloor = null;
    roomSharing = null;
    roomPrice = '';
    roomDeposit = '';
    roomLocked = false;
  }

  /// Phase 1: hold a bed in the room the student typed (the server makes the room if it's new).
  Future<void> claimTypedRoom() => _api.claimRoom(
        roomNo: roomNo.trim(),
        floor: roomFloor ?? 0,
        sharing: roomSharing ?? 1,
        rent: int.tryParse(roomPrice) ?? 0,
        deposit: int.tryParse(roomDeposit) ?? 0,
        existing: existing,
      );

  Future<String> _upload(String kind, XFile file) async {
    var type = file.mimeType ?? 'image/jpeg';
    if (!['image/jpeg', 'image/png', 'image/webp'].contains(type)) type = 'image/jpeg';
    final bytes = await file.readAsBytes();
    if (bytes.length > 2 * 1024 * 1024) throw AppException('FILE_TOO_BIG_OR_MISSING');
    return _api.upload(kind, bytes, type);
  }

  /// Small photo (~100×100 px, ~10–20 KB) for the owner's lists, made on the phone (Supabase resizing is paid).
  /// Never stops joining if it fails – lists then show initials.
  Future<void> _saveThumb(XFile file) async {
    try {
      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes, targetWidth: 100);
      final frame = await codec.getNextFrame();
      final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
      frame.image.dispose();
      if (data == null) return;
      final key = await _api.upload('thumb', data.buffer.asUint8List(), 'image/png');
      await _api.setThumb(key);
    } catch (_) {}
  }

  /// Uploads the photos and sends the details (needs a held bed). Returns the next route.
  Future<String> submit(String joinCode) async {
    try {
      idKey ??= await _upload('id', idFile!);
      if (photo != null) photoKey ??= await _upload('photo', photo!);
    } on AppException catch (e) {
      if (e.code == 'FILE_TOO_BIG_OR_MISSING') {
        idKey = null;
        photoKey = null;
      }
      rethrow;
    }
    final r = await _api.submitDetails({
      'full_name': name.trim(),
      'parent_name': parentName.trim(),
      'reference_name': referenceName.trim(),
      'parent_phone': normalizePhone(parent),
      'reference_phone': reference.trim().isEmpty ? null : normalizePhone(reference),
      'id_type': idType,
      'id_number': idDigits,
      'id_file_key': idKey,
      'photo_key': photoKey,
      'home_address': home.trim(),
      'office_address': office.trim(),
      'org_name': org.trim(),
      'is_existing': existing,
      'joining_date': existing && joinedOn != null ? isoDate(joinedOn!) : null,
      'consent': true,
    });
    if (photo != null) await _saveThumb(photo!);
    await clear();
    return r['status'] == 'pending_approval' ? '/j/$joinCode/done?existing=1' : '/j/$joinCode/pay';
  }
}

StudentDraft get _draft => StudentDraft.instance;

Future<XFile?> _pickImage(BuildContext context) async {
  final t = context.l10n;
  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
          leading: const Icon(Icons.photo_camera_rounded),
          title: Text(t.takePhoto),
          onTap: () => Navigator.pop(ctx, ImageSource.camera),
        ),
        ListTile(
          leading: const Icon(Icons.photo_library_rounded),
          title: Text(t.chooseFromGallery),
          onTap: () => Navigator.pop(ctx, ImageSource.gallery),
        ),
      ]),
    ),
  );
  if (source == null) return null;
  // Compressed on the phone before upload (about 200–300 KB).
  return ImagePicker().pickImage(source: source, maxWidth: 1280, maxHeight: 1280, imageQuality: 70);
}

/// Round photo / initials with a pen badge.
class _PhotoPen extends StatelessWidget {
  const _PhotoPen({required this.onTap, this.initials});
  final VoidCallback onTap;
  final String? initials;

  @override
  Widget build(BuildContext context) {
    final bytes = _draft.photoBytes;
    return Center(
      child: Semantics(
        button: true,
        label: context.l10n.profilePhotoOptional,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 92,
            height: 92,
            child: Stack(children: [
              CircleAvatar(
                radius: 46,
                backgroundColor: initials != null ? AppColors.primary : const Color(0xFFE3E6EE),
                backgroundImage: bytes == null ? null : MemoryImage(bytes),
                child: bytes != null
                    ? null
                    : (initials != null
                        ? Text(initials!, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800))
                        : const Icon(Icons.person_rounded, size: 50, color: Color(0xFF8B93A7))),
              ),
              Positioned(
                right: 0,
                bottom: 2,
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.ground, width: 3),
                  ),
                  child: const Icon(Icons.edit_rounded, size: 14, color: Colors.white),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

String _initialsOf(String name) {
  final p = name.trim().split(RegExp(r'\s+')).where((x) => x.isNotEmpty).toList();
  if (p.isEmpty) return '?';
  return (p.first[0] + (p.length > 1 ? p.last[0] : '')).toUpperCase();
}

/// Held bed (owner booking) shown on the details / profile pages, with the hold timer.
class _HeldBedStrip extends StatelessWidget {
  const _HeldBedStrip({required this.quote, required this.onExpired});
  final Json quote;
  final VoidCallback onExpired;

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    final until = asDate(quote['held_until']);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionCard(
        child: Row(children: [
          const Icon(Icons.bed_rounded, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text('${t.room} ${roomBed(quote['room_no'], quote['bed_label'])} · ${t.sharingN('${quote['sharing']}')}',
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          Text('${money(asInt(quote['rent_month']))}${t.perMonthShort}', style: const TextStyle(fontWeight: FontWeight.w800)),
        ]),
      ),
      if (until != null) HoldTimer(until: until, onExpired: onExpired),
    ]);
  }
}

// ---------------------------------------------------------------- Student Details Entry
class DetailsScreen extends StatelessWidget {
  const DetailsScreen({super.key, required this.joinCode});
  final String joinCode;

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    return StudentFrame(
      title: t.detailsEntryTitle,
      step: 2,
      totalSteps: _totalSteps,
      backTo: '/j/$joinCode',
      body: _StudentLoader<Json>(
        joinCode: joinCode,
        load: () async {
          await _draft.load();
          final h = await _api.hostel();
          _api.typedRoomFlow = h['tenant_room_entry'] == true && !_api.isBookedFlow;
          Json? q;
          if (_api.isBookedFlow) q = await _api.quote();
          return {'hostel': h, 'quote': q, 'phone': q?['phone'] ?? h['phone']};
        },
        builder: (context, d, _) {
          final h = Json.from(d['hostel'] as Map);
          final status = h['tenant_status'];
          if (status == 'pending_approval' || status == 'active' || status == 'notice') {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (context.mounted) context.go('/s/${_api.token}');
            });
          }
          return _DetailsEntry(
            joinCode: joinCode,
            hostel: h,
            quote: d['quote'] == null ? null : Json.from(d['quote'] as Map),
          );
        },
      ),
    );
  }
}

class _DetailsEntry extends StatefulWidget {
  const _DetailsEntry({required this.joinCode, required this.hostel, this.quote});
  final String joinCode;
  final Json hostel;
  final Json? quote;

  @override
  State<_DetailsEntry> createState() => _DetailsEntryState();
}

class _DetailsEntryState extends State<_DetailsEntry> {
  late final _name = TextEditingController(text: _draft.name);
  late final _idNumber = TextEditingController(text: _draft.idNumber);
  late final _parentName = TextEditingController(text: _draft.parentName);
  late final _parent = TextEditingController(text: _draft.parent);
  late final _referenceName = TextEditingController(text: _draft.referenceName);
  late final _reference = TextEditingController(text: _draft.reference);
  late final _home = TextEditingController(text: _draft.home);
  late final _org = TextEditingController(text: _draft.org);
  late final _office = TextEditingController(text: _draft.office);
  // Ground floor: the field shows a fixed "G" and holds only the number (G3 → "3").
  late final _roomNo = TextEditingController(
      text: _draft.roomFloor == 0 && _draft.roomNo.startsWith('G') ? _draft.roomNo.substring(1) : _draft.roomNo);
  late String _lastRoomText = _roomNo.text;
  late final _roomPrice = TextEditingController(text: _draft.roomPrice);
  late final _roomDeposit = TextEditingController(text: _draft.roomDeposit);
  bool _otherId = false;
  bool _lost = false;
  Timer? _lookupTimer;

  List<TextEditingController> get _all =>
      [_name, _idNumber, _parentName, _parent, _referenceName, _reference, _home, _org, _office, _roomNo, _roomPrice, _roomDeposit];

  @override
  void initState() {
    super.initState();
    _otherId = _draft.idType != 'aadhaar';
    if (widget.quote?['offline_bed'] == true) _draft.existing = true;
    for (final c in _all) {
      c.addListener(_sync);
    }
  }

  @override
  void dispose() {
    _lookupTimer?.cancel();
    for (final c in _all) {
      c.dispose();
    }
    super.dispose();
  }

  /// Typed room number: if the owner already set that room, fill in and lock its details.
  void _roomNoChanged() {
    _lookupTimer?.cancel();
    final no = _draft.roomNo.trim();
    if (no.isEmpty) return;
    _lookupTimer = Timer(const Duration(milliseconds: 600), () async {
      try {
        final r = await _api.roomLookup(no);
        if (!mounted || _draft.roomNo.trim() != no) return;
        setState(() {
          if (r['found'] == true) {
            _draft
              ..roomLocked = true
              ..roomFloor = asInt(r['floor'])
              ..roomSharing = asInt(r['sharing']);
            _roomPrice.text = '${asInt(r['rent_month'])}';
            _roomDeposit.text = asInt(r['deposit']) > 0 ? '${asInt(r['deposit'])}' : '';
          } else if (_draft.roomLocked) {
            _draft
              ..roomLocked = false
              ..roomFloor = null
              ..roomSharing = null;
            _roomPrice.clear();
            _roomDeposit.clear();
          }
        });
        _draft.save();
      } catch (_) {
        // lookup is only a convenience; the student can still type everything
      }
    });
  }

  void _sync() {
    _draft
      ..name = _name.text
      ..idNumber = _idNumber.text
      ..parentName = _parentName.text
      ..parent = _parent.text
      ..referenceName = _referenceName.text
      ..reference = _reference.text
      ..home = _home.text
      ..org = _org.text
      ..office = _office.text
      ..roomPrice = _roomPrice.text
      ..roomDeposit = _roomDeposit.text;
    final raw = _roomNo.text;
    final ground = _draft.roomFloor == 0;
    if (!ground && startsWithG(raw) && !startsWithG(_lastRoomText)) {
      // the student typed a G: switch to Ground, the field keeps only the number
      _draft.roomFloor = 0;
      final n = raw.trim().substring(1).replaceAll(RegExp(r'\D'), '');
      _lastRoomText = n;
      _roomNo.value = TextEditingValue(text: n, selection: TextSelection.collapsed(offset: n.length));
      return; // this listener runs again with the new text
    }
    _lastRoomText = raw;
    final full = ground ? (raw.trim().isEmpty ? '' : 'G${raw.trim()}') : raw;
    if (_draft.roomNo != full) {
      _draft.roomNo = full;
      _roomNoChanged();
    }
    _draft.save();
    if (mounted) setState(() {});
  }

  Future<void> _pickPhoto() async {
    final f = await _pickImage(context);
    if (f == null) return;
    final bytes = await f.readAsBytes();
    setState(() {
      _draft
        ..photo = f
        ..photoBytes = bytes
        ..photoKey = null;
    });
  }

  Future<void> _pickId() async {
    final f = await _pickImage(context);
    if (f == null) return;
    final bytes = await f.readAsBytes();
    setState(() {
      _draft
        ..idFile = f
        ..idBytes = bytes
        ..idKey = null;
    });
  }

  /// One "Label : value" row (Student Details Entry design).
  Widget _row(String label, TextEditingController c,
      {bool required = true, String? hint, TextInputType? keyboard, int maxLines = 1, List<TextInputFormatter>? fmt, bool last = false}) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 4),
      decoration: BoxDecoration(border: last ? null : const Border(bottom: BorderSide(color: Color(0xFFEEF0F5)))),
      child: Row(crossAxisAlignment: maxLines > 1 ? CrossAxisAlignment.start : CrossAxisAlignment.center, children: [
        SizedBox(
          width: 128,
          child: Padding(
            padding: EdgeInsets.only(top: maxLines > 1 ? 12 : 0),
            child: Text('$label${required ? ' *' : ''} :',
                style: const TextStyle(color: Color(0xFF5C6782), fontWeight: FontWeight.w400, fontSize: 14)),
          ),
        ),
        Expanded(
          child: TextField(
            controller: c,
            keyboardType: keyboard,
            maxLines: maxLines,
            inputFormatters: fmt,
            textCapitalization: keyboard == null ? TextCapitalization.words : TextCapitalization.none,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            decoration: InputDecoration(
              hintText: hint,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              filled: false,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
      ]),
    );
  }

  /// White rounded box holding "Label : value" rows.
  Widget _box(List<Widget> rows) => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.line),
        ),
        child: Column(children: rows),
      );

  Widget _sectionHead(IconData icon, String title) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 18, 2, 8),
        child: Row(children: [
          Icon(icon, size: 19, color: AppColors.primary),
          const SizedBox(width: 6),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        ]),
      );

  /// Small labelled input used in the "Your room" card.
  Widget _roomInput(String label, TextEditingController c,
      {bool required = true, bool number = false, bool lockable = false, String? hint, String? prefix, bool strongPrefix = false}) {
    final locked = lockable && _draft.roomLocked;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('$label${required ? ' *' : ''}',
          style: const TextStyle(color: Color(0xFF5C6782), fontWeight: FontWeight.w400, fontSize: 12.5)),
      const SizedBox(height: 4),
      TextField(
        controller: c,
        enabled: !locked,
        keyboardType: number ? TextInputType.number : TextInputType.text,
        inputFormatters: number
            ? [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)]
            : [LengthLimitingTextInputFormatter(20)],
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        decoration: InputDecoration(
          isDense: true,
          hintText: hint,
          prefixText: prefix,
          prefixStyle: strongPrefix ? const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600, fontSize: 14) : null,
          filled: true,
          fillColor: locked ? AppColors.ground : Colors.white,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        ),
      ),
    ]);
  }

  /// Phase 1: floor, room number, sharing, monthly price, deposit typed by the student.
  Widget _roomCard() {
    final t = context.l10n;
    final locked = _draft.roomLocked;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.35)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 110,
            child: _draft.roomFloor == 0
                ? _roomInput(t.roomNoShort, _roomNo, hint: '1', number: true, prefix: 'G ', strongPrefix: true)
                : _roomInput(t.roomNoShort, _roomNo, hint: '204'),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${t.floor} *',
                  style: const TextStyle(color: Color(0xFF5C6782), fontWeight: FontWeight.w400, fontSize: 12.5)),
              const SizedBox(height: 4),
              FloorPicker(
                value: _draft.roomFloor,
                locked: locked,
                onChanged: (f) {
                  setState(() {
                    final wasGround = _draft.roomFloor == 0;
                    _draft.roomFloor = f;
                    if (f == 0 && !wasGround) {
                      // a non-G number can't stay on the ground floor
                      final keep = isGroundRoom(_draft.roomNo) ? _draft.roomNo.substring(1) : '';
                      _lastRoomText = keep;
                      _roomNo.text = keep;
                    } else if (f != 0 && wasGround) {
                      // keep the G number visible so the student sees why it doesn't fit
                      _lastRoomText = _draft.roomNo;
                      _roomNo.text = _draft.roomNo;
                    }
                  });
                  _draft.save();
                },
              ),
            ]),
          ),
        ]),
        if (_draft.roomNo.trim().isNotEmpty && _draft.roomFloor != null && !roomMatchesFloor(_draft.roomNo, _draft.roomFloor))
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(_draft.roomFloor == 0 ? t.errGroundRoomNeedsG : t.errGRoomNotGround,
                style: const TextStyle(color: AppColors.danger, fontSize: 12.5)),
          ),
        const SizedBox(height: 12),
        Text('${t.sharing} *', style: const TextStyle(color: Color(0xFF5C6782), fontWeight: FontWeight.w400, fontSize: 12.5)),
        const SizedBox(height: 4),
        SharingPicker(
          value: _draft.roomSharing,
          locked: locked,
          onChanged: (n) {
            setState(() => _draft.roomSharing = n);
            _draft.save();
          },
        ),
        const SizedBox(height: 12),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: _roomInput(t.monthlyPrice, _roomPrice, number: true, lockable: true, hint: '6500', prefix: '₹ ')),
          const SizedBox(width: 10),
          Expanded(
            child: _roomInput(t.depositIfAny, _roomDeposit,
                required: false, number: true, lockable: true, hint: t.noneText, prefix: '₹ '),
          ),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Icon(locked ? Icons.lock_outline_rounded : Icons.info_outline_rounded,
              size: 16, color: locked ? AppColors.success : AppColors.muted),
          const SizedBox(width: 6),
          Expanded(
            child: Text(locked ? t.roomLockedHelp : t.roomEntryHelp,
                style: TextStyle(fontSize: 12.5, color: locked ? AppColors.success : AppColors.muted)),
          ),
        ]),
      ]),
    );
  }

  /// ID copy / your photo tile (side by side).
  Widget _uploadTile({required IconData icon, required String label, required Uint8List? bytes, required VoidCallback onTap}) {
    final t = context.l10n;
    final done = bytes != null;
    return Expanded(
      child: Material(
        color: done ? AppColors.successSoft : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: done ? AppColors.success : const Color(0xFFA5B4FC), width: 1.4),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
            child: Column(children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(12),
                  image: bytes == null ? null : DecorationImage(image: MemoryImage(bytes), fit: BoxFit.cover),
                ),
                child: bytes == null ? Icon(icon, color: AppColors.primary) : null,
              ),
              const SizedBox(height: 6),
              Text(label, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5)),
              Text(done ? t.tapToChange : t.tapToAdd, style: const TextStyle(color: AppColors.muted, fontSize: 11)),
            ]),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    if (_lost) return BedLostView(joinCode: widget.joinCode);
    final h = widget.hostel;
    final q = widget.quote;
    final isAadhaar = _draft.idType == 'aadhaar';
    final digits = [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)];
    final rules = (h['house_rules'] as String? ?? '').trim();
    final typedRoom = _api.typedRoomFlow && !_api.isBookedFlow;
    return PageList(children: [
      if (q != null) _HeldBedStrip(quote: q, onExpired: () => setState(() => _lost = true)),
      // ---- joining (only when the student picks the room; a bed the owner booked is a new joiner)
      if (!_api.isBookedFlow) ...[
        SegmentedButton<bool>(
          segments: [
            ButtonSegment(value: false, label: Text(t.newJoiner)),
            ButtonSegment(value: true, label: Text(t.alreadyStaying)),
          ],
          selected: {_draft.existing},
          onSelectionChanged: (s) => setState(() => _draft.existing = s.first),
        ),
        if (_draft.existing) ...[
          const SizedBox(height: 10),
          DateField(
            label: t.whenDidYouJoin,
            value: _draft.joinedOn,
            first: today().subtract(const Duration(days: 1825)),
            last: today(),
            onChanged: (d) => setState(() => _draft.joinedOn = d),
          ),
          const SizedBox(height: 4),
          Text(t.existingStudentHelp, style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
        ],
      ],
      // ---- Phase 1: your room (floor, room no, sharing, price, deposit)
      if (typedRoom) ...[
        _sectionHead(Icons.bed_outlined, t.yourRoom),
        _roomCard(),
      ],
      // ---- about you
      _sectionHead(Icons.person_outline_rounded, t.aboutYou),
      _box([
        _row(t.fullName, _name, hint: 'Rohith Sharma'),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFEEF0F5)))),
          child: Row(children: [
            SizedBox(
              width: 128,
              child: Text('${t.mobileShort} * :',
                  style: const TextStyle(color: Color(0xFF5C6782), fontWeight: FontWeight.w400, fontSize: 14)),
            ),
            Expanded(
              child: Text(phoneText(q?['phone'] as String? ?? h['phone'] as String?),
                  style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.success)),
            ),
            const Icon(Icons.verified_rounded, color: AppColors.success, size: 18),
          ]),
        ),
        _row(t.parentName, _parentName, hint: 'Mr. Ramesh Sharma'),
        _row(t.parentPhone, _parent, hint: '+91', keyboard: TextInputType.phone, fmt: digits),
        _row(t.referenceName, _referenceName, required: false, hint: '—'),
        _row(t.referencePhoneShort, _reference, required: false, hint: '+91', keyboard: TextInputType.phone, fmt: digits, last: true),
      ]),
      // ---- ID proof: number, then ID copy + your photo side by side
      _sectionHead(Icons.badge_outlined, t.idProof),
      if (_otherId)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: DropdownButtonFormField<String>(
            value: _draft.idType,
            decoration: InputDecoration(labelText: t.idType),
            items: [
              for (final k in ['aadhaar', 'passport', 'driving_licence'])
                DropdownMenuItem(value: k, child: Text(idTypeLabel(context, k))),
            ],
            onChanged: (v) => setState(() => _draft.idType = v ?? 'aadhaar'),
          ),
        ),
      _box([
        _row(isAadhaar ? t.aadhaarNumber : idTypeLabel(context, _draft.idType), _idNumber,
            hint: isAadhaar ? '1234 5678 9012' : 'A1234567',
            keyboard: isAadhaar ? TextInputType.number : TextInputType.text,
            fmt: [FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9 -]')), LengthLimitingTextInputFormatter(24)],
            last: true),
      ]),
      if (_idNumber.text.trim().isNotEmpty && !_draft.idOk)
        Padding(
          padding: const EdgeInsets.only(top: 6, left: 4),
          child: Text(t.errBadIdNumber, style: const TextStyle(color: AppColors.danger, fontSize: 12.5)),
        ),
      Padding(
        padding: const EdgeInsets.only(top: 4, left: 4),
        child: Text(t.idStoredSafely, style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
      ),
      if (!_otherId)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(onPressed: () => setState(() => _otherId = true), child: Text(t.useAnotherId)),
        )
      else
        const SizedBox(height: 10),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _uploadTile(icon: Icons.upload_rounded, label: '${t.idCopy} *', bytes: _draft.idBytes, onTap: _pickId),
        const SizedBox(width: 10),
        _uploadTile(icon: Icons.photo_camera_outlined, label: t.yourPhoto, bytes: _draft.photoBytes, onTap: _pickPhoto),
      ]),
      const SizedBox(height: 6),
      Text(t.photosPrivate, style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
      // ---- address: home, then college / office name and address
      _sectionHead(Icons.home_outlined, t.address),
      _box([
        _row(t.addressShort, _home, hint: t.homeAddress, maxLines: 3),
        _row(t.collegeOffice, _org, hint: t.orgNameHelp),
        _row(t.collegeOfficeAddress, _office, required: false, hint: '—', last: true),
      ]),
      const SizedBox(height: 12),
      // ---- house rules
      SectionCard(
        title: t.houseRules,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (rules.isNotEmpty) Text(rules, style: const TextStyle(fontSize: 12.5, height: 1.4)),
          const SizedBox(height: 6),
          Text(t.noticeRule('${h['notice_days'] ?? 15}'), style: const TextStyle(fontSize: 12.5, color: AppColors.muted, height: 1.4)),
        ]),
      ),
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        value: _draft.acceptRules,
        onChanged: (v) => setState(() => _draft.acceptRules = v ?? false),
        title: Text(t.acceptHostelTerms, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      ),
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        value: _draft.consent,
        onChanged: (v) => setState(() => _draft.consent = v ?? false),
        title: Text(t.dpdpConsent, style: const TextStyle(fontSize: 12.5)),
        subtitle: Align(
          alignment: Alignment.centerLeft,
          child: TextButton(onPressed: () => context.push('/privacy'), child: Text(t.readPolicy)),
        ),
      ),
      const SizedBox(height: 8),
      SizedBox(
        height: 52,
        child: FilledButton(
          onPressed: _draft.ready ? () => context.push('/j/${widget.joinCode}/profile') : null,
          child: Text(typedRoom ? (_draft.existing ? t.sendForApproval : t.saveAndContinue) : t.saveAndSubmit),
        ),
      ),
      if (!_draft.ready) ...[
        const SizedBox(height: 6),
        Text(t.enabledWhenFilled, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
      ],
    ]);
  }
}

// ---------------------------------------------------------------- Student Profile (review)
class StudentProfileScreen extends StatefulWidget {
  const StudentProfileScreen({super.key, required this.joinCode});
  final String joinCode;

  @override
  State<StudentProfileScreen> createState() => _StudentProfileScreenState();
}

class _StudentProfileScreenState extends State<StudentProfileScreen> {
  bool _lost = false;

  Future<void> _continue() async {
    final typedRoom = _api.typedRoomFlow && !_api.isBookedFlow;
    if (!_api.isBookedFlow && !typedRoom) {
      context.push('/j/${widget.joinCode}/rooms');
      return;
    }
    try {
      // Phase 1: hold a bed in the room the student typed, then send the details
      if (typedRoom) await _draft.claimTypedRoom();
      final next = await _draft.submit(widget.joinCode);
      if (mounted) context.go(next);
    } on AppException catch (e) {
      if (e.code == 'HOLD_EXPIRED' || e.code == 'BED_TAKEN' || e.code == 'NO_BED_HELD') {
        if (mounted) setState(() => _lost = true);
        return;
      }
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    final d = _draft;
    if (!d.ready) {
      // opened without details (e.g. after a restart): back to the form
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go('/j/${widget.joinCode}/details');
      });
      return const Scaffold(body: SizedBox.shrink());
    }
    Widget row(String l, String v, {bool col = false, bool last = false}) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(border: last ? null : const Border(bottom: BorderSide(color: Color(0xFFEEF0F5)))),
          child: col
              ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(l, style: const TextStyle(color: AppColors.muted)),
                  const SizedBox(height: 2),
                  Text(v, style: const TextStyle(fontWeight: FontWeight.w600)),
                ])
              : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: Text(l, style: const TextStyle(color: AppColors.muted))),
                  const SizedBox(width: 10),
                  Flexible(child: Text(v, textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w600))),
                ]),
        );
    final last4 = d.idDigits.length >= 4 ? d.idDigits.substring(d.idDigits.length - 4) : d.idDigits;
    final isAadhaar = d.idType == 'aadhaar';
    return StudentFrame(
      title: t.studentProfileTitle,
      step: 2,
      totalSteps: _totalSteps,
      backTo: '/j/${widget.joinCode}/details',
      body: _lost
          ? BedLostView(joinCode: widget.joinCode)
          : PageList(children: [
              _PhotoPen(onTap: () => goBack(context), initials: _initialsOf(d.name)),
              const SizedBox(height: 8),
              Text(d.name.trim(), textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              Container(
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.line)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  row(t.fullName, d.name.trim()),
                  row(isAadhaar ? t.aadhaarNumber : idTypeLabel(context, d.idType), '•••• •••• $last4'),
                  row(t.parentName, d.parentName.trim()),
                  row(t.parentPhone, phoneText(normalizePhone(d.parent))),
                  if (d.referenceName.trim().isNotEmpty) row(t.referenceName, d.referenceName.trim()),
                  if (d.reference.trim().isNotEmpty) row(t.referencePhoneShort, phoneText(normalizePhone(d.reference))),
                  if (d.existing && d.joinedOn != null) row(t.joiningDate, dateText(context, d.joinedOn)),
                  if (_api.typedRoomFlow && !_api.isBookedFlow) ...[
                    row(t.room, t.roomFloorSharing(d.roomNo.trim(),
                        (d.roomFloor ?? 0) == 0 ? t.groundFloor : t.floorN('${d.roomFloor}'), t.sharingN('${d.roomSharing ?? 1}'))),
                    row(t.monthlyPrice, money(int.tryParse(d.roomPrice) ?? 0)),
                    row(t.deposit, (int.tryParse(d.roomDeposit) ?? 0) > 0 ? money(int.parse(d.roomDeposit)) : t.noneText),
                  ],
                  row(t.addressShort, d.home.trim(), col: true),
                  row(t.collegeOffice, [d.org.trim(), d.office.trim()].where((x) => x.isNotEmpty).join(' · '), col: true, last: true),
                ]),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                icon: const Icon(Icons.visibility_outlined),
                label: Text(isAadhaar ? t.viewIdCard : t.viewOtherIdCard),
                onPressed: d.idBytes == null
                    ? null
                    : () => showDialog<void>(
                          context: context,
                          builder: (ctx) => Dialog(
                            clipBehavior: Clip.antiAlias,
                            child: Column(mainAxisSize: MainAxisSize.min, children: [
                              Flexible(child: InteractiveViewer(child: Image.memory(d.idBytes!, fit: BoxFit.contain))),
                              TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(t.close)),
                            ]),
                          ),
                        ),
              ),
              const SizedBox(height: 10),
              BusyButton(
                label: _shortFlow ? (d.existing ? t.sendForApproval : t.saveContinuePayment) : t.saveSelectRoom,
                onPressed: _continue,
              ),
              TextButton.icon(
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: Text(t.editDetails),
                onPressed: () => goBack(context),
              ),
            ]),
    );
  }
}

// ---------------------------------------------------------------- Room Selection (student scanned the hostel QR)
class RoomsPickScreen extends StatefulWidget {
  const RoomsPickScreen({super.key, required this.joinCode});
  final String joinCode;

  @override
  State<RoomsPickScreen> createState() => _RoomsPickScreenState();
}

class _RoomsPickScreenState extends State<RoomsPickScreen> {
  int? _floor;
  int? _sharing;
  Json? _room;
  Json? _bed;
  bool _agree = false;
  int _version = 0;

  /// Beds the student may pick: free ones; "I stay here" beds only for existing tenants.
  bool _pickable(Json b) {
    final s = b['state'];
    return s == 'free' || s == 'yours' || (s == 'offline' && _draft.existing);
  }

  Future<void> _confirm() async {
    final t = context.l10n;
    if (!_draft.ready) {
      context.go('/j/${widget.joinCode}/details');
      return;
    }
    try {
      if (_bed!['state'] != 'yours') await _api.hold(_bed!['id'] as String);
      final next = await _draft.submit(widget.joinCode);
      if (mounted) context.go(next);
    } on AppException catch (e) {
      if ((e.code == 'BED_TAKEN' || e.code == 'HOLD_EXPIRED') && mounted) {
        showSnack(context, t.errBedTaken, error: true);
        setState(() {
          _room = null;
          _bed = null;
          _version++;
        });
        return;
      }
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    return StudentFrame(
      title: t.roomSelectionTitle,
      step: 3,
      totalSteps: _totalSteps,
      backTo: '/j/${widget.joinCode}/profile',
      bottom: BusyButton(
        label: _bed == null ? t.pickRoomFirst : t.confirmProceedPayment,
        onPressed: _bed == null || !_agree ? null : _confirm,
      ),
      body: _StudentLoader<List<Json>>(
        key: ValueKey(_version),
        joinCode: widget.joinCode,
        load: _api.rooms,
        builder: (context, rooms, reload) {
          if (rooms.isEmpty) {
            return ListView(children: [EmptyView(icon: Icons.bed_outlined, title: t.noRoomsTitle, message: t.noRoomsStudent)]);
          }
          final floors = rooms.map((r) => asInt(r['floor'])).toSet().toList()..sort();
          final sharings = rooms.map((r) => asInt(r['sharing'])).toSet().toList()..sort();
          final shown = rooms
              .where((r) => (_floor == null || asInt(r['floor']) == _floor) && (_sharing == null || asInt(r['sharing']) == _sharing))
              .toList();
          List<Json> bedsOf(Json r) => (r['beds'] as List).cast<Json>();
          final freeBeds = _room == null ? const <Json>[] : bedsOf(_room!).where(_pickable).toList();
          String floorName(int f) => f == 0 ? t.groundFloor : t.floorN('$f');
          return RefreshIndicator(
            onRefresh: () async => reload(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                Narrow(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Row(children: [
                      Expanded(
                        child: DropdownButtonFormField<int?>(
                          value: _floor,
                          isExpanded: true,
                          decoration: const InputDecoration(isDense: true),
                          items: [
                            DropdownMenuItem(value: null, child: Text(t.floorAll)),
                            for (final f in floors) DropdownMenuItem(value: f, child: Text(floorName(f))),
                          ],
                          onChanged: (v) => setState(() => _floor = v),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButtonFormField<int?>(
                          value: _sharing,
                          isExpanded: true,
                          decoration: const InputDecoration(isDense: true),
                          items: [
                            DropdownMenuItem(value: null, child: Text(t.sharingAll)),
                            for (final s in sharings) DropdownMenuItem(value: s, child: Text(t.sharingN('$s'))),
                          ],
                          onChanged: (v) => setState(() => _sharing = v),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 12),
                    // room grid
                    LayoutBuilder(builder: (context, box) {
                      final cols = box.maxWidth >= 480 ? 6 : 4;
                      final w = (box.maxWidth - 8 * (cols - 1)) / cols;
                      return Wrap(spacing: 8, runSpacing: 8, children: [
                        for (final r in shown)
                          Builder(builder: (context) {
                            final open = bedsOf(r).any(_pickable);
                            final sel = _room?['id'] == r['id'];
                            return SizedBox(
                              width: w,
                              child: Semantics(
                                button: open,
                                selected: sel,
                                label: '${t.room} ${r['room_no']}',
                                excludeSemantics: true,
                                child: Material(
                                  color: sel ? AppColors.primary : (open ? Colors.white : const Color(0xFFF0F1F5)),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    side: BorderSide(
                                      color: sel ? AppColors.primary : (open ? const Color(0xFFB7E4CB) : const Color(0xFFF0F1F5)),
                                      width: 1.5,
                                    ),
                                  ),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(12),
                                    onTap: open
                                        ? () => setState(() {
                                              _room = r;
                                              final picks = bedsOf(r).where(_pickable).toList();
                                              _bed = picks.firstWhere((b) => b['state'] == 'yours', orElse: () => picks.first);
                                            })
                                        : null,
                                    child: SizedBox(
                                      height: 46,
                                      child: Center(
                                        child: Text('${r['room_no']}',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w600,
                                              color: sel ? Colors.white : (open ? const Color(0xFF0E5C3E) : const Color(0xFFB0B6C4)),
                                              decoration: open ? null : TextDecoration.lineThrough,
                                            )),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }),
                      ]);
                    }),
                    const SizedBox(height: 8),
                    Wrap(spacing: 12, children: [
                      _legend(Colors.white, const Color(0xFFB7E4CB), t.legendAvailable),
                      _legend(AppColors.primary, AppColors.primary, t.legendSelected),
                      _legend(const Color(0xFFE4E7EF), const Color(0xFFE4E7EF), t.legendFull),
                    ]),
                    if (_room != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(12)),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Expanded(
                              child: Text('${t.room} ${roomBed(_room!['room_no'], _bed?['label'])}',
                                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                            ),
                            Chip2(t.legendSelected, tone: Tone.success),
                          ]),
                          Text(
                            [
                              t.sharingN('${_room!['sharing']}'),
                              t.bedsFreeN('${freeBeds.length}'),
                              floorName(asInt(_room!['floor'])),
                              ...((_room!['features'] as List?) ?? const []).cast<String>().map((f) => featureLabel(context, f)),
                            ].join(' · '),
                            style: const TextStyle(color: AppColors.muted, fontSize: 12.5),
                          ),
                          if (freeBeds.length > 1) ...[
                            const SizedBox(height: 8),
                            Text(t.chooseBed, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5)),
                            const SizedBox(height: 6),
                            Wrap(spacing: 6, children: [
                              for (final b in freeBeds)
                                ChoiceChip(
                                  label: Text('${t.bed} ${b['label']}'),
                                  selected: _bed?['id'] == b['id'],
                                  onSelected: (_) => setState(() => _bed = b),
                                ),
                            ]),
                          ],
                          if (_bed?['state'] == 'offline') ...[
                            const SizedBox(height: 8),
                            Banner2(tone: Tone.warning, text: t.offlineBedStudent),
                          ],
                        ]),
                      ),
                      SectionCard(
                        title: t.feeDetailsRoom('${_room!['room_no']}'),
                        child: Column(children: [
                          InfoRow(t.rentMonthly, money(asInt(_room!['rent_month']))),
                          InfoRow(t.depositOneTime, money(asInt(_room!['deposit_month']))),
                          const Divider(),
                          InfoRow(t.firstPayment, money(asInt(_room!['rent_month']) + asInt(_room!['deposit_month'])), bold: true),
                          InfoRow(t.everyMonthAfter, money(asInt(_room!['rent_month']))),
                        ]),
                      ),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        value: _agree,
                        onChanged: (v) => setState(() => _agree = v ?? false),
                        title: Text(t.agreeTermsPolicies, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(t.holdInfo, style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                  ]),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _legend(Color fill, Color border, String label) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.circular(3), border: Border.all(color: border, width: 1.5)),
        ),
        const SizedBox(width: 5),
        Text(label, style: const TextStyle(fontSize: 12.5, color: AppColors.muted)),
      ]);
}

// =====================================================================================
// Step 4 – Stay & payment
// =====================================================================================
class PaymentScreen extends StatelessWidget {
  const PaymentScreen({super.key, required this.joinCode});
  final String joinCode;

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    return StudentFrame(
      title: t.choosePaymentTitle,
      step: _payStep,
      totalSteps: _totalSteps,
      backTo: '/j/$joinCode/details',
      body: _StudentLoader<Json>(
        joinCode: joinCode,
        load: _api.quote,
        builder: (context, q, _) {
          if (q['tenant_status'] != 'awaiting_payment') {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!context.mounted) return;
              context.go(q['tenant_status'] == 'draft' ? '/j/$joinCode/details' : '/s/${_api.token}');
            });
            return const SizedBox.shrink();
          }
          return _PaymentForm(joinCode: joinCode, quote: q);
        },
      ),
    );
  }
}

class _PaymentForm extends StatefulWidget {
  const _PaymentForm({required this.joinCode, required this.quote});
  final String joinCode;
  final Json quote;

  @override
  State<_PaymentForm> createState() => _PaymentFormState();
}

class _PaymentFormState extends State<_PaymentForm> {
  final _form = GlobalKey<FormState>();
  final _utr = TextEditingController();
  late final List<String> _methods = acceptedMethods(widget.quote);
  late String? _method = _methods.isEmpty ? null : _methods.first;
  DateTime _paidOn = today();
  bool _agreed = false;
  bool _lost = false;

  @override
  void dispose() {
    _utr.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    final q = widget.quote;
    if (_lost) return BedLostView(joinCode: widget.joinCode);
    final total = asInt(q['total']);
    final notice = asInt(q['notice_days']);
    final heldUntil = asDate(q['held_until']);
    final needsUtr = _method == 'upi' || _method == 'bank';
    return Form(
      key: _form,
      child: PageList(
        children: [
          if (heldUntil != null) HoldTimer(until: heldUntil, onExpired: () => setState(() => _lost = true)),
          Text(t.stayType, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: [ButtonSegment(value: 'monthly', label: Text(t.monthly))],
            selected: const {'monthly'},
            onSelectionChanged: (_) {},
          ),
          const SizedBox(height: 12),
          SectionCard(
            child: Column(children: [
              InfoRow(t.roomBed, roomBed(q['room_no'], q['bed_label'])),
              InfoRow(t.joiningDate, dateText(context, q['joining_date'])),
              InfoRow(
                q['prorated'] == true
                    ? t.rentProrated(shortDate(context, q['rent_period_start']), shortDate(context, q['rent_period_end']))
                    : t.rentPeriod(shortDate(context, q['rent_period_start']), shortDate(context, q['rent_period_end'])),
                money(asInt(q['rent_amount'])),
              ),
              InfoRow(t.securityDeposit, money(asInt(q['deposit']))),
              const Divider(),
              InfoRow(t.totalToPay, money(total), bold: true),
              const SizedBox(height: 4),
              Text(
                '${t.yourRentDay}: ${rentDayText(context, q)}${q['prorated'] == true ? '\n${t.proratedHelp}' : ''}',
                style: const TextStyle(color: AppColors.muted, fontSize: 12.5),
              ),
            ]),
          ),
          Banner2(tone: Tone.warning, icon: Icons.policy_rounded, text: t.refundPolicy('$notice')),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _agreed,
            onChanged: (v) => setState(() => _agreed = v ?? false),
            title: Text(t.iAgree, style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          const SizedBox(height: 8),
          Text(t.howToPay, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 8),
          if (_methods.isEmpty)
            Banner2(tone: Tone.danger, text: t.noPaymentMethods)
          else ...[
            MethodPicker(methods: _methods, value: _method, onChanged: (m) => setState(() => _method = m)),
            const SizedBox(height: 4),
            PayInstructions(method: _method!, options: q, amount: total, note: q['payment_note'] as String),
            if (needsUtr) ...[
              UtrField(controller: _utr),
              const SizedBox(height: 12),
              DateField(
                label: t.paidOn,
                value: _paidOn,
                first: today().subtract(const Duration(days: 3)),
                last: today(),
                onChanged: (d) => setState(() => _paidOn = d),
              ),
            ],
            const SizedBox(height: 16),
            BusyButton(
              label: needsUtr ? t.iHavePaid : t.payCashSend,
              onPressed: () async {
                if (!_agreed) {
                  showSnack(context, t.errAgreePolicy, error: true);
                  return;
                }
                if (!_form.currentState!.validate()) return;
                try {
                  final r = await _api.submitPayment(
                    method: _method!,
                    utr: needsUtr ? _utr.text.trim().toUpperCase() : null,
                    paidOn: needsUtr ? _paidOn : null,
                  );
                  if (mounted) context.go('/j/${widget.joinCode}/done?amount=${asInt(r['amount'])}');
                } on AppException catch (e) {
                  if (e.code == 'HOLD_EXPIRED') {
                    if (mounted) setState(() => _lost = true);
                    return;
                  }
                  rethrow;
                }
              },
            ),
            const SizedBox(height: 8),
            Text(t.ownerWillConfirm, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
          ],
        ],
      ),
    );
  }
}

// =====================================================================================
// Submitted
// =====================================================================================
class DoneScreen extends StatefulWidget {
  const DoneScreen({super.key, required this.joinCode, required this.existing, this.amount});
  final String joinCode;
  final bool existing;
  final int? amount;

  @override
  State<DoneScreen> createState() => _DoneScreenState();
}

class _DoneScreenState extends State<DoneScreen> {
  String? _token;
  Json? _me;

  @override
  void initState() {
    super.initState();
    _token = _api.token;
    () async {
      _token ??= await _api.savedToken(joinCode: widget.joinCode);
      if (_token == null) return;
      try {
        final me = await _api.me();
        if (mounted) setState(() => _me = me);
      } catch (_) {}
      if (mounted) setState(() {});
    }();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    final tenant = _me == null ? null : Json.from(_me!['tenant'] as Map);
    final bills = _me == null ? const <Json>[] : (_me!['bills'] as List).cast<Json>();
    // next fee date = the day after the latest rent period
    DateTime? nextFee;
    for (final b in bills) {
      if (b['kind'] == 'rent' && b['period_end'] != null) {
        final e = asDate(b['period_end']);
        final next = e?.add(const Duration(days: 1));
        if (next != null && (nextFee == null || next.isAfter(nextFee))) nextFee = next;
      }
    }
    Widget row(String l, Widget v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(children: [Expanded(child: Text(l, style: const TextStyle(color: AppColors.muted))), v]),
        );
    return Scaffold(
      body: SafeArea(
        child: PageList(
          children: [
            if (!widget.existing) StepProgress(_totalSteps, total: _totalSteps),
            const SizedBox(height: 24),
            Center(
              child: Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  color: const Color(0xFF0E9F6E),
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: const Color(0xFF0E9F6E).withValues(alpha: 0.18), spreadRadius: 12)],
                ),
                child: const Icon(Icons.check_rounded, size: 50, color: Colors.white),
              ),
            ),
            const SizedBox(height: 26),
            Text(widget.existing ? t.sentForApprovalTitle : t.bookingSubmittedTitle,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(widget.existing ? t.sentForApprovalText : t.bookingSubmittedText,
                textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted)),
            const SizedBox(height: 16),
            if (tenant != null)
              SectionCard(
                child: Column(children: [
                  row(t.roomNumber, Text(roomBed(tenant['room_no'], tenant['bed_label']),
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.success))),
                  const Divider(height: 1),
                  row(t.dateOfJoining, Text(dateText(context, tenant['joining_date']), style: const TextStyle(fontWeight: FontWeight.w600))),
                  if (nextFee != null) ...[
                    const Divider(height: 1),
                    row(t.nextFeeDate, Text(dateText(context, nextFee), style: const TextStyle(fontWeight: FontWeight.w600))),
                  ],
                  if (widget.amount != null) ...[
                    const Divider(height: 1),
                    row(t.paidLabel, Text(money(widget.amount), style: const TextStyle(fontWeight: FontWeight.w800))),
                  ],
                ]),
              ),
            Banner2(icon: Icons.notifications_active_outlined, text: t.waitingOwnerConfirm),
            const SizedBox(height: 8),
            if (_token != null)
              SizedBox(height: 52, child: FilledButton(onPressed: () => context.go('/s/$_token'), child: Text(t.goToHome))),
          ],
        ),
      ),
    );
  }
}
