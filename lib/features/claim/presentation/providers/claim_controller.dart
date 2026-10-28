import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/security/pii_masker.dart';
import '../../../../core/security/privacy_settings_store.dart';
import '../../data/claim_analysis_service.dart';
import '../../domain/models/claim_models.dart';

/// Selects the demo service by default. Live API mode is opt-in and requires
/// a backend that authenticates users, checks consent, and protects health data.
ClaimAnalysisService createClaimAnalysisService() {
  const useLiveApi = bool.fromEnvironment('SATHI_USE_LIVE_API', defaultValue: false);
  const baseUrl = String.fromEnvironment('SATHI_API_BASE_URL', defaultValue: '');
  if (useLiveApi) return ApiClaimAnalysisService(baseUrl: baseUrl);
  return DemoClaimAnalysisService();
}

/// BLoC/Cubit state owner for the claim journey.
class ClaimCubit extends Cubit<ClaimState> {
  ClaimCubit(this._analysisService, {PrivacySettingsStore? privacyStore})
      : _privacyStore = privacyStore ?? PrivacySettingsStore(),
        super(ClaimState.demo());

  final ClaimAnalysisService _analysisService;
  final PrivacySettingsStore _privacyStore;

  void attachDocument(String id, String fileName, {String? localPath}) {
    final now = DateTime.now();
    final updated = state.documents.map((document) {
      if (document.id != id) return document;
      return document.copyWith(
        uploaded: true,
        fileName: fileName,
        uploadedAt: now,
        localPath: localPath,
        clearLocalPath: true,
      );
    }).toList();
    final title = updated.firstWhere((document) => document.id == id).title;
    emit(state.copyWith(
      documents: updated,
      timeline: [
        ClaimTimelineEvent(
          title: 'Document added',
          description: '$title attached locally in this demo.',
          dateLabel: 'Just now',
          done: true,
        ),
        ...state.timeline.map((event) => event.copyWith(isCurrent: false)),
      ],
      clearAnalysis: true,
      clearAnalysisError: true,
    ));
  }

  void removeDocument(String id) {
    final updated = state.documents.map((document) {
      if (document.id != id) return document;
      return document.copyWith(uploaded: false, clearAttachment: true);
    }).toList();
    emit(state.copyWith(documents: updated, clearAnalysis: true));
  }

  Future<void> analyzeClaim() async {
    emit(state.copyWith(isAnalyzing: true, clearAnalysisError: true));
    try {
      if (_analysisService is ApiClaimAnalysisService && !(await _privacyStore.readCloudConsent())) {
        throw StateError('Cloud analysis is switched off. Open “How Sathi works” and enable the privacy preference only after reviewing the data-sharing note.');
      }
      final uploaded = state.documents.where((d) => d.uploaded).map((d) => d.title).toList();
      final required = state.documents.where((d) => d.required).map((d) => d.title).toList();
      // Always redact common identifiers before the optional backend call.
      // The production backend must perform its own validation and masking too.
      final redactedReason = PiiMasker.mask(state.insurerReason);
      final result = await _analysisService.analyze(
        claimId: state.claimId,
        insurerReason: redactedReason,
        uploadedDocuments: uploaded,
        requiredDocuments: required,
      );
      emit(state.copyWith(analysis: result, isAnalyzing: false));
    } catch (error) {
      final message = error is StateError
          ? error.message.toString()
          : 'Could not analyse the claim. Please retry. Details: $error';
      emit(state.copyWith(isAnalyzing: false, analysisError: message));
    }
  }

  void saveDraft(String draft) {
    emit(state.copyWith(appealDraft: draft));
  }

  void markReconsiderationSubmitted() {
    if (state.reconsiderationMarkedSubmitted) return;
    emit(state.copyWith(
      reconsiderationMarkedSubmitted: true,
      timeline: [
        const ClaimTimelineEvent(
          title: 'Reconsideration marked as submitted',
          description: 'You recorded that you submitted the draft through the insurer’s official channel. Sathi has not sent it.',
          dateLabel: 'Just now',
          done: true,
          isCurrent: true,
        ),
        ...state.timeline.map((e) => e.copyWith(isCurrent: false)),
      ],
    ));
  }
}
