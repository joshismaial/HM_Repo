import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/back_nav.dart';
import '../../core/format.dart';
import '../../data/owner_repo.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import 'rooms_screen.dart';

/// Result of Add room, used by Hostel settings to highlight the new room and show "saved".
class AddedRoom {
  const AddedRoom(this.roomNo, this.beds);
  final String roomNo;
  final int beds;
}

/// Add room (opened from Hostel settings → Rooms & beds):
/// Room – floor and room number side by side, sharing 1–6;
/// Fees – monthly rent / deposit and per-day rent / day-wise deposit side by side;
/// Features – AC, Geyser… Save room goes back to Hostel settings, where the list is updated.
class AddRoomScreen extends StatefulWidget {
  const AddRoomScreen({super.key, required this.hostelId});
  final String hostelId;

  @override
  State<AddRoomScreen> createState() => _AddRoomScreenState();
}

class _AddRoomScreenState extends State<AddRoomScreen> {
  final _form = GlobalKey<FormState>();
  final _roomNo = TextEditingController();
  final _rent = TextEditingController();
  final _deposit = TextEditingController();
  final _rentDay = TextEditingController();
  final _depositDay = TextEditingController();
  int _floor = 1;
  int _sharing = 2;
  final Set<String> _features = {};

  @override
  void dispose() {
    for (final c in [_roomNo, _rent, _deposit, _rentDay, _depositDay]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final roomNo = _roomNo.text.trim();
    await OwnerRepo.instance.addRoom(
      hostelId: widget.hostelId,
      roomNo: roomNo,
      floor: _floor,
      sharing: _sharing,
      rent: int.parse(_rent.text),
      deposit: int.tryParse(_deposit.text) ?? 0,
      rentDay: int.tryParse(_rentDay.text),
      depositDay: int.tryParse(_depositDay.text),
      features: _features.toList(),
    );
    if (!mounted) return;
    // back to Hostel settings with the new room (it shows "saved" and highlights it)
    final result = AddedRoom(roomNo, _sharing);
    if (context.canPop()) {
      context.pop(result);
    } else {
      showSnack(context, context.l10n.roomSavedBeds(roomNo, '$_sharing'));
      await goBack(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    final digits = [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(7)];
    String? money0(String? v) => (int.tryParse(v ?? '') ?? 0) <= 0 ? t.errAmount : null;
    Widget card(String title, List<Widget> children) => Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.line),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            const SizedBox(height: 10),
            ...children,
          ]),
        );
    Widget pair(Widget a, Widget b) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: a),
          const SizedBox(width: 10),
          Expanded(child: b),
        ]);
    return Scaffold(
      appBar: AppBar(title: Text(t.addRoom), leading: const AppBackButton()),
      body: Form(
        key: _form,
        child: PageList(
          children: [
            card(t.roomSection, [
              pair(
                DropdownButtonFormField<int>(
                  value: _floor,
                  decoration: InputDecoration(labelText: t.floor),
                  items: [
                    for (var f = 0; f <= 20; f++)
                      DropdownMenuItem(value: f, child: Text(f == 0 ? t.groundFloor : t.floorN('$f'))),
                  ],
                  onChanged: (v) => setState(() => _floor = v ?? 1),
                ),
                TextFormField(
                  controller: _roomNo,
                  decoration: InputDecoration(labelText: t.roomNumber, hintText: '205'),
                  inputFormatters: [LengthLimitingTextInputFormatter(20)],
                  validator: (v) => (v ?? '').trim().isEmpty ? t.required : null,
                ),
              ),
              const SizedBox(height: 12),
              Text(t.sharingBeds, style: const TextStyle(color: AppColors.muted, fontSize: 12.5, fontWeight: FontWeight.w400)),
              const SizedBox(height: 6),
              Row(children: [
                for (var i = 1; i <= 6; i++) ...[
                  if (i > 1) const SizedBox(width: 6),
                  Expanded(
                    child: Semantics(
                      button: true,
                      selected: _sharing == i,
                      label: t.sharingN('$i'),
                      excludeSemantics: true,
                      child: Material(
                        color: _sharing == i ? AppColors.primary : Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: _sharing == i ? AppColors.primary : AppColors.field),
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => setState(() => _sharing = i),
                          child: SizedBox(
                            height: 42,
                            child: Center(
                              child: Text('$i',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                      color: _sharing == i ? Colors.white : AppColors.ink)),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ]),
            ]),
            card(t.feesSection, [
              pair(
                TextFormField(
                  controller: _rent,
                  keyboardType: TextInputType.number,
                  inputFormatters: digits,
                  decoration: InputDecoration(labelText: t.rentPerBed, prefixText: '₹ '),
                  validator: money0,
                ),
                TextFormField(
                  controller: _deposit,
                  keyboardType: TextInputType.number,
                  inputFormatters: digits,
                  decoration: InputDecoration(labelText: t.depositMonthly, prefixText: '₹ '),
                ),
              ),
              const SizedBox(height: 10),
              pair(
                TextFormField(
                  controller: _rentDay,
                  keyboardType: TextInputType.number,
                  inputFormatters: digits,
                  decoration: InputDecoration(labelText: t.perDayRentOptional, prefixText: '₹ '),
                ),
                TextFormField(
                  controller: _depositDay,
                  keyboardType: TextInputType.number,
                  inputFormatters: digits,
                  decoration: InputDecoration(labelText: t.depositDaywise, prefixText: '₹ '),
                ),
              ),
            ]),
            card(t.roomFeatures, [
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final f in roomFeatureCodes)
                    FilterChip(
                      label: Text(featureLabel(context, f)),
                      selected: _features.contains(f),
                      onSelected: (on) => setState(() => on ? _features.add(f) : _features.remove(f)),
                    ),
                ],
              ),
            ]),
            BusyButton(label: t.saveRoom, onPressed: _save),
            const SizedBox(height: 8),
            Text(t.afterSaveBackToSettings,
                textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
          ],
        ),
      ),
    );
  }
}
