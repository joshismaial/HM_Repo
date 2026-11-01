import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config.dart';
import '../../core/format.dart';
import '../../data/student_api.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import 'student_frame.dart' show HoldTimer;

const _indigo = Color(0xFF1560BD); // Trust blue
const _violet = Color(0xFF0D4F9E); // darker Trust blue

/// Web page opened by the hostel QR (office poster) or the owner's bed QR when the app is not
/// installed: "Welcome! You've been invited by <owner> to join <hostel>" and a Google Play button.
/// The Play Store link carries the join code and bed, so the app opens on this hostel after install.
/// (No "continue in browser": students join in the app.)
class GetAppScreen extends StatefulWidget {
  const GetAppScreen({super.key, required this.joinCode, this.bedId, this.bookingCode});
  final String joinCode;
  final String? bedId;
  final String? bookingCode;

  @override
  State<GetAppScreen> createState() => _GetAppScreenState();
}

class _GetAppScreenState extends State<GetAppScreen> {
  late Future<Json> _peek = _load();

  Future<Json> _load() => StudentApi.instance.peek(widget.joinCode, bedId: widget.bedId, code: widget.bookingCode);

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    return Scaffold(
      backgroundColor: AppColors.ground,
      body: FutureBuilder<Json>(
        future: _peek,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          if (snap.hasError) return ErrorView(error: snap.error!, onRetry: () => setState(() => _peek = _load()));
          final peek = snap.data!;
          final booking = peek['booking'] is Map ? Json.from(peek['booking'] as Map) : null;
          final hostel = peek['hostel_name'] as String? ?? '';
          final owner = peek['owner_name'] as String?;
          final city = peek['city'] as String?;
          return ListView(padding: EdgeInsets.zero, children: [
            Container(
              color: _indigo,
              padding: EdgeInsets.fromLTRB(16, MediaQuery.paddingOf(context).top + 20, 16, 28),
              child: Column(children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                  child: const Icon(Icons.home_work_rounded, size: 44, color: _indigo),
                ),
                const SizedBox(height: 8),
                Text(t.appName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                const Align(alignment: Alignment.topRight, child: LanguageButton()),
              ]),
            ),
            Narrow(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(children: [
                  Text(t.welcomeExclaim, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text(owner == null ? t.invitedPlain : t.invitedBy(owner),
                      textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, color: AppColors.muted)),
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.line),
                    ),
                    child: Column(children: [
                      Text(hostel, textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                      if (city != null && city.isNotEmpty)
                        Text(city, style: const TextStyle(color: AppColors.muted)),
                      if (booking != null) ...[
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(color: AppColors.successSoft, borderRadius: BorderRadius.circular(12)),
                          child: Text('🛏  ${t.bedHeldForYou('${booking['room_no']}', '${booking['bed_label']}')}',
                              textAlign: TextAlign.center, style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.w600)),
                        ),
                        const SizedBox(height: 6),
                        Text(t.holdStartsOnOpen, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12.5, color: AppColors.muted)),
                      ],
                    ]),
                  ),
                  const SizedBox(height: 24),
                  Text(t.getAppToContinue, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 12),
                  Semantics(
                    button: true,
                    label: t.getTheApp,
                    child: Material(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => launchUrl(
                          Uri.parse(AppConfig.playStoreUrl(
                              joinCode: widget.joinCode, bedId: widget.bedId, bookingCode: widget.bookingCode)),
                          mode: LaunchMode.externalApplication,
                        ),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 22, vertical: 10),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.play_arrow_rounded, color: Color(0xFF34D399), size: 30),
                            SizedBox(width: 8),
                            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('GET IT ON', style: TextStyle(color: Colors.white, fontSize: 11)),
                              Text('Google Play', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
                            ]),
                          ]),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(t.opensOnHostel(hostel), textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                ]),
              ),
            ),
          ]);
        },
      ),
    );
  }
}

