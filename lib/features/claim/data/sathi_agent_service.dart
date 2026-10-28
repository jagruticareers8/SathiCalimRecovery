import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../../core/security/pii_masker.dart';

enum SathiLanguageMode { hinglish, hindi, english }

extension SathiLanguageModeValue on SathiLanguageMode {
  String get apiValue => switch (this) {
        SathiLanguageMode.hinglish => 'hinglish',
        SathiLanguageMode.hindi => 'hindi',
        SathiLanguageMode.english => 'english',
      };

  String get label => switch (this) {
        SathiLanguageMode.hinglish => 'Hinglish',
        SathiLanguageMode.hindi => 'हिन्दी',
        SathiLanguageMode.english => 'English',
      };
}

class SathiAgentReply {
  const SathiAgentReply({
    required this.answer,
    required this.intent,
    required this.actionIndex,
    required this.actionLabel,
    required this.mode,
    this.model = '',
    this.notice = '',
  });

  final String answer;
  final String intent;
  final int actionIndex;
  final String actionLabel;
  /// gemini_agent, local_rules, or offline_fallback.
  final String mode;
  final String model;
  final String notice;

  factory SathiAgentReply.fromJson(Map<String, dynamic> json) => SathiAgentReply(
        answer: json['answer'] as String? ?? 'I could not prepare an answer. Please try again.',
        intent: json['intent'] as String? ?? 'general_help',
        actionIndex: json['actionIndex'] is int ? json['actionIndex'] as int : 1,
        actionLabel: json['actionLabel'] as String? ?? 'Review my claim',
        mode: json['mode'] as String? ?? 'unknown',
        model: json['model'] as String? ?? '',
        notice: json['notice'] as String? ?? '',
      );
}

/// Connects the Flutter app to a Sathi backend without ever storing the model key
/// in the mobile application. Without a configured/consented backend, it uses
/// transparent local rules and labels that response as non-model output.
class SathiAgentService {
  SathiAgentService({http.Client? client, String? baseUrl})
      : _client = client ?? http.Client(),
        baseUrl = (baseUrl ?? const String.fromEnvironment('SATHI_API_BASE_URL')).trim();

  final http.Client _client;
  final String baseUrl;

  bool get isConfigured => baseUrl.isNotEmpty;

  Uri _endpoint(String path) {
    final normalised = baseUrl.endsWith('/') ? baseUrl : '$baseUrl/';
    return Uri.parse(normalised).resolve(path.replaceFirst(RegExp(r'^/'), ''));
  }

  Future<SathiAgentReply> ask({
    required String message,
    required SathiLanguageMode language,
    required bool allowCloudAnalysis,
  }) async {
    final safeMessage = PiiMasker.mask(message.trim());
    if (allowCloudAnalysis && isConfigured) {
      try {
        final response = await _client
            .post(
              _endpoint('/v1/agent/chat'),
              headers: const {'content-type': 'application/json'},
              body: jsonEncode({
                'message': safeMessage,
                'language': language.apiValue,
                'claimContext': {
                  'claimId': 'STH-26-10482',
                  'status': 'Partially approved',
                  'requestedAmount': 68500,
                  'approvedAmount': 42000,
                  'unpaidAmount': 26500,
                  'statedReason': 'The sample decision letter refers to a missing itemised hospital bill and discharge summary.',
                  'requiredDocuments': ['Itemised hospital bill', 'Discharge summary'],
                },
              }),
            )
            .timeout(const Duration(seconds: 45));
        if (response.statusCode >= 200 && response.statusCode < 300) {
          final decoded = jsonDecode(response.body);
          if (decoded is Map<String, dynamic>) {
            return SathiAgentReply.fromJson(decoded);
          }
        }
      } catch (_) {
        // Fall back to deterministic local support, while clearly marking it.
      }
      final local = SathiLocalAgent.answer(safeMessage, language);
      return SathiAgentReply(
        answer: local.answer,
        intent: local.intent,
        actionIndex: local.actionIndex,
        actionLabel: local.actionLabel,
        mode: 'offline_fallback',
        notice: 'Sathi server/model unavailable. This response came from local demo rules, not Gemini.',
      );
    }
    final local = SathiLocalAgent.answer(safeMessage, language);
    return SathiAgentReply(
      answer: local.answer,
      intent: local.intent,
      actionIndex: local.actionIndex,
      actionLabel: local.actionLabel,
      mode: 'local_rules',
      notice: allowCloudAnalysis
          ? 'SATHI_API_BASE_URL is not configured; local demo rules were used.'
          : 'Cloud analysis is off. This response came from local demo rules, not an AI model.',
    );
  }

