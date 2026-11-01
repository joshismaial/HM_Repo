import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderAbstractViewport;
import 'package:flutter/services.dart';

import '../../core/back_nav.dart';
import '../../core/errors.dart';
import '../../core/format.dart';
import '../../data/owner_repo.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import 'hostel_scope.dart';
import 'rooms_screen.dart';
import '../../widgets/room_pickers.dart';

/// Hostel settings: details, accepting students, rent day, notice period, payment options,
/// amenities and house rules.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.hostelId});
  final String hostelId;

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(t.hostelSettings),
        leading: const AppBackButton(),
      ),
      body: Loader<Json>(
        load: () => OwnerRepo.instance.hostel(hostelId),
        builder: (context, h, _) => _SettingsForm(hostel: h),
      ),
    );
  }
}

class _SettingsForm extends StatefulWidget {
  const _SettingsForm({required this.hostel});
  final Json hostel;

  @override
  State<_SettingsForm> createState() => _SettingsFormState();
}

class _SettingsFormState extends State<_SettingsForm> with WidgetsBindingObserver {
  late final Json h = widget.hostel;
  // Hostel details (owner only)
  late String _name = (h['name'] as String?) ?? '';
  late String _address = (h['address'] as String?) ?? '';
  late String _city = (h['city'] as String?) ?? '';
  late String _pincode = (h['pincode'] as String?) ?? '';
  late String _contact = (h['contact_phone'] as String?) ?? '';
  late bool _open = h['is_open'] == true;
  // Add room (draft until Save)
  int? _newFloor;
  final _newRoom = TextEditingController();
  int? _newSharing;
  Future<void> Function()? _reloadRooms;
  // rent per sharing, deposit, rent date, notice
  // Rent per bed lines (saved at once on every change)
  late final List<Json> _prices = [
    for (final p in (h['sharing_prices'] as List? ?? const [])) {'sharing': asInt((p as Map)['sharing']), 'rent': asInt(p['rent'])},
  ];
  late bool _depositOn = h['deposit_on'] != false;
  late int _depositAmount = asInt(h['deposit_amount']);
  late String _rentMode = h['rent_day_mode'] as String? ?? 'fixed_day';
  late int _fixedDay = asInt(h['rent_fixed_day']).clamp(1, 28);
  late int _notice = asInt(h['notice_days']);
  // Wi-Fi lines: floor + password
  late final List<Json> _wifi = [
    for (final w in (h['wifi'] as List? ?? const []))
      if ((w as Map)['floor'] is num) {'floor': asInt(w['floor']), 'password': (w['password'] as String?) ?? '', 'name': (w['name'] as String?) ?? ''},
  ];
  // One setting open at a time. Its values are a draft until Save; _openSnap = how it looked when opened.
  String? _openKey;
  String _openSnap = '';
  bool _grid = false; // Rent date: 1–28 grid shown
  final Map<String, GlobalKey> _cardKeys = {}; // to place the opened setting on screen
  double _lastInset = 0; // keyboard height last seen
  Timer? _revealTimer;
  bool _busy = false;
  // "Your changes are saved" over one setting for 1½ seconds
  String? _savedKey;
  String _savedSub = '';
  Timer? _savedTimer;
  // prices as last saved (Change room details uses these)
  late List<Json> _savedPrices = [for (final p in _prices) Json.from(p)];
  // day-wise stay, extra charges
  late bool _dayWise = h['day_wise_on'] == true;
  late int _perDay = asInt(h['per_day_rent']);
  late final List<Json> _charges = [
    for (final c in (h['extra_charges'] as List? ?? const [])) Json.from(c as Map),
  ];
  // payment options
  late bool _upi = h['accept_upi'] == true;
  late bool _gpay = h['accept_gpay'] == true;
  late bool _phonepe = h['accept_phonepe'] == true;
  late bool _paytm = h['accept_paytm'] == true;
  late bool _bankOn = h['accept_bank'] == true;
  late bool _cash = h['accept_cash'] == true;
  late bool _online = h['accept_online'] == true; // Instant online pay (Razorpay) – students see it only when on
  // late fee (moved here from the Rent tab, 20 Oct 2026)
  late bool _lateOn = h['late_fee_on'] == true;
  late int _latePer = asInt(h['late_fee_per_day']);
  late String _upiId = (h['upi_id'] as String?) ?? '';
  late final String? _upiName = h['upi_payee_name'] as String?;
  late String _bank = (h['bank_details'] as String?) ?? '';
  late final _cashNote = TextEditingController(text: h['cash_note'] as String?);
  // amenities and house rules (unchanged, at the bottom)
  late final _rules = TextEditingController(text: h['house_rules'] as String?);
  late final Set<String> _amenities = {...((h['amenities'] as List?) ?? const []).cast<String>()};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  /// Keyboard height in logical pixels (read from the window: the page itself is already made shorter).
  double get _keyboard {
    final v = View.of(context);
    return v.viewInsets.bottom / v.devicePixelRatio;
  }

  /// The keyboard opened or closed: when it opens, put the open setting just above it again.
  @override
  void didChangeMetrics() {
    if (!mounted) return;
    final inset = _keyboard;
    final opened = inset > _lastInset;
    _lastInset = inset;
    if (!opened || _openKey == null) return;
    _revealTimer?.cancel();
    _revealTimer = Timer(const Duration(milliseconds: 350), () {
      if (mounted && _openKey != null) _reveal(_openKey!);
    });
  }

  @override
  void dispose() {
    _newRoom.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _revealTimer?.cancel();
    _savedTimer?.cancel();
    _cashNote.dispose();
    _rules.dispose();
    _newRule.dispose();
    super.dispose();
  }

  String? _nn(String? v) => (v ?? '').trim().isEmpty ? null : v!.trim();

  // House rules are kept one per line in _rules (so "Don't save" works as before).
  final _newRule = TextEditingController();
  List<String> get _ruleLines =>
      _rules.text.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
  void _setRules(List<String> lines) => _rules.text = lines.join('\n');
  void _addRule(String text) {
    final v = text.trim();
    if (v.isEmpty || _ruleLines.length >= 30) return;
    setState(() {
      _setRules([..._ruleLines, v]);
      _newRule.clear();
    });
  }
  String _floorName(int f) => f == 0 ? context.l10n.groundShort : context.l10n.floorN('$f');

  // ---------------------------------------------------------------- one setting at a time, Save per setting

  List<Json> _copyList(List<Json> l) => [for (final x in l) Json.from(x)];

  /// The values of one setting (to see if something changed, and to undo with "Don't save").
  Json _values(String key) => switch (key) {
        'rpb' => {'prices': _prices},
        'dep' => {'on': _depositOn, 'amount': _depositAmount},
        'rd' => {'mode': _rentMode, 'day': _fixedDay},
        'wf' => {'wifi': _wifi},
        'dw' => {'on': _dayWise, 'per': _perDay},
        'ec' => {'charges': _charges},
        'po' => {
            'upi': _upi, 'upiId': _upiId, 'gpay': _gpay, 'phonepe': _phonepe, 'paytm': _paytm,
            'bank': _bankOn, 'bankText': _bank, 'cash': _cash, 'cashNote': _cashNote.text, 'online': _online,
          },
        'am' => {'list': (_amenities.toList()..sort())},
        'hd' => {'name': _name, 'address': _address, 'city': _city, 'pincode': _pincode, 'contact': _contact, 'open': _open},
        'add' => {'floor': _newFloor, 'room': _newRoom.text, 'sharing': _newSharing},
        'np' => {'days': _notice},
        'lf' => {'on': _lateOn, 'per': _latePer},
        'hr' => {'rules': _ruleLines.join('\n')},
        _ => const {},
      };

  String _snap(String key) => jsonEncode(_values(key));

  bool get _dirty => _openKey != null && _snap(_openKey!) != _openSnap;

