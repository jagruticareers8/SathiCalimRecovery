import 'dart:async';
import 'dart:io';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/security/pii_masker.dart';
import '../../../../core/storage/local_private_vault.dart';
import '../../data/claim_analysis_service.dart';
import '../../domain/models/claim_models.dart';

/// Creates the remote claim-analysis adapter for integrations that are explicitly
/// non-private. Personal documents use the encrypted local vault only.
ClaimAnalysisService createClaimAnalysisService() {
  const baseUrl = String.fromEnvironment('SATHI_API_BASE_URL', defaultValue: '');
  return ApiClaimAnalysisService(baseUrl: baseUrl);
}

/// BLoC/Cubit owner for claim workflow state. Private claim text and drafts are
/// persisted in an encrypted app-private vault; no network call occurs here for
/// documents, OCR, or claim analysis.
class ClaimCubit extends Cubit<ClaimState> {
  ClaimCubit(ClaimAnalysisService _, {LocalPrivateVault? vault})
      : _vault = vault ?? LocalPrivateVault(),
        super(ClaimState.empty()) {
    _ready = _restoreLocalState();
  }

  final LocalPrivateVault _vault;
  late final Future<void> _ready;

  Future<void> _restoreLocalState() async {
    try {
      final saved = await _vault.readSnapshot();
      final savedRows = saved['documents'];
      final byId = <String, Map>{};
      if (savedRows is List) {
        for (final row in savedRows) {
          if (row is Map && row['id'] is String) byId[row['id'] as String] = row;
        }
      }
      final restoredDocuments = state.documents.map((document) {
        final row = byId[document.id];
        if (row == null) return document;
        final extractedText = row['extractedText'] as String?;
        final fileName = row['fileName'] as String?;
        final uploadedAtText = row['uploadedAt'] as String?;
        return document.copyWith(
          uploaded: row['uploaded'] == true,
          fileName: fileName,
          uploadedAt: uploadedAtText == null ? null : DateTime.tryParse(uploadedAtText),
          clearLocalPath: true, // Never persist a potentially temporary source path.
          extractedText: extractedText,
          clearExtractedText: extractedText == null || extractedText.isEmpty,
          storedLocally: row['storedLocally'] == true,
        );
      }).toList();

      final restoredTimeline = <ClaimTimelineEvent>[];
      final savedTimeline = saved['timeline'];
      if (savedTimeline is List) {
        for (final row in savedTimeline) {
          if (row is! Map) continue;
          restoredTimeline.add(ClaimTimelineEvent(
            title: (row['title'] ?? '').toString(),
            description: (row['description'] ?? '').toString(),
            dateLabel: (row['dateLabel'] ?? '').toString(),
            done: row['done'] == true,
            isCurrent: row['isCurrent'] == true,
          ));
        }
      }
      if (isClosed) return;
      emit(state.copyWith(
        documents: restoredDocuments,
        timeline: restoredTimeline,
        appealDraft: (saved['appealDraft'] ?? '').toString(),
        reconsiderationMarkedSubmitted: saved['reconsiderationMarkedSubmitted'] == true,
      ));
    } catch (_) {
      // Do not silently overwrite encrypted data if decryption fails. This
      // session remains usable but starts with empty in-memory state.
    }
  }

  Map<String, dynamic> _snapshotFor(ClaimState current) => {
        'version': 1,
        'documents': current.documents.map((document) => <String, dynamic>{
              'id': document.id,
              'title': document.title,
              'description': document.description,
              'required': document.required,
              'uploaded': document.uploaded,
              'fileName': document.fileName,
              'uploadedAt': document.uploadedAt?.toIso8601String(),
              'storedLocally': document.storedLocally,
              // The OCR text is PII-masked before it reaches state and this
              // entire snapshot is encrypted by LocalPrivateVault.
              'extractedText': document.extractedText,
            }).toList(),
        'timeline': current.timeline.map((event) => <String, dynamic>{
              'title': event.title,
              'description': event.description,
              'dateLabel': event.dateLabel,
              'done': event.done,
              'isCurrent': event.isCurrent,
            }).toList(),
        'appealDraft': current.appealDraft,
        'reconsiderationMarkedSubmitted': current.reconsiderationMarkedSubmitted,
      };

  Future<void> _persistLocalState() async {
    try {
      await _vault.saveSnapshot(_snapshotFor(state));
    } catch (_) {
      // Do not log private text. UI state remains available for this session;
      // callers that must persist a selected attachment receive an explicit error.
    }
  }

