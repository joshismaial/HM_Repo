import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../widgets/common.dart';
import 'hostel_scope.dart';

/// Bottom tab bar inside a hostel: Home · Requests · Tenants · Rent · More.
/// Sub-screens keep the bar with their parent tab highlighted.
class OwnerShell extends StatefulWidget {
  const OwnerShell({super.key, required this.hostelId, required this.location, required this.child});
  final String hostelId;
  final String location;
  final Widget child;

  @override
  State<OwnerShell> createState() => _OwnerShellState();
}

class _OwnerShellState extends State<OwnerShell> {
  late HostelState _state = HostelState(widget.hostelId);

  @override
  void didUpdateWidget(OwnerShell old) {
    super.didUpdateWidget(old);
    if (old.hostelId != widget.hostelId) {
      _state.dispose();
      _state = HostelState(widget.hostelId);
    } else if (old.location != widget.location) {
      _state.refresh(); // keep badges fresh when moving between tabs
    }
  }

  @override
  void dispose() {
    _state.dispose();
    super.dispose();
  }

  static const _tabs = ['home', 'requests', 'rooms', 'rent', 'more'];

  int get _index {
    final parts = widget.location.split('/'); // ['', 'h', hid, section, ...]
    final section = parts.length > 3 ? parts[3] : 'home';
    if (['settings', 'invite', 'manage-rooms', 'reports', 'tenant-rooms', 'sharing-prices', 'staff', 'notices'].contains(section)) {
      return 4; // under More
    }
    if (section == 'tenants' || section == 'complaints') return 0; // opened from Home
    if (section == 'share-bed') return 2; // QR for a bed, opened from Rooms
    final i = _tabs.indexOf(section);
    return i < 0 ? 0 : i;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    return HostelScope(
      state: _state,
      child: Scaffold(
        body: widget.child,
        bottomNavigationBar: ListenableBuilder(
          listenable: _state,
          builder: (context, _) {
            final requests = _state.requestsCount;
            return FloatingTabBar(
                child: NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: (i) => context.go('/h/${widget.hostelId}/${_tabs[i]}'),
              destinations: [
                NavigationDestination(icon: const Icon(Icons.home_outlined), selectedIcon: const Icon(Icons.home_rounded), label: t.tabHome),
                NavigationDestination(
                  icon: Badge(isLabelVisible: requests > 0, label: Text('$requests'), child: const Icon(Icons.inbox_outlined)),
                  selectedIcon: Badge(isLabelVisible: requests > 0, label: Text('$requests'), child: const Icon(Icons.inbox_rounded)),
                  label: t.tabRequests,
                ),
                NavigationDestination(icon: const Icon(Icons.bed_outlined), selectedIcon: const Icon(Icons.bed_rounded), label: t.tabRooms),
                NavigationDestination(icon: const Icon(Icons.currency_rupee_rounded), label: t.tabRent),
                NavigationDestination(icon: const Icon(Icons.menu_rounded), label: t.tabMore),
              ],
            ));
          },
        ),
      ),
    );
  }
}
