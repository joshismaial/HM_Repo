import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/errors.dart';
import '../core/format.dart';

SupabaseClient get supa => Supabase.instance.client;

/// All owner data access. Row-level security on the server makes sure an owner
/// only ever sees their own hostels.
class OwnerRepo {
  OwnerRepo._();
  static final instance = OwnerRepo._();

  Future<T> _run<T>(Future<T> Function() f) async {
    try {
      return await f();
    } catch (e) {
      // Show the real cause in the console (the screen only shows a short message).
      // ignore: avoid_print
      print('[OwnerRepo] failed: ${e.runtimeType}: $e');
      throw AppException.from(e);
    }
  }

  // ---------------- login ----------------
  Future<void> signUp({required String phone, required String password, required String name, required String language}) =>
      _run(() => supa.auth.signUp(phone: phone, password: password, data: {'full_name': name, 'language': language}));

  Future<void> verifySignUp(String phone, String code) =>
      _run(() => supa.auth.verifyOTP(phone: phone, token: code, type: OtpType.sms));

  Future<void> resendSignUpOtp(String phone) => _run(() => supa.auth.resend(type: OtpType.sms, phone: phone));

  Future<void> login(String phone, String password) =>
      _run(() => supa.auth.signInWithPassword(phone: phone, password: password));

  Future<void> sendLoginOtp(String phone) =>
      _run(() => supa.auth.signInWithOtp(phone: phone, shouldCreateUser: false));

  Future<void> verifyLoginOtp(String phone, String code) =>
      _run(() => supa.auth.verifyOTP(phone: phone, token: code, type: OtpType.sms));

  Future<void> setPassword(String password) =>
      _run(() => supa.auth.updateUser(UserAttributes(password: password)));

  Future<void> logout() => _run(() => supa.auth.signOut());

  /// Logging in within 7 days of asking for deletion cancels it. Returns true if it was cancelled.
  Future<bool> cancelDeletionIfRequested() => _run(() async {
        final p = await profile();
        if (p != null && p['delete_requested_at'] != null) {
          await supa.rpc('cancel_account_deletion');
          return true;
        }
        return false;
      });

  Future<Json?> profile() => _run(() async {
        final uid = supa.auth.currentUser?.id;
        if (uid == null) return null;
        return await supa.from('profiles').select().eq('id', uid).maybeSingle();
      });

  Future<void> setProfileLanguage(String code) => _run(() async {
        final uid = supa.auth.currentUser?.id;
        if (uid == null) return;
        await supa.from('profiles').update({'language': code}).eq('id', uid);
      });

  Future<void> requestAccountDeletion() => _run(() => supa.rpc('request_account_deletion'));

  // ---------------- hostels ----------------
  /// All hostels of this owner, oldest first, including removed ones
  /// (`archived_at` set). My hostels hides the removed ones but uses the full
  /// order so each hostel keeps its card colour.
  Future<List<Json>> hostels() => _run(() async {
        final rows = await supa.from('hostels').select().order('created_at');
        return List<Json>.from(rows);
      });

  /// "Remove" a hostel from My hostels: hidden and closed to new joins.
  /// Tenants, rooms and payment history stay in the database.
  Future<void> removeHostel(String id) => _run(() => supa
      .from('hostels')
      .update({'archived_at': DateTime.now().toUtc().toIso8601String(), 'is_open': false}).eq('id', id));

  /// Bring a removed hostel back: shown again and open for joins.
  /// (The daily rent job then catches up on bills for the removed period.)
  Future<void> restoreHostel(String id) =>
      _run(() => supa.from('hostels').update({'archived_at': null, 'is_open': true}).eq('id', id));

  /// How many hostels the owner has removed (0 hides the Removed hostels links).
  Future<int> removedHostelCount() => _run(() async {
        final rows = await supa.from('hostels').select('id').not('archived_at', 'is', null);
        return rows.length;
      });

