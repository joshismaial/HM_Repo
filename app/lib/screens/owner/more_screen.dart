import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/back_nav.dart';
import '../../core/format.dart';
import '../../data/owner_repo.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import 'hostel_scope.dart';

/// Support e-mail shown under "Help & support". Change before launch.
const supportEmail = 'support@myhostel.app';

/// Simple More: Hostel (Tenants, Hostel settings, Invite students, Reports) and
/// You (Language, Privacy & account, Help, Log out). Rooms entered by tenants live in Hostel settings.
class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key, required this.hostelId});
  final String hostelId;

  void _privacySheet(BuildContext context) {
    final t = context.l10n;
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
            child: Text(t.privacyAccount, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          ),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined, color: AppColors.primary),
            title: Text(t.privacyPolicy),
            onTap: () {
              Navigator.pop(ctx);
              context.push('/privacy');
            },
          ),
          ListTile(
            leading: const Icon(Icons.description_outlined, color: AppColors.primary),
            title: Text(t.termsOfUse),
            onTap: () {
              Navigator.pop(ctx);
              context.push('/privacy?tab=terms');
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_forever_rounded, color: AppColors.danger),
            title: Text(t.deleteAccount, style: const TextStyle(color: AppColors.danger)),
            onTap: () {
              Navigator.pop(ctx);
              context.push('/delete-account');
            },
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    final scope = HostelScope.of(context);
    Widget section(String title) => Padding(
          padding: const EdgeInsets.fromLTRB(4, 18, 4, 6),
          child: Text(title, style: const TextStyle(color: AppColors.muted, fontWeight: FontWeight.w400, fontSize: 12.5)),
        );
    Widget row(IconData icon, String label, VoidCallback onTap, {Widget? trailing, Color? color, bool last = false}) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(icon, color: color ?? AppColors.primary),
              title: Text(label, style: TextStyle(fontWeight: FontWeight.w600, color: color)),
              trailing: trailing ?? (color == null ? const Icon(Icons.chevron_right_rounded, color: AppColors.primary) : null),
              onTap: onTap,
            ),
            if (!last) const Divider(height: 1, indent: 56),
          ],
        );
    Widget group(List<Widget> rows) => Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.line),
          ),
          child: Material(color: Colors.white, child: Column(children: rows)),
        );
    return Scaffold(
      appBar: AppBar(title: Text(t.tabMore), leading: const AppBackButton()),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Narrow(
            maxWidth: 640,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Loader<Json?>(
                  load: OwnerRepo.instance.profile,
                  builder: (context, p, _) {
                    final name = (p?['full_name'] as String?)?.isNotEmpty == true ? p!['full_name'] as String : t.owner;
                    final initials = name.trim().split(RegExp(r'\s+')).take(2).map((w) => w.isEmpty ? '' : w[0]).join().toUpperCase();
                    return Row(children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundColor: AppColors.primarySoft,
                        child: Text(initials, style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                          Text('${t.owner} · ${hostelTitle(context, scope.hostel)}', style: const TextStyle(color: AppColors.muted)),
                        ]),
                      ),
                    ]);
                  },
                ),
                section(t.hostel),
                // "Removed hostels" sits below Reports, and only when the owner has removed a hostel.
                FutureBuilder<int>(
                  future: OwnerRepo.instance.removedHostelCount().catchError((_) => 0),
                  builder: (context, snap) {
                    final removed = snap.data ?? 0;
                    return group([
                      row(Icons.people_outline_rounded, t.tenantsStudentsList, () => context.go('/h/$hostelId/tenants')),
                      row(Icons.tune_rounded, t.hostelSettings, () => context.go('/h/$hostelId/settings')),
                      row(Icons.badge_outlined, t.staffTitle, () => context.go('/h/$hostelId/staff')),
                      row(Icons.campaign_outlined, t.noticeToStudents, () => context.go('/h/$hostelId/notices')),
                      row(Icons.qr_code_2_rounded, t.inviteStudents, () => context.go('/h/$hostelId/invite')),
                      row(Icons.bar_chart_rounded, t.reports, () => context.push('/h/$hostelId/reports'),
                          last: removed == 0),
                      if (removed > 0)
                        row(Icons.inventory_2_outlined, t.removedHostelsCount('$removed'),
                            () => context.push('/hostels/removed'),
                            last: true),
                    ]);
                  },
                ),
                section(t.sectionYou),
                group([
                  row(
                    Icons.translate_rounded,
                    t.language,
                    () {},
                    trailing: LanguageButton(onChanged: (code) => OwnerRepo.instance.setProfileLanguage(code).catchError((_) {})),
                  ),
                  row(Icons.shield_outlined, t.privacyAccount, () => _privacySheet(context)),
                  row(Icons.help_outline_rounded, t.helpSupport,
                      () => launchUrl(Uri.parse('mailto:$supportEmail?subject=${Uri.encodeComponent(t.appName)}'))),
                  row(Icons.logout_rounded, t.logout, () async {
                    final ok = await confirm(context, title: t.logout, message: t.logoutConfirm, okLabel: t.logout);
                    if (ok) await OwnerRepo.instance.logout();
                  }, color: AppColors.danger, last: true),
                ]),
                const SizedBox(height: 16),
                Text(t.appVersion('1.0.0'), textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
