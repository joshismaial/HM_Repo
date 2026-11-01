import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../../core/back_nav.dart';
import '../../core/format.dart';
import '../../data/owner_repo.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

/// Register hostel (24 Oct 2026 short form): name, type, location. One button: Create hostel.
/// "Are you at the hostel now?" Yes: the phone saves the exact point (latitude / longitude) and
/// fills area, city and pincode. No: type area, city and pincode. House / street is optional.
/// No floors, photos or contact number here (students type their own room; the photo is added
/// from My hostels; the contact number is the owner's login number, set by the server).
class HostelFormScreen extends StatefulWidget {
  const HostelFormScreen({super.key});

  @override
  State<HostelFormScreen> createState() => _HostelFormScreenState();
}

enum _Mode { ask, gps, type }

class _HostelFormScreenState extends State<HostelFormScreen> {
  // Removed hostels of this owner (0 = hide the Restore link); a failed read just hides it.
  late final Future<int> _removedCount = OwnerRepo.instance.removedHostelCount().catchError((_) => 0);
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _area = TextEditingController();
  final _city = TextEditingController();
  final _pin = TextEditingController();
  final _street = TextEditingController();
  String _type = 'mens';
  _Mode _mode = _Mode.ask;
  bool _finding = false;
  double? _lat;
  double? _lng;