  /// Tenants living in each hostel now (active + on notice): hostel id -> count.
  Future<Map<String, int>> tenantCounts(List<String> hostelIds) => _run(() async {
        if (hostelIds.isEmpty) return <String, int>{};
        final rows = await supa
            .from('tenants')
            .select('hostel_id')
            .inFilter('hostel_id', hostelIds)
            .inFilter('status', ['active', 'notice']);
        final out = <String, int>{};
        for (final r in rows) {
          final id = r['hostel_id'] as String;
          out[id] = (out[id] ?? 0) + 1;
        }
        return out;
      });

  Future<Json> hostel(String id) => _run(() => supa.from('hostels').select().eq('id', id).single());

  Future<Json> addHostel(Json values) => _run(() => supa.from('hostels').insert(values).select().single());

  Future<void> updateHostel(String id, Json values) =>
      _run(() => supa.from('hostels').update(values).eq('id', id));

  /// Home numbers (+ open complaints, rooms with a free bed, cash to check).
  Future<Json> summary(String hostelId) => _run(() async {
        final base = Json.from(await supa.rpc('hostel_summary', params: {'p_hostel': hostelId}) as Map);
        final extra = Json.from(await supa.rpc('hostel_summary_extra', params: {'p_hostel': hostelId}) as Map);
        return {...base, ...extra};
      });

  // ---------------- hostel photo (private storage; short-lived links) ----------------
  Future<String?> hostelPhotoUrl(String hostelId) => _run(() async {
        final r = await supa.functions.invoke('owner-actions', body: {'action': 'hostel_photo_url', 'hostel_id': hostelId});
        return (r.data as Map)['url'] as String?;
      });

  /// Uploads a compressed photo (~200 KB) and saves it as the hostel photo. Returns a 1-hour link to show it.
  Future<String?> setHostelPhoto(String hostelId, Uint8List bytes) => _run(() async {
        final r = await supa.functions.invoke('owner-actions',
            body: {'action': 'hostel_photo_upload', 'hostel_id': hostelId, 'content_type': 'image/jpeg'});
        final up = Map<String, dynamic>.from(r.data as Map);
        final res = await http
            .put(Uri.parse(up['url'] as String), headers: {'Content-Type': 'image/jpeg'}, body: bytes)
            .timeout(const Duration(seconds: 60));
        if (res.statusCode >= 300) throw AppException('FILE_TOO_BIG_OR_MISSING');
        final saved = await supa.functions.invoke('owner-actions',
            body: {'action': 'hostel_photo_saved', 'hostel_id': hostelId, 'key': up['key']});
        return (saved.data as Map)['url'] as String?;
      });

  Future<void> removeHostelPhoto(String hostelId) => _run(() => supa.functions
      .invoke('owner-actions', body: {'action': 'hostel_photo_saved', 'hostel_id': hostelId, 'key': null}));

  /// Student thumbnails for lists: tenant id -> 1-hour link.
  Future<Map<String, String>> thumbUrls(String hostelId) => _run(() async {
        final r = await supa.functions.invoke('owner-actions', body: {'action': 'thumb_urls', 'hostel_id': hostelId});
        return Map<String, String>.from(((r.data as Map)['urls'] as Map?) ?? const {});
      });

  // ---------------- notices to students ----------------
  Future<List<Json>> ownerNotices(String hostelId) => _run(() async => List<Json>.from(await supa
      .from('owner_notices')
      .select()
      .eq('hostel_id', hostelId)
      .gte('created_at', DateTime.now().subtract(const Duration(days: 30)).toUtc().toIso8601String())
      .order('created_at', ascending: false)));

  Future<void> postNotice(String hostelId, {required String icon, required String title, String? body}) => _run(() =>
      supa.rpc('post_owner_notice', params: {'p_hostel': hostelId, 'p_icon': icon, 'p_title': title, 'p_body': body}));

  Future<void> removeNotice(String noticeId) => _run(() => supa.rpc('remove_owner_notice', params: {'p_notice': noticeId}));

  // ---------------- complaints (students' Report issue) ----------------
  Future<List<Json>> complaints(String hostelId) => _run(() async => List<Json>.from(await supa
      .from('complaints')
      .select('*, tenants(full_name, beds(label, rooms(room_no)))')
      .eq('hostel_id', hostelId)
      .order('created_at', ascending: false)
      .limit(200)));

