import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/security/pii_masker.dart';
import '../../../../core/security/privacy_settings_store.dart';
import '../../data/claim_analysis_service.dart';
import '../../domain/models/claim_models.dart';

/// Always uses the backend for AI analysis. Missing configuration is reported to
/// the user; the app does not silently substitute a demo answer.
ClaimAnalysisService createClaimAnalysisService() {
  const baseUrl = String.fromEnvironment('SATHI_API_BASE_URL', defaultValue: '');
  return ApiClaimAnalysisService(baseUrl: baseUrl);
}

/// BLoC/Cubit state owner for the claim journey.
class ClaimCubit extends Cubit<ClaimState> {
  ClaimCubit(this._analysisService, {PrivacySettingsStore? privacyStore})
      : _privacyStore = privacyStore ?? PrivacySettingsStore(),
        super(ClaimState.empty());

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
        clearExtractedText: true,
      );
    }).toList();
    final title = updated.firstWhere((document) => document.id == id).title;
    emit(state.copyWith(
      documents: updated,
      timeline: [
        ClaimTimelineEvent(
          title: 'Document added',
          description: '$title attached on this device. It has not been sent to the insurer.',
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

  /// Stores only PII-masked OCR text in in-memory app state. It is not sent to
  /// the backend unless the user enables cloud analysis and asks Sathi.
  void saveExtractedText(String id, String maskedText) {
    final updated = state.documents.map((document) {
      if (document.id != id) return document;
      return document.copyWith(extractedText: maskedText);
    }).toList();
    emit(state.copyWith(documents: updated, clearAnalysis: true));
  }

  Future<void> analyzeClaim() async {
    emit(state.copyWith(isAnalyzing: true, clearAnalysisError: true));
    try {
      if (_analysisService is ApiClaimAnalysisService && !(await _privacyStore.readCloudConsent())) {
        throw StateError('Cloud analysis is switched off. Open “How Sathi works” and enable the privacy preference only after reviewing the data-sharing note.');
      }
      // Never treat user interface defaults as insurer facts. Analysis is based only
      // on files the user actually attached and OCR text they explicitly read on device.
      final uploaded = state.documents
          .where((d) => d.uploaded && d.localPath != null)
          .map((d) => d.fileName ?? d.title)
          .toList();
      final documentTexts = state.documents
          .where((d) => (d.extractedText ?? '').trim().isNotEmpty)
          .map((d) => <String, String>{'title': d.title, 'text': PiiMasker.mask(d.extractedText!)})
          .toList();
      final result = await _analysisService.analyze(
        claimId: '',
        insurerReason: '',
        uploadedDocuments: uploaded,
        requiredDocuments: const [],
        documentTexts: documentTexts,
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