  @override
  void dispose() {
    for (final c in [_name, _area, _city, _pin, _street]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Asks the phone for its position, then looks up the area, city and pincode.
  /// If the address lookup fails, the point is still kept and the owner types the address.
  Future<void> _useLocation() async {
    setState(() {
      _mode = _Mode.gps;
      _finding = true;
    });
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever ||
          !await Geolocator.isLocationServiceEnabled()) {
        throw const _NoLocation();
      }
      final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 20)));
      _lat = double.parse(pos.latitude.toStringAsFixed(6));
      _lng = double.parse(pos.longitude.toStringAsFixed(6));
      try {
        final marks = await placemarkFromCoordinates(pos.latitude, pos.longitude);
        final m = marks.isEmpty ? null : marks.first;
        String pick(List<String?> xs) => xs.firstWhere((x) => x != null && x.trim().isNotEmpty, orElse: () => '')!.trim();
        _area.text = pick([m?.subLocality, m?.thoroughfare, m?.locality]);
        _city.text = pick([m?.locality, m?.subAdministrativeArea, m?.administrativeArea]);
        _pin.text = (m?.postalCode ?? '').replaceAll(RegExp(r'\D'), '');
      } catch (_) {
        // address lookup not available: the exact point is still saved, the owner types the address
      }
      if (!mounted) return;
      setState(() {
        _finding = false;
        // area or city could not be found: let the owner fill the gap
        if (_area.text.trim().length < 2 || _city.text.trim().length < 2) _mode = _Mode.type;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _finding = false;
        _mode = _Mode.type;
        _lat = null;
        _lng = null;
      });
      showSnack(context, context.l10n.rhNoPermission, error: true);
    }
  }

  void _reset() => setState(() {
        _mode = _Mode.ask;
        _lat = null;
        _lng = null;
        _area.clear();
        _city.clear();
        _pin.clear();
      });

  Future<void> _save() async {
    final t = context.l10n;
    if (!(_form.currentState?.validate() ?? true)) return;
    final area = _area.text.trim();
    final city = _city.text.trim();
    if (_mode == _Mode.ask || area.length < 2 || city.length < 2) {
      showSnack(context, t.rhNeedLocation, error: true);
      return;
    }
    final pin = _pin.text.trim();
    if (pin.isNotEmpty && pin.length != 6) {
      showSnack(context, t.rhPinDigits, error: true);
      return;
    }
    final street = _street.text.trim();
    final h = await OwnerRepo.instance.addHostel({
      'name': _name.text.trim(),
      'type': _type,
      'area': area,
      'city': city,
      if (pin.isNotEmpty) 'pincode': pin,
      'address': [street, area, city, pin].where((x) => x.isNotEmpty).join(', '),
      if (_lat != null && _lng != null) ...{'latitude': _lat, 'longitude': _lng},
    });
    if (!mounted) return;
    showSnack(context, t.hostelSaved);
    context.go('/h/${h['id']}/home');
  }

  Widget _answer(IconData icon, String title, String sub, VoidCallback onTap, {bool primary = false}) {
    final fg = primary ? Colors.white : AppColors.ink;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
          decoration: BoxDecoration(
            color: primary ? AppColors.primary : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: primary ? AppColors.primary : AppColors.line, width: 1.2),
          ),
          child: Column(children: [
            Icon(icon, size: 22, color: primary ? Colors.white : AppColors.primary),
            const SizedBox(height: 4),
            Text(title, textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w600, color: fg)),
            const SizedBox(height: 2),
            Text(sub,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: primary ? AppColors.onBlueMuted : AppColors.muted)),
          ]),
        ),
      ),
    );
  }

  Widget _locationBlock() {
    final t = context.l10n;
    switch (_mode) {
      case _Mode.ask:
        return SectionCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              const Icon(Icons.location_on_rounded, size: 22, color: AppColors.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t.rhAtHostelQ,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.primaryDark)),
                  Text(t.rhPhoneSaves, style: const TextStyle(fontSize: 12.5, color: AppColors.muted)),
                ]),
              ),
            ]),
            const SizedBox(height: 12),
            IntrinsicHeight(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _answer(Icons.navigation_rounded, t.rhYesUse, t.rhFillsArea, _useLocation, primary: true),
                const SizedBox(width: 10),
                _answer(Icons.edit_outlined, t.rhNoType, t.rhAreaCityPin, () => setState(() => _mode = _Mode.type)),
              ]),
            ),
          ]),
        );
      case _Mode.gps:
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (_finding)
            SectionCard(
              child: Row(children: [
                const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)),
                const SizedBox(width: 12),
                Text(t.rhFinding, style: const TextStyle(color: AppColors.muted)),
              ]),
            )
          else
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.successSoft,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFBFE3CB)),
              ),
              child: Row(children: [
                const CircleAvatar(
                    radius: 18,
                    backgroundColor: AppColors.success,
                    child: Icon(Icons.location_on_rounded, size: 18, color: Colors.white)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(t.rhSaved, style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.success)),
                    Text('${_area.text}, ${_city.text} ${_pin.text}'.trim(),
                        style: const TextStyle(fontSize: 12.5, color: AppColors.muted)),
                  ]),
                ),
                TextButton(onPressed: _reset, child: Text(t.rhChange)),
              ]),
            ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _street,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(labelText: t.rhStreetOpt),
          ),
        ]);
      case _Mode.type:
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextFormField(
            controller: _area,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(labelText: t.rhArea),
            validator: (v) => (v ?? '').trim().length < 2 ? t.required : null,
          ),
          const SizedBox(height: 12),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: TextFormField(
                controller: _city,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(labelText: t.city),
                validator: (v) => (v ?? '').trim().length < 2 ? t.required : null,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: _pin,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
                decoration: InputDecoration(labelText: t.rhPinOptional),
                validator: (v) => (v ?? '').isEmpty || RegExp(r'^[1-9]\d{5}$').hasMatch(v!) ? null : t.errBadPincode,
              ),
            ),
          ]),
          const SizedBox(height: 12),
          TextFormField(
            controller: _street,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(labelText: t.rhStreetOpt),
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              icon: const Icon(Icons.navigation_rounded, size: 16),
              label: Text(t.rhUseLink),
              onPressed: _useLocation,
            ),
          ),
        ]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(t.registerHostel),
        leading: IconButton(
          tooltip: t.back,
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => goBack(context),
        ),
        actions: [
          IconButton(
            tooltip: t.logout,
            icon: const Icon(Icons.logout_rounded),
            onPressed: () => OwnerRepo.instance.logout(),
          ),
        ],
      ),
      // Column (not bottomNavigationBar): the Create button bar takes only its own height.
      body: Column(children: [
        Expanded(
          child: Form(
        key: _form,
        child: PageList(
          children: [
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(labelText: t.hostelName, hintText: 'Sunrise Boys PG'),
              validator: (v) => (v ?? '').trim().length < 2 ? t.required : null,
            ),
            const SizedBox(height: 16),
            Text(t.hostelType, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: [
                ButtonSegment(value: 'mens', label: Text(t.typeMens)),
                ButtonSegment(value: 'womens', label: Text(t.typeWomens)),
                ButtonSegment(value: 'coliving', label: Text(t.typeColiving)),
              ],
              selected: {_type},
              onSelectionChanged: (s) => setState(() => _type = s.first),
            ),
            const SizedBox(height: 16),
            Text(t.rhLocation, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            _locationBlock(),
            const SizedBox(height: 14),
            Text(t.rhLaterNote, style: const TextStyle(fontSize: 12.5, color: AppColors.muted)),
            // Owner removed a hostel earlier: a way back to it (also when no hostel is left).
            FutureBuilder<int>(
              future: _removedCount,
              builder: (context, snap) {
                final n = snap.data ?? 0;
                if (n == 0) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      icon: const Icon(Icons.restore_rounded, size: 18),
                      label: Text(t.restoreRemovedHostel('$n')),
                      onPressed: () => context.push('/hostels/removed'),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
          ),
        ),
        Container(
          width: double.infinity,
          decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: AppColors.line))),
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: SafeArea(
            top: false,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: BusyButton(label: t.rhCreate, onPressed: _save),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

class _NoLocation implements Exception {
  const _NoLocation();
}
