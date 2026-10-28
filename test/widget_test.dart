
import 'package:flutter_test/flutter_test.dart';
import 'package:sathi_claim_recovery/features/claim/domain/models/claim_models.dart';

void main() {
  group('Sathi ClaimState', () {
    test('new Sathi state never invents a user claim', () {
      final claim = ClaimState.empty();

      expect(claim.claimId, 'Not provided');
      expect(claim.insurerName, 'Not connected');
      expect(claim.requestedAmount, 0);
      expect(claim.approvedAmount, 0);
      expect(claim.timeline, isEmpty);
      expect(claim.appealDraft, isEmpty);
    });
  });
}
