import 'package:flutter_test/flutter_test.dart';
import 'package:sathi_claim_recovery/features/claim/data/on_device_rag_service.dart';

void main() {
  group('Sathi on-device RAG utilities', () {
    test('splits long local document text into bounded, non-empty chunks', () {
      final input = List<String>.generate(40, (i) => 'Line $i explains a policy term and a customer next step.').join('\n');
      final chunks = SathiOnDeviceRagService.splitTextIntoChunks(input, maxChars: 120);

      expect(chunks.length, greaterThan(1));
      expect(chunks.every((chunk) => chunk.trim().isNotEmpty), isTrue);
      expect(chunks.every((chunk) => chunk.length <= 120), isTrue);
      expect(chunks.join(' '), contains('Line 0'));
      expect(chunks.join(' '), contains('Line 39'));
    });

    test('cosine similarity ranks identical vectors above orthogonal vectors', () {
      final same = SathiOnDeviceRagService.cosineSimilarity([1, 0, 1], [1, 0, 1]);
      final orthogonal = SathiOnDeviceRagService.cosineSimilarity([1, 0], [0, 1]);
      final opposite = SathiOnDeviceRagService.cosineSimilarity([1, 0], [-1, 0]);

      expect(same, closeTo(1, 0.00001));
      expect(orthogonal, closeTo(0, 0.00001));
      expect(opposite, closeTo(-1, 0.00001));
    });

    test('rejects vectors with mismatched sizes instead of treating them as evidence', () {
      expect(SathiOnDeviceRagService.cosineSimilarity([1, 2], [1]), 0);
      expect(SathiOnDeviceRagService.cosineSimilarity([], []), 0);
    });
  });
}