  Future<void> updateComplaint(String id, {String? status, String? reply}) =>
      _run(() => supa.rpc('update_complaint', params: {'p_complaint': id, 'p_status': status, 'p_reply': reply}));

  // ---------------- rooms & beds ----------------
  Future<List<Json>> roomsWithBeds(String hostelId) => _run(() async {
        final rows = await supa
            .from('rooms')
            .select('*, beds(id, label, status, held_until, held_for)')
            .eq('hostel_id', hostelId)
            .order('floor')
            .order('room_no');
        return List<Json>.from(rows);
      });

  /// Who sits on which bed (living tenants only).
  Future<Map<String, Json>> tenantsByBed(String hostelId) => _run(() async {
        final rows = await supa
            .from('tenants')
            .select('id, full_name, bed_id, status')
            .eq('hostel_id', hostelId)
            .inFilter('status', ['active', 'notice', 'pending_approval']);
        return {for (final r in rows) if (r['bed_id'] != null) r['bed_id'] as String: Json.from(r)};
      });

  /// Creates the room and its beds (A, B, C…); per-day rent / day-wise deposit are saved on the room.
  Future<String> addRoom({
    required String hostelId,
    required String roomNo,
    required int floor,
    required int sharing,
    required int rent,
    required int deposit,
    required List<String> features,
    int offlineBeds = 0,
    int? rentDay,
    int? depositDay,
  }) =>
      _run(() async {
        final id = await supa.rpc('add_room', params: {
          'p_hostel': hostelId,
          'p_room_no': roomNo,
          'p_floor': floor,
          'p_sharing': sharing,
          'p_rent': rent,
          'p_deposit': deposit,
          'p_features': features,
          'p_offline_beds': offlineBeds,
        }) as String;
        if (rentDay != null || depositDay != null) {
          await supa.from('rooms').update({'rent_day': rentDay, 'deposit_day': depositDay}).eq('id', id);
        }
        return id;
      });

  Future<void> updateRoom(String roomId, Json values) => _run(() => supa.from('rooms').update(values).eq('id', roomId));

  /// Hostel settings → Change room details: sharing (beds follow) and rent. When the sharing changes,
  /// the students in the room pay the new rent from their next fee date and get a message.
  Future<void> changeRoom(String roomId, {required String roomNo, required int sharing, required int rent}) =>
      _run(() => supa.rpc('update_room', params: {'p_room': roomId, 'p_room_no': roomNo, 'p_sharing': sharing, 'p_rent': rent}));

  /// Hostel settings → Add room (floor, room number, sharing, rent per bed).
  Future<void> addRoomSimple(String hostelId, {required int floor, required String roomNo, required int sharing, required int rent}) =>
      _run(() => supa.rpc('add_room_simple',
          params: {'p_hostel': hostelId, 'p_floor': floor, 'p_room_no': roomNo, 'p_sharing': sharing, 'p_rent': rent}));

  /// Hostel settings → Rent date. Staying students move to the new date (days in between added or
  /// taken off once) and get a message. Returns how many students were moved.
  Future<int> changeRentDay(String hostelId, {required String mode, required int fixedDay}) => _run(() async =>
      asInt(await supa.rpc('change_rent_day', params: {'p_hostel': hostelId, 'p_mode': mode, 'p_fixed_day': fixedDay})));

  /// Students staying (monthly) — for the "Yes, change" sheet of Rent date.
  Future<int> stayingCount(String hostelId) => _run(() async => asInt(((await supa.rpc('rent_day_preview',
      params: {'p_hostel': hostelId, 'p_mode': 'fixed_day', 'p_fixed_day': 1})) as Map)['staying']));

  /// More → Staff (owner only).
  Future<List<Json>> staffList(String hostelId) => _run(() async =>
      [for (final r in (await supa.rpc('staff_list', params: {'p_hostel': hostelId}) as List)) Json.from(r as Map)]);

