import 'package:flutter/material.dart';

import '../core/format.dart';
import '../theme.dart';

/// Phase 1 "Your room" pickers, used on the student's details form and the owner's
/// "Rooms from tenants" fix panel.

/// Highest sharing the "+" button goes to (the database allows 1–12 beds per room).
const maxSharing = 12;

/// Ground floor rooms are G + a number (G1, G2 …); rooms on floors 1–9 can't start with G.
bool isGroundRoom(String no) => RegExp(r'^G\d{1,4}$').hasMatch(no.trim());
bool startsWithG(String no) => no.trim().toUpperCase().startsWith('G');
bool roomMatchesFloor(String no, int? floor) => floor == 0 ? isGroundRoom(no) : !startsWithG(no);

/// Highest floor the "+ Tap to add next floor" bar goes to (the database allows floors 0–50).
const maxFloor = 50;

/// Floor: a "Ground" chip and a "Floor" button that opens a pop-up over a dimmed screen:
/// Floor 1–9 in a 3×3 grid and a full-width "+ Tap to add next floor" bar (10, 11 … up to [maxFloor]).
/// [value] is 0 (ground) – 50 or null. [allowGround] = false disables Ground;
/// [onlyGround] disables the Floor button (a G room).
class FloorPicker extends StatefulWidget {
  const FloorPicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.locked = false,
    this.allowGround = true,
    this.onlyGround = false,
  });
  final int? value;
  final ValueChanged<int> onChanged;
  final bool locked;
  final bool allowGround;
  final bool onlyGround;

  @override
  State<FloorPicker> createState() => _FloorPickerState();
}

class _FloorPickerState extends State<FloorPicker> {
  // floors shown in the pop-up; stays bigger once the student adds floors
  late int _count = (widget.value ?? 0) > 9 ? widget.value! : 9;
  final Set<int> _added = {};

  Future<void> _open() async {
    final t = context.l10n;
    final picked = await showDialog<int>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => Dialog(
          insetPadding: const EdgeInsets.all(24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(t.chooseYourFloor, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                const SizedBox(height: 12),
                Flexible(
                  child: SingleChildScrollView(
                    child: GridView.count(
                      crossAxisCount: 3,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      childAspectRatio: 2.3,
                      children: [
                        for (var n = 1; n <= _count; n++) _floorTile(ctx, n),
                      ],
                    ),
                  ),
                ),
                if (_count < maxFloor) ...[
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(46),
                      backgroundColor: AppColors.primarySoft,
                      side: const BorderSide(color: AppColors.primary),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.add_rounded),
                    label: Text(t.tapToAddNextFloor, style: const TextStyle(fontWeight: FontWeight.w600)),
                    onPressed: () {
                      setState(() {
                        _count++;
                        _added.add(_count);
                      });
                      setDialog(() {}); // show the new floor in the pop-up
                    },
                  ),
                ],
                const SizedBox(height: 4),
                TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(t.cancel)),
              ]),
            ),
          ),
        ),
      ),
    );
    if (picked != null) widget.onChanged(picked);
  }

  Widget _floorTile(BuildContext ctx, int n) {
    final t = context.l10n;
    final selected = widget.value == n;
    final isNew = _added.contains(n) && !selected;
    final (bg, fg) = selected
        ? (AppColors.primarySoft, AppColors.primary)
        : isNew
            ? (AppColors.successSoft, AppColors.success)
            : (Colors.white, AppColors.ink);
    return Material(
      color: bg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: selected ? AppColors.primary : (isNew ? AppColors.success : AppColors.line), width: 1.2),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(ctx).pop(n),
        child: Center(
          child: Text(t.floorN('$n'), style: TextStyle(fontWeight: FontWeight.w600, color: fg, fontSize: 12.5)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    final v = widget.value;
    final ground = v == 0;
    final upper = v != null && v > 0 ? v : null;
    final floorOff = widget.locked || widget.onlyGround;
    return Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
      ChoiceChip(
        label: Text(t.groundShort),
        selected: ground,
        onSelected: widget.locked || !widget.allowGround ? null : (_) => widget.onChanged(0),
      ),
      OutlinedButton(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 38),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          backgroundColor: upper != null ? AppColors.primarySoft : Colors.white,
          foregroundColor: upper != null ? AppColors.primary : AppColors.ink,
          side: BorderSide(color: upper != null ? AppColors.primary : AppColors.field),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        onPressed: floorOff ? null : _open,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(upper != null ? t.floorN('$upper') : t.floor, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(width: 4),
          const Icon(Icons.expand_more_rounded, size: 18),
        ]),
      ),
    ]);
  }
}

/// Sharing: chips 1–5 then "+"; each "+" adds and selects the next number (up to [maxSharing]).
class SharingPicker extends StatelessWidget {
  const SharingPicker({super.key, required this.value, required this.onChanged, this.locked = false});
  final int? value;
  final ValueChanged<int> onChanged;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final shown = (value ?? 0) > 5 ? value! : 5;
    return Wrap(spacing: 6, runSpacing: 6, children: [
      for (var n = 1; n <= shown; n++)
        ChoiceChip(
          label: Text('$n'),
          selected: value == n,
          onSelected: locked && value != n ? null : (_) => onChanged(n),
        ),
      if (!locked && shown < maxSharing)
        ActionChip(
          label: const Icon(Icons.add_rounded, size: 18, color: AppColors.primary),
          tooltip: '${shown + 1}',
          side: const BorderSide(color: AppColors.primary),
          onPressed: () => onChanged(shown + 1),
        ),
    ]);
  }
}
