import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/back_nav.dart';
import '../../core/format.dart';
import '../../data/owner_repo.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

String tenantStatusLabel(BuildContext context, String? s) {
  final t = context.l10n;
  return switch (s) {
    'active' => t.statusActive,
    'notice' => t.statusNotice,
    'pending_approval' => t.statusPending,
    'awaiting_payment' => t.statusAwaitingPayment,
    'vacated' => t.statusVacated,
    'rejected' => t.statusRejected,
    'expired' => t.statusExpired,
    _ => t.statusDraft,
  };
}

Tone tenantStatusTone(String? s) => switch (s) {
      'active' => Tone.success,
      'notice' => Tone.warning,
      'pending_approval' || 'awaiting_payment' => Tone.info,
      'rejected' || 'expired' => Tone.danger,
      _ => Tone.neutral,
    };

class TenantsScreen extends StatefulWidget {
  const TenantsScreen({super.key, required this.hostelId});
  final String hostelId;

  @override
  State<TenantsScreen> createState() => _TenantsScreenState();
}

class _TenantsScreenState extends State<TenantsScreen> {
  String _filter = 'living';
  String _search = '';
  bool _initial = true;

  static const _statuses = {
    'living': ['active', 'notice'],
    'notice': ['notice'],
    'pending': ['pending_approval'],
    'left': ['vacated'],
  };

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initial) {
      _initial = false;
      final f = GoRouterState.of(context).uri.queryParameters['filter'];
      if (f != null && _statuses.containsKey(f)) _filter = f;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    final labels = {'living': t.filterLiving, 'notice': t.filterLeaving, 'pending': t.filterPending, 'left': t.filterLeft};
    return Scaffold(
      appBar: AppBar(
        title: Text(t.tabTenants),
        leading: const AppBackButton(),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              decoration: InputDecoration(prefixIcon: const Icon(Icons.search_rounded), hintText: t.searchTenants),
              onChanged: (v) => setState(() => _search = v.trim().toLowerCase()),
            ),
          ),
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              children: [
                for (final e in labels.entries)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(e.value),
                      selected: _filter == e.key,
                      onSelected: (_) => setState(() => _filter = e.key),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: Loader<List<Json>>(
              key: ValueKey(_filter),
              load: () => OwnerRepo.instance.tenants(widget.hostelId, _statuses[_filter]!),
              builder: (context, all, reload) {
                final list = _search.isEmpty
                    ? all
                    : all.where((x) {
                        final name = (x['full_name'] ?? '').toString().toLowerCase();
                        final phone = (x['phone'] ?? '').toString();
                        final bed = x['beds'] as Map?;
                        final room = ((bed?['rooms'] as Map?)?['room_no'] ?? '').toString().toLowerCase();
                        return name.contains(_search) || phone.contains(_search) || room == _search;
                      }).toList();
                if (list.isEmpty) {
                  return ListView(children: [
                    EmptyView(
                      icon: Icons.people_outline_rounded,
                      title: _search.isEmpty ? t.noTenantsTitle : t.noResults,
                      message: _search.isEmpty ? t.noTenantsMessage : t.noResultsMessage,
                      action: _search.isEmpty && _filter == 'living'
                          ? SizedBox(
                              width: 240,
                              child: OutlinedButton(
                                onPressed: () => context.go('/h/${widget.hostelId}/invite'),
                                child: Text(t.inviteStudents),
                              ),
                            )
                          : null,
                    ),
                  ]);
                }
                return RefreshIndicator(
                  onRefresh: reload,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final x = list[i];
                      final bed = x['beds'] as Map?;
                      final room = (bed?['rooms'] as Map?)?['room_no'];
                      final name = (x['full_name'] as String?) ?? phoneText(x['phone'] as String?);
                      return Material(
                        color: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12), side: const BorderSide(color: AppColors.line)),
                        child: ListTile(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          leading: CircleAvatar(
                            backgroundColor: AppColors.primarySoft,
                            child: Text(name.isEmpty ? '?' : name.characters.first.toUpperCase(),
                                style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600)),
                          ),
                          title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(
                            '${t.room} ${roomBed(room, bed?['label'])} · ${t.joinedOn(shortDate(context, x['joining_date']))}'
                            '${x['status'] == 'notice' ? ' · ${t.leavesOn(shortDate(context, x['leaving_date']))}' : ''}',
                          ),
                          trailing: Chip2(tenantStatusLabel(context, x['status'] as String?),
                              tone: tenantStatusTone(x['status'] as String?)),
                          onTap: () => context.go('/h/${widget.hostelId}/tenants/${x['id']}'),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
