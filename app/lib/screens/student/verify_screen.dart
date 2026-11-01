import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/errors.dart';
import '../../core/format.dart';
import '../../data/student_api.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import 'student_frame.dart';

/// Step 1 of 4: only the hostel name, language, mobile + one OTP. No hostel details,
/// rooms or prices are shown before the mobile is verified.
/// Opened from the owner's "Share with student" QR (bed + k in the link): step 1 of 3 and the
/// held bed, rent and deposit are shown; after the OTP the student goes straight to Your details.
class VerifyScreen extends StatefulWidget {
  const VerifyScreen({super.key, required this.joinCode, this.bedId, this.bookingCode, this.findBooking = false});
  final String joinCode;
  final String? bedId;
  final String? bookingCode;
  final bool findBooking;

  @override
  State<VerifyScreen> createState() => _VerifyScreenState();
}

/// Where to go after verification, by booking status.
String studentNextRoute(String joinCode, String? status, String token) {
  switch (status) {
    case 'pending_approval':
    case 'active':
    case 'notice':
    case 'vacated':
      return '/s/$token';
    default:
      return '/j/$joinCode/details'; // details first, then Profile → Room selection → Payment
  }
}

class _VerifyScreenState extends State<VerifyScreen> {
  final _form = GlobalKey<FormState>();
  final _phone = TextEditingController();
  final _otp = TextEditingController();
  late Future<Json> _peek = _start();
  String? _sentTo;
  String? _otpError;
  late bool _findBooking = widget.findBooking;
  int _resendIn = 0;
  DateTime? _lockedUntil;
  String? _ownerPhone;
  Timer? _timer;

  StudentApi get api => StudentApi.instance;

  bool get _booked => widget.bedId != null && widget.bookingCode != null;

  /// QR booking: take the held bed, then go to Your details. Returns null if the student
  /// has already joined (then the normal route is used).
  Future<String?> _takeBookedBed(String? status) async {
    if (!_booked) return null;
    if (status != null && !['draft', 'awaiting_payment', 'expired', 'rejected'].contains(status)) return null;
    await api.holdBooked(widget.bedId!, widget.bookingCode!);
    api.bookedBedId = widget.bedId;
    api.bookedCode = widget.bookingCode;
    return '/j/${widget.joinCode}/details';
  }

