import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/back_nav.dart';
import '../../core/errors.dart';
import '../../core/format.dart';
import '../../core/reports.dart';
import '../../data/owner_repo.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import 'hostel_scope.dart';

const _green = Color(0xFF15803D);
const _blue = Color(0xFF1560BD);

/// More → Reports. Pick Rent report or Students list, month-wise or year-wise, see it on
/// screen and download it as Excel or PDF (saved on the phone, then Share).
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key, required this.hostelId});
  final String hostelId;

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  bool _rent = true; // Rent report | Students list
  late ReportPeriod _period = ReportPeriod.month(today().year, today().month);
  String _filter = 'all'; // rent: all | paid | pending · students: all | staying | joined | left
  late Future<_Data> _data = _load();

  Future<_Data> _load() async {
    final repo = OwnerRepo.instance;
    if (_rent) {
      final r = await Future.wait([
        repo.reportBills(widget.hostelId, _period.from, _period.to),
        repo.reportPayments(widget.hostelId, _period.from, _period.to),
      ]);
      return _Data(rent: RentReport.build(r[0], r[1]));
    }
    return _Data(students: StudentsReport(await repo.reportTenants(widget.hostelId), _period));
  }

  void _reload() => setState(() => _data = _load());

  void _setKind(bool rent) {
    if (rent == _rent) return;
    _rent = rent;
    _filter = 'all';
    _reload();
  }

  void _setYearMode(bool year) {
    _period = year
        ? ReportPeriod.year(_period.year)
        : ReportPeriod.month(_period.year, _period.year == today().year ? today().month : 12);
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(t.reports), leading: const AppBackButton()),
      body: FutureBuilder<_Data>(
        future: _data,
        builder: (context, snap) {
          final loading = snap.connectionState != ConnectionState.done;
          return Stack(children: [
            ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
              children: [
                Narrow(
                  maxWidth: 640,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    // ---- choose the report
                    Row(children: [
                      Expanded(child: _KindCard(icon: Icons.currency_rupee_rounded, label: t.rentReport, on: _rent, onTap: () => _setKind(true))),
                      const SizedBox(width: 8),
                      Expanded(child: _KindCard(icon: Icons.people_alt_outlined, label: t.studentsList, on: !_rent, onTap: () => _setKind(false))),
                    ]),
                    const SizedBox(height: 10),
                    SegmentedButton<bool>(
                      showSelectedIcon: false,
                      segments: [
                        ButtonSegment(value: false, label: Text(t.monthWise)),
                        ButtonSegment(value: true, label: Text(t.yearWise)),
                      ],
                      selected: {_period.isYear},
                      onSelectionChanged: (v) => _setYearMode(v.first),
                    ),
                    const SizedBox(height: 10),
                    // ---- period picker
                    Container(
                      decoration: BoxDecoration(
                          color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.line)),
                      child: Row(children: [
                        IconButton(
                          tooltip: t.previous,
                          icon: const Icon(Icons.chevron_left_rounded, color: _blue),
                          onPressed: () {
                            _period = _period.previous;
                            _reload();
                          },
                        ),
                        Expanded(
                          child: Text(_period.label(context.lang),
                              textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                        ),
                        IconButton(
                          tooltip: t.next,
                          icon: const Icon(Icons.chevron_right_rounded, color: _blue),
                          onPressed: () {
                            _period = _period.next;
                            _reload();
                          },
                        ),
                      ]),
                    ),
                    const SizedBox(height: 10),
                    if (loading)
                      const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
                    else if (snap.hasError)
                      ErrorView(error: snap.error!, onRetry: _reload)
                    else if (_rent)
                      _RentView(
                        report: snap.data!.rent!,
                        period: _period,
                        filter: _filter,
                        onFilter: (f) => setState(() => _filter = f),
                        onOpenMonth: (m) {
                          _period = ReportPeriod.month(_period.year, m);
                          _reload();
                        },
                      )
                    else
                      _StudentsView(report: snap.data!.students!, filter: _filter, onFilter: (f) => setState(() => _filter = f)),
                  ]),
                ),
              ],
            ),
            // ---- download
            Positioned(
              left: 16,
              right: 16,
              bottom: 12,
              child: SafeArea(
                top: false,
                child: SizedBox(
                  height: 52,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: _green),
                    icon: const Icon(Icons.download_rounded),
                    label: Text(t.downloadReport, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    onPressed: loading || snap.hasError ? null : _openDownload,
                  ),
                ),
              ),
            ),
          ]);
        },
      ),
    );
  }

  Future<void> _openDownload() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (_) => _DownloadSheet(
        hostelId: widget.hostelId,
        hostelName: '${HostelScope.read(context).hostel?['name'] ?? ''}',
        rent: _rent,
        period: _period,
      ),
    );
  }
}

