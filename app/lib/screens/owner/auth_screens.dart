import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/back_nav.dart';
import '../../core/errors.dart';
import '../../core/format.dart';
import '../../core/locale_controller.dart';
import '../../data/owner_repo.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

class _AuthFrame extends StatelessWidget {
  const _AuthFrame({required this.title, this.subtitle, required this.children, this.showBack = false});
  final String title;
  final String? subtitle;
  final List<Widget> children;
  final bool showBack;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.ground,
        automaticallyImplyLeading: false,
        leading: showBack
            ? IconButton(
                tooltip: context.l10n.back,
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => goBack(context),
              )
            : null,
        actions: const [Padding(padding: EdgeInsets.only(right: 12), child: LanguageButton())],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            Narrow(
              maxWidth: 440,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(12)),
                        child: const Icon(Icons.apartment_rounded, color: Colors.white),
                      ),
                      const SizedBox(width: 10),
                      Text(context.l10n.appName,
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Text(title, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 6),
                    Text(subtitle!, style: const TextStyle(color: AppColors.muted)),
                  ],
                  const SizedBox(height: 20),
                  ...children,
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- Login
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _phone = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    _phone.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_form.currentState!.validate()) return;
    final t = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    await OwnerRepo.instance.login(normalizePhone(_phone.text)!, _password.text);
    final cancelled = await OwnerRepo.instance.cancelDeletionIfRequested().catchError((_) => false);
    if (cancelled) messenger.showSnackBar(SnackBar(content: Text(t.deletionCancelled)));
    // The router shows the welcome screen (then My hostels) once the login is saved.
  }

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    return _AuthFrame(
      title: t.ownerLoginTitle,
      subtitle: t.ownerLoginSubtitle,
      children: [
        Form(
          key: _form,
          child: AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PhoneField(controller: _phone),
                const SizedBox(height: 14),
                PasswordField(controller: _password),
              ],
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(onPressed: () => context.push('/forgot'), child: Text(t.forgotPassword)),
        ),
        const SizedBox(height: 8),
        BusyButton(label: t.login, onPressed: _login),
        const SizedBox(height: 12),
        OutlinedButton(onPressed: () => context.push('/signup'), child: Text(t.createAccount)),
        const SizedBox(height: 24),
        Banner2(icon: Icons.qr_code_scanner_rounded, text: t.studentNote),
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.center,
          children: [
            TextButton(onPressed: () => context.push('/privacy'), child: Text(t.privacyPolicy)),
            TextButton(onPressed: () => context.push('/privacy?tab=terms'), child: Text(t.termsOfUse)),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- Sign up
class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _otp = TextEditingController();
  String? _sentTo;
  String? _otpError;
  bool _agreed = false;

  @override
  void dispose() {
    for (final c in [_name, _phone, _password, _otp]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _send() async {
    if (!_form.currentState!.validate()) return;
    if (!_agreed) {
      showSnack(context, context.l10n.errConsent, error: true);
      return;
    }
    final phone = normalizePhone(_phone.text)!;
    final lang = LocaleScope.of(context).locale.languageCode;
    await OwnerRepo.instance.signUp(phone: phone, password: _password.text, name: _name.text.trim(), language: lang);
    setState(() => _sentTo = phone);
  }

  Future<void> _verify() async {
    setState(() => _otpError = null);
    try {
      await OwnerRepo.instance.verifySignUp(_sentTo!, _otp.text);
      // Logged in now: the router opens "My hostels" (first time: Register hostel).
    } catch (e) {
      if (mounted) setState(() => _otpError = errorText(context, e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    if (_sentTo != null) {
      return _AuthFrame(
        showBack: true,
        title: t.verifyMobileTitle,
        subtitle: t.otpSentTo(phoneText(_sentTo)),
        children: [
          OtpField(controller: _otp, errorText: _otpError),
          const SizedBox(height: 16),
          BusyButton(label: t.verifyAndContinue, onPressed: _verify),
          TextButton(
            onPressed: () async {
              try {
                await OwnerRepo.instance.resendSignUpOtp(_sentTo!);
                if (context.mounted) showSnack(context, t.otpResent);
              } catch (e) {
                if (context.mounted) showSnack(context, errorText(context, e), error: true);
              }
            },
            child: Text(t.resendOtp),
          ),
          TextButton(onPressed: () => setState(() => _sentTo = null), child: Text(t.changeNumber)),
        ],
      );
    }
    return _AuthFrame(
      showBack: true,
      title: t.signUpTitle,
      subtitle: t.signUpSubtitle,
      children: [
        Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(labelText: t.yourName),
                validator: (v) => (v ?? '').trim().length < 2 ? t.required : null,
              ),
              const SizedBox(height: 14),
              PhoneField(controller: _phone),
              const SizedBox(height: 14),
              PasswordField(controller: _password, checkStrength: true),
            ],
          ),
        ),
        const SizedBox(height: 8),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: _agreed,
          onChanged: (v) => setState(() => _agreed = v ?? false),
          title: Text(t.agreeTerms),
          subtitle: Align(
            alignment: Alignment.centerLeft,
            child: TextButton(onPressed: () => context.push('/privacy'), child: Text(t.readPolicy)),
          ),
        ),
        const SizedBox(height: 8),
        BusyButton(label: t.sendOtp, onPressed: _send),
        const SizedBox(height: 12),
        TextButton(onPressed: () => context.go('/login'), child: Text(t.haveAccount)),
      ],
    );
  }
}

// ---------------------------------------------------------------- Forgot password
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _phoneForm = GlobalKey<FormState>();
  final _passForm = GlobalKey<FormState>();
  final _phone = TextEditingController();
  final _otp = TextEditingController();
  final _password = TextEditingController();
  int _step = 0; // 0 = mobile, 1 = OTP, 2 = new password
  String? _otpError;

  @override
  void dispose() {
    _phone.dispose();
    _otp.dispose();
    _password.dispose();
    super.dispose();
  }

  String get _number => normalizePhone(_phone.text)!;

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    switch (_step) {
      case 0:
        return _AuthFrame(
          showBack: true,
          title: t.forgotTitle,
          subtitle: t.forgotSubtitle,
          children: [
            Form(key: _phoneForm, child: PhoneField(controller: _phone)),
            const SizedBox(height: 16),
            BusyButton(
              label: t.sendOtp,
              onPressed: () async {
                if (!_phoneForm.currentState!.validate()) return;
                await OwnerRepo.instance.sendLoginOtp(_number);
                setState(() => _step = 1);
              },
            ),
          ],
        );
      case 1:
        return _AuthFrame(
          showBack: true,
          title: t.verifyMobileTitle,
          subtitle: t.otpSentTo(phoneText(_number)),
          children: [
            OtpField(controller: _otp, errorText: _otpError),
            const SizedBox(height: 16),
            BusyButton(
              label: t.verifyAndContinue,
              onPressed: () async {
                setState(() => _otpError = null);
                try {
                  await OwnerRepo.instance.verifyLoginOtp(_number, _otp.text);
                  setState(() => _step = 2);
                } catch (e) {
                  if (mounted) setState(() => _otpError = errorText(context, e));
                }
              },
            ),
            TextButton(onPressed: () => setState(() => _step = 0), child: Text(t.changeNumber)),
          ],
        );
      default:
        return _AuthFrame(
          title: t.newPasswordTitle,
          children: [
            Form(key: _passForm, child: PasswordField(controller: _password, label: t.newPassword, checkStrength: true)),
            const SizedBox(height: 16),
            BusyButton(
              label: t.savePassword,
              onPressed: () async {
                if (!_passForm.currentState!.validate()) return;
                await OwnerRepo.instance.setPassword(_password.text);
                await OwnerRepo.instance.cancelDeletionIfRequested().catchError((_) => false);
                if (mounted) {
                  showSnack(context, t.passwordSaved);
                  context.go('/hostels');
                }
              },
            ),
          ],
        );
    }
  }
}

// ---------------------------------------------------------------- 404
class NotFoundScreen extends StatelessWidget {
  const NotFoundScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    return Scaffold(
      body: Center(
        child: EmptyView(
          icon: Icons.link_off_rounded,
          title: t.notFoundTitle,
          message: t.notFoundMessage,
          action: SizedBox(width: 220, child: FilledButton(onPressed: () => context.go('/'), child: Text(t.goHome))),
        ),
      ),
    );
  }
}