  /// If this phone already verified for this hostel, skip straight ahead.
  Future<Json> _start() async {
    final peek = await api.peek(widget.joinCode, bedId: widget.bedId, code: widget.bookingCode);
    final token = await api.savedToken(joinCode: widget.joinCode);
    if (token != null) {
      try {
        final h = await api.hostel();
        final booked = await _takeBookedBed(h['tenant_status'] as String?);
        if (mounted) {
          final route = booked ?? studentNextRoute(widget.joinCode, h['tenant_status'] as String?, token);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) context.go(route);
          });
        }
      } on AppException catch (e) {
        if (e.code == 'SESSION_INVALID') await api.forget();
      }
    }
    return peek;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _phone.dispose();
    _otp.dispose();
    super.dispose();
  }

  int get _lockLeft {
    final u = _lockedUntil;
    if (u == null) return 0;
    final left = u.difference(DateTime.now()).inSeconds;
    return left > 0 ? left : 0;
  }

  bool get _locked => _lockLeft > 0;

  /// One 1-second ticker for both the resend countdown and the lock countdown.
  void _ensureTicker() {
    if (_timer?.isActive ?? false) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        if (_resendIn > 0) _resendIn--;
        if (_lockedUntil != null && !_locked) _lockedUntil = null;
      });
      if (_resendIn == 0 && _lockedUntil == null) timer.cancel();
    });
  }

  void _startResendTimer() {
    setState(() => _resendIn = 30);
    _ensureTicker();
  }

  /// Too many wrong tries: show the lock screen with a countdown (server says 10 minutes).
  void _lock(AppException e) {
    final secs = e.extra['retry_after'] is num ? (e.extra['retry_after'] as num).toInt() : 600;
    setState(() {
      _lockedUntil = DateTime.now().add(Duration(seconds: secs));
      _ownerPhone = e.extra['owner_phone'] as String? ?? _ownerPhone;
      _otpError = null;
      _otp.clear();
    });
    _ensureTicker();
  }

  Future<void> _send() async {
    if (!_form.currentState!.validate()) return;
    final phone = normalizePhone(_phone.text)!;
    try {
      await api.sendOtp(widget.joinCode, phone);
    } catch (e) {
      final ex = AppException.from(e);
      if (ex.code == 'OTP_LOCKED') {
        if (mounted) _lock(ex);
        return;
      }
      rethrow;
    }
    setState(() {
      _sentTo = phone;
      _otpError = null;
      _otp.clear();
    });
    _startResendTimer();
  }

  Future<void> _verify() async {
    if (_otp.text.length != 6) {
      setState(() => _otpError = context.l10n.errOtpWrongSimple);
      return;
    }
    setState(() => _otpError = null);
    try {
      final status = await api.verifyOtp(widget.joinCode, _sentTo!, _otp.text);
      final booked = await _takeBookedBed(status);
      if (!mounted) return;
      context.go(booked ?? studentNextRoute(widget.joinCode, status, api.token!));
    } catch (e) {
      if (!mounted) return;
      final ex = AppException.from(e);
      if (ex.code == 'OTP_LOCKED') {
        _lock(ex);
        return;
      }
      setState(() {
        _otpError = errorText(context, e);
        if (ex.code == 'OTP_WRONG') _otp.clear();
      });
    }
  }

  String _mmss(int secs) => '${(secs ~/ 60).toString().padLeft(2, '0')}:${(secs % 60).toString().padLeft(2, '0')}';

  Widget _lockedCard() {
    final t = context.l10n;
    final phone = _ownerPhone;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(t.tooManyTriesTitle, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
      const SizedBox(height: 12),
      Banner2(tone: Tone.warning, icon: Icons.lock_clock_rounded, text: t.otpLockedTryAgain(_mmss(_lockLeft))),
      if (phone != null && phone.isNotEmpty)
        OutlinedButton.icon(
          icon: const Icon(Icons.call_rounded),
          label: Text(t.callOwner),
          onPressed: () => launchUrl(Uri(scheme: 'tel', path: phone)),
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(t.appName),
        actions: const [Padding(padding: EdgeInsets.only(right: 8), child: LanguageButton())],
      ),
      body: FutureBuilder<Json>(
        future: _peek,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return ErrorView(error: snap.error!, onRetry: () => setState(() => _peek = _start()));
          }
          final peek = snap.data!;
          final booking = peek['booking'] is Map ? Json.from(peek['booking'] as Map) : null;
          final step2 = _sentTo != null && !_locked;
          return LayoutBuilder(
            builder: (context, box) => SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: box.maxHeight - 48),
                child: Center(
                  child: Narrow(
                    maxWidth: 480,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        StepProgress(1, total: booking != null ? 4 : 5),
                        Text(peek['hostel_name'] as String? ?? '',
                            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                        if (booking != null) ...[
                          const SizedBox(height: 10),
                          BookedBedCard(booking: booking),
                        ],
                        const SizedBox(height: 16),
                        if (_locked)
                          _lockedCard()
                        else if (!step2) ...[
                          Text(_findBooking ? t.findBookingSubtitle : t.verifySubtitle,
                              style: const TextStyle(color: AppColors.muted)),
                          const SizedBox(height: 16),
                          if (peek['is_open'] != true && !_findBooking)
                            Banner2(tone: Tone.warning, text: t.hostelClosedStudent),
                          Form(key: _form, child: PhoneField(controller: _phone)),
                          const SizedBox(height: 14),
                          BusyButton(label: t.sendOtp, onPressed: _send),
                        ] else ...[
                          Text(t.enterOtpTitle,
                              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                          const SizedBox(height: 4),
                          Text(t.otpSentTo(phoneText(_sentTo)), style: const TextStyle(color: AppColors.muted)),
                          const SizedBox(height: 16),
                          OtpBoxes(controller: _otp, hasError: _otpError != null, onCompleted: () {}),
                          if (_otpError != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(_otpError!,
                                  style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600)),
                            ),
                          const SizedBox(height: 14),
                          BusyButton(label: t.verifyAndContinue, onPressed: _verify),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              TextButton(
                                onPressed: () => setState(() {
                                  _sentTo = null;
                                  _otpError = null;
                                  _otp.clear();
                                }),
                                child: Text(t.changeNumber),
                              ),
                              TextButton(
                                onPressed: _resendIn > 0
                                    ? null
                                    : () async {
                                        try {
                                          await api.sendOtp(widget.joinCode, _sentTo!);
                                          if (!mounted) return;
                                          showSnack(this.context, t.otpResent);
                                          setState(() {
                                            _otpError = null;
                                            _otp.clear();
                                          });
                                          _startResendTimer();
                                        } catch (e) {
                                          if (!mounted) return;
                                          final ex = AppException.from(e);
                                          if (ex.code == 'OTP_LOCKED') {
                                            _lock(ex);
                                          } else {
                                            setState(() => _otpError = errorText(this.context, e));
                                          }
                                        }
                                      },
                                child: Text(_resendIn > 0 ? t.resendIn('$_resendIn') : t.resendOtp),
                              ),
                            ],
                          ),
                        ],
                        if (booking != null) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(12)),
                            child: Row(children: [
                              const Icon(Icons.lock_outline_rounded, size: 18, color: AppColors.primary),
                              const SizedBox(width: 8),
                              Expanded(child: Text(t.noPasswordNote, style: const TextStyle(fontSize: 12.5))),
                            ]),
                          ),
                        ],
                        const SizedBox(height: 8),
                        if (!_findBooking && _sentTo == null && !_locked)
                          TextButton.icon(
                            icon: const Icon(Icons.search_rounded),
                            label: Text(t.findMyBooking),
                            onPressed: () => setState(() => _findBooking = true),
                          ),
                        const SizedBox(height: 16),
                        Text(t.agreeByContinuing,
                            textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                        Wrap(
                          alignment: WrapAlignment.center,
                          children: [
                            TextButton(onPressed: () => context.push('/privacy'), child: Text(t.privacyPolicy)),
                            TextButton(onPressed: () => context.push('/privacy?tab=terms'), child: Text(t.termsOfUse)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// The bed the owner held for this student (shown on the QR link): room, bed, rent, deposit
/// and how long it stays held. (The amount to pay is shown only on the payment step.)
class BookedBedCard extends StatelessWidget {
  const BookedBedCard({super.key, required this.booking, this.showTimer = true});
  final Json booking;
  final bool showTimer;

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    final until = asDate(booking['held_until']);
    Widget row(String l, String v, {bool strong = false}) => Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(children: [
            Expanded(
              child: Text(l,
                  style: TextStyle(
                      fontWeight: strong ? FontWeight.w600 : FontWeight.w600,
                      color: strong ? AppColors.ink : AppColors.muted)),
            ),
            Text(v,
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: strong ? 18 : 14,
                    color: strong ? AppColors.success : AppColors.ink)),
          ]),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (until != null && showTimer) HoldTimer(until: until, onExpired: () {}),
      SectionCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(color: AppColors.successSoft, borderRadius: BorderRadius.circular(12)),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text('${booking['room_no']}',
                    style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.success, height: 1.1)),
                Text('${booking['bed_label']}',
                    style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.success, height: 1.1)),
              ]),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t.bookBedTitle('${booking['room_no']}', '${booking['bed_label']}'),
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                Text('${booking['floor'] == 0 ? t.groundFloor : t.floorN('${booking['floor']}')} · ${t.sharingN('${booking['sharing']}')}',
                    style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
              ]),
            ),
          ]),
          const SizedBox(height: 4),
          row(t.rentPerMonth, money(asInt(booking['rent_month']))),
          row(t.securityDeposit, money(asInt(booking['deposit']))),
        ]),
      ),
    ]);
  }
}

