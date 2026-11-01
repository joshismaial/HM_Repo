import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/errors.dart';
import '../core/format.dart';
import '../core/locale_controller.dart';
import '../theme.dart';

/// Loads data once (and again on retry / pull-to-refresh) with loading, error and data states.
class Loader<T> extends StatefulWidget {
  const Loader({super.key, required this.load, required this.builder});
  final Future<T> Function() load;
  final Widget Function(BuildContext context, T data, Future<void> Function() reload) builder;

  @override
  State<Loader<T>> createState() => LoaderState<T>();
}

class LoaderState<T> extends State<Loader<T>> {
  late Future<T> _future = widget.load();

  Future<void> reload() async {
    final f = widget.load();
    setState(() => _future = f);
    try {
      await f;
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return ErrorView(error: snap.error!, onRetry: reload);
        }
        return widget.builder(context, snap.data as T, reload);
      },
    );
  }
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.error, this.onRetry});
  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    final offline = AppException.from(error).code == 'NETWORK';
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(offline ? Icons.wifi_off_rounded : Icons.error_outline_rounded, size: 48, color: AppColors.muted),
            const SizedBox(height: 12),
            Text(offline ? t.offlineTitle : t.errorTitle,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text(errorText(context, error), textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted)),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              SizedBox(width: 200, child: OutlinedButton(onPressed: onRetry, child: Text(t.tryAgain))),
            ],
          ],
        ),
      ),
    );
  }
}

class EmptyView extends StatelessWidget {
  const EmptyView({super.key, required this.icon, required this.title, required this.message, this.action});
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 32,
            backgroundColor: AppColors.primarySoft,
            child: Icon(icon, size: 30, color: AppColors.primary),
          ),
          const SizedBox(height: 14),
          Text(title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(message, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted)),
          if (action != null) ...[const SizedBox(height: 16), action!],
        ],
      ),
    );
  }
}

/// Very light shadow under bordered cards (the thin border keeps cards visible on dim, low-cost screens).
const appCardShadow = [BoxShadow(color: Color(0x0F0F172A), blurRadius: 2, offset: Offset(0, 1))];

class SectionCard extends StatelessWidget {
  const SectionCard({super.key, this.title, required this.child, this.trailing, this.padding});
  final String? title;
  final Widget child;
  final Widget? trailing;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
        boxShadow: appCardShadow,
      ),
      padding: padding ?? const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(title!,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                  ),
                  if (trailing != null) trailing!,
                ],
              ),
            ),
          child,
        ],
      ),
    );
  }
}

class InfoRow extends StatelessWidget {
  const InfoRow(this.label, this.value, {super.key, this.bold = false, this.trailing});
  final String label;
  final String value;
  final bool bold;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 4, child: Text(label, style: const TextStyle(color: AppColors.muted))),
          const SizedBox(width: 8),
          Expanded(
            flex: 6,
            child: Text(value,
                textAlign: TextAlign.end,
                style: TextStyle(fontWeight: bold ? FontWeight.w600 : FontWeight.w600)),
          ),
          if (trailing != null) ...[const SizedBox(width: 6), trailing!],
        ],
      ),
    );
  }
}

enum Tone { info, success, warning, danger, neutral }

class Chip2 extends StatelessWidget {
  const Chip2(this.text, {super.key, this.tone = Tone.neutral});
  final String text;
  final Tone tone;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (tone) {
      Tone.info => (AppColors.primarySoft, AppColors.primary),
      Tone.success => (AppColors.successSoft, AppColors.success),
      Tone.warning => (AppColors.warningSoft, AppColors.warning),
      Tone.danger => (AppColors.dangerSoft, AppColors.danger),
      Tone.neutral => (AppColors.ground, AppColors.muted),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16)),
      child: Text(text, style: TextStyle(color: fg, fontWeight: FontWeight.w600, fontSize: 12.5)),
    );
  }
}

