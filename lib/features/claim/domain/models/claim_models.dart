class ClaimDocument {
  const ClaimDocument({
    required this.id,
    required this.title,
    required this.description,
    required this.required,
    this.uploaded = false,
    this.fileName,
    this.uploadedAt,
    this.localPath,
  });

  final String id;
  final String title;
  final String description;
  final bool required;
  final bool uploaded;
  final String? fileName;
  final DateTime? uploadedAt;
  /// Ephemeral path on this device; never sent to the backend in this prototype.
  final String? localPath;

  ClaimDocument copyWith({bool? uploaded, String? fileName, DateTime? uploadedAt, String? localPath, bool clearLocalPath = false, bool clearAttachment = false}) {
    return ClaimDocument(
      id: id,
      title: title,
      description: description,
      required: required,
      uploaded: uploaded ?? this.uploaded,
      fileName: clearAttachment ? null : (fileName ?? this.fileName),
      uploadedAt: clearAttachment ? null : (uploadedAt ?? this.uploadedAt),
      localPath: clearAttachment ? null : (clearLocalPath ? localPath : (localPath ?? this.localPath)),
    );
  }
}

class ClaimTimelineEvent {
  const ClaimTimelineEvent({
    required this.title,
    required this.description,
    required this.dateLabel,
    required this.done,
    this.isCurrent = false,
  });

  final String title;
  final String description;
  final String dateLabel;
  final bool done;
  final bool isCurrent;

  ClaimTimelineEvent copyWith({String? title, String? description, String? dateLabel, bool? done, bool? isCurrent}) {
    return ClaimTimelineEvent(
      title: title ?? this.title,
      description: description ?? this.description,
      dateLabel: dateLabel ?? this.dateLabel,
      done: done ?? this.done,
      isCurrent: isCurrent ?? this.isCurrent,
    );
  }
}

class ClaimCitation {
  const ClaimCitation({
    required this.sourceTitle,
    required this.section,
    required this.excerpt,
    this.page,
  });

  final String sourceTitle;
  final String section;
  final String excerpt;
  final int? page;

  factory ClaimCitation.fromJson(Map<String, dynamic> json) => ClaimCitation(
        sourceTitle: json['sourceTitle'] as String? ?? 'Source document',
        section: json['section'] as String? ?? 'Unspecified section',
        excerpt: json['excerpt'] as String? ?? '',
        page: json['page'] is int ? json['page'] as int : null,
      );
}

class ClaimAnalysis {
  const ClaimAnalysis({
    required this.summary,
    required this.missingDocuments,
    required this.nextSteps,
    required this.disclaimer,
    this.citations = const [],
  });

  final String summary;
  final List<String> missingDocuments;
  final List<String> nextSteps;
  final String disclaimer;
  final List<ClaimCitation> citations;

