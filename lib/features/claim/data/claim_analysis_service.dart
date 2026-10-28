import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/models/claim_models.dart';

abstract interface class ClaimAnalysisService {
  Future<ClaimAnalysis> analyze({
    required String claimId,
    required String insurerReason,
    required List<String> uploadedDocuments,
    required List<String> requiredDocuments,
    required List<Map<String, String>> documentTexts,
  });
}

/// Live Gemini-backed analysis through the Sathi API. There is intentionally no
/// silent canned-answer fallback: if backend/model access is unavailable, the UI
/// receives an actionable error instead of a fabricated analysis.
class ApiClaimAnalysisService implements ClaimAnalysisService {
  ApiClaimAnalysisService({
    required this.baseUrl,
    http.Client? client,
    this.tokenProvider,
  }) : _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;
  final Future<String?> Function()? tokenProvider;
  static const _allowUnauthenticatedDev = bool.fromEnvironment(
    'SATHI_ALLOW_UNAUTHENTICATED_DEV',
    defaultValue: false,
  );

  @override
  Future<ClaimAnalysis> analyze({
    required String claimId,
    required String insurerReason,
    required List<String> uploadedDocuments,
    required List<String> requiredDocuments,
    required List<Map<String, String>> documentTexts,
  }) async {
    if (baseUrl.trim().isEmpty) {
      throw StateError('Live claim analysis is not connected. Configure SATHI_API_BASE_URL and start the backend.');
    }

    final headers = <String, String>{'content-type': 'application/json'};
    if (tokenProvider != null) {
      final token = await tokenProvider!.call();
      if (token == null || token.isEmpty) {
        throw StateError('You need to sign in before using cloud claim analysis.');
      }
      headers['authorization'] = 'Bearer $token';
    } else if (!_allowUnauthenticatedDev) {
      throw StateError(
        'No authenticated session is configured. For local synthetic-data development only, run with --dart-define=SATHI_ALLOW_UNAUTHENTICATED_DEV=true. Do not use that setting in a public deployment or with real customer data.',
      );
    }

    final base = Uri.parse(baseUrl.endsWith('/') ? baseUrl : '$baseUrl/');
    final uri = base.resolve('v1/claims/analyze');
    final response = await _client
        .post(
      uri,
      headers: headers,
      body: jsonEncode({
        'cloudConsent': true,
        // The current prototype deliberately does not send the seeded claim ID
        // or the hard-coded demo reason. Only user-read OCR text and actual
        // attached filenames are included.
        'insurerReason': insurerReason,
        'uploadedDocuments': uploadedDocuments,
        'requiredDocuments': requiredDocuments,
        'documentTexts': documentTexts,
      }),
    )
        .timeout(const Duration(seconds: 45));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      String detail = 'Live claim analysis failed (HTTP ${response.statusCode}).';
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic> && decoded['detail'] is String) {
          detail = decoded['detail'] as String;
        }
      } catch (_) {}
      throw StateError(detail);
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic> || decoded['mode'] != 'gemini_agent') {
      throw const FormatException('Backend did not confirm a live AI analysis.');
    }
    return ClaimAnalysis.fromJson(decoded);
  }
}