class Banner2 extends StatelessWidget {
  const Banner2({super.key, required this.text, this.tone = Tone.info, this.icon});
  final String text;
  final Tone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (tone) {
      Tone.success => (AppColors.successSoft, AppColors.success),
      Tone.warning => (AppColors.warningSoft, AppColors.warning),
      Tone.danger => (AppColors.dangerSoft, AppColors.danger),
      _ => (AppColors.primarySoft, AppColors.primaryDark),
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon ?? Icons.info_outline_rounded, color: fg, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: TextStyle(color: fg, fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }
}

/// "Step 2 of 4" with a progress bar (student joining flow).
class StepProgress extends StatelessWidget {
  const StepProgress(this.step, {super.key, this.total = 4});
  final int step;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.l10n.stepOf('$step', '$total'),
              style: const TextStyle(color: AppColors.muted, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: step / total,
              minHeight: 6,
              backgroundColor: AppColors.primaryTint,
            ),
          ),
        ],
      ),
    );
  }
}

/// Button that shows a spinner while its async action runs and shows errors as a snackbar.
class BusyButton extends StatefulWidget {
  const BusyButton({super.key, required this.label, required this.onPressed, this.outlined = false, this.icon});
  final String label;
  final Future<void> Function()? onPressed;
  final bool outlined;
  final IconData? icon;

  @override
  State<BusyButton> createState() => _BusyButtonState();
}

class _BusyButtonState extends State<BusyButton> {
  bool _busy = false;

  Future<void> _tap() async {
    if (_busy || widget.onPressed == null) return;
    setState(() => _busy = true);
    try {
      await widget.onPressed!();
    } catch (e) {
      if (mounted) showSnack(context, errorText(context, e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final child = _busy
        ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.icon != null) ...[Icon(widget.icon, size: 20), const SizedBox(width: 8)],
              Flexible(child: Text(widget.label, textAlign: TextAlign.center)),
            ],
          );
    final onPressed = widget.onPressed == null ? null : _tap;
    return widget.outlined
        ? OutlinedButton(onPressed: onPressed, child: child)
        : FilledButton(onPressed: onPressed, child: child);
  }
}

void showSnack(BuildContext context, String text, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(text),
      backgroundColor: error ? AppColors.danger : null,
    ));
}

Future<bool> confirm(BuildContext context, {required String title, required String message, required String okLabel, bool danger = false}) async {
  final t = context.l10n;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t.cancel)),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: danger ? TextButton.styleFrom(foregroundColor: AppColors.danger) : null,
          child: Text(okLabel),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// Mobile number field with a fixed +91.
class PhoneField extends StatelessWidget {
  const PhoneField({super.key, required this.controller, this.label, this.required = true, this.enabled = true});
  final TextEditingController controller;
  final String? label;
  final bool required;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    return TextFormField(
      controller: controller,
      enabled: enabled,
      keyboardType: TextInputType.phone,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)],
      decoration: InputDecoration(labelText: label ?? t.mobileNumber, prefixText: '+91  '),
      validator: (v) {
        final s = (v ?? '').trim();
        if (s.isEmpty) return required ? t.required : null;
        return normalizePhone(s) == null ? t.errBadPhone : null;
      },
    );
  }
}

class OtpField extends StatelessWidget {
  const OtpField({super.key, required this.controller, this.errorText, this.onCompleted});
  final TextEditingController controller;
  final String? errorText;
  final VoidCallback? onCompleted;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      autofillHints: const [AutofillHints.oneTimeCode],
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 24, letterSpacing: 14, fontWeight: FontWeight.w800),
      inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
      decoration: InputDecoration(
        labelText: context.l10n.otpLabel,
        errorText: errorText,
        errorMaxLines: 3,
      ),
      onChanged: (v) {
        if (v.length == 6) onCompleted?.call();
      },
    );
  }
}

/// Six OTP boxes driven by one hidden text field (so SMS auto-fill and paste still work).
class OtpBoxes extends StatefulWidget {
  const OtpBoxes({super.key, required this.controller, this.hasError = false, this.enabled = true, this.onCompleted});
  final TextEditingController controller;
  final bool hasError;
  final bool enabled;
  final VoidCallback? onCompleted;

