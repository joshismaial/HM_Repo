import 'package:flutter/material.dart';

import '../../core/back_nav.dart';
import '../../core/errors.dart';
import '../../core/format.dart';
import '../../data/owner_repo.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

/// Delete account (Google Play / App Store rule): explain, optional reason, type DELETE, one OTP.
/// The account is removed after 7 days; logging in again within 7 days cancels it.
class DeleteAccountScreen extends StatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  State<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends State<DeleteAccountScreen> {
  final _confirmText = TextEditingController();
  final _reason = TextEditingController();
  final _otp = TextEditingController();
  bool _otpSent = false;
  String? _otpError;

  @override
  void dispose() {
    _confirmText.dispose();
    _reason.dispose();
    _otp.dispose();
    super.dispose();
  }

  String? get _phone {
    final p = supa.auth.currentUser?.phone;
    if (p == null || p.isEmpty) return null;
    return p.startsWith('+') ? p : '+$p';
  }

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    final ready = _confirmText.text.trim().toUpperCase() == 'DELETE';
    return Scaffold(
      appBar: AppBar(
        title: Text(t.deleteAccount),
        leading: const AppBackButton(),
      ),
      body: PageList(
        children: [
          Banner2(tone: Tone.danger, icon: Icons.warning_amber_rounded, text: t.deleteWarning),
          SectionCard(
            title: t.whatIsDeleted,
            child: Text(t.whatIsDeletedList, style: const TextStyle(height: 1.6)),
          ),
          SectionCard(
            title: t.whatIsKept,
            child: Text(t.whatIsKeptText, style: const TextStyle(height: 1.5)),
          ),
          TextField(
            controller: _reason,
            maxLines: 2,
            decoration: InputDecoration(labelText: t.reasonOptional),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _confirmText,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(labelText: t.typeDelete),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 14),
          if (!_otpSent)
            BusyButton(
              label: t.sendOtp,
              onPressed: ready && _phone != null
                  ? () async {
                      await OwnerRepo.instance.sendLoginOtp(_phone!);
                      setState(() => _otpSent = true);
                    }
                  : null,
            )
          else ...[
            Text(t.otpSentTo(phoneText(_phone))),
            const SizedBox(height: 8),
            OtpField(controller: _otp, errorText: _otpError),
            const SizedBox(height: 14),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
              onPressed: () async {
                setState(() => _otpError = null);
                try {
                  await OwnerRepo.instance.verifyLoginOtp(_phone!, _otp.text);
                  await OwnerRepo.instance.requestAccountDeletion();
                  if (!context.mounted) return;
                  await showDialog<void>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: Text(t.deletionRequestedTitle),
                      content: Text(t.deletionRequestedText),
                      actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: Text(t.ok))],
                    ),
                  );
                  await OwnerRepo.instance.logout();
                } catch (e) {
                  if (mounted) setState(() => _otpError = errorText(this.context, e));
                }
              },
              child: Text(t.deleteMyAccount),
            ),
          ],
        ],
      ),
    );
  }
}
