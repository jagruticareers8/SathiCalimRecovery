import 'package:flutter_test/flutter_test.dart';
import 'package:sathi_claim_recovery/features/claim/data/local_first_sathi_agent_service.dart';
import 'package:sathi_claim_recovery/features/claim/data/sathi_agent_service.dart';
import 'package:sathi_claim_recovery/core/storage/local_private_vault.dart';

void main() {
  const ocrText = '''
SAMPLE HEALTH ASSURANCE
Health Insurance Claim: Partial Approval Notice
Amount claimed
Rs. 85,000
Amount
Rs. 52,000
approved
Amount pending
Rs. 33,000
Current status
Partially approved - more information needed
''';

  late LocalFirstSathiAgentService service;

  setUp(() {
    service = LocalFirstSathiAgentService(
      cloudService: SathiAgentService(baseUrl: ''),
      vault: _MemoryVault(ocrText),
    );
  });

  test(
    'answers claimed amount from OCR locally, without cloud consent',
    () async {
      final reply = await service.ask(
        message: 'Mera claim kitne ka tha?',
        language: SathiLanguageMode.hinglish,
        allowCloudAnalysis: false,
        queryMode: SathiQueryMode.privateLocal,
      );

      expect(reply.mode, 'local_document_fact');
      expect(reply.answer, contains('₹85,000'));
      expect(reply.answer, contains('₹52,000'));
      expect(reply.answer, contains('₹33,000'));
      expect(reply.notice, contains('No question or document was sent online'));
    },
  );

  test('answers approved amount from OCR locally', () async {
    final reply = await service.ask(
      message: 'Kitna amount approve hua?',
      language: SathiLanguageMode.hinglish,
      allowCloudAnalysis: false,
      queryMode: SathiQueryMode.privateLocal,
    );

    expect(reply.mode, 'local_document_fact');
    expect(reply.answer, contains('₹52,000'));
  });
}

class _MemoryVault implements LocalPrivateVault {
  _MemoryVault(this.text);

  final String text;

  @override
  Future<Map<String, dynamic>> readSnapshot() async => {
    'documents': [
      {'title': 'Synthetic claim letter', 'extractedText': text},
    ],
  };

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
