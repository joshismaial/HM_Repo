import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:open_filex/open_filex.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'format.dart';

// =====================================================================================
// Report data (built from bills, payments and tenants) – used by the Reports screen and
// by the Excel / PDF downloads, so both always show the same numbers.
// =====================================================================================

/// The period a report covers: one month, or a whole year.
class ReportPeriod {
  const ReportPeriod.month(this.year, this.month) : isYear = false;
  const ReportPeriod.year(this.year)
      : isYear = true,
        month = 1;
  final int year;
  final int month;
  final bool isYear;

  DateTime get from => DateTime(year, isYear ? 1 : month, 1);
  DateTime get to => isYear ? DateTime(year, 12, 31) : DateTime(year, month + 1, 0);
  bool contains(DateTime? d) => d != null && !d.isBefore(from) && !d.isAfter(to);

  ReportPeriod get previous =>
      isYear ? ReportPeriod.year(year - 1) : (month == 1 ? ReportPeriod.month(year - 1, 12) : ReportPeriod.month(year, month - 1));
  ReportPeriod get next =>
      isYear ? ReportPeriod.year(year + 1) : (month == 12 ? ReportPeriod.month(year + 1, 1) : ReportPeriod.month(year, month + 1));

  String label(String locale) => isYear ? '$year' : DateFormat('MMMM yyyy', locale).format(from);

  /// For file names: Oct_2026 or 2026
  String get fileTag => isYear ? '$year' : '${DateFormat('MMM').format(from)}_$year';
}

String _roomOf(Json? tenant) {
  final bed = tenant?['beds'];
  if (bed is! Map) return '—';
  final room = bed['rooms'];
  return '${room is Map ? room['room_no'] : ''} ${bed['label'] ?? ''}'.trim();
}

/// One tenant's rent for the period.
class RentRow {
  RentRow({required this.name, required this.phone, required this.room});
  final String name, phone, room;
  int due = 0;
  int paid = 0;
  String method = '';
  DateTime? paidOn;
  DateTime? dueOn; // first due date in the period
  int get pending => due - paid < 0 ? 0 : due - paid;
  bool get isPaid => pending == 0;
}

/// One month of a year report.
class MonthRow {
  MonthRow(this.month);
  final int month;
  int expected = 0, collected = 0, pending = 0;
}

class RentReport {
  RentReport({required this.rows, required this.months, required this.byMethod});
  final List<RentRow> rows; // per tenant
  final List<MonthRow> months; // 12 months (used in year view)
  final Map<String, int> byMethod; // upi / cash / bank / online → amount
  int get expected => rows.fold(0, (s, r) => s + r.due);
  int get collected => byMethod.values.fold(0, (s, v) => s + v);
  int get pending => rows.fold(0, (s, r) => s + r.pending);

  static RentReport build(List<Json> bills, List<Json> payments) {
    final byTenant = <String, RentRow>{};
    final months = [for (var m = 1; m <= 12; m++) MonthRow(m)];
    for (final b in bills) {
      final t = b['tenants'] is Map ? Json.from(b['tenants'] as Map) : null;
      final row = byTenant.putIfAbsent(
          '${b['tenant_id']}',
          () => RentRow(name: '${t?['full_name'] ?? '—'}', phone: '${t?['phone'] ?? ''}', room: _roomOf(t)));
      final amount = asInt(b['amount']);
      final paid = asInt(b['paid_amount']);
      row.due += amount;
      row.paid += paid > amount ? amount : paid;
      final d = DateTime.tryParse('${b['due_date']}');
      if (d != null && (row.dueOn == null || d.isBefore(row.dueOn!))) row.dueOn = d;
      if (d != null) {
        months[d.month - 1].expected += amount;
        months[d.month - 1].pending += (amount - paid) < 0 ? 0 : amount - paid;
      }
    }
    final byMethod = <String, int>{};
    for (final p in payments) {
      final amount = asInt(p['amount_received']);
      final m = '${p['method']}';
      byMethod[m] = (byMethod[m] ?? 0) + amount;
      final d = DateTime.tryParse('${p['paid_on']}');
      if (d != null) months[d.month - 1].collected += amount;
      final row = byTenant['${p['tenant_id']}'];
      if (row != null && (row.paidOn == null || (d != null && d.isAfter(row.paidOn!)))) {
        row.paidOn = d;
        row.method = m;
      }
    }
    final rows = byTenant.values.toList()..sort((a, b) => a.room.compareTo(b.room));
    return RentReport(rows: rows, months: months, byMethod: byMethod);
  }
}

