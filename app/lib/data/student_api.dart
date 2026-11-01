import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import '../core/errors.dart';
import '../core/format.dart';

/// Talks to the student Edge Functions. Students never log in: after one OTP they get a long
/// random token (kept on the phone and in their private link) that is sent in "x-student-token".
class StudentApi {
  StudentApi._();
  static final instance = StudentApi._();

  static const _tokenKey = 'student_token';
  static const _codeKey = 'student_join_code';

  String? _token;
  String? get token => _token;

  /// Set when the student opened the owner's "Share with student" QR for one bed:
  /// then the flow is Verify → Your details → Pay (no hostel page / room picking).
  String? bookedBedId;
  String? bookedCode;
  bool get isBookedFlow => bookedBedId != null;

  /// Restore the token saved on this phone (if any) for this hostel.
  Future<String?> savedToken({String? joinCode}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final t = prefs.getString(_tokenKey);
      final c = prefs.getString(_codeKey);
      if (t == null) return null;
      if (joinCode != null && c != null && c != joinCode.toUpperCase()) return null;
      _token = t;
      return t;
    } catch (_) {
      return null;
    }
  }

  Future<void> useToken(String token, {String? joinCode}) async {
    _token = token;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_tokenKey, token);
      if (joinCode != null) await prefs.setString(_codeKey, joinCode.toUpperCase());
    } catch (_) {}
  }

  Future<void> forget() async {
    _token = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_tokenKey);
      await prefs.remove(_codeKey);
    } catch (_) {}
  }

  Future<Json> _post(String fn, Json body, {bool withToken = true}) async {
    final headers = {
      'Content-Type': 'application/json',
      'apikey': AppConfig.supabaseAnonKey,
      'Authorization': 'Bearer ${AppConfig.supabaseAnonKey}',
      if (withToken && _token != null) 'x-student-token': _token!,
    };
    http.Response res;
    try {
      res = await http
          .post(Uri.parse(AppConfig.functionUrl(fn)), headers: headers, body: jsonEncode(body))
          .timeout(const Duration(seconds: 25));
    } on TimeoutException {
      throw AppException('NETWORK');
    } on http.ClientException {
      throw AppException('NETWORK');
    } catch (e) {
      throw AppException.from(e);
    }
    dynamic data;
    try {
      data = res.body.isEmpty ? null : jsonDecode(res.body);
    } catch (_) {
      throw AppException('SERVER_ERROR');
    }
    if (res.statusCode >= 400) {
      if (data is Map && data['error'] is String) {
        throw AppException(data['error'] as String, Map<String, dynamic>.from(data));
      }
      throw AppException('SERVER_ERROR');
    }
    if (data is Map<String, dynamic>) return data;
    if (data is List) return {'items': data};
    return {};
  }

  // --- mobile verification (student-otp) ---
  /// [start] = the app opened on the held bed: the 15-minute timer starts now (once).
  Future<Json> peek(String joinCode, {String? bedId, String? code, bool start = false}) => _post(
      'student-otp',
      {
        'action': 'peek',
        'join_code': joinCode,
        if (bedId != null) 'bed': bedId,
        if (code != null) 'k': code,
        if (start) 'start': true,
      },
      withToken: false);

  Future<void> sendOtp(String joinCode, String phone) =>
      _post('student-otp', {'action': 'send', 'join_code': joinCode, 'phone': phone}, withToken: false);

  /// Returns tenant_status (null for a new visitor). Saves the token on the phone.
  Future<String?> verifyOtp(String joinCode, String phone, String code) async {
    final r = await _post('student-otp',
        {'action': 'verify', 'join_code': joinCode, 'phone': phone, 'code': code},
        withToken: false);
    await useToken(r['token'] as String, joinCode: joinCode);
    return r['tenant_status'] as String?;
  }

  // --- everything after verification (student-api) ---
  Future<Json> hostel() => _post('student-api', {'action': 'hostel'});

  Future<List<Json>> rooms() async {
    final r = await _post('student-api', {'action': 'rooms'});
    return (r['items'] as List? ?? const []).cast<Json>();
  }

  Future<Json> hold(String bedId) => _post('student-api', {'action': 'hold', 'bed_id': bedId});

  /// Take the bed the owner held and shared as a QR code.
  Future<Json> holdBooked(String bedId, String code) =>
      _post('student-api', {'action': 'hold_booked', 'bed_id': bedId, 'code': code});

  Future<Json> quote() => _post('student-api', {'action': 'quote'});

  // --- Phase 1: the student types their own room (owner hasn't set up rooms yet) ---
  /// True while the hostel lets tenants type their room (set from the hostel info).
  bool typedRoomFlow = false;

  /// A room the owner already set: its details are filled in and locked on the form.
  Future<Json> roomLookup(String roomNo) => _post('student-api', {'action': 'room_lookup', 'room_no': roomNo});

  /// Creates the typed room (unconfirmed) if needed and holds a bed in it for this student.
  Future<Json> claimRoom({
    required String roomNo,
    required int floor,
    required int sharing,
    required int rent,
    required int deposit,
    required bool existing,
  }) =>
      _post('student-api', {
        'action': 'claim_room',
        'room_no': roomNo,
        'floor': floor,
        'sharing': sharing,
        'rent_month': rent,
        'deposit': deposit,
        'is_existing': existing,
      });

  /// Uploads a (compressed) image to private storage; returns its key.
  Future<String> upload(String kind, Uint8List bytes, String contentType) async {
    final r = await _post('student-api', {'action': 'upload_url', 'kind': kind, 'content_type': contentType});
    try {
      final res = await http
          .put(Uri.parse(r['url'] as String), headers: {'Content-Type': contentType}, body: bytes)
          .timeout(const Duration(seconds: 60));
      if (res.statusCode >= 300) throw AppException('FILE_TOO_BIG_OR_MISSING');
    } on TimeoutException {
      throw AppException('NETWORK');
    } on http.ClientException {
      throw AppException('NETWORK');
    }
    return r['key'] as String;
  }

  Future<Json> submitDetails(Json details) => _post('student-api', {'action': 'details', ...details});

  Future<Json> submitPayment({required String method, String? utr, DateTime? paidOn}) => _post('student-api', {
        'action': 'pay',
        'method': method,
        'utr': utr,
        if (paidOn != null) 'paid_on': isoDate(paidOn),
      });

  Future<Json> me() => _post('student-api', {'action': 'me'});

  Future<Json> payBill({required String method, String? utr, required int amount, DateTime? paidOn}) =>
      _post('student-api', {
        'action': 'pay_bill',
        'method': method,
        'utr': utr,
        'amount': amount,
        if (paidOn != null) 'paid_on': isoDate(paidOn),
      });

  /// Vacate notice. The leaving date is always the next fee date (decided 20 Oct 2026), so it is optional.
  Future<Json> giveNotice([DateTime? leavingDate]) => _post('student-api',
      {'action': 'give_notice', if (leavingDate != null) 'leaving_date': isoDate(leavingDate)});

  Future<void> cancelNotice() => _post('student-api', {'action': 'cancel_notice'});

  /// Small photo for the owner's lists (~100×100, made on the phone).
  Future<void> setThumb(String key) => _post('student-api', {'action': 'set_thumb', 'key': key});

  /// Pay by cash → "When will you pay?" today / tomorrow / paid → the owner is told.
  Future<Json> cashPlan({required String plan, required int amount}) =>
      _post('student-api', {'action': 'cash_plan', 'plan': plan, 'amount': amount});

  Future<void> cancelCashPlan() => _post('student-api', {'action': 'cancel_cash_plan'});

  /// A message in Fees / Home stays until the student taps OK.
  Future<void> ackMessage(String id) => _post('student-api', {'action': 'ack_message', 'id': id});

  Future<void> reportIssue({required String category, required String body}) =>
      _post('student-api', {'action': 'report_issue', 'category': category, 'body': body});

  Future<void> readIssue(String id) => _post('student-api', {'action': 'read_issue', 'id': id});

  /// Ad shown / tapped (counts for the app admin). Never fails the screen.
  Future<void> adEvent(String id, {required bool click}) async {
    try {
      await _post('student-api', {'action': 'ad_event', 'id': id, 'click': click});
    } catch (_) {}
  }
}
