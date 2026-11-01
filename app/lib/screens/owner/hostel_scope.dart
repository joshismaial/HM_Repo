import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../data/owner_repo.dart';

/// The hostel the owner is working in: its settings and Home numbers. Screens call
/// [refresh] after changes so badges and counts stay up to date.
class HostelState extends ChangeNotifier {
  HostelState(this.hostelId) {
    refresh();
  }
  final String hostelId;
  Json? hostel;
  Json? summary;
  Object? error;
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<void> refresh() async {
    try {
      final results = await Future.wait([
        OwnerRepo.instance.hostel(hostelId),
        OwnerRepo.instance.summary(hostelId),
      ]);
      hostel = results[0];
      summary = results[1];
      error = null;
    } catch (e) {
      error = e;
    }
    if (!_disposed) notifyListeners();
  }

  int get requestsCount => asInt(summary?['payments_to_check']) + asInt(summary?['joins_to_approve']);
}

class HostelScope extends InheritedNotifier<HostelState> {
  const HostelScope({super.key, required HostelState state, required super.child}) : super(notifier: state);

  static HostelState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<HostelScope>()!.notifier!;

  /// Same as [of] but without rebuilding when it changes (for button handlers).
  static HostelState read(BuildContext context) =>
      (context.getElementForInheritedWidgetOfExactType<HostelScope>()!.widget as HostelScope).notifier!;
}