/// First app screen for a hostel QR / bed QR (also right after installing from it):
/// "Welcome", the hostel name, and the Student registration button below it.
/// Opened from the owner's bed QR it also shows the held bed; opening it starts the 15-minute hold.
class StudentWelcomeScreen extends StatefulWidget {
  const StudentWelcomeScreen({super.key, required this.joinCode, this.bedId, this.bookingCode});
  final String joinCode;
  final String? bedId;
  final String? bookingCode;

  @override
  State<StudentWelcomeScreen> createState() => _StudentWelcomeScreenState();
}

class _StudentWelcomeScreenState extends State<StudentWelcomeScreen> {
  late Future<Json> _peek = _load();

  bool get _booked => widget.bedId != null && widget.bookingCode != null;

  Future<Json> _load() => StudentApi.instance
      .peek(widget.joinCode, bedId: widget.bedId, code: widget.bookingCode, start: _booked);

  String _verifyRoute({bool find = false}) {
    final q = <String>[
      if (_booked) 'bed=${Uri.encodeComponent(widget.bedId!)}',
      if (_booked) 'k=${Uri.encodeComponent(widget.bookingCode!)}',
      if (find) 'find=1',
    ];
    return '/j/${widget.joinCode}/verify${q.isEmpty ? '' : '?${q.join('&')}'}';
  }

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        actions: const [Padding(padding: EdgeInsets.only(right: 8), child: LanguageButton())],
      ),
      body: FutureBuilder<Json>(
        future: _peek,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          if (snap.hasError) return ErrorView(error: snap.error!, onRetry: () => setState(() => _peek = _load()));
          final peek = snap.data!;
          final booking = peek['booking'] is Map ? Json.from(peek['booking'] as Map) : null;
          final hostel = peek['hostel_name'] as String? ?? '';
          final owner = peek['owner_name'] as String?;
          final city = peek['city'] as String?;
          final until = booking == null ? null : asDate(booking['held_until']);
          return PageList(children: [
            const SizedBox(height: 24),
            Text(t.welcomeTitle, textAlign: TextAlign.center, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.line),
              ),
              child: Column(children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: const LinearGradient(colors: [_indigo, _violet]),
                  ),
                  alignment: Alignment.center,
                  child: Text(hostel.isEmpty ? '?' : hostel[0].toUpperCase(),
                      style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),
                ),
                const SizedBox(height: 10),
                Text(hostel, textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                if (city != null && city.isNotEmpty) Text(city, style: const TextStyle(color: AppColors.muted)),
                if (owner != null) Text(t.ownerDot(owner), style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                if (booking != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: AppColors.successSoft, borderRadius: BorderRadius.circular(12)),
                    child: Text('🛏  ${t.bedHeldForYou('${booking['room_no']}', '${booking['bed_label']}')}',
                        textAlign: TextAlign.center, style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.w600)),
                  ),
                ],
              ]),
            ),
            if (until != null) ...[
              const SizedBox(height: 10),
              HoldTimer(until: until, onExpired: () {}),
            ],
            const SizedBox(height: 20),
            // Student registration (button below the hostel name)
            Material(
              color: _indigo,
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => context.push(_verifyRoute()),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(12)),
                      child: const Icon(Icons.person_add_alt_1_rounded, color: Colors.white),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(t.studentRegistration, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
                        Text(booking != null ? t.registrationStepsBooked : t.registrationSteps,
                            style: const TextStyle(color: Color(0xFFD3E2F7), fontSize: 12.5)),
                      ]),
                    ),
                    const Icon(Icons.chevron_right_rounded, color: Color(0xFFD3E2F7)),
                  ]),
                ),
              ),
            ),
            const SizedBox(height: 10),
            TextButton(onPressed: () => context.push(_verifyRoute(find: true)), child: Text(t.alreadyJoinedFind)),
            const SizedBox(height: 24),
            Text(t.noAccountNeeded, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
          ]);
        },
      ),
    );
  }
}
