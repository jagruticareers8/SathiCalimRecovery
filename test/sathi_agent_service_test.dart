import 'package:flutter_test/flutter_test.dart';
import 'package:sathi_claim_recovery/features/claim/data/sathi_agent_service.dart';

void main() {
  group('Sathi online privacy boundary', () {
    final service = SathiAgentService(baseUrl: 'http://127.0.0.1:8000');

    test('cloud answers require explicit consent', () async {
      expect(
        () => service.ask(
          message: 'What does co-pay mean?',
          language: SathiLanguageMode.english,
          allowCloudAnalysis: false,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test(
      'claim context cannot be sent to online general-information API',
      () async {
        expect(
          () => service.ask(
            message: 'What does co-pay mean?',
            language: SathiLanguageMode.english,
            allowCloudAnalysis: true,
            claimContext: {
              'documentTexts': [
                {'title': 'Decision letter', 'text': 'private text'},
              ],
            },
          ),
          throwsA(isA<StateError>()),
        );
      },
    );

    test(
      'chat history cannot be sent to online general-information API',
      () async {
        expect(
          () => service.ask(
            message: 'What does co-pay mean?',
            language: SathiLanguageMode.english,
            allowCloudAnalysis: true,
            chatHistory: const [
              {'role': 'user', 'content': 'private question'},
            ],
          ),
          throwsA(isA<StateError>()),
        );
      },
    );
  });
}