class _Data {
  _Data({this.rent, this.students});
  final RentReport? rent;
  final StudentsReport? students;
}

class _KindCard extends StatelessWidget {
  const _KindCard({required this.icon, required this.label, required this.on, required this.onTap});
  final IconData icon;
  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: on,
      child: Material(
        color: on ? AppColors.primarySoft : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: on ? _blue : AppColors.field, width: 1.5),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(color: on ? _blue : AppColors.primarySoft, borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, size: 19, color: on ? Colors.white : _blue),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14))),
            ]),
          ),
        ),
      ),
    );
  }
}

Widget _kpi(String label, String value, Color color) => Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.line)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: AppColors.muted, fontWeight: FontWeight.w400)),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: color)),
          ),
        ]),
      ),
    );

Widget _filters(BuildContext context, Map<String, String> options, String value, ValueChanged<String> onChanged, {String? trailing}) =>
    Padding(
      padding: const EdgeInsets.fromLTRB(2, 12, 2, 8),
      child: Row(children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (final e in options.entries) ...[
                ChoiceChip(label: Text(e.value), selected: value == e.key, onSelected: (_) => onChanged(e.key)),
                const SizedBox(width: 6),
              ],
            ]),
          ),
        ),
        if (trailing != null) Text(trailing, style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
      ]),
    );

Widget _status(String text, Color fg, Color bg) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg)),
    );

class _RentView extends StatelessWidget {
  const _RentView({required this.report, required this.period, required this.filter, required this.onFilter, required this.onOpenMonth});
  final RentReport report;
  final ReportPeriod period;
  final String filter;
  final ValueChanged<String> onFilter;
  final ValueChanged<int> onOpenMonth;

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    final rows = report.rows;
    final card = BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.line));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        _kpi(t.collectedLabel, money(report.collected), _green),
        const SizedBox(width: 8),
        _kpi(t.expectedLabel, money(report.expected), AppColors.ink),
        const SizedBox(width: 8),
        _kpi(t.pendingLabel, money(report.pending), AppColors.danger),
      ]),
      if (period.isYear) ...[
        const SizedBox(height: 10),
        Container(
          decoration: card,
          clipBehavior: Clip.antiAlias,
          child: Column(children: [
            Container(
              color: const Color(0xFFFAFBFD),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(children: [
                Expanded(flex: 5, child: Text(t.monthLabel, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.muted))),
                Expanded(flex: 4, child: Text(t.expectedLabel, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.muted))),
                Expanded(flex: 4, child: Text(t.collectedLabel, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.muted))),
                Expanded(flex: 4, child: Text(t.pendingLabel, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.muted))),
              ]),
            ),
            for (final m in report.months.where((m) => m.expected > 0 || m.collected > 0))
              InkWell(
                onTap: () => onOpenMonth(m.month),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFFEEF1F5)))),
                  child: Row(children: [
                    Expanded(flex: 5, child: Text(ReportPeriod.month(period.year, m.month).label(context.lang), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5))),
                    Expanded(flex: 4, child: Text(money(m.expected), style: const TextStyle(fontSize: 12.5))),
                    Expanded(flex: 4, child: Text(money(m.collected), style: const TextStyle(fontSize: 12.5, color: _green, fontWeight: FontWeight.w800))),
                    Expanded(flex: 4, child: Text(m.pending == 0 ? '—' : money(m.pending), style: TextStyle(fontSize: 12.5, color: m.pending == 0 ? AppColors.muted : AppColors.danger, fontWeight: FontWeight.w800))),
                  ]),
                ),
              ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(t.tapMonthHint, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
        ),
      ],
      if (report.pending == 0 && report.rows.isNotEmpty)
        Container(
          margin: const EdgeInsets.only(top: 10),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: const Color(0xFFE3F4E8), borderRadius: BorderRadius.circular(12)),
          child: Text('✓ ${t.allRentCollectedFor(period.label(context.lang))}',
              textAlign: TextAlign.center, style: const TextStyle(color: _green, fontWeight: FontWeight.w600)),
        ),
      const SizedBox(height: 10),
      if (rows.isEmpty)
        Padding(
          padding: const EdgeInsets.all(24),
          child: Text(t.noReportRows, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted)),
        )
      else
        // the same table as the downloaded file: Room · Name · Rent · Due · Status, then Total
        Container(
          decoration: card,
          clipBehavior: Clip.antiAlias,
          child: Column(children: [
            Container(
              color: const Color(0xFF1D4ED8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              child: Row(children: [
                _cell(t.room, 3, head: true),
                _cell(t.colName, 5, head: true),
                _cell(t.colRent, 4, head: true),
                _cell(t.colDue, 3, head: true),
                _cell(t.colStatus, 4, head: true),
              ]),
            ),
            for (final (i, r) in rows.indexed)
              Container(
                color: i.isOdd ? const Color(0xFFF8FAFC) : Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                child: Row(children: [
                  _cell(r.room.replaceAll(' ', ''), 3),
                  _cell(r.name.split(' ').first, 5),
                  _cell(money(r.due), 4),
                  _cell(r.dueOn == null ? '—' : DateFormat('dd MMM', context.lang).format(r.dueOn!), 3),
                  Expanded(
                    flex: 4,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: r.isPaid
                          ? _status(t.paidLabel, _green, const Color(0xFFDDF3E8))
                          : _status(t.dueShort, AppColors.danger, AppColors.dangerSoft),
                    ),
                  ),
                ]),
              ),
            Container(
              color: const Color(0xFFEEF1F6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              child: Row(children: [
                _cell(t.totalRow, 8, bold: true),
                _cell(money(report.expected), 4, bold: true),
                Expanded(
                  flex: 7,
                  child: Text(report.pending == 0 ? t.allPaid : t.pendingAmount(money(report.pending)),
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: report.pending == 0 ? _green : AppColors.danger)),
                ),
              ]),
            ),
          ]),
        ),
    ]);
  }
}