  @override
  State<OtpBoxes> createState() => _OtpBoxesState();
}

class _OtpBoxesState extends State<OtpBoxes> {
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    _focus.addListener(_changed);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    _focus.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.controller.text;
    final active = _focus.hasFocus && widget.enabled ? text.length.clamp(0, 5) : -1;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.enabled ? () => _focus.requestFocus() : null,
      child: Stack(children: [
        Row(
          children: [
            for (var i = 0; i < 6; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(
                child: Container(
                  height: 56,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: widget.enabled ? Colors.white : AppColors.ground,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: widget.hasError
                          ? AppColors.danger
                          : i == active
                              ? AppColors.primary
                              : AppColors.field,
                      width: i == active || widget.hasError ? 2 : 1.5,
                    ),
                  ),
                  child: Text(i < text.length ? text[i] : '',
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                ),
              ),
            ],
          ],
        ),
        // Hidden field: receives typing, paste and the SMS one-time-code suggestion.
        Positioned.fill(
          child: Opacity(
            opacity: 0,
            child: TextField(
              controller: widget.controller,
              focusNode: _focus,
              enabled: widget.enabled,
              autofocus: true,
              keyboardType: TextInputType.number,
              autofillHints: const [AutofillHints.oneTimeCode],
              showCursor: false,
              enableInteractiveSelection: false,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
              onChanged: (v) {
                if (v.length == 6) widget.onCompleted?.call();
              },
            ),
          ),
        ),
      ]),
    );
  }
}

class PasswordField extends StatefulWidget {
  const PasswordField({super.key, required this.controller, this.label, this.checkStrength = false});
  final TextEditingController controller;
  final String? label;
  final bool checkStrength;

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _hidden = true;

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    return TextFormField(
      controller: widget.controller,
      obscureText: _hidden,
      autofillHints: const [AutofillHints.password],
      decoration: InputDecoration(
        labelText: widget.label ?? t.password,
        helperText: widget.checkStrength ? t.passwordHint : null,
        suffixIcon: IconButton(
          tooltip: _hidden ? t.showPassword : t.hidePassword,
          icon: Icon(_hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined),
          onPressed: () => setState(() => _hidden = !_hidden),
        ),
      ),
      validator: (v) {
        final s = v ?? '';
        if (s.isEmpty) return t.required;
        if (widget.checkStrength && s.length < 8) return t.errWeakPassword;
        return null;
      },
    );
  }
}

/// Language dropdown (English / हिन्दी / తెలుగు).
class LanguageButton extends StatelessWidget {
  const LanguageButton({super.key, this.onChanged});
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final ctrl = LocaleScope.of(context);
    return PopupMenuButton<String>(
      tooltip: context.l10n.language,
      initialValue: ctrl.locale.languageCode,
      onSelected: (code) {
        ctrl.setLanguage(code);
        onChanged?.call(code);
      },
      itemBuilder: (_) => [
        for (final e in appLanguages.entries) PopupMenuItem(value: e.key, child: Text(e.value)),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.field),
          borderRadius: BorderRadius.circular(16),
          color: Colors.white,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.translate_rounded, size: 18),
            const SizedBox(width: 6),
            Text(appLanguages[ctrl.locale.languageCode] ?? 'English',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const Icon(Icons.arrow_drop_down_rounded),
          ],
        ),
      ),
    );
  }
}

/// Centers content and limits width (nice on web / tablets).
class Narrow extends StatelessWidget {
  const Narrow({super.key, required this.child, this.maxWidth = 560});
  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(constraints: BoxConstraints(maxWidth: maxWidth), child: child),
    );
  }
}

/// Scrollable page body with standard padding.
class PageList extends StatelessWidget {
  const PageList({super.key, required this.children, this.onRefresh});
  final List<Widget> children;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final list = ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [Narrow(maxWidth: 640, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children))],
    );
    return onRefresh == null ? list : RefreshIndicator(onRefresh: onRefresh!, child: list);
  }
}