  /// "Don't save": put the open setting back the way it was.
  void _restore(String key, String snap) {
    final v = jsonDecode(snap) as Map<String, dynamic>;
    List<Json> list(String k) => [for (final x in (v[k] as List)) Json.from(x as Map)];
    switch (key) {
      case 'rpb':
        _prices..clear()..addAll(list('prices'));
      case 'dep':
        _depositOn = v['on'] as bool;
        _depositAmount = v['amount'] as int;
      case 'rd':
        _rentMode = v['mode'] as String;
        _fixedDay = v['day'] as int;
      case 'wf':
        _wifi..clear()..addAll(list('wifi'));
      case 'dw':
        _dayWise = v['on'] as bool;
        _perDay = v['per'] as int;
      case 'ec':
        _charges..clear()..addAll(list('charges'));
      case 'po':
        _upi = v['upi'] as bool;
        _upiId = v['upiId'] as String;
        _gpay = v['gpay'] as bool;
        _phonepe = v['phonepe'] as bool;
        _paytm = v['paytm'] as bool;
        _bankOn = v['bank'] as bool;
        _bank = v['bankText'] as String;
        _cash = v['cash'] as bool;
        _cashNote.text = v['cashNote'] as String;
        _online = v['online'] as bool;
      case 'am':
        _amenities..clear()..addAll((v['list'] as List).cast<String>());
      case 'hr':
        _rules.text = v['rules'] as String;
      case 'hd':
        _name = v['name'] as String;
        _address = v['address'] as String;
        _city = v['city'] as String;
        _pincode = v['pincode'] as String;
        _contact = v['contact'] as String;
        _open = v['open'] as bool;
      case 'add':
        _newFloor = v['floor'] as int?;
        _newRoom.text = v['room'] as String;
        _newSharing = v['sharing'] as int?;
      case 'np':
        _notice = v['days'] as int;
      case 'lf':
        _lateOn = v['on'] as bool;
        _latePer = v['per'] as int;
    }
  }

