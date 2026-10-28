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
    this.draft = '',
    this.evidenceUsed = const [],
  });

  final String answer;
  final String intent;
  final int actionIndex;
  final String actionLabel;
  /// Only `gemini_agent` is accepted as a successful response.
  final String mode;
  final String model;
  final String notice;
  final String draft;
  final List<String> evidenceUsed;

  factory SathiAgentReply.fromJson(Map<String, dynamic> json) => SathiAgentReply(
    answer: json['answer'] as String? ?? 'I could not prepare an answer. Please try again.',
    intent: json['intent'] as String? ?? 'general_help',
    actionIndex: json['actionIndex'] is int ? json['actionIndex'] as int : 1,
    actionLabel: json['actionLabel'] as String? ?? 'Review my claim',
    mode: json['mode'] as String? ?? 'unknown',
    model: json['model'] as String? ?? '',
    notice: json['notice'] as String? ?? '',
    draft: json['draft'] as String? ?? '',
    evidenceUsed: (json['evidenceUsed'] as List<dynamic>? ?? const [])
        .map((item) => item.toString())
        .toList(),
  );
}

/// Connects the Flutter app to a Sathi backend without ever storing the model key
/// in the mobile application. A configured, consented live backend is required;
/// this service never silently substitutes static content for a model result.
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

  /// Returns only a live backend/model answer. It deliberately never returns canned
  /// local demo text when users press "Help me with this".
  Future<SathiAgentReply> ask({
    required String message,
    required SathiLanguageMode language,
    required bool allowCloudAnalysis,
    Map<String, dynamic>? claimContext,
    List<Map<String, String>> chatHistory = const [],
  }) async {
    final safeMessage = PiiMasker.mask(message.trim());
    if (safeMessage.isEmpty) throw StateError('Type or speak a question first.');
    if (!allowCloudAnalysis) {
      throw StateError('Live AI is switched off. Open “How Sathi works” and enable cloud analysis after reviewing the privacy note.');
    }
    if (!isConfigured) {
      throw StateError('Sathi live AI is not connected. Start the backend and set SATHI_API_BASE_URL when running Flutter.');
    }

    final response = await _client
        .post(
      _endpoint('/v1/agent/chat'),
      headers: const {'content-type': 'application/json'},
      body: jsonEncode({
        'message': safeMessage,
        'language': language.apiValue,
        'cloudConsent': true,
        // The app must pass only user-supplied OCR/text context here. No seeded
        // claim ID, balance, status, or fictional decision letter is injected.
        'claimContext': _safeContext(claimContext),
        'chatHistory': chatHistory.take(10).map((turn) {
          final content = PiiMasker.mask((turn['content'] ?? '').trim());
          return {
            'role': turn['role'] == 'assistant' ? 'assistant' : 'user',
            'content': content.substring(0, content.length > 1500 ? 1500 : content.length),
          };
        }).toList(),
      }),
    )
        .timeout(const Duration(seconds: 60));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      String detail = 'Live AI request failed (HTTP ${response.statusCode}).';
      try {
        final body = jsonDecode(response.body);
        if (body is Map<String, dynamic> && body['detail'] is String) {
          detail = body['detail'] as String;
        }
      } catch (_) {}
      throw StateError(detail);
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('The Sathi backend returned an invalid response.');
    }
    final reply = SathiAgentReply.fromJson(decoded);
    if (reply.mode != 'gemini_agent') {
      throw StateError('The backend did not confirm a live AI response. No answer was shown as an actual result.');
    }
    return reply;
  }

  Map<String, dynamic> _safeContext(Map<String, dynamic>? source) {
    if (source == null) return const {};
    final raw = source['documentTexts'];
    final documents = <Map<String, String>>[];
    if (raw is List) {
      for (final entry in raw.take(5)) {
        if (entry is! Map) continue;
        final title = (entry['title'] ?? 'User-provided document').toString();
        final text = PiiMasker.mask((entry['text'] ?? '').toString()).trim();
        if (text.isNotEmpty) {
          documents.add({'title': title.substring(0, title.length > 120 ? 120 : title.length), 'text': text.substring(0, text.length > 6000 ? 6000 : text.length)});
        }
      }
    }
    final namesRaw = source['attachedDocumentNames'];
    final names = namesRaw is List
        ? namesRaw.take(20).map((value) { final masked = PiiMasker.mask(value.toString()); return masked.substring(0, masked.length > 120 ? 120 : masked.length); }).toList()
        : <String>[];
    return {
      if (documents.isNotEmpty) 'documentTexts': documents,
      if (names.isNotEmpty) 'attachedDocumentNames': names,
    };
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
      ..fields['cloudConsent'] = 'true'
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
