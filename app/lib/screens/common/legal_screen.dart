import 'package:flutter/material.dart';

import '../../core/back_nav.dart';
import '../../core/format.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

/// Privacy policy and Terms of use (tabs). DRAFT text: a lawyer must review it and fill the
/// [placeholders] before launch.
class LegalScreen extends StatelessWidget {
  const LegalScreen({super.key, this.initialTab = 0});
  final int initialTab;

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    final privacy = [
      (t.ppCollectTitle, t.ppCollectText),
      (t.ppWhyTitle, t.ppWhyText),
      (t.ppWhoTitle, t.ppWhoText),
      (t.ppProtectTitle, t.ppProtectText),
      (t.ppKeepTitle, t.ppKeepText),
      (t.ppRightsTitle, t.ppRightsText),
      (t.ppGrievanceTitle, t.ppGrievanceText),
    ];
    final terms = [
      (t.tmUseTitle, t.tmUseText),
      (t.tmOwnerTitle, t.tmOwnerText),
      (t.tmStudentTitle, t.tmStudentText),
      (t.tmPaymentsTitle, t.tmPaymentsText),
      (t.tmLiabilityTitle, t.tmLiabilityText),
    ];
    Widget page(List<(String, String)> sections) => PageList(children: [
          Banner2(text: t.legalDraftNote, tone: Tone.warning),
          for (final (title, body) in sections)
            SectionCard(
              title: title,
              child: Text(body, style: const TextStyle(height: 1.5, color: AppColors.ink)),
            ),
        ]);
    return DefaultTabController(
      length: 2,
      initialIndex: initialTab,
      child: Scaffold(
        appBar: AppBar(
          title: Text(t.privacyLegal),
          leading: const AppBackButton(),
          bottom: TabBar(tabs: [Tab(text: t.privacyPolicy), Tab(text: t.termsOfUse)]),
        ),
        body: TabBarView(children: [page(privacy), page(terms)]),
      ),
    );
  }
}