  /// Before leaving the open setting: if something changed, ask "Save changes?". Returns false to stay.
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
            const SizedBox(height: 6),
            Text(t.saveChangesText, style: const TextStyle(color: AppColors.muted)),
            const SizedBox(height: 16),
            SizedBox(height: 50, child: FilledButton(onPressed: () => Navigator.pop(ctx, 'save'), child: Text(t.save))),
            const SizedBox(height: 6),
            TextButton(onPressed: () => Navigator.pop(ctx, 'drop'), child: Text(t.dontSave)),
          ]),
        ),
      ),
    );
    if (!mounted || choice == null) return false;
    if (choice == 'save') return _saveSection();
    setState(() => _restore(_openKey!, _openSnap));
    return true;
  }

  Future<void> _toggle(String key) async {
    if (!await _leave()) return;
    setState(() {
      if (_openKey == key) {
        _openKey = null;
      } else {
        _openKey = key;
        _openSnap = _snap(key);
        _grid = false;
      }
    });
    if (_openKey != key) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _reveal(key));
  }

  /// Places the opened setting: whole, just above the keyboard with a small gap. Without the keyboard
  /// the page moves only if the setting doesn't fit. Too tall to fit → its title goes to the top.
  void _reveal(String key) {
    final c = _cardKeys[key]?.currentContext;
    if (c == null || !c.mounted) return;
    final ro = c.findRenderObject();
    final pos = Scrollable.maybeOf(c)?.position;
    if (ro is! RenderBox || pos == null) return;
    final viewport = RenderAbstractViewport.maybeOf(ro);
    if (viewport == null) return;
    const gap = 16.0; // + the 8 below every setting ≈ one finger of space
    final keyboardUp = _keyboard > 0;
    final topAt = viewport.getOffsetToReveal(ro, 0).offset; // scroll that puts the title at the top
    final bottomAt = viewport.getOffsetToReveal(ro, 1).offset; // scroll that puts the end at the bottom
    final double target;
    if (ro.size.height + gap > pos.viewportDimension) {
      target = topAt - 4;
    } else if (!keyboardUp && pos.pixels >= bottomAt + gap && pos.pixels <= topAt) {
      return; // already fully visible
    } else {
      target = bottomAt + gap;
    }
    pos.animateTo(target.clamp(pos.minScrollExtent, pos.maxScrollExtent), duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  }


  /// What is missing in the open setting, or null when it can be saved.
  String? _problem(String key) {
    final t = context.l10n;
    switch (key) {
      case 'dep':
        if (_depositOn && _depositAmount <= 0) return '${t.advanceDeposit}: ${t.errAmount}';
      case 'dw':
        if (_dayWise && _perDay <= 0) return '${t.pricePerDay}: ${t.errAmount}';
      case 'hd':
        if (_name.trim().length < 2) return '${t.hostelName}: ${t.required}';
        if (_address.trim().length < 5) return '${t.address}: ${t.required}';
        if (_city.trim().length < 2) return '${t.city}: ${t.required}';
        if (!RegExp(r'^[1-9][0-9]{5}$').hasMatch(_pincode.trim())) return t.errBadPincode;
        if (!RegExp(r'^\+91[6-9][0-9]{9}$').hasMatch(_contact.trim())) return t.errBadPhone;
      case 'add':
        final no = _newRoom.text.trim().toUpperCase();
        if (_newFloor == null) return t.pickFloor;
        if (no.isEmpty) return t.typeRoomNumber;
        if (_newFloor == 0 && !isGroundRoom(no)) return t.errGroundRoomNeedsG;
        if (_newFloor != 0 && startsWithG(no)) return t.errGRoomNotGround;
        if (_newSharing == null) return t.pickSharing;
        if (_priceOf(_newSharing!) == null) return t.addSharingPriceFirst('$_newSharing');
      case 'np':
        if (_notice < 1 || _notice > 90) return t.noticeDaysRange;
      case 'lf':
        if (_lateOn && (_latePer <= 0 || _latePer > 10000)) return '${t.lateFeeTitle}: ${t.errAmount}';
      case 'po':
        if (!_upi && !_bankOn && !_cash) return t.errNoPaymentOption;
        if (_upi && !RegExp(r'^[A-Za-z0-9._-]{2,128}@[A-Za-z]{2,64}$').hasMatch(_upiId.trim())) return t.errBadUpi;
        if (_bankOn && _bank.trim().isEmpty) return '${t.bankDetails}: ${t.required}';
    }
    return null;
  }

  String _subFor(String key) {
    final t = context.l10n;
    return switch (key) {
      'rpb' => '${t.rentPerBedTitle} · ${t.nSharings('${_prices.length}')}',
      'dep' => _depositOn ? '${t.advanceDeposit} · ${money(_depositAmount)}' : t.advanceDeposit,
      'rd' => _rentMode == 'joining_date' ? '${t.rentDate} · ${t.joiningDateShort}' : '${t.rentDate} · ${_dayText(_fixedDay)}',
      'wf' => '${t.wifiTitle} · ${t.nFloors('${_wifi.length}')}',
      'dw' => _dayWise ? '${t.allowDayWise} · ${t.perDayPrice(money(_perDay))}' : t.allowDayWise,
      'ec' => t.extraCharges,
      'po' => t.paymentOptions,
      'am' => t.amenities,
      'hr' => t.houseRules,
      'hd' => t.hostelDetails,
      'add' => '${t.room} ${_newRoom.text.trim().toUpperCase()} · ${t.sharingN('${_newSharing ?? ''}')}',
      'np' => '${t.noticePeriod} · ${t.daysN('$_notice')}',
      'lf' => _lateOn ? '${t.lateFeeTitle} · ${t.lateFeePerDay(money(_latePer))}' : t.lateFeeOff,
      _ => '',
    };
  }

  /// Save button of the open setting. Shows "Your changes are saved" over it for 1½ seconds.
  Future<bool> _saveSection() async {
    final key = _openKey;
    if (key == null || _busy) return false;
    final problem = _problem(key);
    if (problem != null) {
      showSnack(context, problem, error: true);
      return false;
    }
    // Rent date: ask first when students are staying
    if (key == 'rd' && _openSnap != _snap('rd')) {
      final old = jsonDecode(_openSnap) as Map<String, dynamic>;
      if (!await _confirmRentDate(old['mode'] as String, old['day'] as int)) return false;
    }
    final sub = _subFor(key);
    setState(() => _busy = true);
    try {
      final id = h['id'] as String;
      switch (key) {
        case 'rd':
          await OwnerRepo.instance.changeRentDay(id, mode: _rentMode, fixedDay: _fixedDay);
          if (mounted) HostelScope.read(context).refresh();
        case 'np':
          await OwnerRepo.instance.setNoticeDays(id, _notice);
          if (mounted) HostelScope.read(context).refresh();
        case 'lf':
          await OwnerRepo.instance.setLateFee(id, on: _lateOn, perDay: _latePer);
          if (mounted) HostelScope.read(context).refresh();
        case 'add':
          // the rent comes from Sharing + price
          await OwnerRepo.instance.addRoomSimple(id,
              floor: _newFloor!, roomNo: _newRoom.text.trim(), sharing: _newSharing!, rent: _priceOf(_newSharing!)!);
          _newFloor = null;
          _newRoom.clear();
          _newSharing = null;
          await _reloadRooms?.call();
        default:
          await _save();
      }
    } catch (e) {
      if (mounted) showSnack(context, errorText(context, e), error: true);
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return false;
    setState(() {
      if (key == 'rpb') _savedPrices = _copyList(_prices);
      _openSnap = _snap(key);
    });
    _showSaved(key, sub);
    return true;
  }

  /// Grey cover "Your changes are saved · <sub>" over setting [key] for 1½ seconds.
  void _showSaved(String key, String sub) {
    _savedTimer?.cancel();
    setState(() {
      _savedKey = key;
      _savedSub = sub;
    });
    _savedTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _savedKey = null);
    });
  }

  /// "Fee date: 5th → 10th" sheet: what happens to the students' fees. Returns true for "Yes, change".
  Future<bool> _confirmRentDate(String oldMode, int oldDay) async {
    final t = context.l10n;
    int staying;
    try {
      staying = await OwnerRepo.instance.stayingCount(h['id'] as String);
    } catch (_) {
      staying = 0;
    }
    if (staying == 0 || !mounted) return true;
    String name(String mode, int day) => mode == 'joining_date' ? t.joiningDateShort : _dayText(day);
    final ok = await showModalBottomSheet<bool>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(t.feeDateFromTo(name(oldMode, oldDay), name(_rentMode, _fixedDay)),
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            _infoBox(t.feeDateChangeInfo('$staying')),
            const SizedBox(height: 16),
            SizedBox(height: 50, child: FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t.yesChange))),
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t.cancel)),
          ]),
        ),
      ),
    );
    return ok == true;
  }

  Widget _infoBox(String text) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF7E6),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFF5D38A)),
        ),
        child: Text(text, style: const TextStyle(fontSize: 14, height: 1.45)),
      );

  /// Sends every setting (only the open one can have changes).
  Future<void> _save() async {
    final id = h['id'] as String;
    _prices.sort((a, b) => asInt(a['sharing']).compareTo(asInt(b['sharing'])));
    _wifi.sort((a, b) => asInt(a['floor']).compareTo(asInt(b['floor'])));
    await OwnerRepo.instance.updateHostel(id, {
      'name': _name.trim(),
      'address': _address.trim(),
      'city': _city.trim(),
      'pincode': _pincode.trim(),
      'contact_phone': _contact.trim(),
      'is_open': _open,
      'wifi': [
        for (final w in _wifi)
          if ((w['password'] as String).trim().isNotEmpty) {'floor': w['floor'], 'name': w['name'] ?? '', 'password': (w['password'] as String).trim()},
      ],
      'extra_charges': _charges,
      'accept_upi': _upi,
      'upi_id': _nn(_upiId),
      'upi_payee_name': _upiName,
      'accept_gpay': _upi && _gpay,
      'accept_phonepe': _upi && _phonepe,
      'accept_paytm': _upi && _paytm,
      'accept_bank': _bankOn,
      'bank_details': _nn(_bank),
      'accept_cash': _cash,
      'accept_online': _online,
      'cash_note': _nn(_cashNote.text),
      'amenities': _amenities.toList(),
      'house_rules': _nn(_ruleLines.join('\n')),
    });
    await OwnerRepo.instance.saveHostelPrices(id,
        prices: _prices, depositOn: _depositOn, depositAmount: _depositAmount, dayWiseOn: _dayWise, perDay: _perDay);
    if (mounted) HostelScope.read(context).refresh();
  }

  /// "+ Add …" on the left (optional), Save on the right.
  Widget _foot([Widget? left]) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(children: [
          if (left != null) left,
          const Spacer(),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44), padding: const EdgeInsets.symmetric(horizontal: 26)),
            onPressed: _busy ? null : _saveSection,
            child: Text(context.l10n.save, style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        ]),
      );

  String _dayText(int d) {
    if (Localizations.localeOf(context).languageCode != 'en') return '$d';
    final suffix = (d % 100 >= 11 && d % 100 <= 13) ? 'th' : const {1: 'st', 2: 'nd', 3: 'rd'}[d % 10] ?? 'th';
    return '$d$suffix';
  }

  Widget _removeBtn(VoidCallback onTap) => SizedBox(
        width: 46,
        height: 48,
        child: Material(
          color: const Color(0xFFFFF5F5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: Color(0xFFF3C4C4))),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: Tooltip(message: context.l10n.delete, child: const Icon(Icons.close_rounded, color: AppColors.danger)),
          ),
        ),
      );

  /// The empty line [A ✎] [B ✎] [✕] shown when a list is empty; tapping a box opens the add sheet.
  Widget _blankLine(String aHint, String bHint, VoidCallback onAdd) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [
          _penBox(aHint, onAdd, muted: true),
          const SizedBox(width: 8),
          _penBox(bHint, onAdd, muted: true),
          const SizedBox(width: 8),
          _removeBtn(() {}),
        ]),
      );

  Future<void> _addPrice() async {
    final added = await _addSharingSheet();
    if (added == null) return;
    setState(() => _prices
      ..add(added)
      ..sort((a, b) => asInt(a['sharing']).compareTo(asInt(b['sharing']))));
  }

  Future<void> _addWifi() async {
    final t = context.l10n;
    final row = await _addWifiSheet();
    if (row == null || !mounted) return;
    if (_wifi.any((w) => asInt(w['floor']) == asInt(row['floor']))) {
      showSnack(context, t.wifiFloorExists(_floorName(asInt(row['floor']))), error: true);
      return;
    }
    setState(() => _wifi
      ..add(row)
      ..sort((a, b) => asInt(a['floor']).compareTo(asInt(b['floor']))));
  }

  Widget _colLabels(String a, String b, {bool removeCol = false}) => Padding(
        padding: const EdgeInsets.only(left: 2, bottom: 3),
        child: Row(children: [
          Expanded(child: Text(a, style: const TextStyle(color: AppColors.muted, fontSize: 11))),
          const SizedBox(width: 8),
          Expanded(child: Text(b, style: const TextStyle(color: AppColors.muted, fontSize: 11))),
          if (removeCol) const SizedBox(width: 54),
        ]),
      );

  // ---------------------------------------------------------------- small pieces

  /// Bottom sheet with one field and Save. Returns the new value (text or number).
  /// [rupee]: show ₹ before a number (off for floor, days, pincode, phone). [allowZero]: 0 is fine (Ground floor).
  Future<String?> _editValue({required String title, String? sub, String? initial, bool number = false, String? hint, bool rupee = true, bool allowZero = false}) {
    final t = context.l10n;
    final c = TextEditingController(text: initial ?? '');
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          if (sub != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(sub, style: const TextStyle(color: AppColors.muted))),
          const SizedBox(height: 14),
          TextField(
            controller: c,
            autofocus: true,
            keyboardType: number ? TextInputType.number : TextInputType.text,
            inputFormatters: number ? [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(rupee ? 6 : 10)] : null,
            maxLines: number ? 1 : null,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            decoration: InputDecoration(prefixText: number && rupee ? '₹ ' : null, hintText: hint),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 50,
            child: FilledButton(
              onPressed: () {
                final v = c.text.trim();
                if (v.isEmpty || (number && (int.tryParse(v) ?? 0) < (allowZero ? 0 : 1))) {
                  showSnack(ctx, number && rupee ? t.errAmount : t.cantBeEmpty, error: true);
                  return;
                }
                Navigator.pop(ctx, v);
              },
              child: Text(t.save),
            ),
          ),
        ]),
      ),
    ).whenComplete(c.dispose);
  }

  Future<int?> _pickSharing(int? current) {
    final t = context.l10n;
    final taken = _prices.map((p) => asInt(p['sharing'])).toSet();
    int? n = current;
    return showModalBottomSheet<int>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(t.sharing, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            Text(t.sharingSheetHelp, style: const TextStyle(color: AppColors.muted)),
            const SizedBox(height: 12),
            SharingPicker(
              value: n,
              onChanged: (x) {
                if (taken.contains(x) && x != current) {
                  showSnack(ctx, t.sharingAlreadyPriced('$x'), error: true);
                  return;
                }
                setSheet(() => n = x);
              },
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 50,
              child: FilledButton(
                onPressed: () {
                  if (n == null) {
                    showSnack(ctx, t.pickSharing, error: true);
                  } else {
                    Navigator.pop(ctx, n);
                  }
                },
                child: Text(t.save),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Future<int?> _pickFloor(int? current) {
    final t = context.l10n;
    int? f = current;
    return showModalBottomSheet<int>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(t.whichFloor, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            FloorPicker(value: f, onChanged: (x) => setSheet(() => f = x)),
            const SizedBox(height: 14),
            SizedBox(
              height: 50,
              child: FilledButton(
                onPressed: () {
                  if (f == null) {
                    showSnack(ctx, t.pickFloor, error: true);
                  } else {
                    Navigator.pop(ctx, f);
                  }
                },
                child: Text(t.save),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _addCharge() async {
    final t = context.l10n;
    final name = TextEditingController();
    final amount = TextEditingController();
    var per = 'month';
    final added = await showModalBottomSheet<Json>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(t.addAnotherCharge, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 14),
            TextField(
              controller: name,
              textCapitalization: TextCapitalization.sentences,
              inputFormatters: [LengthLimitingTextInputFormatter(40)],
              decoration: InputDecoration(labelText: t.nameOfService),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: amount,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
              decoration: InputDecoration(labelText: t.amountLabel, prefixText: '₹ '),
            ),
            const SizedBox(height: 12),
            Text(t.howOften, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            SegmentedButton<String>(
              segments: [
                ButtonSegment(value: 'day', label: Text(t.everyDay)),
                ButtonSegment(value: 'month', label: Text(t.everyMonth)),
                ButtonSegment(value: 'once', label: Text(t.oneTimeOption)),
              ],
              selected: {per},
              onSelectionChanged: (v) => setSheet(() => per = v.first),
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 50,
              child: FilledButton(
                onPressed: () {
                  if (name.text.trim().length < 2) {
                    showSnack(ctx, t.enterServiceName, error: true);
                    return;
                  }
                  final a = int.tryParse(amount.text) ?? 0;
                  if (a <= 0) {
                    showSnack(ctx, t.errAmount, error: true);
                    return;
                  }
                  Navigator.pop(ctx, {'kind': 'custom', 'name': name.text.trim(), 'amount': a, 'per': per, 'on': true});
                },
                child: Text(t.saveCharge),
              ),
            ),
          ]),
        ),
      ),
    );
    name.dispose();
    amount.dispose();
    if (added == null) return;
    setState(() => _charges.add(added));
  }

  /// "+ Add sharing": how many beds and the rent per bed, saved together.
  Future<Json?> _addSharingSheet() {
    final t = context.l10n;
    final taken = _prices.map((p) => asInt(p['sharing'])).toSet();
    final rent = TextEditingController();
    int? n;
    return showModalBottomSheet<Json>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(t.addSharing, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            Text(t.sharingSheetHelp, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            SharingPicker(
              value: n,
              onChanged: (x) {
                if (taken.contains(x)) {
                  showSnack(ctx, t.sharingAlreadyPriced('$x'), error: true);
                } else {
                  setSheet(() => n = x);
                }
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: rent,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
              decoration: InputDecoration(labelText: t.perBedEveryMonth, prefixText: '₹ '),
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 50,
              child: FilledButton(
                onPressed: () {
                  final r = int.tryParse(rent.text) ?? 0;
                  if (n == null) {
                    showSnack(ctx, t.pickSharing, error: true);
                  } else if (r <= 0) {
                    showSnack(ctx, t.errAmount, error: true);
                  } else {
                    Navigator.pop(ctx, {'sharing': n, 'rent': r});
                  }
                },
                child: Text(t.addLine),
              ),
            ),
          ]),
        ),
      ),
    ).whenComplete(rent.dispose);
  }

  /// "+ Add Wi-Fi": floor and password together; the row is added only after Save.
  Future<Json?> _addWifiSheet() {
    final t = context.l10n;
    final pw = TextEditingController();
    int? f;
    return showModalBottomSheet<Json>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(t.addWifi, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            Text(t.floor, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            FloorPicker(value: f, onChanged: (x) => setSheet(() => f = x)),
            const SizedBox(height: 12),
            TextField(
              controller: pw,
              inputFormatters: [LengthLimitingTextInputFormatter(60)],
              decoration: InputDecoration(labelText: t.password),
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 50,
              child: FilledButton(
                onPressed: () {
                  if (f == null) {
                    showSnack(ctx, t.pickFloor, error: true);
                  } else if (pw.text.trim().isEmpty) {
                    showSnack(ctx, t.typePassword, error: true);
                  } else {
                    Navigator.pop(ctx, {'floor': f, 'password': pw.text.trim(), 'name': ''});
                  }
                },
                child: Text(t.addLine),
              ),
            ),
          ]),
        ),
      ),
    ).whenComplete(pw.dispose);
  }

  Future<void> _changePassword() async {
    final t = context.l10n;
    final a = TextEditingController();
    final b = TextEditingController();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(t.changePassword, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 14),
          PasswordField(controller: a, label: t.newPassword, checkStrength: true),
          const SizedBox(height: 10),
          PasswordField(controller: b, label: t.typeAgain),
          const SizedBox(height: 14),
          SizedBox(
            height: 50,
            child: BusyButton(
              label: t.savePassword,
              onPressed: () async {
                if (a.text.length < 8) {
                  showSnack(ctx, t.errWeakPassword, error: true);
                  return;
                }
                if (a.text != b.text) {
                  showSnack(ctx, t.passwordsDiffer, error: true);
                  return;
                }
                await OwnerRepo.instance.setPassword(a.text);
                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) showSnack(context, t.passwordSaved);
              },
            ),
          ),
        ]),
      ),
    );
    a.dispose();
    b.dispose();
  }

  Widget _penBox(String text, VoidCallback onTap, {bool muted = false}) => Expanded(
        child: Opacity(
          opacity: muted ? 0.45 : 1,
          child: Material(
            color: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: AppColors.field)),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
                child: Row(children: [
                  Expanded(child: Text(text, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14), overflow: TextOverflow.ellipsis)),
                  const Icon(Icons.edit_rounded, size: 18, color: AppColors.primary),
                ]),
              ),
            ),
          ),
        ),
      );

  /// A setting shown as one line with a down arrow; only one is open at a time.
  Widget _card(String key, IconData icon, String title, Widget Function() body) {
    final open = _openKey == key;
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
            onTap: () => _toggle(key),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 8, 14),
              child: Row(children: [
                Icon(icon, color: AppColors.primary, size: 24),
                const SizedBox(width: 8),
                Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
                Icon(open ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded, color: AppColors.primary, size: 28),
              ]),
            ),
          ),
          if (open) Padding(padding: const EdgeInsets.fromLTRB(14, 0, 14, 14), child: body()),
        ]),
      ),
    );
    return Padding(
      key: _cardKeys.putIfAbsent(key, () => GlobalKey()),
      padding: const EdgeInsets.only(bottom: 8),
      child: _savedKey == key ? Stack(children: [card, Positioned.fill(child: SavedCover(sub: _savedSub))]) : card,
    );
  }

  /// "+ Add …"; greyed and not tappable when [onTap] is null.
  Widget _addLink(String label, VoidCallback? onTap) =>
      TextButton.icon(onPressed: onTap, icon: const Icon(Icons.add_circle_outline_rounded), label: Text(label));

  Widget _switchRow(IconData icon, String label, bool value, ValueChanged<bool> onChanged, {bool enabled = true}) => Opacity(
        opacity: enabled ? 1 : 0.45,
        child: Row(children: [
          Icon(icon, color: AppColors.primary, size: 21),
          const SizedBox(width: 10),
          Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600))),
          Switch(value: value, onChanged: onChanged),
        ]),
      );

  String _per(String? p) {
    final t = context.l10n;
    return switch (p) { 'unit' => t.perUnit, 'once' => t.oneTime, 'day' => t.perDayCharge, _ => t.perMonth };
  }

  String _chargeName(Json c) {
    final t = context.l10n;
    return switch (c['kind']) {
      'electricity' => t.chargeElectricity,
      'laundry' => t.chargeLaundry,
      _ => (c['name'] as String?) ?? '',
    };
  }

  // ---------------------------------------------------------------- page

  /// Hostel details (owner only): name, address, city, pincode, contact number, open for new students.
  Widget _hostelDetails() {
    final t = context.l10n;
    Widget line(String label, String value, Future<void> Function() onTap) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.only(left: 2, bottom: 3),
              child: Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 11)),
            ),
            Row(children: [_penBox(value, () => onTap())]),
          ]),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      line(t.hostelName, _name, () async {
        final v = await _editValue(title: t.hostelName, initial: _name);
        if (v != null) setState(() => _name = v);
      }),
      line(t.address, _address, () async {
        final v = await _editValue(title: t.address, initial: _address);
        if (v != null) setState(() => _address = v);
      }),
      line(t.city, _city, () async {
        final v = await _editValue(title: t.city, initial: _city);
        if (v != null) setState(() => _city = v);
      }),
      line(t.pincode, _pincode, () async {
        final v = await _editValue(title: t.pincode, initial: _pincode, number: true, rupee: false);
        if (v != null) setState(() => _pincode = v);
      }),
      line(t.mobileNumber, _contact.replaceFirst('+91', '+91 '), () async {
        final v = await _editValue(title: t.mobileNumber, initial: _contact.replaceFirst('+91', ''), number: true, rupee: false);
        if (v != null) setState(() => _contact = '+91${v.replaceAll(RegExp(r'\D'), '')}');
      }),
      _onOffRow(t.openForJoins, _open, (v) => setState(() => _open = v)),
      _foot(),
    ]);
  }

  /// Saved price of a sharing (Sharing + price), or null.
  int? _priceOf(int sharing) {
    for (final p in _savedPrices) {
      if (asInt(p['sharing']) == sharing) return asInt(p['rent']);
    }
    return null;
  }

  /// Add room: [Floor  box ✎] and [Room number  box] side by side with their names, then Sharing and Save.
  /// The rent comes from Sharing + price (no price box here).
  Widget _addRoom() {
    final t = context.l10n;
    Widget labelled(String label, Widget box) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(children: [
            SizedBox(width: 120, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600))),
            box,
          ]),
        );
    final price = _newSharing == null ? null : _priceOf(_newSharing!);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      labelled(
        t.floor,
        _penBox(_newFloor == null ? '—' : (_newFloor == 0 ? t.groundShort : '$_newFloor'), () async {
          final v = await _editValue(title: t.floor, sub: t.floorNumberHelp, initial: _newFloor == null ? '' : '$_newFloor', number: true, rupee: false, allowZero: true);
          if (v == null) return;
          final f = int.parse(v);
          if (f > maxFloor) {
            if (mounted) showSnack(context, t.floorNumberHelp, error: true);
            return;
          }
          setState(() {
            _newFloor = f;
            final no = _newRoom.text.trim().toUpperCase();
            if (f == 0 && !startsWithG(no)) _newRoom.text = 'G${_newRoom.text.trim()}';
            if (f != 0 && startsWithG(no)) _newRoom.text = _newRoom.text.trim().substring(1);
          });
        }, muted: _newFloor == null),
      ),
      labelled(
        t.roomNumber,
        Expanded(
          child: TextField(
            controller: _newRoom,
            textCapitalization: TextCapitalization.characters,
            inputFormatters: [LengthLimitingTextInputFormatter(8)],
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            decoration: InputDecoration(hintText: _newFloor == 0 ? 'G1' : '305'),
            onChanged: (v) {
              if (startsWithG(v) && _newFloor != 0) setState(() => _newFloor = 0);
            },
          ),
        ),
      ),
      Text(t.sharing, style: const TextStyle(fontWeight: FontWeight.w600)),
      const SizedBox(height: 6),
      SharingPicker(value: _newSharing, onChanged: (n) => setState(() => _newSharing = n)),
      if (_newSharing != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            price == null ? t.addSharingPriceFirst('$_newSharing') : t.rentFromPrices(money(price)),
            style: TextStyle(color: price == null ? AppColors.danger : AppColors.muted, fontSize: 12.5),
          ),
        ),
      _foot(),
    ]);
  }

  Widget _onOffRow(String label, bool value, ValueChanged<bool> onChanged) => Row(children: [
        Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600))),
        Switch(value: value, onChanged: onChanged),
      ]);

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    final canAddSharing = _prices.length < maxSharing;
    return PageList(
      children: [
        // ---- Rooms & beds: counts + Change room details
        // ---- Rooms & beds counts, then "Change room details" as one more setting line
        _RoomsBlock(
          hostelId: h['id'] as String,
          roomCard: (rooms, reload) {
            _reloadRooms = reload;
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _card('hd', Icons.home_work_outlined, t.hostelDetails, _hostelDetails),
              _card('room', Icons.edit_note_rounded, t.changeRoomDetails, () => _ChangeRoomCard(
                    rooms: rooms,
                    prices: _savedPrices,
                    onSaved: (sub) async {
                      _showSaved('room', sub);
                      await reload();
                    },
                  )),
              _card('add', Icons.add_home_outlined, t.addRoom, _addRoom),
            ]);
          },
        ),

        // ---- 1. Rent per bed: [sharing ✎] [price ✎] [✕] · + Add sharing ... Save
        _card('rpb', Icons.currency_rupee_rounded, t.rentPerBedTitle, () => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _colLabels(t.sharing, t.priceLabel, removeCol: true),
              for (final p in _prices)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(children: [
                    _penBox(t.sharingN('${p['sharing']}'), () async {
                      final n = await _pickSharing(asInt(p['sharing']));
                      if (n == null) return;
                      setState(() => p['sharing'] = n);
                    }),
                    const SizedBox(width: 8),
                    _penBox(money(asInt(p['rent'])), () async {
                      final v = await _editValue(
                          title: t.rentForSharing('${p['sharing']}'), sub: t.perBedEveryMonth, initial: '${p['rent']}', number: true);
                      if (v == null) return;
                      setState(() => p['rent'] = int.parse(v));
                    }),
                    const SizedBox(width: 8),
                    _removeBtn(() => setState(() => _prices.remove(p))),
                  ]),
                ),
              if (_prices.isEmpty) _blankLine(t.sharing, '₹ ${t.priceLabel}', _addPrice),
              _foot(canAddSharing ? _addLink(t.addSharing, _prices.isEmpty ? null : _addPrice) : null),
            ])),

        // ---- 2. Advance / deposit: switch + amount ✎
        _card('dep', Icons.lock_outline_rounded, t.advanceDeposit, () => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _onOffRow(t.advanceDeposit, _depositOn, (v) => setState(() => _depositOn = v)),
              Row(children: [
                _penBox(money(_depositAmount), () async {
                  final v = await _editValue(title: t.advanceDeposit, sub: t.depositPaidOnce, initial: '$_depositAmount', number: true);
                  if (v != null) setState(() => _depositAmount = int.parse(v));
                }, muted: !_depositOn),
              ]),
              _foot(),
            ])),

        // ---- 3. Rent date: joining date / fixed date (pick 1–28 → grid closes, line + Change)
        _card('rd', Icons.calendar_month_rounded, t.rentDate, () => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SegmentedButton<String>(
                segments: [
                  ButtonSegment(value: 'joining_date', label: Text(t.joiningDateShort)),
                  ButtonSegment(value: 'fixed_day', label: Text(t.fixedDateShort)),
                ],
                selected: {_rentMode},
                onSelectionChanged: (v) => setState(() {
                  _rentMode = v.first;
                  _grid = false;
                }),
              ),
              const SizedBox(height: 10),
              if (_rentMode == 'joining_date')
                Text(t.joinedExample, style: const TextStyle(color: AppColors.muted))
              else if (_grid)
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (var d = 1; d <= 28; d++)
                    SizedBox(
                      width: 40,
                      child: ChoiceChip(
                        label: Text('$d'),
                        showCheckmark: false,
                        padding: EdgeInsets.zero,
                        labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                        selected: _fixedDay == d,
                        selectedColor: AppColors.primary,
                        labelStyle: TextStyle(color: _fixedDay == d ? Colors.white : null, fontWeight: FontWeight.w600),
                        onSelected: (_) => setState(() {
                          _fixedDay = d;
                          _grid = false; // only the line below stays
                        }),
                      ),
                    ),
                ])
              else
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: AppColors.successSoft, borderRadius: BorderRadius.circular(12)),
                  child: Row(children: [
                    Expanded(
                      child: Text(t.fixedFeeDate(_dayText(_fixedDay)),
                          style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.w600, fontSize: 14)),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                          backgroundColor: Colors.white, minimumSize: const Size(0, 36), padding: const EdgeInsets.symmetric(horizontal: 10)),
                      onPressed: () => setState(() => _grid = true),
                      icon: const Icon(Icons.edit_rounded, size: 16),
                      label: Text(t.changeLabel),
                    ),
                  ]),
                ),
              _foot(),
            ])),

        // ---- Late fee (moved from the Rent tab): on/off, ₹20 / ₹50 / ₹100 per day or type, example, Save
        _card('lf', Icons.timer_outlined, t.lateFeeTitle, () => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _onOffRow(t.chargeLateFee, _lateOn, (v) => setState(() {
                    _lateOn = v;
                    if (v && _latePer <= 0) _latePer = 50;
                  })),
              Text(t.lateFeeAfterDate, style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
              const SizedBox(height: 8),
              Opacity(
                opacity: _lateOn ? 1 : 0.45,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Wrap(spacing: 8, runSpacing: 6, children: [
                    for (final v in [20, 50, 100])
                      ChoiceChip(
                        label: Text('${money(v)} ${t.perDayShort}'),
                        selected: _latePer == v,
                        onSelected: _lateOn ? (_) => setState(() => _latePer = v) : null,
                      ),
                  ]),
                  const SizedBox(height: 8),
                  Row(children: [
                    _penBox([20, 50, 100].contains(_latePer) || _latePer <= 0 ? t.typeAmount : t.lateFeePerDay(money(_latePer)), () async {
                      if (!_lateOn) return;
                      final v = await _editValue(title: t.amountPerDay, sub: t.lateFeeAfterDate, initial: _latePer > 0 ? '$_latePer' : '', number: true);
                      if (v != null) setState(() => _latePer = int.parse(v));
                    }, muted: !_lateOn || [20, 50, 100].contains(_latePer)),
                  ]),
                  if (_lateOn && _latePer > 0) ...[
                    const SizedBox(height: 8),
                    _infoBox(t.lateFeeExample(money(8000), '3', money(_latePer), money(3 * _latePer), money(8000 + 3 * _latePer))),
                  ],
                ]),
              ),
              _foot(),
            ])),

        // ---- Notice period: 15 / 30 / 45 days or any number of days
        _card('np', Icons.hourglass_bottom_rounded, t.noticePeriod, () => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(t.noticePeriodHelp, style: const TextStyle(color: AppColors.muted)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 6, children: [
                for (final d in [15, 30, 45])
                  ChoiceChip(
                    label: Text(t.daysN('$d')),
                    selected: _notice == d,
                    onSelected: (_) => setState(() => _notice = d),
                  ),
              ]),
              const SizedBox(height: 10),
              Text(t.orTypeDays, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Row(children: [
                _penBox([15, 30, 45].contains(_notice) ? t.typeDaysHint : t.daysN('$_notice'), () async {
                  final v = await _editValue(title: t.noticePeriod, sub: t.noticeDaysRange, initial: [15, 30, 45].contains(_notice) ? '' : '$_notice', number: true, rupee: false);
                  if (v != null) setState(() => _notice = int.parse(v));
                }, muted: [15, 30, 45].contains(_notice)),
              ]),
              const SizedBox(height: 10),
              _infoBox(t.noticeStudentsTold),
              _foot(),
            ])),

        // ---- 4. Wi-Fi: [floor ✎] [password ✎] [✕] · + Add Wi-Fi ... Save
        _card('wf', Icons.wifi_rounded, t.wifiTitle, () => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _colLabels(t.floor, t.password, removeCol: true),
              for (final w in _wifi)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(children: [
                    _penBox(_floorName(asInt(w['floor'])), () async {
                      final f = await _pickFloor(asInt(w['floor']));
                      if (f == null || f == asInt(w['floor']) || !context.mounted) return;
                      if (_wifi.any((x) => asInt(x['floor']) == f)) {
                        showSnack(context, t.wifiFloorExists(_floorName(f)), error: true);
                        return;
                      }
                      setState(() => w['floor'] = f);
                    }),
                    const SizedBox(width: 8),
                    _penBox(w['password'] as String, () async {
                      final v = await _editValue(
                          title: t.wifiPasswordFor(_floorName(asInt(w['floor']))), sub: t.wifiStudentsSee, initial: w['password'] as String);
                      if (v != null) setState(() => w['password'] = v);
                    }),
                    const SizedBox(width: 8),
                    _removeBtn(() => setState(() => _wifi.remove(w))),
                  ]),
                ),
              if (_wifi.isEmpty) _blankLine(t.floor, t.password, _addWifi),
              _foot(_addLink(t.addWifi, _wifi.isEmpty ? null : _addWifi)),
            ])),

        // ---- 5. Day-wise stay: switch + price per day ✎
        _card('dw', Icons.wb_sunny_outlined, t.allowDayWise, () => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _onOffRow(t.allowDayWise, _dayWise, (v) => setState(() => _dayWise = v)),
              Row(children: [
                _penBox(t.perDayPrice(money(_perDay)), () async {
                  final v = await _editValue(title: t.pricePerDay, sub: t.pricePerDayHelp, initial: _perDay > 0 ? '$_perDay' : '', number: true);
                  if (v != null) setState(() => _perDay = int.parse(v));
                }, muted: !_dayWise),
              ]),
              _foot(),
            ])),

        // ---- 6. Extra charges: name · amount ✎ · switch, + Add another charge ... Save
        _card('ec', Icons.receipt_long_rounded, t.extraCharges, () => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (final c in _charges)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(children: [
                    Icon(
                        switch (c['kind']) {
                          'electricity' => Icons.bolt_rounded,
                          'laundry' => Icons.local_laundry_service_outlined,
                          _ => Icons.sell_outlined,
                        },
                        color: AppColors.primary,
                        size: 21),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_chargeName(c), style: const TextStyle(fontWeight: FontWeight.w600))),
                    Opacity(
                      opacity: c['on'] == true ? 1 : 0.45,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(minimumSize: const Size(0, 36), padding: const EdgeInsets.symmetric(horizontal: 10)),
                        icon: const Icon(Icons.edit_rounded, size: 16),
                        label: Text('${money(asInt(c['amount']))} ${_per(c['per'] as String?)}'),
                        onPressed: () async {
                          final v = await _editValue(
                              title: _chargeName(c),
                              sub: c['per'] == 'unit' ? t.electricityRateHelp : t.amountLabel,
                              initial: '${c['amount']}',
                              number: true);
                          if (v != null) setState(() => c['amount'] = int.parse(v));
                        },
                      ),
                    ),
                    Switch(value: c['on'] == true, onChanged: (v) => setState(() => c['on'] = v)),
                  ]),
                ),
              _foot(_addLink(t.addAnotherCharge, _addCharge)),
            ])),

        // ---- 7. Payment options: only the ones switched on show to students
        _card('po', Icons.account_balance_wallet_outlined, t.paymentOptions, () => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _switchRow(Icons.qr_code_2_rounded, t.methodUpi, _upi, (v) => setState(() => _upi = v)),
              if (_upi)
                Padding(
                  padding: const EdgeInsets.only(left: 31, bottom: 6),
                  child: Row(children: [
                    _penBox(_upiId.isEmpty ? t.upiId : _upiId, () async {
                      final v = await _editValue(title: t.upiId, sub: t.upiAppsUseThis, initial: _upiId, hint: 'name@okicici');
                      if (v != null) setState(() => _upiId = v);
                    }, muted: _upiId.isEmpty),
                  ]),
                ),
              for (final (icon, label, value, set) in [
                (Icons.g_mobiledata_rounded, t.payGpay, _gpay, (bool v) => _gpay = v),
                (Icons.phone_android_rounded, t.payPhonepe, _phonepe, (bool v) => _phonepe = v),
                (Icons.phone_android_rounded, t.payPaytm, _paytm, (bool v) => _paytm = v),
              ])
                _switchRow(icon, label, value, (v) {
                  if (_upi) {
                    setState(() => set(v));
                  } else {
                    showSnack(context, t.turnOnUpiFirst);
                  }
                }, enabled: _upi),
              _switchRow(Icons.account_balance_rounded, t.methodBank, _bankOn, (v) => setState(() => _bankOn = v)),
              if (_bankOn)
                Padding(
                  padding: const EdgeInsets.only(left: 31, bottom: 6),
                  child: Row(children: [
                    _penBox(_bank.isEmpty ? t.bankDetails : _bank.replaceAll('\n', ' · '), () async {
                      final v = await _editValue(title: t.bankDetails, sub: t.bankDetailsHint, initial: _bank);
                      if (v != null) setState(() => _bank = v);
                    }, muted: _bank.isEmpty),
                  ]),
                ),
              _switchRow(Icons.payments_outlined, t.methodCash, _cash, (v) => setState(() => _cash = v)),
              if (_cash)
                Padding(
                  padding: const EdgeInsets.only(left: 31, bottom: 6),
                  child: TextField(
                    controller: _cashNote,
                    maxLines: 3,
                    minLines: 2,
                    maxLength: 160,
                    decoration: InputDecoration(labelText: t.cashMessageLabel, hintText: t.cashNoteHint),
                  ),
                ),
              _switchRow(Icons.public_rounded, t.instantOnlinePay, _online, (v) => setState(() => _online = v)),
              Padding(
                padding: const EdgeInsets.only(left: 31, bottom: 6),
                child: Text(t.instantOnlineHelp, style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
              ),
              _foot(),
            ])),

        // ---- amenities and house rules (shown to students)
        _card('am', Icons.checklist_rounded, t.amenities, () => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Wrap(spacing: 8, runSpacing: 4, children: [
                for (final a in amenityCodes)
                  FilterChip(
                    label: Text(featureLabel(context, a)),
                    selected: _amenities.contains(a),
                    onSelected: (on) => setState(() => on ? _amenities.add(a) : _amenities.remove(a)),
                  ),
              ]),
              _foot(),
            ])),
        // ---- House rules: one line per rule (✎ edit, ✕ delete), type a rule + Add, quick-add chips.
        // Students see them in Settings → House rules.
        _card('hr', Icons.rule_rounded, t.houseRules, () => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (_ruleLines.isEmpty)
                Text(t.noRulesYet, style: const TextStyle(color: AppColors.muted))
              else
                for (var i = 0; i < _ruleLines.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(children: [
                      _penBox('${i + 1}. ${_ruleLines[i]}', () async {
                        final v = await _editValue(title: t.editRule, initial: _ruleLines[i]);
                        if (v != null) setState(() => _setRules([..._ruleLines]..[i] = v));
                      }),
                      const SizedBox(width: 8),
                      _removeBtn(() => setState(() => _setRules([..._ruleLines]..removeAt(i)))),
                    ]),
                  ),
              const SizedBox(height: 4),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _newRule,
                    textCapitalization: TextCapitalization.sentences,
                    inputFormatters: [LengthLimitingTextInputFormatter(120)],
                    decoration: InputDecoration(hintText: t.typeRuleHint, isDense: true),
                    onSubmitted: (_) => _addRule(_newRule.text),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                  onPressed: () => _addRule(_newRule.text),
                  child: Text(t.addRule),
                ),
              ]),
              const SizedBox(height: 10),
              Text(t.quickRules, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5)),
              const SizedBox(height: 4),
              Wrap(spacing: 6, runSpacing: 4, children: [
                for (final q in [t.ruleGate, t.ruleNoSmoking, t.ruleNoGuests, t.ruleKeepClean, t.ruleSaveWater, t.ruleNoNoise])
                  if (!_ruleLines.contains(q))
                    ActionChip(avatar: const Icon(Icons.add_rounded, size: 16), label: Text(q), onPressed: () => _addRule(q)),
              ]),
              _foot(),
            ])),

        // ---- 8. Account (Change password has its own Save)
        _card('ac', Icons.account_circle_outlined, t.account, () => Material(
              color: Colors.white,
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.lock_outline_rounded, color: AppColors.primary),
                title: Text(t.changePassword, style: const TextStyle(fontWeight: FontWeight.w600)),
                trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.primary),
                onTap: _changePassword,
              ),
            )),
        InfoRow(t.joinCode, h['join_code'] as String),
        const SizedBox(height: 16),
        // room below, so even the last setting can move to the top with the keyboard open
        if (_openKey != null) SizedBox(height: MediaQuery.sizeOf(context).height * 0.6),
      ],
    );
  }
}

