// Quick checks that run without Supabase or a phone (flutter test).
import 'package:flutter_test/flutter_test.dart';

import 'package:my_hostel/widgets/common.dart';

void main() {
  test('hostel names drop words that only say who the hostel is for', () {
    expect(cleanHostelName('Sai Residency Ladies PG'), 'Sai Residency');
    expect(cleanHostelName('Green Park'), 'Green Park');
  });
}
