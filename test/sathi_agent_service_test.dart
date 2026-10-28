import 'package:flutter_test/flutter_test.dart';
import 'package:sathi_claim_recovery/features/claim/data/sathi_agent_service.dart';

void main() {
  group('Sathi local Hinglish intent router', () {
    test('recognises Roman Hinglish rejection', () {
      expect(SathiLocalAgent.detectIntent('Mera claim reject ho gaya, ab kya karu?'), 'explain_rejection');
    });

    test('recognises Hindi script rejection', () {
      expect(SathiLocalAgent.detectIntent('मेरा क्लेम रिजेक्ट हो गया, अब क्या करूँ?'), 'explain_rejection');
    });

    test('recognises document question', () {
      expect(SathiLocalAgent.detectIntent('Kaun se documents chahiye?'), 'required_documents');
    });

    test('recognises Hindi status question', () {
      expect(SathiLocalAgent.detectIntent('मेरा क्लेम स्टेटस क्या है?'), 'claim_status');
    });

    test('local response clearly identifies action and language', () {
      final result = SathiLocalAgent.answer('claim ka status kya hai', SathiLanguageMode.hinglish);
      expect(result.intent, 'claim_status');
      expect(result.actionIndex, 3);
      expect(result.answer, contains('Demo mein'));
    });
  });
}
