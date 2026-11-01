import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'format.dart';

/// An error with a short code from the server (e.g. BED_TAKEN) or the app (e.g. NETWORK).
class AppException implements Exception {
  AppException(this.code, [this.extra = const {}]);
  final String code;
  final Map<String, dynamic> extra;

  @override
  String toString() => 'AppException($code)';

  static AppException from(Object error) {
    if (error is AppException) return error;
    if (error is TimeoutException) return AppException('NETWORK');
    if (error is http.ClientException) return AppException('NETWORK');
    if (error is PostgrestException) {
      final m = error.message;
      if (error.code == '23505' && m.contains('room_no')) return AppException('ROOM_EXISTS');
      if (error.code == '23514') {
        if (m.contains('upi_id')) return AppException('BAD_UPI');
        if (m.contains('pincode')) return AppException('BAD_PINCODE');
        if (m.contains('phone')) return AppException('BAD_PHONE');
        return AppException('INVALID_VALUE');
      }
      return AppException(_codeFrom(m));
    }
    if (error is FunctionException) {
      final d = error.details;
      if (d is Map && d['error'] is String) return AppException(d['error'] as String, Map<String, dynamic>.from(d));
      return AppException(error.status == 0 ? 'NETWORK' : 'SERVER_ERROR');
    }
    if (error is AuthException) {
      final m = error.message.toLowerCase();
      if (m.contains('invalid login') || m.contains('invalid credentials')) return AppException('WRONG_LOGIN');
      if (m.contains('already registered') || m.contains('already exists')) return AppException('ALREADY_REGISTERED');
      if (m.contains('expired') || m.contains('invalid') && m.contains('otp') || m.contains('token')) {
        return AppException('OTP_WRONG');
      }
      if (m.contains('rate') || m.contains('seconds')) return AppException('OTP_RATE_LIMIT');
      if (m.contains('password') && (m.contains('short') || m.contains('characters') || m.contains('weak'))) {
        return AppException('WEAK_PASSWORD');
      }
      return AppException('SERVER_ERROR');
    }
    final text = error.toString();
    if (text.contains('SocketException') || text.contains('Failed host lookup') || text.contains('XMLHttpRequest')) {
      return AppException('NETWORK');
    }
    return AppException(_codeFrom(text));
  }

  static String _codeFrom(String message) {
    final first = message.trim().split(RegExp(r'\s')).first;
    return RegExp(r'^[A-Z_]{4,40}$').hasMatch(first) ? first : 'SERVER_ERROR';
  }
}

/// Text to show for an error, in the user's language.
String errorText(BuildContext context, Object error) {
  final e = AppException.from(error);
  final t = context.l10n;
  switch (e.code) {
    case 'NETWORK':
      return t.errNetwork;
    case 'SESSION_INVALID':
      return t.errSessionInvalid;
    case 'HOSTEL_NOT_FOUND':
      return t.errHostelNotFound;
    case 'HOSTEL_CLOSED':
      return t.errHostelClosed;
    case 'BED_TAKEN':
      return t.errBedTaken;
    case 'HOLD_EXPIRED':
    case 'NO_BED_HELD':
      return t.errHoldExpired;
    case 'BOOKING_EXPIRED':
      return t.errBookingExpired;
    case 'BOOKING_LINK_INVALID':
      return t.errBookingLinkInvalid;
    case 'PARENT_PHONE_REQUIRED':
      return t.errParentPhoneRequired;
    case 'PARENT_NAME_REQUIRED':
      return t.errParentNameRequired;
    case 'ALREADY_JOINED':
      return t.errAlreadyJoined;
    case 'DUPLICATE_UTR':
      return t.errDuplicateUtr;
    case 'UTR_REQUIRED':
      return t.errUtrRequired;
    case 'OTP_WRONG':
      final left = e.extra['tries_left'];
      return left == null ? t.errOtpWrongSimple : t.errOtpWrong('$left');
    case 'OTP_EXPIRED':
      return t.errOtpExpired;
    case 'OTP_LOCKED':
      return t.errOtpLocked;
    case 'OTP_RATE_LIMIT':
      return t.errOtpRateLimit;
    case 'BAD_PHONE':
      return t.errBadPhone;
    case 'BAD_ID_NUMBER':
      return t.errBadIdNumber;
    case 'FILES_REQUIRED':
    case 'FILE_TOO_BIG_OR_MISSING':
    case 'BAD_FILE_TYPE':
      return t.errFiles;
    case 'BAD_JOINING_DATE':
      return t.errJoiningDate;
    case 'CONSENT_REQUIRED':
      return t.errConsent;
    case 'BAD_AMOUNT':
      return t.errAmount;
    case 'BAD_DATE':
      return t.errDate;
    case 'TOO_MANY_PENDING':
      return t.errTooManyPending;
    case 'NOT_ACTIVE':
    case 'NOT_READY_FOR_PAYMENT':
      return t.errNotActive;
    case 'NO_BOOKING':
      return t.errNoBooking;
    case 'ROOM_IN_USE':
      return t.errRoomInUse;
    case 'BED_IN_USE':
      return t.errBedInUse;
    case 'ALREADY_DECIDED':
    case 'NOT_PENDING':
      return t.errAlreadyDecided;
    case 'NOT_ALLOWED':
    case 'NOT_LOGGED_IN':
      return t.errNotAllowed;
    case 'WRONG_LOGIN':
      return t.errWrongLogin;
    case 'ALREADY_REGISTERED':
      return t.errAlreadyRegistered;
    case 'WEAK_PASSWORD':
      return t.errWeakPassword;
    case 'BAD_OFFLINE_BEDS':
      return t.errOfflineBeds;
    case 'TOO_LONG':
      return t.errTooLong;
    case 'ROOM_EXISTS':
      return t.errRoomExists;
    case 'BAD_UPI':
      return t.errBadUpi;
    case 'BAD_PINCODE':
      return t.errBadPincode;
    case 'INVALID_VALUE':
      return t.errInvalidValue;
    // Phase 1: rooms typed by tenants
    case 'ROOM_ENTRY_OFF':
      return t.errRoomEntryOff;
    case 'BAD_ROOM_NO':
      return t.errBadRoomNo;
    case 'BAD_FLOOR':
      return t.errBadFloor;
    case 'BAD_SHARING':
      return t.errBadSharing;
    case 'ROOM_FULL':
      return t.errRoomFullTyped;
    case 'TOO_MANY_TENANTS':
      return t.errTooManyTenants;
    case 'BAD_GROUND_ROOM':
      return t.errGroundRoom;
    case 'STAFF_EXISTS':
      return t.errStaffExists;
    case 'BAD_NAME':
      return t.errName;
    case 'BAD_DUTY':
      return t.cantBeEmpty;
    case 'BAD_DAYS':
      return t.noticeDaysRange;
    case 'BAD_DAY':
      return t.pickDate;
    default:
      return t.errGeneric;
  }
}
