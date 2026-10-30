import 'package:flutter_test/flutter_test.dart';
import 'package:sathi_claim_recovery/core/storage/local_private_vault.dart';
import 'package:sathi_claim_recovery/features/claim/data/local_first_sathi_agent_service.dart';
import 'package:sathi_claim_recovery/features/claim/data/sathi_agent_service.dart';

const _syntheticOcr = '''
SYNTHETIC HEALTH INSURANCE CLAIM DECISION LETTER
Claim ID: SYN-CLM-2048
Policy number: SYN-POL-7842
Insurer: Example Health Assurance
Hospital name: Example City Hospital
Claim decision date: 14 January 2026
Amount claimed
Rs. 85,000
Amount
Rs. 52,000 approved
Amount pending
Rs. 33,000
Current status
Partially approved - more information needed
Reason for partial approval
The itemised hospital bill and diagnostic report are required for final review.
Additional information deadline
Submit the additional information within 30 days from the date of this letter.
Diagnosis: Viral fever, as stated in this synthetic example only.
''';

void main() {
  late LocalFirstSathiAgentService service;

  setUp(() {
    service = LocalFirstSathiAgentService(
      cloudService: SathiAgentService(baseUrl: ''),
      vault: _MemoryVault(_syntheticOcr),
    );
  });

  Future<SathiAgentReply> ask(String question) => service.ask(
    message: question,
    language: SathiLanguageMode.hinglish,
    allowCloudAnalysis: false,
    queryMode: SathiQueryMode.privateLocal,
  );

  test('answers claim amount using varied Hinglish wording locally', () async {
    final reply = await ask('Mera claim kitne ka tha?');
    expect(reply.answer, contains('₹85,000'));
    expect(reply.notice, contains('No question or document was sent online'));
  });

  test('answers partial approval reason from nearby OCR lines', () async {
    final reply = await ask('Mera claim kyun partly approve hua?');
    expect(reply.answer.toLowerCase(), contains('partial approval'));
    expect(reply.answer.toLowerCase(), contains('itemised hospital bill'));
    expect(reply.notice, contains('ON DEVICE'));
  });

  test('answers current document status from OCR', () async {
    final reply = await ask('Abhi claim ka status kya hai?');
    expect(reply.answer.toLowerCase(), contains('partially approved'));
    expect(reply.mode, 'local_document_fact');
  });

  test(
    'extracts status value when OCR table rows are reordered with the synthetic header',
    () async {
      final noisyService = LocalFirstSathiAgentService(
        cloudService: SathiAgentService(baseUrl: ''),
        vault: _MemoryVault('''
SAMPLE HEALTH ASSURANCE
SYNTHETIC TEST DOCUMENT | NOT A REAL INSURER LETTER | SATHI OCR + LOCAL Q&A TEST
Amount pending review | Rs. 33,000 | Current status
Partially approved - more information needed
Reason given in this synthetic example
The remaining amount has not been finally decided.
'''),
      );
      final reply = await noisyService.ask(
        message: 'Mera claim status kya hai?',
        language: SathiLanguageMode.hinglish,
        allowCloudAnalysis: false,
        queryMode: SathiQueryMode.privateLocal,
      );

      expect(reply.answer.toLowerCase(), contains('partially approved'));
      expect(reply.answer.toLowerCase(), contains('more information needed'));
      expect(
        reply.answer,
        isNot(
          contains(
            'SYNTHETIC TEST DOCUMENT | NOT A REAL INSURER LETTER | SATHI OCR',
          ),
        ),
      );
      expect(reply.mode, 'local_document_fact');
      expect(reply.evidenceUsed.single, contains('Current status'));
    },
  );

  test(
    'does not answer claim status with header labels when OCR has no status value',
    () async {
      final noisyService = LocalFirstSathiAgentService(
        cloudService: SathiAgentService(baseUrl: ''),
        vault: _MemoryVault(
          'SYNTHETIC TEST DOCUMENT | NOT A REAL INSURER LETTER | Current status | SATHI OCR + LOCAL Q&A TEST',
        ),
      );
      final reply = await noisyService.ask(
        message: 'Mera claim status kya hai?',
        language: SathiLanguageMode.hinglish,
        allowCloudAnalysis: false,
        queryMode: SathiQueryMode.privateLocal,
      );

      expect(reply.mode, 'local_fact_not_found');
      expect(reply.answer.toLowerCase(), contains('claim status/decision'));
      expect(
        reply.answer,
        isNot(
          contains(
            'SYNTHETIC TEST DOCUMENT | NOT A REAL INSURER LETTER | Current status',
          ),
        ),
      );
    },
  );

  test('answers required documents in English', () async {
    final reply = await ask('Which documents do I need to submit?');
    expect(reply.answer.toLowerCase(), contains('itemised hospital bill'));
    expect(reply.answer.toLowerCase(), contains('diagnostic report'));
  });

  test(
    'finds appeal deadline even though question contains claim words',
    () async {
      final reply = await ask('Appeal kitne din mein submit karni hai?');
      expect(reply.answer.toLowerCase(), contains('within 30 days'));
      expect(reply.answer.toLowerCase(), contains('deadline'));
    },
  );

  test('finds policy reference locally', () async {
    final reply = await ask('Mera policy number kya hai?');
    expect(reply.answer, contains('SYN-POL-7842'));
  });

  test('finds hospital name locally', () async {
    final reply = await ask('Hospital ka naam kya hai?');
    expect(reply.answer, contains('Example City Hospital'));
  });

  test('answers treatment question using saved text only', () async {
    final reply = await ask('What treatment or diagnosis is mentioned?');
    expect(reply.answer.toLowerCase(), contains('viral fever'));
  });

  test(
    'never sends private question or OCR to cloud when local evidence is found',
    () async {
      final reply = await ask(
        'Tell me the claim rejection reason in my letter',
      );
      expect(reply.notice, contains('No question or document was sent online'));
      expect(reply.mode, 'local_document_fact');
    },
  );

  test(
    'understands alternate English wording for the claimed amount',
    () async {
      final reply = await ask('How much money was originally requested?');
      expect(reply.answer, contains('₹85,000'));
      expect(reply.notice, contains('No question or document was sent online'));
    },
  );

  test('understands approval phrasing without the word status', () async {
    final reply = await ask('Has my claim been approved yet?');
    expect(reply.answer.toLowerCase(), contains('partially approved'));
    expect(reply.mode, 'local_document_fact');
  });

  test('understands paper/upload wording for required documents', () async {
    final reply = await ask('Which papers should I upload now?');
    expect(reply.answer.toLowerCase(), contains('itemised hospital bill'));
    expect(reply.answer.toLowerCase(), contains('diagnostic report'));
  });

  test('understands final date wording for a submission deadline', () async {
    final reply = await ask(
      'What is the final date to submit supporting documents?',
    );
    expect(reply.answer.toLowerCase(), contains('within 30 days'));
    expect(reply.intent, 'deadline');
  });

  test('finds insurer from a natural-language company question', () async {
    final reply = await ask('Who is my insurance company?');
    expect(reply.answer, contains('Example Health Assurance'));
    expect(reply.notice, contains('ON DEVICE'));
  });

  test('summarises when user asks for key points', () async {
    final reply = await ask(
      'Tell me the important points in this decision letter',
    );
    expect(reply.answer.toLowerCase(), contains('saved document'));
    expect(reply.answer.toLowerCase(), contains('itemised hospital bill'));
    expect(reply.intent, 'summary');
  });

  test(
    'creates an editable reconsideration draft from local evidence',
    () async {
      final reply = await ask('Please write an appeal letter for me');
      expect(reply.draft.toLowerCase(), contains('request for review'));
      expect(reply.draft.toLowerCase(), contains('itemised hospital bill'));
      expect(reply.answer.toLowerCase(), contains('draft'));
      expect(reply.mode, 'local_document_fact');
    },
  );

  test(
    'does not infer coverage when no policy coverage clause is present',
    () async {
      final reply = await ask('Does my policy cover viral fever treatment?');
      expect(reply.mode, 'local_fact_not_found');
      expect(reply.answer.toLowerCase(), contains('coverage clause'));
      expect(reply.notice, contains('No cloud request was made'));
    },
  );

  test(
    'returns an evidence-based search for an unclassified document question',
    () async {
      final reply = await ask('What does the document say about final review?');
      expect(reply.mode, 'local_document_search');
      expect(reply.answer.toLowerCase(), contains('relevant text'));
      expect(reply.evidenceUsed, isNotEmpty);
      expect(
        reply.notice,
        contains('No document text or question was sent online'),
      );
    },
  );
}

class _MemoryVault implements LocalPrivateVault {
  _MemoryVault(this.text);
  final String text;

  @override
  Future<Map<String, dynamic>> readSnapshot() async => {
    'version': 1,
    'documents': [
      {'title': 'Synthetic claim decision letter', 'extractedText': text},
    ],
  };

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
