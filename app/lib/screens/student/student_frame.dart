import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/back_nav.dart';
import '../../core/format.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

/// Page frame for the student joining flow: back button, language, "Step x of 4".
class StudentFrame extends StatelessWidget {
  const StudentFrame({
    super.key,
    required this.title,
    required this.body,
    this.step,
    this.totalSteps = 4,
    this.backTo,
    this.bottom,
  });
  final String title;
  final Widget body;
  final int? step;
  final int totalSteps;
  final String? backTo;
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        automaticallyImplyLeading: false,
        leading: backTo == null
            ? null
            : IconButton(
                tooltip: context.l10n.back,
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => goBack(context),
              ),
        actions: const [Padding(padding: EdgeInsets.only(right: 8), child: LanguageButton())],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (step != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Narrow(child: StepProgress(step!, total: totalSteps)),
              ),
            Expanded(child: body),
          ],
        ),
      ),
      bottomNavigationBar: bottom == null
          ? null
          : SafeArea(
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(top: BorderSide(color: AppColors.line)),
                ),
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                child: Narrow(child: bottom!),
              ),
            ),
    );
  }
}

/// Shows minutes:seconds left on the bed hold and refreshes every second.
class HoldTimer extends StatefulWidget {
  const HoldTimer({super.key, required this.until, this.onExpired});
  final DateTime until;
  final VoidCallback? onExpired;

  @override
  State<HoldTimer> createState() => _HoldTimerState();
}

class _HoldTimerState extends State<HoldTimer> {
  late final Stream<int> _ticks = Stream.periodic(const Duration(seconds: 1), (i) => i);
  bool _fired = false;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: _ticks,
      builder: (context, _) {
        final left = widget.until.difference(DateTime.now());
        if (left.isNegative) {
          if (!_fired) {
            _fired = true;
            WidgetsBinding.instance.addPostFrameCallback((_) => widget.onExpired?.call());
          }
          return Banner2(tone: Tone.danger, icon: Icons.timer_off_rounded, text: context.l10n.holdExpiredShort);
        }
        // Long holds (owner checking a payment / existing tenant) don't need a countdown.
        if (left.inHours >= 1) return const SizedBox.shrink();
        final mm = left.inMinutes.toString().padLeft(2, '0');
        final ss = (left.inSeconds % 60).toString().padLeft(2, '0');
        return Banner2(
          tone: left.inMinutes < 3 ? Tone.warning : Tone.info,
          icon: Icons.timer_rounded,
          text: context.l10n.bedHeldFor('$mm:$ss'),
        );
      },
    );
  }
}

/// "Bed taken / hold ran out" state with a way back to the room list.
class BedLostView extends StatelessWidget {
  const BedLostView({super.key, required this.joinCode});
  final String joinCode;

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    return ListView(children: [
      EmptyView(
        icon: Icons.bed_outlined,
        title: t.bedLostTitle,
        message: t.bedLostMessage,
        action: SizedBox(
          width: 240,
          child: FilledButton(onPressed: () => context.go('/j/$joinCode/rooms'), child: Text(t.seeAllRooms)),
        ),
      ),
    ]);
  }
}

String rentDayText(BuildContext context, Json h) {
  final t = context.l10n;
  return h['rent_day_mode'] == 'joining_date'
      ? t.rentDayJoiningText
      : t.rentDayFixedText('${h['rent_fixed_day']}');
}