Widget _cell(String text, int flex, {bool head = false, bool bold = false}) => Expanded(
      flex: flex,
      child: Text(text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: head ? 11.5 : 13,
            fontWeight: head || bold ? FontWeight.w600 : FontWeight.w400,
            color: head ? Colors.white : AppColors.ink,
          )),
    );

class _StudentsView extends StatelessWidget {
  const _StudentsView({required this.report, required this.filter, required this.onFilter});
  final StudentsReport report;
  final String filter;
  final ValueChanged<String> onFilter;

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    final list = switch (filter) {
      'staying' => report.staying,
      'joined' => report.joined,
      'left' => report.left,
      _ => report.inPeriod,
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        _kpi(t.stayingNow, '${report.staying.length}', _blue),
        const SizedBox(width: 8),
        _kpi(t.joinedLabel, '${report.joined.length}', _green),
        const SizedBox(width: 8),
        _kpi(t.leftLabel, '${report.left.length}', AppColors.ink),
      ]),
      _filters(context, {'all': t.all, 'staying': t.stayingLabel, 'joined': t.joinedLabel, 'left': t.leftLabel}, filter, onFilter,
          trailing: t.studentsCount('${list.length}')),
      if (list.isEmpty)
        Padding(
          padding: const EdgeInsets.all(24),
          child: Text(t.noReportRows, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted)),
        )
      else
        // one card per student: initials, name · room, phone · joined · deposit, ID badge
        Column(children: [
          for (final s in list)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.line)),
              child: Row(children: [
                CircleAvatar(
                  radius: 21,
                  backgroundColor: AppColors.primarySoft,
                  child: Text(_initials(s.name), style: const TextStyle(fontWeight: FontWeight.w600, color: _blue, fontSize: 12.5)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text.rich(TextSpan(children: [
                      TextSpan(text: s.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                      TextSpan(text: '  ·  ${s.room.replaceAll(' ', '')}', style: const TextStyle(color: AppColors.muted, fontWeight: FontWeight.w600)),
                    ])),
                    const SizedBox(height: 2),
                    Text('📞 ${phoneText(s.phone)} · ${t.joinedOn(dateText(context, s.joined))} · ${t.deposit} ${money(s.deposit)}',
                        style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                    if (s.state != StudentState.staying)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: s.state == StudentState.leaving
                            ? _status(t.leavingOn(dateText(context, s.leftOn)), AppColors.danger, AppColors.dangerSoft)
                            : _status(t.leftOn(dateText(context, s.leftOn)), AppColors.muted, const Color(0xFFEEF1F5)),
                      ),
                  ]),
                ),
                const SizedBox(width: 6),
                s.hasId
                    ? _status('ID ✓', _green, const Color(0xFFDDF3E8))
                    : _status('ID ?', const Color(0xFFB7700B), const Color(0xFFFFF3DD)),
              ]),
            ),
        ]),
    ]);
  }
}

