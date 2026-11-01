import 'package:flutter_test/flutter_test.dart';
import 'package:my_hostel/core/format.dart';
import 'package:my_hostel/widgets/pay_widgets.dart';

void main() {
  test('Indian money format', () {
    expect(money(125000), '₹1,25,000');
  });

  test('phone numbers', () {
    expect(normalizePhone('98765 43210'), '+919876543210');
    expect(normalizePhone('+91 98765 43210'), '+919876543210');
    expect(normalizePhone('12345'), isNull);
    expect(phoneText('+919876543210'), '98765 43210');
  });

  test('UPI link has amount and note filled in', () {
    final link = upiLink(upiId: 'hostel@okicici', payee: 'Sri Sai PG', amount: 8500, note: 'SSP-204B-1011');
    expect(link, startsWith('upi://pay?pa=hostel%40okicici'));
    expect(link, contains('am=8500.00'));
    expect(link, contains('tn=SSP-204B-1011'));
  });
}