/// Grey cover with a green tick and "Your changes are saved" over one box (shown for 1½ seconds).
class SavedCover extends StatelessWidget {
  const SavedCover({super.key, required this.sub});
  final String sub;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        decoration: BoxDecoration(color: const Color(0xE6E9EDF3), borderRadius: BorderRadius.circular(16)),
        alignment: Alignment.center,
        child: Container(
          width: 250,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 18, offset: Offset(0, 6))],
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 50,
              height: 50,
              decoration: const BoxDecoration(color: AppColors.success, shape: BoxShape.circle),
              child: const Icon(Icons.check_rounded, color: Colors.white, size: 32),
            ),
            const SizedBox(height: 8),
            Text(context.l10n.changesSaved, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            if (sub.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(sub, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted, fontSize: 14)),
            ],
          ]),
        ),
      ),
    );
  }
}

// =====================================================================================
// Rooms & beds (top of Hostel settings)
// =====================================================================================
const _blue = Color(0xFF1560BD);
const _green = Color(0xFF15803D);

class _RoomsBlock extends StatefulWidget {
  const _RoomsBlock({required this.hostelId, required this.roomCard});
  final String hostelId;
  /// The "Change room details" line, built by the page with the loaded rooms.
  final Widget Function(List<Json> rooms, Future<void> Function() reload) roomCard;

