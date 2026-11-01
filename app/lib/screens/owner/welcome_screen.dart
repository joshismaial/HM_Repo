import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/format.dart';
import '../../data/owner_repo.dart';

// Login splash (22 Oct 2026): solid Trust blue background, white check circle and white text.
const _bg = Color(0xFF1560BD);
const _tick = Colors.white;
const _tickIcon = Color(0xFF1560BD);
const _ring = Color(0x2EFFFFFF);
const _label = Color(0xFFD6ECFC);
const _ink = Colors.white;
const _muted = Color(0xFFD6ECFC);
const _track = Color(0x40FFFFFF);
const _brand = Color(0xFFD6ECFC);

/// Shown for a moment right after the owner logs in, then opens My hostels by itself
/// (tap anywhere to skip).
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  Timer? _timer;
  String? _name;
  bool _left = false;

  @override
  void initState() {
    super.initState();
    final meta = Supabase.instance.client.auth.currentUser?.userMetadata;
    _name = _firstName(meta?['full_name'] as String?);
    if (_name == null) {
      OwnerRepo.instance.profile().then((p) {
        if (mounted) setState(() => _name = _firstName(p?['full_name'] as String?));
      }).catchError((_) {});
    }
    _timer = Timer(const Duration(milliseconds: 1500), _open);
  }

  String? _firstName(String? full) {
    final parts = (full ?? '').trim().split(RegExp(r'\s+')).where((x) => x.isNotEmpty).toList();
    return parts.isEmpty ? null : parts.first;
  }

  void _open() {
    if (!mounted || _left) return;
    _left = true;
    context.go('/hostels');
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    return Scaffold(
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _open,
        child: Container(
          color: _bg,
          child: SafeArea(
            child: Column(children: [
              Expanded(
                child: Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0.6, end: 1),
                      duration: const Duration(milliseconds: 450),
                      curve: Curves.easeOutBack,
                      builder: (context, v, child) => Transform.scale(scale: v, child: child),
                      child: Container(
                        width: 108,
                        height: 108,
                        decoration: const BoxDecoration(color: _ring, shape: BoxShape.circle),
                        alignment: Alignment.center,
                        child: Container(
                          width: 84,
                          height: 84,
                          decoration: const BoxDecoration(color: _tick, shape: BoxShape.circle),
                          child: const Icon(Icons.check_rounded, color: _tickIcon, size: 48),
                        ),
                      ),
                    ),
                    const SizedBox(height: 26),
                    Text(t.loggedInLabel,
                        style: const TextStyle(color: _label, fontSize: 14, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text(_name == null ? t.welcomePlain : t.welcomeName(_name!),
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: _ink, fontSize: 24, fontWeight: FontWeight.w800)),
                    ),
                    const SizedBox(height: 40),
                    const SizedBox(
                      width: 26,
                      height: 26,
                      child: CircularProgressIndicator(strokeWidth: 3, color: _ink, backgroundColor: _track),
                    ),
                    const SizedBox(height: 10),
                    Text(t.openingMyHostels, style: const TextStyle(color: _muted, fontSize: 12.5)),
                  ]),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: Text(t.appName,
                    style: const TextStyle(color: _brand, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