Future<void> copyText(BuildContext context, String text) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) showSnack(context, context.l10n.copied);
}

// Hostel name shown as "Name – Type" (22 Oct 2026). Words that only say who the hostel is for
// (Ladies, Girls, Gents, Boys, Men's, Women's, Co-living, PG) are dropped from the display;
// the name the owner typed stays unchanged in the database.
const _typeWords = {'ladies', 'girls', 'women', 'womens', 'gents', 'boys', 'men', 'mens', 'coliving', 'pg'};
String _normWord(String w) => w.toLowerCase().replaceAll(RegExp(r"[’'`.\-]"), '');

/// "Sai Residency Ladies PG" -> "Sai Residency".
String cleanHostelName(String? name) {
  final words = (name ?? '').trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  final out = <String>[];
  for (var i = 0; i < words.length; i++) {
    final w = _normWord(words[i]);
    if (w == 'co' && i + 1 < words.length && _normWord(words[i + 1]) == 'living') {
      i++; // "Co Living"
      continue;
    }
    if (!_typeWords.contains(w)) out.add(words[i]);
  }
  return out.isEmpty ? (name ?? '').trim() : out.join(' ');
}

/// "Sai Residency – Women's". The type is joined with no-break spaces so it never splits across lines.
String hostelTitle(BuildContext context, Json? hostel) {
  if (hostel == null) return '';
  final t = context.l10n;
  final type = switch (hostel['type']) {
    'mens' => t.typeMens,
    'womens' => t.typeWomens,
    'coliving' => t.typeColiving,
    _ => '',
  };
  final clean = cleanHostelName(hostel['name'] as String?);
  return type.isEmpty ? clean : '$clean\u00A0–\u00A0${type.replaceAll('-', '\u2011')}';
}

/// Short name of a hostel: first letters of its words, at most 3 (first word + last two).
/// "Elite Deluxe Women's Hostel" -> "EWH", "Sunrise Boys PG" -> "SBP", "Nest Co-living" -> "NC".
String hostelShortName(String? name) {
  final words = (name ?? '').trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  final pick = words.length > 3 ? [words.first, ...words.sublist(words.length - 2)] : words;
  final letters = pick.map((w) {
    final m = RegExp(r'[A-Za-z0-9]').firstMatch(w);
    return m == null ? '' : m.group(0)!.toUpperCase();
  }).join();
  return letters.isEmpty ? '?' : letters;
}

/// Box with the hostel's short name. Shown where the hostel photo will go (photos come in Phase 2).
/// [onBlue]: white box for the blue Home header; otherwise light blue.
class HostelShortNameBox extends StatelessWidget {
  const HostelShortNameBox({super.key, required this.name, this.width = 56, this.height = 56, this.onBlue = false});
  final String? name;
  final double width;
  final double height;
  final bool onBlue;

  @override
  Widget build(BuildContext context) {
    final s = hostelShortName(cleanHostelName(name));
    return Semantics(
      label: name,
      excludeSemantics: true,
      child: Container(
        width: width,
        height: height,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: onBlue ? Colors.white : AppColors.primaryTint,
          borderRadius: BorderRadius.circular(12),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(s,
                maxLines: 1,
                style: TextStyle(
                    fontSize: (s.length > 2 ? 0.32 : 0.38) * width,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                    color: AppColors.primary)),
          ),
        ),
      ),
    );
  }
}

/// Lifted floating tab bar (22 Oct 2026): white rounded bar with a thin border and light shadow,
/// 14 px above the phone's gesture area. It sits in the page flow, so no card ever hides behind it.
class FloatingTabBar extends StatelessWidget {
  const FloatingTabBar({super.key, required this.child});
  final Widget child; // a NavigationBar

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.ground,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 14),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: AppColors.line),
              boxShadow: const [BoxShadow(color: Color(0x140F172A), blurRadius: 6, offset: Offset(0, 2))],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(26),
              child: MediaQuery.removePadding(context: context, removeBottom: true, child: child),
            ),
          ),
        ),
      ),
    );
  }
}
