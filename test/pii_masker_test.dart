import 'package:flutter_test/flutter_test.dart';
import 'package:sathi_claim_recovery/core/security/pii_masker.dart';

void main() {
  group('PiiMasker', () {
    test('masks common email, phone, PAN-like and Aadhaar-like values', () {
      const sample = 'Reach me at jagruti@example.com or +91 98765 43210. PAN ABCDE1234F and Aadhaar 1234 5678 9012.';
      final masked = PiiMasker.mask(sample);
      expect(masked, contains('[EMAIL REDACTED]'));
      expect(masked, contains('[PHONE REDACTED]'));
      expect(masked, contains('[PAN REDACTED]'));
      expect(masked, contains('[ID REDACTED]'));
      expect(masked, isNot(contains('jagruti@example.com')));
      expect(masked, isNot(contains('98765 43210')));
    });
  });
}