  /// Add (id null) or change a staff member. [duties] null = the job's usual duties.
  Future<String> saveStaff(String hostelId,
          {String? id, required String name, required String phone, required String job, String? jobOther,
          List<String>? duties, List<Json> custom = const [], String? checklist}) =>
      _run(() async => (await supa.rpc('save_staff', params: {
            'p_hostel': hostelId, 'p_id': id, 'p_name': name, 'p_phone': phone, 'p_job': job, 'p_job_other': jobOther,
            'p_duties': duties, 'p_custom': custom, 'p_checklist': checklist,
          })) as String);

  Future<void> removeStaff(String staffId) => _run(() => supa.rpc('remove_staff', params: {'p_staff': staffId}));

  /// Hostel settings → Notice period (1–90 days). Students who haven't given notice get a message.
  Future<void> setNoticeDays(String hostelId, int days) =>
      _run(() => supa.rpc('set_notice_days', params: {'p_hostel': hostelId, 'p_days': days}));

  Future<void> deleteRoom(String roomId) => _run(() => supa.rpc('delete_room', params: {'p_room': roomId}));

  /// Hold a free bed for 15 minutes and get its one-time booking code (for the student QR).
  Future<Json> holdBedForBooking(String bedId) =>
      _run(() async => Json.from(await supa.rpc('owner_hold_bed', params: {'p_bed': bedId}) as Map));

  /// Give back a bed held for a QR booking that nobody has started yet.
  Future<void> releaseBookingHold(String bedId) => _run(() => supa.rpc('owner_release_bed', params: {'p_bed': bedId}));

  Future<void> setBedOffline(String bedId, bool offline) =>
      _run(() => supa.rpc('set_bed_offline', params: {'p_bed': bedId, 'p_offline': offline}));

  /// Hostel settings: rent per sharing, deposit on/off + amount, day-wise on/off + price per day.
  /// The server copies them to the hostel's rooms (students already staying keep their rent).
  Future<void> saveHostelPrices(String hostelId,
          {required List<Json> prices, required bool depositOn, required int depositAmount, required bool dayWiseOn, required int perDay}) =>
      _run(() => supa.rpc('save_hostel_prices', params: {
            'p_hostel': hostelId,
            'p_prices': [for (final p in prices) {'sharing': asInt(p['sharing']), 'rent': asInt(p['rent'])}],
            'p_deposit_on': depositOn,
            'p_deposit_amount': depositAmount,
            'p_day_wise_on': dayWiseOn,
            'p_per_day': perDay,
          }));

  // ---------------- Phase 1: rooms entered by tenants ----------------
  /// One row per room tenants typed: room values, what each tenant entered, status confirmed / fix / ok.
  Future<List<Json>> tenantRooms(String hostelId) => _run(() async {
        final r = await supa.rpc('tenant_rooms', params: {'p_hostel': hostelId});
        return List<Json>.from((r as List?) ?? const []);
      });

  /// Correct one room (students are not told) and confirm it.
  Future<void> confirmTenantRoom(String roomId, {required int floor, required int sharing, required int rent, required int deposit}) =>
      _run(() => supa.rpc('confirm_tenant_room', params: {
            'p_room': roomId,
            'p_floor': floor,
            'p_sharing': sharing,
            'p_rent': rent,
            'p_deposit': deposit,
          }));

  /// Confirm every room whose tenants all typed the same thing. Returns how many.
  Future<int> confirmCorrectTenantRooms(String hostelId) =>
      _run(() async => asInt(await supa.rpc('confirm_correct_tenant_rooms', params: {'p_hostel': hostelId})));

  /// Price by sharing: one price and deposit for every tenant-entered room of that sharing.
  Future<void> setSharingPrice(String hostelId, {required int sharing, required int rent, required int deposit}) =>
      _run(() => supa.rpc('set_sharing_price', params: {
            'p_hostel': hostelId,
            'p_sharing': sharing,
            'p_rent': rent,
            'p_deposit': deposit,
          }));

  // ---------------- requests ----------------
  static const _tenantWithBed = 'id, full_name, phone, status, is_existing, joining_date, id_type, id_last4, '
      'rent_month, deposit, beds(label, rooms(room_no))';

