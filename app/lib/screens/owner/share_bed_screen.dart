import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config.dart';
import '../../core/back_nav.dart';
import '../../core/format.dart';
import '../../data/owner_repo.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import 'hostel_scope.dart';
import 'rooms_screen.dart' show featureLabel;

const _green = Color(0xFF15803D);
const _greenSoft = Color(0xFFDDF3E8);
const _greenLine = Color(0xFFCDEEDC);

/// Rooms → Book on a free bed: the bed is held for 15 minutes and this screen shows the
/// room, rent, deposit, total and a QR code for the student to scan. The student verifies
/// their mobile, fills their details, accepts the house rules and pays; the owner then
/// approves in Requests and the bed becomes filled.
class ShareBedScreen extends StatefulWidget {
  const ShareBedScreen({super.key, required this.hostelId, required this.bedId});
  final String hostelId;
  final String bedId;

  @override
  State<ShareBedScreen> createState() => _ShareBedScreenState();
}

class _ShareBedScreenState extends State<ShareBedScreen> {
  final _loader = GlobalKey<LoaderState<Json>>();
  Timer? _tick;
  Duration _left = Duration.zero;
  DateTime? _until;

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<Json> _hold() async {
    final b = await OwnerRepo.instance.holdBedForBooking(widget.bedId);
    _startTimer(asDate(b['held_until']));
    return b;
  }

  void _startTimer(DateTime? until) {
    _tick?.cancel();
    _until = until;
    void update() {
      final left = _until == null ? Duration.zero : _until!.difference(DateTime.now());
      if (!mounted) return;
      setState(() => _left = left.isNegative ? Duration.zero : left);
      if (left.isNegative) _tick?.cancel();
    }

    _tick = Timer.periodic(const Duration(seconds: 1), (_) => update());
    WidgetsBinding.instance.addPostFrameCallback((_) => update());
  }

  String get _mmss =>
      '${_left.inMinutes.toString().padLeft(2, '0')}:${(_left.inSeconds % 60).toString().padLeft(2, '0')}';

  Future<void> _cancel() async {
    try {
      await OwnerRepo.instance.releaseBookingHold(widget.bedId);
    } catch (_) {}
    if (mounted) await goBack(context);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    final hostel = HostelScope.of(context).hostel;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: Text(t.shareWithStudent), leading: const AppBackButton(), backgroundColor: Colors.white),
      body: Loader<Json>(
        key: _loader,
        load: _hold,
        builder: (context, b, reload) {
          final link = '${AppConfig.joinLink('${hostel?['join_code'] ?? ''}')}'
              '?bed=${b['bed_id']}&k=${b['booking_code']}';
          final features = (b['features'] as List? ?? const []).cast<String>();
          final floor = asInt(b['floor']);
          final expired = _until != null && _left == Duration.zero;
          final message = t.bookBedShareMessage(
            '${hostel?['name'] ?? ''}',
            '${b['room_no']}',
            '${b['bed_label']}',
            money(asInt(b['total'])),
            link,
          );
          Widget row(String l, String v, {bool strong = false}) => Padding(
                padding: const EdgeInsets.only(top: 7),
                child: Row(children: [
                  Expanded(
                    child: Text(l,
                        style: TextStyle(
                            fontSize: strong ? 15 : 14,
                            fontWeight: strong ? FontWeight.w600 : FontWeight.w600,
                            color: strong ? AppColors.ink : AppColors.muted)),
                  ),
                  Text(v,
                      style: TextStyle(
                          fontSize: strong ? 20 : 14.5,
                          fontWeight: FontWeight.w600,
                          color: strong ? _green : AppColors.ink)),
                ]),
              );
          return PageList(
            children: [
              // ---- bed and money
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.line),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(color: _greenSoft, borderRadius: BorderRadius.circular(12)),
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Text('${b['room_no']}',
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: _green, height: 1.05)),
                        Text('${b['bed_label']}',
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5, color: _green, height: 1.05)),
                      ]),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(t.bookBedTitle('${b['room_no']}', '${b['bed_label']}'),
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                        Text(
                          [
                            floor == 0 ? t.groundFloor : t.floorN('$floor'),
                            t.sharingN('${b['sharing']}'),
                            ...features.take(2).map((f) => featureLabel(context, f)),
                          ].join(' · '),
                          maxLines: 2,
                          style: const TextStyle(color: AppColors.muted, fontSize: 12.5),
                        ),
                      ]),
                    ),
                  ]),
                  const SizedBox(height: 4),
                  row(t.rentPerMonth, money(asInt(b['rent_month']))),
                  row(t.securityDeposit, money(asInt(b['deposit']))),
                  const Divider(height: 20),
                  row(t.toPayNow, money(asInt(b['total'])), strong: true),
                ]),
              ),
              const SizedBox(height: 14),
              // ---- QR for the student
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF7FCF9),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _greenLine, width: 1.5),
                ),
                child: Column(children: [
                  Opacity(
                    opacity: expired ? 0.15 : 1,
                    child: Semantics(
                      label: t.askStudentToScan,
                      image: true,
                      child: QrImageView(data: link, size: 200, backgroundColor: Colors.white),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(expired ? t.bookingHoldEnded : t.askStudentToScan,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text(t.askStudentToScanHelp,
                      textAlign: TextAlign.center, style: const TextStyle(fontSize: 12.5, color: AppColors.muted)),
                  const SizedBox(height: 10),
                  if (expired)
                    FilledButton.icon(
                      icon: const Icon(Icons.refresh_rounded),
                      label: Text(t.holdAgain),
                      onPressed: () => _loader.currentState?.reload(),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(color: AppColors.warningSoft, borderRadius: BorderRadius.circular(99)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.timer_outlined, size: 16, color: AppColors.warning),
                        const SizedBox(width: 5),
                        Text(t.bedHeldFor(_mmss),
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5, color: AppColors.warning)),
                      ]),
                    ),
                ]),
              ),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.whatsapp,
                      minimumSize: const Size.fromHeight(50),
                    ),
                    icon: const Icon(Icons.chat_rounded, size: 18),
                    label: Text(t.whatsappLink),
                    onPressed: expired
                        ? null
                        : () async {
                            final ok = await launchUrl(
                              Uri.parse('https://wa.me/?text=${Uri.encodeComponent(message)}'),
                              mode: LaunchMode.externalApplication,
                            );
                            if (!ok && context.mounted) await copyText(context, message);
                          },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    label: Text(t.copyLink),
                    onPressed: expired ? null : () => copyText(context, link),
                  ),
                ),
              ]),
              const SizedBox(height: 6),
              TextButton(onPressed: _cancel, child: Text(t.cancelBooking)),
            ],
          );
        },
      ),
    );
  }
}