  Future<void> attachDocument(String id, String fileName, {String? localPath}) async {
    await _ready;
    if (localPath == null || localPath.trim().isEmpty) {
      throw StateError('Sathi could not access this file path to create its encrypted local copy. Try choosing the file again, or paste its text instead.');
    }
    // An encrypted app-private copy is required before we label the file as saved.
    await _vault.saveAttachment(id: id, sourcePath: localPath);

    final now = DateTime.now();
    final updated = state.documents.map((document) {
      if (document.id != id) return document;
      return document.copyWith(
        uploaded: true,
        fileName: fileName,
        uploadedAt: now,
        localPath: localPath,
        storedLocally: true,
        clearExtractedText: true,
      );
    }).toList();
    final title = updated.firstWhere((document) => document.id == id).title;
    emit(state.copyWith(
      documents: updated,
      timeline: [
        ClaimTimelineEvent(
          title: 'Document saved privately',
          description: '$title encrypted into Sathi local storage on this device. It has not been uploaded.',
          dateLabel: 'Just now',
          done: true,
        ),
        ...state.timeline.map((event) => event.copyWith(isCurrent: false)),
      ],
      clearAnalysis: true,
      clearAnalysisError: true,
    ));
    await _persistLocalState();
  }

  Future<void> removeDocument(String id) async {
    await _ready;
    await _vault.deleteAttachment(id);
    final updated = state.documents.map((document) {
      if (document.id != id) return document;
      return document.copyWith(uploaded: false, clearAttachment: true);
    }).toList();
    emit(state.copyWith(documents: updated, clearAnalysis: true));
    await _persistLocalState();
  }

  /// Returns a source path for on-device OCR. Persisted attachments are decrypted
  /// only into a temporary file; the calling screen must delete it in finally.
  Future<String?> pathForOnDeviceOcr(String id) async {
    await _ready;
    ClaimDocument? document;
    for (final item in state.documents) {
      if (item.id == id) { document = item; break; }
    }
    if (document == null) return null;
    final currentPath = document.localPath;
    if (currentPath != null && await File(currentPath).exists()) return currentPath;
    if (!document.storedLocally || document.fileName == null) return null;
    return _vault.materializeAttachmentForOcr(id: id, fileName: document.fileName!);
  }

  /// Save only PII-masked OCR text. The text is encrypted at rest and searchable
  /// locally even after the app is restarted.
  Future<void> saveExtractedText(String id, String maskedText) async {
    await _ready;
    final redacted = PiiMasker.mask(maskedText.trim());
    final updated = state.documents.map((document) {
      if (document.id != id) return document;
      return document.copyWith(extractedText: redacted);
    }).toList();
    emit(state.copyWith(documents: updated, clearAnalysis: true));
    // Wait for the encrypted snapshot write before telling the user it was saved.
    await _persistLocalState();
  }

  /// Claim analysis is deliberately local-only. It reports which documents have
  /// readable local text; it does not upload OCR or ask a cloud model to inspect
  /// a private claim. This is a local completeness hint, not insurer verification.
  Future<void> analyzeClaim() async {
    await _ready;
    emit(state.copyWith(isAnalyzing: true, clearAnalysisError: true));
    try {
      final readable = state.documents.where((d) => (d.extractedText ?? '').trim().isNotEmpty).toList();
      final noText = state.documents.where((d) => d.uploaded && (d.extractedText ?? '').trim().isEmpty).map((d) => d.title).toList();
      final result = ClaimAnalysis(
        summary: readable.isEmpty
            ? 'No readable document text has been saved yet. Add a decision letter or bill, then choose “Read text on device”. No claim data was sent online.'
            : 'Sathi found readable text in ${readable.length} locally saved document(s). This is a local document-readiness check only; it does not verify coverage, claim status, or the insurer’s decision.',
        missingDocuments: noText,
        nextSteps: readable.isEmpty
            ? const ['Attach the decision letter.', 'Run Read text on device or paste a relevant excerpt.', 'Ask Sathi in Private files mode.']
            : const ['Search the saved document text for the insurer’s reason.', 'Compare the stated reason with the supporting records.', 'Confirm exact requirements with the insurer through its official channel.'],
        disclaimer: 'OFFLINE LOCAL CHECK · No OCR text or claim details were sent to a server. This is not a coverage decision or a guarantee of claim recovery.',
        evidenceUsed: readable.map((document) => document.title).toList(),
      );
      emit(state.copyWith(analysis: result, isAnalyzing: false));
    } catch (error) {
      emit(state.copyWith(isAnalyzing: false, analysisError: 'Local document check failed. No document data was sent online. ${error.runtimeType}'));
    }
  }


  /// Erases the encrypted local vault and resets all app-owned personal data.
  /// This does not delete the original files in Photos/Downloads.
  Future<void> clearAllLocalData() async {
    await _ready;
    await _vault.clearAll();
    if (isClosed) return;
    emit(ClaimState.empty());
  }

  void saveDraft(String draft) {
    emit(state.copyWith(appealDraft: draft));
    unawaited(_persistLocalState());
  }

  void markReconsiderationSubmitted() {
    if (state.reconsiderationMarkedSubmitted) return;
    emit(state.copyWith(
      reconsiderationMarkedSubmitted: true,
      timeline: [
        const ClaimTimelineEvent(
          title: 'Reconsideration marked by you',
          description: 'You recorded that you submitted the draft through the insurer’s official channel. Sathi has not sent it or verified receipt.',
          dateLabel: 'Just now',
          done: true,
          isCurrent: true,
        ),
        ...state.timeline.map((e) => e.copyWith(isCurrent: false)),
      ],
    ));
    unawaited(_persistLocalState());
  }
}