/// Status of a student in the list.
enum StudentState { staying, leaving, left }

class StudentRow {
  StudentRow(Json t)
      : name = '${t['full_name'] ?? '—'}',
        phone = '${t['phone'] ?? ''}',
        room = _roomOf(t),
        org = '${t['org_name'] ?? ''}',
        deposit = asInt(t['deposit']),
        hasId = t['id_file_key'] != null,
        joined = DateTime.tryParse('${t['joining_date']}'),
        leftOn = DateTime.tryParse('${t['vacated_at'] ?? t['leaving_date'] ?? ''}'),
        state = switch (t['status']) {
          'vacated' => StudentState.left,
          'notice' => StudentState.leaving,
          _ => StudentState.staying,
        };
  final String name, phone, room, org;
  final int deposit;
  final bool hasId; // ID proof uploaded
  final DateTime? joined, leftOn;
  final StudentState state;
}

class StudentsReport {
  StudentsReport(List<Json> tenants, this.period) : all = tenants.map(StudentRow.new).toList();
  final List<StudentRow> all;
  final ReportPeriod period;

  List<StudentRow> get staying => all.where((s) => s.state != StudentState.left).toList();
  List<StudentRow> get joined => all.where((s) => period.contains(s.joined)).toList();
  List<StudentRow> get left => all.where((s) => s.state == StudentState.left && period.contains(s.leftOn)).toList();

  /// "All": staying now + joined in the period + left in the period.
  List<StudentRow> get inPeriod => {...staying, ...joined, ...left}.toList()
    ..sort((a, b) => (b.joined ?? DateTime(2000)).compareTo(a.joined ?? DateTime(2000)));
}

// =====================================================================================
// Downloads: Excel (.xlsx) and PDF, saved on the phone and opened there (no sharing).
// =====================================================================================

final _inr = NumberFormat('#,##,##0', 'en_IN');
String _rs(int v) => 'Rs. ${_inr.format(v)}'; // PDF fonts have no ₹ sign
String _d(DateTime? d) => d == null ? '' : DateFormat('dd-MM-yyyy').format(d);
String _phone(String p) => p.startsWith('+91') ? p.substring(3) : p;
String _method(String m) => switch (m) { 'upi' => 'UPI', 'cash' => 'Cash', 'bank' => 'Bank', 'online' => 'Online', _ => m };
String _state(StudentState s, DateTime? leftOn) => switch (s) {
      StudentState.staying => 'Staying',
      StudentState.leaving => 'Leaving ${_d(leftOn)}',
      StudentState.left => 'Left ${_d(leftOn)}',
    };

class ReportFile {
  ReportFile(this.name, this.path, this.savedAt, this.title);
  final String name, path, title;
  final DateTime savedAt;
  Json toJson() => {'name': name, 'path': path, 'at': savedAt.toIso8601String(), 'title': title};
  static ReportFile fromJson(Json j) =>
      ReportFile('${j['name']}', '${j['path']}', DateTime.tryParse('${j['at']}') ?? DateTime.now(), '${j['title']}');
}

class ReportExporter {
  static const _key = 'report_downloads';