  @override
  State<_RoomsBlock> createState() => _RoomsBlockState();
}

class _RoomsBlockState extends State<_RoomsBlock> {
  List<Json>? _rooms;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rooms = await OwnerRepo.instance.roomsWithBeds(widget.hostelId);
      if (!mounted) return;
      setState(() {
        _rooms = rooms;
        _error = null;
      });
    } catch (e) {
      if (mounted && _rooms == null) setState(() => _error = e);
    }
  }

  /// Reload after a change without a spinner, so "Change room details" stays open.
  Future<void> _reload() async {
    await _load();
    if (mounted) HostelScope.read(context).refresh();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    if (_error != null && _rooms == null) {
      return ErrorView(error: _error!, onRetry: () async {
        setState(() => _error = null);
        await _load();
      });
    }
    if (_rooms == null) return const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()));
    return Builder(
      builder: (context) {
        final rooms = _rooms!;
        var total = 0, taken = 0, free = 0;
        for (final r in rooms) {
          for (final b in (r['beds'] as List).cast<Json>()) {
            total++;
            final v = bedView(b);
            if (v == BedView.living || v == BedView.offline) taken++;
            if (v == BedView.free) free++;
          }
        }
        final floors = {for (final r in rooms) asInt(r['floor'])};
        final upper = floors.where((f) => f > 0).length;
        Widget stat(String v, String l, Color c) => Expanded(
              child: Column(children: [
                Text(v, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: c)),
                Text(l, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w400, color: AppColors.muted)),
              ]),
            );
        Widget divider() => Container(width: 1, height: 30, color: AppColors.line);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text(t.manageRooms, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
            Text(t.roomsCount('${rooms.length}'), style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
          ]),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
            decoration: BoxDecoration(
                color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.line)),
            child: Row(children: [
              stat('$total', t.totalBeds, AppColors.ink),
              divider(),
              stat('$taken', t.occupiedBeds, _blue),
              divider(),
              stat('$free', t.availableBeds, _green),
              divider(),
              stat(floors.contains(0) ? '$upper+G' : '$upper', t.floorsLabel, AppColors.ink),
            ]),
          ),
          const SizedBox(height: 12),
          widget.roomCard(rooms, _reload),
        ]);
      },
    );
  }
}