  /// Sends a short WAV recording only after the user has separately opted into
  /// cloud voice transcription. The backend reads it in memory and must not log
  /// or persist it. If this call fails, caller should show a clear error and may
  /// let the user try device speech recognition instead.
  Future<String> transcribeHinglishAudio(String filePath) async {
    if (!isConfigured) {
      throw StateError('Sathi backend URL is not configured.');
    }
    final file = File(filePath);
    if (!await file.exists()) throw StateError('The recording file was not found.');
    final size = await file.length();
    if (size == 0) throw StateError('The recording is empty. Please try again.');
    if (size > 8 * 1024 * 1024) throw StateError('The recording is too large. Keep it under 8 MB.');

    final request = http.MultipartRequest('POST', _endpoint('/v1/voice/transcribe'))
      ..fields['language_hint'] = 'hinglish'
      ..files.add(await http.MultipartFile.fromPath('audio', filePath, filename: 'sathi_voice.wav'));
    final streamed = await request.send().timeout(const Duration(seconds: 75));
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('Transcription service returned HTTP ${response.statusCode}.');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) throw const FormatException('Invalid transcription response.');
    final transcript = (decoded['text'] as String? ?? '').trim();
    if (transcript.isEmpty) throw StateError('No speech was recognised. Try speaking closer to the microphone.');
    return transcript;
  }
}

class SathiLocalIntentResult {
  const SathiLocalIntentResult({
    required this.answer,
    required this.intent,
    required this.actionIndex,
    required this.actionLabel,
  });

  final String answer;
  final String intent;
  final int actionIndex;
  final String actionLabel;
}

/// This is a deterministic multilingual fallback, not an LLM. It understands
/// common romanised Hinglish and Devanagari phrases for the demo journey.
class SathiLocalAgent {
  SathiLocalAgent._();

  static bool _hasAny(String input, List<String> terms) => terms.any(input.contains);