  // ---------------------------------------------------------------- reports
  /// Bills due in [from]..[to] (not cancelled), with the tenant and room.
  Future<List<Json>> reportBills(String hostelId, DateTime from, DateTime to) => _run(() async {
        final rows = await supa
            .from('bills')
            .select('tenant_id, kind, amount, paid_amount, due_date, status, '
                'tenants(full_name, phone, beds(label, rooms(room_no)))')
            .eq('hostel_id', hostelId)
            .neq('status', 'cancelled')
            .gte('due_date', isoDate(from))
            .lte('due_date', isoDate(to))
            .order('due_date');
        return List<Json>.from(rows);
      });

  /// Payments received in [from]..[to].
  Future<List<Json>> reportPayments(String hostelId, DateTime from, DateTime to) => _run(() async {
        final rows = await supa
            .from('payments')
            .select('tenant_id, method, amount_received, paid_on')
            .eq('hostel_id', hostelId)
            .eq('status', 'received')
            .gte('paid_on', isoDate(from))
            .lte('paid_on', isoDate(to))
            .order('paid_on');
        return List<Json>.from(rows);
      });

  /// Every tenant who has joined (staying, leaving or left), for the students list.
  Future<List<Json>> reportTenants(String hostelId) => _run(() async {
        final rows = await supa
            .from('tenants')
            .select('id, full_name, phone, status, joining_date, leaving_date, vacated_at, org_name, rent_month, '
                'deposit, id_file_key, beds(label, rooms(room_no))')
            .eq('hostel_id', hostelId)
            .inFilter('status', ['active', 'notice', 'vacated'])
            .order('joining_date', ascending: false);
        return List<Json>.from(rows);
      });

  Future<List<Json>> pendingPayments(String hostelId) => _run(() async {
        final rows = await supa
            .from('payments')
            .select('*, tenants($_tenantWithBed)')
            .eq('hostel_id', hostelId)
            .eq('status', 'pending')
            .order('created_at');
        return List<Json>.from(rows);
      });

  Future<List<Json>> existingTenantRequests(String hostelId) => _run(() async {
        final rows = await supa
            .from('tenants')
            .select(_tenantWithBed)
            .eq('hostel_id', hostelId)
            .eq('status', 'pending_approval')
            .eq('is_existing', true)
            .order('created_at');
        return List<Json>.from(rows);
      });

  Future<Json> confirmPayment(String paymentId, int amountReceived) => _run(() async => Json.from(
      await supa.rpc('confirm_payment', params: {'p_payment': paymentId, 'p_amount_received': amountReceived}) as Map));

  Future<void> rejectPayment(String paymentId) =>
      _run(() => supa.rpc('reject_payment', params: {'p_payment': paymentId}));

  Future<void> approveTenant(String tenantId) => _run(() => supa.rpc('approve_tenant', params: {'p_tenant': tenantId}));

  Future<void> rejectTenant(String tenantId) => _run(() => supa.rpc('reject_tenant', params: {'p_tenant': tenantId}));

  /// New joiner: confirm the booking (the waiting payment is confirmed for the amount paid).
  Future<void> confirmBooking(String tenantId) =>
      _run(() => supa.rpc('confirm_booking', params: {'p_tenant': tenantId}));

  /// New joiner: reject with one of wrong_details, aadhaar_unclear, payment_not_received,
  /// bed_not_available, other. The bed is free again and the student sees the reason.
  Future<void> rejectBooking(String tenantId, String reason) =>
      _run(() => supa.rpc('reject_booking', params: {'p_tenant': tenantId, 'p_reason': reason}));

  // ---------------- tenants ----------------
  Future<List<Json>> tenants(String hostelId, List<String> statuses) => _run(() async {
        final rows = await supa
            .from('tenants')
            .select('id, full_name, phone, status, joining_date, leaving_date, is_existing, rent_month, '
                'beds(label, rooms(room_no))')
            .eq('hostel_id', hostelId)
            .inFilter('status', statuses)
            .order('full_name');
        return List<Json>.from(rows);
      });