  /// Builds the file, saves it on the phone and returns it (newest first in [recent]).
  static Future<ReportFile> export({
    required String hostelName,
    required bool rent,
    required bool pdf,
    required ReportPeriod period,
    required String periodLabel,
    RentReport? rentReport,
    StudentsReport? students,
  }) async {
    final base = rent ? 'Rent_Report_${period.fileTag}' : 'Students_List_${period.fileTag}';
    final name = '$base.${pdf ? 'pdf' : 'xlsx'}';
    final title = '${rent ? 'Rent report' : 'Students list'} · $periodLabel';
    final Uint8List bytes = rent
        ? (pdf ? await _rentPdf(hostelName, periodLabel, period, rentReport!) : _rentXlsx(hostelName, periodLabel, period, rentReport!))
        : (pdf ? await _studentsPdf(hostelName, periodLabel, students!) : _studentsXlsx(hostelName, periodLabel, students!));
    final dir = Directory('${(await getApplicationDocumentsDirectory()).path}/reports');
    await dir.create(recursive: true);
    final file = File('${dir.path}/$name');
    await file.writeAsBytes(bytes, flush: true);
    final rf = ReportFile(name, file.path, DateTime.now(), title);
    await _remember(rf);
    return rf;
  }

  /// Opens a saved report on the phone (PDF viewer / Excel app).
  static Future<void> open(ReportFile f) async {
    await OpenFilex.open(f.path);
  }