/// Inside of "Change room details": type a room number → change its sharing → Save room.
class _ChangeRoomCard extends StatefulWidget {
  const _ChangeRoomCard({required this.rooms, required this.prices, required this.onSaved});
  final List<Json> rooms;
  final List<Json> prices;
  final Future<void> Function(String savedText) onSaved;

  @override
  State<_ChangeRoomCard> createState() => _ChangeRoomCardState();
}

class _ChangeRoomCardState extends State<_ChangeRoomCard> {
  final _search = TextEditingController();
  int? _sharing; // new sharing picked (null = unchanged)

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// "Room 204 · 3 sharing → 4 sharing": who is staying and their new fee. True for "Yes, change".
  Future<bool> _confirmSharing(Json r, int to, int price, int staying) async {
    final t = context.l10n;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(t.roomSharingFromTo(r['room_no'] as String, '${asInt(r['sharing'])}', '$to'),
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7E6),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFF5D38A)),
              ),
              child: Text(t.sharingChangeInfo('$staying', money(price), money(asInt(r['rent_month']))),
                  style: const TextStyle(fontSize: 14, height: 1.45)),
            ),
            const SizedBox(height: 16),
            SizedBox(height: 50, child: FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t.yesChange))),
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t.cancel)),
          ]),
        ),
      ),
    );
    return ok == true;
  }

  Json? get _room {
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return null;
    for (final r in widget.rooms) {
      if ((r['room_no'] as String).toLowerCase() == q) return r;
    }
    return null;
  }

  int? _priceFor(int sharing) {
    for (final p in widget.prices) {
      if (asInt(p['sharing']) == sharing) return asInt(p['rent']);
    }
    return null;
  }

  Future<int?> _pickSharing(int current) {
    final t = context.l10n;
    int? n = current;
    return showModalBottomSheet<int>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(t.sharing, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            Text(t.sharingSheetHelp, style: const TextStyle(color: AppColors.muted)),
            const SizedBox(height: 12),
            SharingPicker(value: n, onChanged: (x) => setSheet(() => n = x)),
            const SizedBox(height: 14),
            SizedBox(height: 50, child: FilledButton(onPressed: () => Navigator.pop(ctx, n), child: Text(t.save))),
          ]),
        ),
      ),
    );
  }

  Widget _box(String label, String text, {VoidCallback? onTap, bool muted = false}) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 3),
            child: Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 11)),
          ),
          Opacity(
            opacity: muted ? 0.5 : 1,
            child: Material(
              color: onTap == null ? AppColors.ground : Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: AppColors.field)),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                  child: Row(children: [
                    Expanded(
                      child: Text(text,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontWeight: FontWeight.w400, fontSize: 14, color: onTap == null ? AppColors.muted : AppColors.ink)),
                    ),
                    Icon(onTap == null ? Icons.lock_outline_rounded : Icons.edit_rounded,
                        size: 16, color: onTap == null ? AppColors.muted : AppColors.primary),
                  ]),
                ),
              ),
            ),
          ),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    final r = _room;
    final beds = r == null ? const <Json>[] : (r['beds'] as List).cast<Json>();
    final staying = beds.where((b) => bedView(b) != BedView.free).length;
    final newSharing = _sharing ?? (r == null ? null : asInt(r['sharing']));
    final price = newSharing == null ? null : _priceFor(newSharing);
    final floor = r == null ? 0 : asInt(r['floor']);
    final changed = r != null && newSharing != asInt(r['sharing']);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(
            controller: _search,
            textCapitalization: TextCapitalization.characters,
            inputFormatters: [LengthLimitingTextInputFormatter(20)],
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            decoration: InputDecoration(prefixIcon: const Icon(Icons.search_rounded), hintText: t.typeRoomNumber),
            onChanged: (_) => setState(() => _sharing = null),
          ),
          if (_search.text.trim().isNotEmpty && r == null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(t.noRoomFound(_search.text.trim()), style: const TextStyle(color: AppColors.danger, fontSize: 12.5)),
            ),
          const SizedBox(height: 10),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // room number can't be changed here
            _box(t.roomNoShort, r == null ? '—' : r['room_no'] as String),
            const SizedBox(width: 8),
            _box(
              t.sharing,
              newSharing == null ? '—' : t.sharingN('$newSharing'),
              muted: r == null,
              onTap: () async {
                if (r == null) {
                  showSnack(context, t.typeRoomFirst, error: true);
                  return;
                }
                final n = await _pickSharing(newSharing!);
                if (n != null) setState(() => _sharing = n);
              },
            ),
          ]),
          if (r != null) ...[
            const SizedBox(height: 8),
            Text(
                t.roomStayingRent(floor == 0 ? t.groundFloor : t.floorN('$floor'), '$staying',
                    price == null ? t.rentNotSet : money(price)),
                style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
          ],
          const SizedBox(height: 10),
          SizedBox(
            height: 50,
            child: BusyButton(
              label: t.saveRoom,
              onPressed: !changed
                  ? null
                  : () async {
                      if (newSharing! < staying) {
                        showSnack(context, t.errTooManyTenants, error: true);
                        return;
                      }
                      if (price == null) {
                        showSnack(context, t.addSharingPriceFirst('$newSharing'), error: true);
                        return;
                      }
                      // students staying: they move to the new fee from their next fee date — ask first
                      if (staying > 0 && !await _confirmSharing(r, newSharing, price, staying)) return;
                      await OwnerRepo.instance.changeRoom(r['id'] as String,
                          roomNo: r['room_no'] as String, sharing: newSharing, rent: price);
                      if (!mounted) return;
                      final text = t.roomSharingTo(r['room_no'] as String, '${asInt(r['sharing'])}', '$newSharing');
                      setState(() {
                        _sharing = null;
                        _search.clear(); // same look as when it was opened
                      });
                      await widget.onSaved(text);
                    },
            ),
          ),
    ]);
  }
}
