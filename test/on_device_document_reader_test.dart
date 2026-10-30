import 'package:flutter_test/flutter_test.dart';
import 'package:sathi_claim_recovery/core/services/on_device_document_reader.dart';

void main() {
  group('OnDeviceDocumentReader', () {
    test('recognises PDF names regardless of case', () {
      expect(OnDeviceDocumentReader.isPdfPath('decision-letter.pdf'), isTrue);
      expect(OnDeviceDocumentReader.isPdfPath('/tmp/CLAIM.PDF'), isTrue);
    });

    test('does not classify photos as PDFs', () {
      expect(OnDeviceDocumentReader.isPdfPath('bill.jpg'), isFalse);
      expect(OnDeviceDocumentReader.isPdfPath('scan.png'), isFalse);
      expect(OnDeviceDocumentReader.isPdfPath('photo.webp'), isFalse);
    });
  });
}