  Future<Json> tenant(String tenantId) => _run(() async {
        final t = await supa
            .from('tenants')
            .select('id, hostel_id, bed_id, phone, full_name, parent_name, parent_phone, reference_name, reference_phone, org_name, id_type, id_last4, '
                'id_file_key, photo_key, home_address, office_address, joining_date, is_existing, stay_type, '
                'rent_month, deposit, status, notice_given_at, leaving_date, vacated_at, deposit_deduction, '
                'deposit_refund, files_purged_at, created_at, beds(label, rooms(room_no, sharing))')
            .eq('id', tenantId)
            .single();
        final bills = await supa
            .from('bills')
            .select()
            .eq('tenant_id', tenantId)
            .neq('status', 'cancelled')
            .order('due_date', ascending: false)
            .limit(24);
        final payments = await supa
            .from('payments')
            .select()
            .eq('tenant_id', tenantId)
            .order('created_at', ascending: false)
            .limit(30);
        return {...t, 'bills': bills, 'payments': payments};
      });

  Future<String?> revealIdNumber(String tenantId) =>
      _run(() async => await supa.rpc('reveal_id_number', params: {'p_tenant': tenantId}) as String?);

  Future<String> fileUrl(String tenantId, String kind) => _run(() async {
        final r = await supa.functions.invoke('owner-actions', body: {'action': 'file_url', 'tenant_id': tenantId, 'kind': kind});
        return (r.data as Map)['url'] as String;
      });

  Future<String> studentLink(String tenantId, {required bool reset, required bool sms}) => _run(() async {
        final r = await supa.functions.invoke('owner-actions',
            body: {'action': 'student_link', 'tenant_id': tenantId, 'reset': reset, 'sms': sms});
        return (r.data as Map)['url'] as String;
      });

  Future<void> recordPayment({
    required String tenantId,
    required int amount,
    required String method,
    required DateTime paidOn,
    String? note,
    bool waiveLateFee = false,
  }) =>
      _run(() => supa.rpc('record_payment', params: {
            'p_tenant': tenantId,
            'p_amount': amount,
            'p_method': method,
            'p_paid_on': isoDate(paidOn),
            'p_note': (note == null || note.trim().isEmpty) ? null : note.trim(),
            'p_waive_late_fee': waiveLateFee,
          }));

  /// Rent due now and late fee so far for Record payment ({late_fee_on, per_day, days, fee, rent_due}).
  Future<Json> lateFeeQuote(String tenantId, DateTime until) => _run(() async => Json.from(
      await supa.rpc('owner_late_fee', params: {'p_tenant': tenantId, 'p_until': isoDate(until)}) as Map));

  Future<void> setLateFee(String hostelId, {required bool on, required int perDay}) =>
      _run(() => supa.from('hostels').update({'late_fee_on': on, 'late_fee_per_day': perDay}).eq('id', hostelId));

  Future<Json> markVacated(String tenantId, int deduction) => _run(() async =>
      Json.from(await supa.rpc('mark_vacated', params: {'p_tenant': tenantId, 'p_deduction': deduction}) as Map));

  // ---------------- rent ----------------
  Future<Json> rentOverview(String hostelId, DateTime month) => _run(() async => Json.from(await supa
      .rpc('rent_overview', params: {'p_hostel': hostelId, 'p_month': isoDate(DateTime(month.year, month.month, 1))}) as Map));

  /// SMS reminder to every tenant whose rent is due today or late (skips anyone reminded in the last 12 hours).
  /// Returns how many reminders were sent.
  Future<int> remindAll(String hostelId) => _run(() async {
        final r = await supa.functions.invoke('rent-reminders', body: {'action': 'remind_all', 'hostel_id': hostelId});
        return asInt((r.data as Map)['sent']);
      });

  Future<void> setAutoRemind(String hostelId, bool on) =>
      _run(() => supa.from('hostels').update({'auto_remind': on}).eq('id', hostelId));
}

/// Amount still due on bills up to today (oldest first is applied by the server).
int dueNow(List bills) {
  final now = today();
  var due = 0;
  for (final b in bills) {
    final status = b['status'];
    if (status != 'unpaid' && status != 'partial') continue;
    final d = asDate(b['due_date']);
    if (d != null && d.isAfter(now)) continue;
    due += asInt(b['amount']) - asInt(b['paid_amount']);
  }
  return due < 0 ? 0 : due;
}