  static String _normalise(String input) => input
      .toLowerCase()
      .replaceAll(RegExp(r'[\.,!?;:(){}\[\]<>/"“”‘’]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static String detectIntent(String raw) {
    final text = _normalise(raw);
    if (_hasAny(text, [
      'status', 'track', 'tracking', 'where is my claim', 'claim kaha', 'claim kahan',
      'kaha tak', 'kahan tak', 'update kya', 'claim update', 'कहाँ तक', 'कहां तक',
      'स्थिति', 'स्टेटस', 'अपडेट', 'मेरा क्लेम कहाँ', 'मेरा क्लेम कहां',
    ])) return 'claim_status';

    if (_hasAny(text, [
      'documents', 'document', 'docs', 'bill', 'paper', 'papers', 'photo', 'upload',
      'kaun se kagaz', 'kaunse kagaz', 'kaun se document', 'kya chahiye', 'missing document',
      'कौन से कागज', 'कौनसे कागज', 'कागज़', 'कागज', 'दस्तावेज', 'डॉक्यूमेंट', 'बिल', 'फोटो', 'अपलोड',
      'discharge summary', 'itemised', 'itemized',
    ])) return 'required_documents';

    if (_hasAny(text, [
      'draft', 'appeal', 'reconsider', 're-consider', 'dobara review', 'review letter',
      'phir se review', 'reply likh', 'letter bana', 'appeal kaise', 'शिकायत पत्र',
      'अपील', 'दोबारा रिव्यू', 'ड्राफ्ट', 'जवाब लिख',
    ])) return 'prepare_reconsideration';

    if (_hasAny(text, [
      'reject', 'rejected', 'rejection', 'deny', 'denied', 'partly', 'partial', 'short pay',
      'kam paisa', 'kam mila', 'paisa kam', 'kyu reject', 'kyon reject', 'kyun reject',
      'claim kyun', 'claim kyu', 'why was', 'why did', 'reason', 'not approved',
      'रिजेक्ट', 'अस्वीकृत', 'कम मिला', 'पैसे कम', 'पूरा पैसा', 'क्यों रिजेक्ट', 'क्यों अस्वीकृत',
      'claim nahi mila', 'claim nahi hua',
    ])) return 'explain_rejection';

    return 'general_help';
  }

  static SathiLocalIntentResult answer(String raw, SathiLanguageMode language) {
    final intent = detectIntent(raw);
    switch (intent) {
      case 'claim_status':
        return SathiLocalIntentResult(
          intent: intent, actionIndex: 3, actionLabel: language == SathiLanguageMode.hindi ? 'क्लेम ट्रैकर खोलें' : 'Open claim tracker',
          answer: switch (language) {
            SathiLanguageMode.hinglish => 'Demo mein claim Partially approved hai: ₹68,500 request kiye gaye the, ₹42,000 approve hue aur ₹26,500 abhi approve nahi hue. Yeh live insurer status nahi hai. Timeline dekhne ke liye tracker kholiye.',
            SathiLanguageMode.hindi => 'डेमो में क्लेम आंशिक रूप से मंजूर है: ₹68,500 मांगे गए थे, ₹42,000 मंजूर हुए और ₹26,500 अभी मंजूर नहीं हुए हैं। यह बीमा कंपनी का लाइव स्टेटस नहीं है। टाइमलाइन देखने के लिए ट्रैकर खोलें।',
            SathiLanguageMode.english => 'The demo claim is partially approved: ₹68,500 requested, ₹42,000 approved, and ₹26,500 not yet approved. This is not a live insurer status. Open the tracker to review the sample timeline.',
          },
        );
      case 'required_documents':
        return SathiLocalIntentResult(
          intent: intent, actionIndex: 2, actionLabel: language == SathiLanguageMode.hindi ? 'दस्तावेज़ खोलें' : 'Open documents',
          answer: switch (language) {
            SathiLanguageMode.hinglish => 'Sample decision letter mein do documents ka zikr hai: itemised hospital bill aur discharge summary. Sirf wahi documents attach karein jo aapke paas sach mein hain. Original letter se list verify karein.',
            SathiLanguageMode.hindi => 'डेमो निर्णय पत्र में दो दस्तावेज़ों का ज़िक्र है: अस्पताल का मदवार बिल और डिस्चार्ज समरी। केवल वही दस्तावेज़ जोड़ें जो वास्तव में आपके पास हैं। असली पत्र से सूची की पुष्टि करें।',
            SathiLanguageMode.english => 'The sample decision letter mentions two documents: an itemised hospital bill and a discharge summary. Attach only documents you actually have, and verify this list against the real decision letter.',
          },
        );
      case 'prepare_reconsideration':
        return SathiLocalIntentResult(
          intent: intent, actionIndex: 4, actionLabel: language == SathiLanguageMode.hindi ? 'ड्राफ्ट देखें' : 'Review draft',
          answer: switch (language) {
            SathiLanguageMode.hinglish => 'Main ek editable reconsideration draft banane mein help kar sakta hoon. Pehle decision letter aur supporting documents match karein, phir har fact verify karke draft review karein. Sathi khud claim submit nahi karta.',
            SathiLanguageMode.hindi => 'मैं समीक्षा के लिए एक संपादन योग्य अनुरोध तैयार करने में मदद कर सकता हूँ। पहले निर्णय पत्र और सहायक दस्तावेज़ मिलाएँ, फिर सभी तथ्यों की जाँच करें। Sathi स्वयं क्लेम जमा नहीं करता।',
            SathiLanguageMode.english => 'I can help prepare an editable reconsideration request. First compare the decision letter with your supporting documents, verify every fact, and review the draft. Sathi does not submit claims.',
          },
        );
      case 'explain_rejection':
        return SathiLocalIntentResult(
          intent: intent, actionIndex: 1, actionLabel: language == SathiLanguageMode.hindi ? 'क्लेम की समीक्षा करें' : 'Review my claim',
          answer: switch (language) {
            SathiLanguageMode.hinglish => 'Aapke sample letter ke mutabik itemised hospital bill aur discharge summary submit nahi hue the. Is wajah se kuch amount approve nahi hua ho sakta hai, lekin exact reason aur coverage insurer hi confirm kar sakta hai. Chaliye pehle letter aur documents check karte hain.',
            SathiLanguageMode.hindi => 'डेमो पत्र के अनुसार अस्पताल का मदवार बिल और डिस्चार्ज समरी जमा नहीं हुए थे। इससे कुछ राशि मंजूर न हुई हो सकती है, लेकिन सही कारण और कवरेज की पुष्टि बीमा कंपनी ही कर सकती है। पहले पत्र और दस्तावेज़ जाँचें।',
            SathiLanguageMode.english => 'The sample letter says the itemised hospital bill and discharge summary were not submitted. That may be relevant to the amount not approved, but only the insurer can confirm the exact reason and coverage. Start by checking the letter and documents.',
          },
        );
      default:
        return SathiLocalIntentResult(
          intent: intent, actionIndex: 1, actionLabel: language == SathiLanguageMode.hindi ? 'क्लेम की समीक्षा करें' : 'Review my claim',
          answer: switch (language) {
            SathiLanguageMode.hinglish => 'Koi baat nahi. Aap Hinglish mein pooch sakte hain—jaise “claim reject kyun hua?”, “kaun se documents chahiye?” ya “mera claim status kya hai?”. Main aapko demo claim ke hisaab se agla step dikhaunga.',
            SathiLanguageMode.hindi => 'कोई बात नहीं। आप पूछ सकते हैं—“क्लेम क्यों अस्वीकृत हुआ?”, “कौन से दस्तावेज़ चाहिए?” या “मेरे क्लेम का स्टेटस क्या है?” मैं डेमो के अनुसार अगला कदम दिखाऊँगा।',
            SathiLanguageMode.english => 'Ask me “Why was my claim rejected?”, “Which documents are needed?”, or “What is my claim status?”. I’ll suggest the next step using the sample claim.',
          },
        );
    }
  }
}
