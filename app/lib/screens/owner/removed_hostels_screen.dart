import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/back_nav.dart';
import '../../core/errors.dart';
import '../../core/format.dart';
import '../../data/owner_repo.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

class _RemovedData {
  _RemovedData(this.removed, this.tenants);
  final List<Json> removed; // newest removal first
  final Map<String, int> tenants; // hostel id -> tenants living there
}

/// "Removed hostels": hostels the owner removed from My hostels, with Restore.
/// Opened from My hostels, More (You) and Register hostel.
class RemovedHostelsScreen extends StatelessWidget {
  const RemovedHostelsScreen({super.key});

  Future<_RemovedData> _load() async {
    final all = await OwnerRepo.instance.hostels();
    final removed = all.where((h) => h['archived_at'] != null).toList()
      ..sort((a, b) => (b['archived_at'] as String).compareTo(a['archived_at'] as String));
    final counts = await OwnerRepo.instance
        .tenantCounts([for (final h in removed) h['id'] as String]).catchError((_) => <String, int>{});
    return _RemovedData(removed, counts);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(t.removedHostels), leading: const AppBackButton()),
      body: Loader<_RemovedData>(
        load: _load,
        builder: (context, data, reload) {
          if (data.removed.isEmpty) {
            return Center(
              child: EmptyView(icon: Icons.inventory_2_outlined, title: t.noRemovedTitle, message: t.noRemovedBody),
            );
          }
          return PageList(
            onRefresh: reload,
            children: [
              for (final h in data.removed) _RemovedCard(hostel: h, tenants: data.tenants[h['id']] ?? 0),
              const SizedBox(height: 4),
              Text(t.removedKeepsData,
                  textAlign: TextAlign.center, style: const TextStyle(fontSize: 12.5, color: AppColors.muted)),
            ],
          );
        },
      ),
    );
  }
}

String _dateText(String iso) {
  final d = DateTime.tryParse(iso)?.toLocal();
  if (d == null) return '';
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.day)}/${two(d.month)}/${d.year}';
}

class _RemovedCard extends StatelessWidget {
  const _RemovedCard({required this.hostel, required this.tenants});
  final Json hostel;
  final int tenants;

  Future<void> _restore(BuildContext context) async {
    final name = (hostel['name'] ?? '').toString();
    final ok = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (ctx) => _RestoreSheet(name: name),
    );
    if (ok != true || !context.mounted) return;
    try {
      await OwnerRepo.instance.restoreHostel(hostel['id'] as String);
      if (!context.mounted) return;
      showSnack(context, context.l10n.hostelRestored(name));
      context.go('/hostels'); // the restored hostel is shown again
    } catch (e) {
      if (context.mounted) showSnack(context, errorText(context, e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    final area = [hostel['area'], hostel['city']]
        .map((e) => (e ?? '').toString().trim())
        .where((e) => e.isNotEmpty)
        .join(', ');
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text((hostel['name'] ?? '').toString(),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.ink)),
          if (area.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(area, style: const TextStyle(color: AppColors.muted)),
          ],
          const SizedBox(height: 4),
          Text(t.removedMeta(_dateText(hostel['archived_at'] as String), '$tenants'),
              style: const TextStyle(fontSize: 12.5, color: AppColors.muted)),
          const SizedBox(height: 12),
          BusyButton(label: t.restoreHostel, onPressed: () => _restore(context)),
        ],
      ),
    );
  }
}

/// Confirm sheet. Pops true to restore.
class _RestoreSheet extends StatelessWidget {
  const _RestoreSheet({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    Widget bullet(String text) => Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('•  ', style: TextStyle(color: AppColors.muted)),
            Expanded(child: Text(text, style: const TextStyle(fontSize: 14, height: 1.4, color: AppColors.muted))),
          ]),
        );
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(color: AppColors.primarySoft, shape: BoxShape.circle),
                child: const Icon(Icons.restore_rounded, color: AppColors.primary, size: 22),
              ),
            ),
            const SizedBox(height: 12),
            Text(t.restoreHostelTitle(name),
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.ink)),
            const SizedBox(height: 8),
            bullet(t.restoreShows),
            bullet(t.restoreJoinsOpen),
            bullet(t.restoreBillsResume),
            const SizedBox(height: 14),
            SizedBox(
              height: 52,
              child: FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(t.restoreHostel),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 48,
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(t.cancel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
