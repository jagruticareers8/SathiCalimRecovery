import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/models/claim_models.dart';

abstract interface class ClaimAnalysisService {
  Future<ClaimAnalysis> analyze({
    required String claimId,
    required String insurerReason,
    required List<String> uploadedDocuments,
    required List<String> requiredDocuments,
  });
}

/// Safe local demo analysis: it uses only the seeded reason and document checklist.
/// No photos, PDFs, identity data or policy documents are sent anywhere.
class DemoClaimAnalysisService implements ClaimAnalysisService {
  @override
  Future<ClaimAnalysis> analyze({
    required String claimId,
    required String insurerReason,
    required List<String> uploadedDocuments,
    required List<String> requiredDocuments,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 700));
    final missing = requiredDocuments.where((name) => !uploadedDocuments.contains(name)).toList();
    final summary = missing.isEmpty
        ? 'The demo checklist shows all required document categories as attached. Compare each file with the insurer’s decision letter before requesting reconsideration.'
        : 'The demo decision text mentions missing evidence. Your checklist still shows ${missing.length} required document category${missing.length == 1 ? '' : 'ies'} to add: ${missing.join(', ')}. This could be relevant to the stated reason, but only the insurer can confirm what is required under your policy.';
    return ClaimAnalysis(
      summary: summary,
      missingDocuments: missing,
      nextSteps: [
        if (missing.isNotEmpty) 'Collect the listed documents from the hospital or your records.',
        'Compare the decision letter with the actual policy wording and exclusions.',
        'Edit the reconsideration draft so every statement is accurate and supported by evidence.',
        'Submit using the insurer’s official grievance or claim channel and keep the acknowledgement.',
        'If unresolved, check the applicable insurer grievance and official escalation process.',
      ],
      disclaimer: 'Prototype guidance only. This is not an insurer decision, medical advice or legal advice. Do not assume a missing document is the only reason for a short payment. Confirm requirements and deadlines with the insurer.',
    );
  }
}

/// Optional adapter for a backend you control. Do not point this directly at an LLM.
/// The backend must authenticate, validate consent, mask PII and enforce access control.
class ApiClaimAnalysisService implements ClaimAnalysisService {
  ApiClaimAnalysisService({required this.baseUrl, http.Client? client, this.tokenProvider}) : _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;
  final Future<String?> Function()? tokenProvider;

  @override
  Future<ClaimAnalysis> analyze({
    required String claimId,
    required String insurerReason,
    required List<String> uploadedDocuments,
    required List<String> requiredDocuments,
  }) async {
    if (baseUrl.trim().isEmpty) {
      throw StateError('SATHI_API_BASE_URL is missing. Set it with --dart-define or use demo mode.');
    }
    // Fail closed: live mode must supply an authenticated token provider.
    // Never send a health-claim request to an unauthenticated endpoint.
    final getToken = tokenProvider;
    if (getToken == null) {
      throw StateError('Live API mode needs an authenticated token provider. Configure your sign-in/backend integration first.');
    }
    final token = await getToken();
    if (token == null || token.isEmpty) {
      throw StateError('No active sign-in token is available. Sign in before using cloud analysis.');
    }
    final base = Uri.parse(baseUrl.endsWith('/') ? baseUrl : '$baseUrl/');
    final uri = base.resolve('v1/claims/analyze');
    final headers = <String, String>{
      'content-type': 'application/json',
      'authorization': 'Bearer $token',
    };
    final response = await _client.post(
      uri,
      headers: headers,
      body: jsonEncode({
        'claimId': claimId,
        'insurerReason': insurerReason,
        'uploadedDocuments': uploadedDocuments,
        'requiredDocuments': requiredDocuments,
      }),
    ).timeout(const Duration(seconds: 20));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Analysis service returned HTTP ${response.statusCode}.');
    }
    final body = jsonDecode(response.body);
    if (body is! Map<String, dynamic>) throw const FormatException('Invalid analysis response.');
    return ClaimAnalysis.fromJson(body);
  }
}