  factory ClaimAnalysis.fromJson(Map<String, dynamic> json) {
    return ClaimAnalysis(
      summary: json['summary'] as String? ?? 'No explanation was returned.',
      missingDocuments: (json['missingDocuments'] as List<dynamic>? ?? const []).map((e) => e.toString()).toList(),
      nextSteps: (json['nextSteps'] as List<dynamic>? ?? const []).map((e) => e.toString()).toList(),
      disclaimer: json['disclaimer'] as String? ?? 'Confirm the next steps with your insurer.',
      citations: (json['citations'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(ClaimCitation.fromJson)
          .toList(),
    );
  }
}

class ClaimState {
  const ClaimState({
    required this.claimId,
    required this.insurerName,
    required this.hospitalName,
    required this.claimDate,
    required this.requestedAmount,
    required this.approvedAmount,
    required this.claimStatus,
    required this.insurerReason,
    required this.documents,
    required this.timeline,
    required this.appealDraft,
    this.analysis,
    this.isAnalyzing = false,
    this.analysisError,
    this.reconsiderationMarkedSubmitted = false,
  });

  final String claimId;
  final String insurerName;
  final String hospitalName;
  final String claimDate;
  final int requestedAmount;
  final int approvedAmount;
  final String claimStatus;
  final String insurerReason;
  final List<ClaimDocument> documents;
  final List<ClaimTimelineEvent> timeline;
  final String appealDraft;
  final ClaimAnalysis? analysis;
  final bool isAnalyzing;
  final String? analysisError;
  final bool reconsiderationMarkedSubmitted;

  int get unpaidAmount => requestedAmount - approvedAmount;
  int get uploadedDocuments => documents.where((d) => d.uploaded).length;
  int get requiredDocuments => documents.where((d) => d.required).length;
  int get uploadedRequiredDocuments => documents.where((d) => d.required && d.uploaded).length;
  double get documentProgress => requiredDocuments == 0 ? 0 : uploadedRequiredDocuments / requiredDocuments;
  List<String> get missingRequiredDocuments => documents.where((d) => d.required && !d.uploaded).map((d) => d.title).toList();

  factory ClaimState.demo() {
    return const ClaimState(
      claimId: 'STH-26-10482',
      insurerName: 'Demo Health Insurance Co.',
      hospitalName: 'CityCare Multispeciality Hospital',
      claimDate: '12 Oct 2026',
      requestedAmount: 68500,
      approvedAmount: 42000,
      claimStatus: 'Partially approved',
      insurerReason: 'The decision letter says the itemised hospital bill and discharge summary were not attached to the submitted claim.',
      documents: [
        ClaimDocument(id: 'discharge', title: 'Discharge summary', description: 'Hospital summary with admission and discharge details.', required: true),
        ClaimDocument(id: 'itemised_bill', title: 'Itemised hospital bill', description: 'Bill with separate line items, charges and totals.', required: true),
        ClaimDocument(id: 'prescriptions', title: 'Doctor prescriptions', description: 'Prescriptions and treatment notes relevant to this claim.', required: true, uploaded: true, fileName: 'prescriptions_demo.pdf'),
        ClaimDocument(id: 'reports', title: 'Investigation reports', description: 'Relevant lab, imaging or diagnostic reports.', required: false),
        ClaimDocument(id: 'policy', title: 'Policy schedule / e-card', description: 'Policy number, coverage details and insured person.', required: true, uploaded: true, fileName: 'policy_demo.pdf'),
        ClaimDocument(id: 'decision', title: 'Claim decision letter', description: 'Insurer document showing approved amount and reason.', required: true, uploaded: true, fileName: 'claim_decision_demo.pdf'),
      ],
      timeline: [
        ClaimTimelineEvent(title: 'Claim submitted', description: 'Claim received by insurer.', dateLabel: '12 Oct 2026', done: true),
        ClaimTimelineEvent(title: 'Documents reviewed', description: 'Insurer reviewed submitted documents.', dateLabel: '15 Oct 2026', done: true),
        ClaimTimelineEvent(title: 'Partial approval', description: '₹42,000 approved out of ₹68,500 requested.', dateLabel: '18 Oct 2026', done: true),
        ClaimTimelineEvent(title: 'Prepare reconsideration', description: 'Add missing evidence and review the draft.', dateLabel: 'Next step', done: false, isCurrent: true),
        ClaimTimelineEvent(title: 'Insurer response', description: 'Waiting for insurer after you submit through its official channel.', dateLabel: 'Pending', done: false),
      ],
      appealDraft: '',
    );
  }

  ClaimState copyWith({
    List<ClaimDocument>? documents,
    List<ClaimTimelineEvent>? timeline,
    String? appealDraft,
    ClaimAnalysis? analysis,
    bool? isAnalyzing,
    String? analysisError,
    bool clearAnalysisError = false,
    bool clearAnalysis = false,
    bool? reconsiderationMarkedSubmitted,
  }) {
    return ClaimState(
      claimId: claimId,
      insurerName: insurerName,
      hospitalName: hospitalName,
      claimDate: claimDate,
      requestedAmount: requestedAmount,
      approvedAmount: approvedAmount,
      claimStatus: claimStatus,
      insurerReason: insurerReason,
      documents: documents ?? this.documents,
      timeline: timeline ?? this.timeline,
      appealDraft: appealDraft ?? this.appealDraft,
      analysis: clearAnalysis ? null : (analysis ?? this.analysis),
      isAnalyzing: isAnalyzing ?? this.isAnalyzing,
      analysisError: clearAnalysisError ? null : (analysisError ?? this.analysisError),
      reconsiderationMarkedSubmitted: reconsiderationMarkedSubmitted ?? this.reconsiderationMarkedSubmitted,
    );
  }
}