String _initials(String name) {
  final p = name.trim().split(RegExp(r'\s+')).where((x) => x.isNotEmpty).toList();
  if (p.isEmpty) return '?';
  return (p.first[0] + (p.length > 1 ? p.last[0] : '')).toUpperCase();
}

/// Download: the report and period are the ones on the screen; the sheet only asks for the
/// file type (PDF or Excel). Tapping one saves the file on the phone and opens it.
class _DownloadSheet extends StatefulWidget {
  const _DownloadSheet({required this.hostelId, required this.hostelName, required this.rent, required this.period});
  final String hostelId, hostelName;
  final bool rent;
  final ReportPeriod period;

  @override
  State<_DownloadSheet> createState() => _DownloadSheetState();
}

class _DownloadSheetState extends State<_DownloadSheet> {
  bool? _busyPdf; // which file is being made (null = none)

  Future<void> _download(bool pdf) async {
    if (_busyPdf != null) return;
    setState(() => _busyPdf = pdf);
    final t = context.l10n;
    final repo = OwnerRepo.instance;
    final p = widget.period;
    try {
      ReportFile f;
      if (widget.rent) {
        final r = await Future.wait([repo.reportBills(widget.hostelId, p.from, p.to), repo.reportPayments(widget.hostelId, p.from, p.to)]);
        if (!mounted) return;
        f = await ReportExporter.export(
            hostelName: widget.hostelName, rent: true, pdf: pdf, period: p, periodLabel: p.label(context.lang), rentReport: RentReport.build(r[0], r[1]));
      } else {
        final list = await repo.reportTenants(widget.hostelId);
        if (!mounted) return;
        f = await ReportExporter.export(
            hostelName: widget.hostelName, rent: false, pdf: pdf, period: p, periodLabel: p.label(context.lang), students: StudentsReport(list, p));
      }
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      messenger.showSnackBar(SnackBar(
        content: Text(t.reportSaved(f.name)),
        action: SnackBarAction(label: t.openLabel, onPressed: () => ReportExporter.open(f)),
      ));
      await ReportExporter.open(f);
    } catch (e) {
      if (mounted) {
        setState(() => _busyPdf = null);
        showSnack(context, errorText(context, e), error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    Widget option(bool pdf, String title, String sub) {
      final busy = _busyPdf == pdf;
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: Colors.white,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12), side: const BorderSide(color: AppColors.line, width: 1.4)),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: _busyPdf == null ? () => _download(pdf) : null,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                      color: pdf ? const Color(0xFFC0392B) : const Color(0xFF1D7A45), borderRadius: BorderRadius.circular(12)),
                  alignment: Alignment.center,
                  child: Text(pdf ? 'PDF' : 'XLS',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12.5)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                    Text(sub, style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                  ]),
                ),
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(color: const Color(0xFFDDF3E8), borderRadius: BorderRadius.circular(12)),
                  alignment: Alignment.center,
                  child: busy
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2, color: _green))
                      : const Icon(Icons.download_rounded, color: _green, size: 20),
                ),
              ]),
            ),
          ),
        ),
      );
    }

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Text(t.downloadNamed(widget.rent ? t.rentReport : t.studentsList),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(widget.period.label(context.lang), style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
          const SizedBox(height: 12),
          option(true, t.pdfFile, t.pdfKeepHelp),
          option(false, t.excelFile, t.excelAccountantHelp),
          const SizedBox(height: 4),
          Text(t.reportSavedNote, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
        ]),
      ),
    );
  }
}