  static Future<List<ReportFile>> recent() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = (jsonDecode(prefs.getString(_key) ?? '[]') as List).map((e) => ReportFile.fromJson(Json.from(e as Map)));
      return list.where((f) => File(f.path).existsSync()).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> _remember(ReportFile f) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = (await recent()).where((x) => x.path != f.path).toList()..insert(0, f);
      await prefs.setString(_key, jsonEncode(list.take(10).map((e) => e.toJson()).toList()));
    } catch (_) {}
  }

  // ---------------------------------------------------------------- Excel
  static void _title(Sheet s, String a, String b) {
    s.appendRow([TextCellValue(a)]);
    s.cell(CellIndex.indexByString('A1')).cellStyle = CellStyle(bold: true, fontSize: 14);
    s.appendRow([TextCellValue(b)]);
    s.appendRow([TextCellValue('')]);
  }

  static void _header(Sheet s, List<String> cols) {
    s.appendRow([for (final c in cols) TextCellValue(c)]);
    final r = s.maxRows - 1;
    for (var i = 0; i < cols.length; i++) {
      s.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: r)).cellStyle = CellStyle(
        bold: true,
        fontColorHex: ExcelColor.white,
        backgroundColorHex: ExcelColor.fromHexString('#1560BD'),
      );
    }
  }

  static Uint8List _save(Excel x) {
    if (x.sheets.containsKey('Sheet1') && x.sheets.length > 1) x.delete('Sheet1');
    return Uint8List.fromList(x.save() ?? const []);
  }

  static Uint8List _rentXlsx(String hostel, String label, ReportPeriod p, RentReport r) {
    final x = Excel.createExcel();
    final s = x['Rent'];
    _title(s, '$hostel – Rent report', '$label · ${r.rows.length} students');
    s.appendRow([TextCellValue('Collected (₹)'), TextCellValue('Expected (₹)'), TextCellValue('Pending (₹)')]);
    s.appendRow([IntCellValue(r.collected), IntCellValue(r.expected), IntCellValue(r.pending)]);
    for (var i = 0; i < 3; i++) {
      final color = i == 1 ? '#000000' : (i == 0 || r.pending == 0 ? '#1F8A4C' : '#C0392B');
      s.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: s.maxRows - 1)).cellStyle =
          CellStyle(bold: true, fontSize: 13, fontColorHex: ExcelColor.fromHexString(color));
    }
    if (r.pending == 0 && r.rows.isNotEmpty) s.appendRow([TextCellValue('✓ All rent collected for $label')]);
    s.appendRow([TextCellValue('')]);
    if (p.isYear) {
      _header(s, ['Month', 'Expected (₹)', 'Collected (₹)', 'Pending (₹)']);
      for (final m in r.months.where((m) => m.expected > 0 || m.collected > 0)) {
        s.appendRow([
          TextCellValue(DateFormat('MMM yyyy').format(DateTime(p.year, m.month))),
          IntCellValue(m.expected),
          IntCellValue(m.collected),
          IntCellValue(m.pending),
        ]);
      }
      s.appendRow([TextCellValue('')]);
    }
    _header(s, ['#', 'Room', 'Name', 'Mobile', 'Rent (₹)', 'Due date', 'Paid on', 'Mode', 'Paid amount (₹)', 'Pending (₹)', 'Status']);
    var n = 0;
    for (final row in r.rows) {
      n++;
      s.appendRow([
        IntCellValue(n),
        TextCellValue(row.room),
        TextCellValue(row.name),
        TextCellValue(_phone(row.phone)),
        IntCellValue(row.due),
        TextCellValue(_d(row.dueOn)),
        TextCellValue(_d(row.paidOn)),
        TextCellValue(_method(row.method)),
        IntCellValue(row.paid),
        IntCellValue(row.pending),
        TextCellValue(row.isPaid ? 'Paid' : 'Pending'),
      ]);
    }
    s.appendRow([
      TextCellValue(''),
      TextCellValue(''),
      TextCellValue('Total'),
      TextCellValue(''),
      IntCellValue(r.expected),
      TextCellValue(''),
      TextCellValue(''),
      TextCellValue(''),
      IntCellValue(r.rows.fold(0, (a, b) => a + b.paid)),
      IntCellValue(r.pending),
      TextCellValue(r.pending == 0 ? 'All paid' : ''),
    ]);
    for (var i = 0; i < 11; i++) {
      s.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: s.maxRows - 1)).cellStyle = CellStyle(bold: true);
    }
    const widths = [5.0, 8.0, 20.0, 14.0, 10.0, 12.0, 12.0, 8.0, 14.0, 11.0, 10.0];
    for (var i = 0; i < widths.length; i++) {
      s.setColumnWidth(i, widths[i]);
    }
    return _save(x);
  }

  static Uint8List _studentsXlsx(String hostel, String label, StudentsReport st) {
    final x = Excel.createExcel();
    final s = x['Students'];
    _title(s, '$hostel – Students list',
        '$label · Staying now ${st.staying.length} · Joined ${st.joined.length} · Left ${st.left.length}');
    _header(s, ['#', 'Name', 'Room', 'Mobile', 'Joined', 'Deposit (₹)', 'ID proof', 'Company / institute', 'Status']);
    var n = 0;
    for (final r in st.inPeriod) {
      n++;
      s.appendRow([
        IntCellValue(n),
        TextCellValue(r.name),
        TextCellValue(r.room),
        TextCellValue(_phone(r.phone)),
        TextCellValue(_d(r.joined)),
        IntCellValue(r.deposit),
        TextCellValue(r.hasId ? 'Uploaded' : 'Not uploaded'),
        TextCellValue(r.org),
        TextCellValue(_state(r.state, r.leftOn)),
      ]);
    }
    const widths = [5.0, 22.0, 8.0, 14.0, 12.0, 12.0, 13.0, 24.0, 18.0];
    for (var i = 0; i < widths.length; i++) {
      s.setColumnWidth(i, widths[i]);
    }
    return _save(x);
  }

  // ---------------------------------------------------------------- PDF
  static pw.Widget _pdfTable(List<String> headers, List<List<String>> rows) => pw.TableHelper.fromTextArray(
        headers: headers,
        data: rows,
        headerStyle: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 9),
        headerDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFF1560BD)),
        cellStyle: const pw.TextStyle(fontSize: 9),
        cellHeight: 22,
        oddRowDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFF3F6FC)),
        border: pw.TableBorder.all(color: const PdfColor.fromInt(0xFFD5DCE5), width: 0.4),
      );

  static Future<Uint8List> _doc(String title, String sub, List<pw.Widget> body) async {
    final doc = pw.Document();
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (_) => [
        pw.Text(title, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4),
        pw.Text(sub, style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
        pw.SizedBox(height: 14),
        ...body,
      ],
      footer: (ctx) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text('My Hostel · page ${ctx.pageNumber} of ${ctx.pagesCount}',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
      ),
    ));
    return doc.save();
  }

  static pw.Widget _box(String label, String value, PdfColor color) => pw.Expanded(
        child: pw.Container(
          padding: const pw.EdgeInsets.symmetric(vertical: 8),
          margin: const pw.EdgeInsets.symmetric(horizontal: 3),
          decoration: pw.BoxDecoration(border: pw.Border.all(color: const PdfColor.fromInt(0xFFE3E7EE), width: 0.8)),
          child: pw.Column(children: [
            pw.Text(label, style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
            pw.SizedBox(height: 3),
            pw.Text(value, style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold, color: color)),
          ]),
        ),
      );

  static const _pdfGreen = PdfColor.fromInt(0xFF1F8A4C);
  static const _pdfRed = PdfColor.fromInt(0xFFDC2626);

  static Future<Uint8List> _rentPdf(String hostel, String label, ReportPeriod p, RentReport r) => _doc(
        '$hostel – Rent report',
        '$label · ${r.rows.length} students',
        [
          pw.Row(children: [
            _box('Collected', _rs(r.collected), _pdfGreen),
            _box('Expected', _rs(r.expected), PdfColors.black),
            _box('Pending', _rs(r.pending), r.pending == 0 ? _pdfGreen : _pdfRed),
          ]),
          if (r.pending == 0 && r.rows.isNotEmpty) ...[
            pw.SizedBox(height: 8),
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(7),
              color: const PdfColor.fromInt(0xFFE3F4E8),
              child: pw.Text('All rent collected for $label',
                  textAlign: pw.TextAlign.center, style: pw.TextStyle(color: _pdfGreen, fontWeight: pw.FontWeight.bold, fontSize: 11)),
            ),
          ],
          pw.SizedBox(height: 12),
          if (p.isYear) ...[
            _pdfTable(['Month', 'Expected', 'Collected', 'Pending'], [
              for (final m in r.months.where((m) => m.expected > 0 || m.collected > 0))
                [DateFormat('MMM yyyy').format(DateTime(p.year, m.month)), _rs(m.expected), _rs(m.collected), _rs(m.pending)],
            ]),
            pw.SizedBox(height: 14),
          ],
          _pdfTable(['#', 'Room', 'Name', 'Mobile', 'Rent', 'Due date', 'Paid on', 'Mode', 'Status'], [
            for (final (i, row) in r.rows.indexed)
              [
                '${i + 1}', row.room, row.name, _phone(row.phone), _rs(row.due), _d(row.dueOn), _d(row.paidOn), _method(row.method),
                row.isPaid ? 'Paid' : 'Pending ${_rs(row.pending)}',
              ],
            ['', '', 'Total', '', _rs(r.expected), '', '', '', r.pending == 0 ? 'All paid' : 'Pending ${_rs(r.pending)}'],
          ]),
        ],
      );

  static Future<Uint8List> _studentsPdf(String hostel, String label, StudentsReport st) => _doc(
        '$hostel – Students list',
        '$label · Staying now ${st.staying.length} · Joined ${st.joined.length} · Left ${st.left.length} · Aadhaar numbers are not included',
        [
          _pdfTable(['#', 'Name', 'Room', 'Mobile', 'Joined', 'Deposit', 'ID proof', 'Status'], [
            for (final (i, r) in st.inPeriod.indexed)
              ['${i + 1}', r.name, r.room, _phone(r.phone), _d(r.joined), _rs(r.deposit), r.hasId ? 'Uploaded' : 'Not uploaded', _state(r.state, r.leftOn)],
          ]),
        ],
      );
}
