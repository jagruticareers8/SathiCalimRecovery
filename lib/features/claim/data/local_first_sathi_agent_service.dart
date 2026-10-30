import '../../../core/security/pii_masker.dart';
import '../../../core/storage/local_private_vault.dart';
import 'on_device_rag_service.dart';
import 'sathi_agent_service.dart';

enum SathiQueryMode {
  /// Private claim questions and attached documents stay on this device.
  privateLocal,

  /// Local content is checked first; only a safe, non-personal general question
  /// may be sent to Gemini, and no file text or chat history is sent with it.
  generalInformation,
}

class LocalFirstSathiAgentService {
  LocalFirstSathiAgentService({
    required SathiAgentService cloudService,
    LocalPrivateVault? vault,
  })  : _cloudService = cloudService,
        _vault = vault ?? LocalPrivateVault() {
    _localRag = SathiOnDeviceRagService(vault: _vault);
  }

  final SathiAgentService _cloudService;
  final LocalPrivateVault _vault;
  late final SathiOnDeviceRagService _localRag;

  bool get isConfigured => _cloudService.isConfigured;

  Future<String> transcribeHinglishAudio(
    String filePath, {
    required bool allowCloudVoice,
    required bool allowCloudGeneralInformation,
    required bool confirmedForGeneralUse,
  }) => _cloudService.transcribeHinglishAudio(
        filePath,
        allowCloudVoice: allowCloudVoice,
        allowCloudGeneralInformation: allowCloudGeneralInformation,
        confirmedForGeneralUse: confirmedForGeneralUse,
      );

  Future<SathiAgentReply> ask({
    required String message,
    required SathiLanguageMode language,
    required bool allowCloudAnalysis,
    required SathiQueryMode queryMode,
    Map<String, dynamic>? claimContext,
    List<Map<String, String>> chatHistory = const [],
    Future<bool> Function(String question)? confirmCloudFallback,
  }) async {
    final question = message.trim();
    if (question.isEmpty) throw StateError('Type or speak a question first.');

    // 1. Search the encrypted local vault and current in-memory OCR first.
    final localSnapshot = await _vault.readSnapshot();
    final documents = _collectDocuments(localSnapshot, claimContext);

    // Required-document questions must take priority over amount extraction.
    // Phrases such as "Which papers should I upload now?" can otherwise be
    // misclassified by a broad matcher or by a model answer. Prefer evidence
    // from the saved decision letter and never let a claim-amount answer win.
    final localFactKind = _localFactKind(question);
    final asksRequiredDocuments = _asksForRequiredDocuments(question);
    if (asksRequiredDocuments && documents.isNotEmpty) {
      final documentReply = _answerLocalLabeledFact(
        question,
        documents,
        language,
        'required_documents',
      );
      if (documentReply != null) return documentReply;
      // For a known personal document question, abstain rather than letting
      // the LLM produce an unrelated claim-amount answer.
      return _localFactNotFound('required_documents', language);
    }

    // Resolve common document-question intents locally first. These include
    // amounts, status, reason, required documents, deadlines, identifiers,
    // insurer/hospital, dates, coverage clauses, summary and draft requests.
    // This path never calls the cloud service.
    final factReply = _answerLocalDocumentFact(question, documents, language);
    // Exact extracted facts are more reliable than generation. If the fact
    // extractor cannot find a value, keep its abstention but let local RAG try
    // to interpret differently formatted OCR before giving up.
    final factNotFound = factReply?.mode == 'local_document_fact_not_found';
    if (factReply != null && !factNotFound) return factReply;

    // 2. If the user has installed the optional on-device LLM + embedder,
    // run semantic RAG on all relevant saved documents and the local guide.
    // Both embeddings and generation run in-process; no HTTP is used here.
    SathiOnDeviceRagAnswer? ragAnswer;
    try {
      ragAnswer = await _localRag.answer(
        question: question,
        language: language,
        documents: documents.map((doc) => SathiRagSource(title: doc.title, text: doc.text)).toList(),
        chatHistory: chatHistory,
      );
    } on SathiOnDeviceRagException {
      final localError = switch (language) {
        SathiLanguageMode.hinglish => 'Aapka sawaal aur documents device se bahar nahi gaye. On-device AI model answer generate nahi kar paya. How Sathi works mein model status check karein, ya offline models ko dobara install karke try karein.',
        SathiLanguageMode.hindi => 'आपका सवाल और दस्तावेज़ डिवाइस से बाहर नहीं गए। ऑन-डिवाइस AI उत्तर नहीं बना पाया। How Sathi works में मॉडल स्थिति देखें या ऑफलाइन मॉडल दोबारा इंस्टॉल करके कोशिश करें।',
        SathiLanguageMode.english => 'Your question and documents stayed on this device. The on-device AI could not generate an answer. Check model status in How Sathi works, or reinstall the offline models and try again.',
      };
      return SathiAgentReply(
        answer: localError,
        intent: _intent(question),
        actionIndex: 1,
        actionLabel: language == SathiLanguageMode.hindi ? 'मॉडल स्थिति देखें' : 'Check model status',
        mode: 'on_device_rag_error',
        model: 'On-device model error',
        notice: 'LOCAL AI ERROR · No question, document text or embeddings were sent online.',
      );
    }
    if (ragAnswer != null) {
      final intent = _intent(question);
      final wantsDraft = intent == 'prepare_reconsideration';
      return SathiAgentReply(
        answer: wantsDraft
            ? (language == SathiLanguageMode.hinglish
                ? 'Maine aapke phone par saved evidence se ek editable reconsideration draft banaya hai. Bhejne se pehle facts verify karein. Kuch bhi insurer ko submit nahi hua hai.\n\n${ragAnswer.answer}'
                : language == SathiLanguageMode.hindi
                    ? 'आपके फोन पर सेव साक्ष्य के आधार पर संपादन योग्य पुनर्विचार ड्राफ्ट बनाया है। भेजने से पहले तथ्य जाँचें। कुछ भी बीमा कंपनी को जमा नहीं किया गया है।\n\n${ragAnswer.answer}'
                    : 'I prepared an editable reconsideration draft from evidence saved on this device. Verify all facts before sending; nothing has been submitted to the insurer.\n\n${ragAnswer.answer}')
            : ragAnswer.answer,
        intent: intent,
        actionIndex: wantsDraft ? 4 : (intent == 'required_documents' || intent == 'document_review' ? 2 : 1),
        actionLabel: wantsDraft
            ? (language == SathiLanguageMode.hindi ? 'ड्राफ्ट देखें' : 'Review draft')
            : (intent == 'required_documents' || intent == 'document_review' ? 'Open documents' : 'Review answer'),
        mode: 'on_device_rag',
        model: ragAnswer.model,
        notice: 'ON-DEVICE RAG · Query, document excerpts and answer stayed on this device.',
        draft: wantsDraft ? _ensureRequestForReview(ragAnswer.answer) : '',
        evidenceUsed: ragAnswer.evidenceUsed,
      );
    }

    if (factReply != null) return factReply;
    // Do not show unrelated snippets for a recognised field question (for
    // example a diagnosis line as an answer to a coverage question). Tell the
    // user that the requested field was not found in OCR instead.
    if (documents.isNotEmpty && localFactKind != null) {
      return _localFactNotFound(localFactKind, language);
    }

    final excerpts = _findRelevantExcerpts(question, documents);
    if (excerpts.isNotEmpty) {
      final intent = _intent(question);
      final reply = _documentAnswer(question, excerpts, language, intent);
      return reply;
    }

    // 2. A small, fixed FAQ works offline and does not need private files.
    final faq = _offlineFaq(question, language);
    if (faq != null) return faq;

    // 3. Never send a personal/sensitive question or private conversation to the
    // cloud. A user's selection of General Information is not permission to send
    // their claim context. Unknown personal questions remain local-only.
    final sensitive = _looksPersonalOrSensitive(question);
    if (queryMode == SathiQueryMode.privateLocal || sensitive) {
      return _localOnlyNotFound(language, sensitive: sensitive);
    }

    // 4. Online is only a general-knowledge fallback, after explicit consent.
    if (!allowCloudAnalysis) {
      return SathiAgentReply(
        answer: switch (language) {
          SathiLanguageMode.hinglish => 'Is general sawal ka jawab mujhe offline saved guide mein nahi mila. Aap “How Sathi works” mein online general-information lookup enable kar sakte hain. Aapke documents aur claim details kabhi is request ke saath nahi bheje jayenge.',
          SathiLanguageMode.hindi => 'इस सामान्य सवाल का जवाब स्थानीय गाइड में नहीं मिला। चाहें तो “How Sathi works” में ऑनलाइन सामान्य जानकारी चालू करें। आपके दस्तावेज़ और क्लेम विवरण इस अनुरोध के साथ नहीं भेजे जाएंगे।',
          SathiLanguageMode.english => 'I could not find this general answer in the offline guide. You can enable online general-information lookup in “How Sathi works”. Your documents and claim details will not be sent with that request.',
        },
        intent: 'general_help',
        actionIndex: 1,
        actionLabel: language == SathiLanguageMode.hindi ? 'वापस जाएँ' : 'Back to Sathi',
        mode: 'local_no_match',
        notice: 'LOCAL ONLY · No question or document was sent online.',
      );
    }

    // Ask for confirmation at the point of use, after local document/FAQ
    // lookup has failed. This lets the user inspect the exact question before
    // any online request is made.
    final confirmed = await confirmCloudFallback?.call(question) ?? false;
    if (!confirmed) {
      return SathiAgentReply(
        answer: switch (language) {
          SathiLanguageMode.hinglish => 'Theek hai—maine online request nahi bheji. Aap Private mode mein local documents search kar sakte hain, ya general sawal ko edit karke dobara try kar sakte hain.',
          SathiLanguageMode.hindi => 'ठीक है—मैंने ऑनलाइन अनुरोध नहीं भेजा। आप निजी मोड में स्थानीय दस्तावेज़ खोज सकते हैं या सामान्य सवाल को बदलकर फिर कोशिश कर सकते हैं।',
          SathiLanguageMode.english => 'Okay—I did not send an online request. You can search local documents in Private mode or edit your question and try again.',
        },
        intent: 'general_help',
        actionIndex: 1,
        actionLabel: language == SathiLanguageMode.hindi ? 'वापस जाएँ' : 'Back to Sathi',
        mode: 'local_no_match',
        notice: 'ONLINE LOOKUP CANCELLED · No question or document was sent online.',
      );
    }

    // Defence in depth: only the confirmed current general question is passed
    // to the cloud adapter. No local documents, claim context, or chat history.
    return _cloudService.ask(
      message: question,
      language: language,
      allowCloudAnalysis: true,
      claimContext: null,
      chatHistory: const [],
    );
  }

  List<_LocalDocument> _collectDocuments(
    Map<String, dynamic> snapshot,
    Map<String, dynamic>? currentContext,
  ) {
    final docs = <_LocalDocument>[];
    final seen = <String>{};

    void add(String title, String text) {
      final cleaned = text.trim();
      if (cleaned.isEmpty) return;
      final key = '${title.toLowerCase()}|${cleaned.hashCode}';
      if (seen.add(key)) docs.add(_LocalDocument(title: title, text: cleaned));
    }

    final saved = snapshot['documents'];
    if (saved is List) {
      for (final row in saved) {
        if (row is Map) {
          add((row['title'] ?? 'Saved document').toString(), (row['extractedText'] ?? '').toString());
        }
      }
    }
    final current = currentContext?['documentTexts'];
    if (current is List) {
      for (final row in current) {
        if (row is Map) {
          add((row['title'] ?? 'Attached document').toString(), (row['text'] ?? '').toString());
        }
      }
    }
    return docs;
  }

  /// Handles labelled factual fields (claim amount, approved amount, and amount
  /// pending) directly from local OCR text. It deliberately does not call Gemini.
  SathiAgentReply? _answerLocalDocumentFact(
    String question,
    List<_LocalDocument> docs,
    SathiLanguageMode language,
  ) {
    if (docs.isEmpty) return null;

    final allText = docs.map((doc) => '${doc.title}\n${doc.text}').join('\n\n');
    // Keep this guard here as well as in ask(), so future callers cannot
    // accidentally route a document checklist question through amount QA.
    if (_asksForRequiredDocuments(question)) {
      return _answerLocalLabeledFact(question, docs, language, 'required_documents');
    }
    final kind = _amountQuestionType(question);
    if (kind == null) {
      final factKind = _localFactKind(question);
      if (factKind == null) return null;
      return _answerLocalLabeledFact(question, docs, language, factKind);
    }

    final amount = _extractLabeledAmount(allText, kind);
    if (amount == null) {
      final message = switch (language) {
        SathiLanguageMode.hinglish => 'Aapke document mein ${_amountLabel(kind, language)} ki exact rakam saaf nahi mil paayi. Main andaza nahi lagaunga/lagaungi. Kripya amount wali line dikhne wala saaf document dobara add karein.',
        SathiLanguageMode.hindi => 'आपके दस्तावेज़ में ${_amountLabel(kind, language)} की सही राशि साफ़ नहीं मिल पाई। मैं अनुमान नहीं लगाऊँगा/लगाऊँगी। कृपया राशि वाली पंक्ति साफ़ दिखने वाला दस्तावेज़ दोबारा जोड़ें।',
        SathiLanguageMode.english => 'I could not clearly find the exact ${_amountLabel(kind, language)} in your document. I will not guess. Please add a clearer copy showing the amount line.',
      };
      return SathiAgentReply(
        answer: message,
        intent: '${kind}_amount',
        actionIndex: 2,
        actionLabel: language == SathiLanguageMode.hindi ? 'दस्तावेज़ खोलें' : 'Open documents',
        mode: 'local_document_fact_not_found',
        notice: 'ON DEVICE · Amount was not readable in the saved document. No cloud request was made.',
      );
    }

    final claimed = kind == 'claimed' ? amount : _extractLabeledAmount(allText, 'claimed');
    final approved = kind == 'approved' ? amount : _extractLabeledAmount(allText, 'approved');
    final pending = kind == 'pending' ? amount : _extractLabeledAmount(allText, 'pending');

    final additionalFacts = <String>[];
    // For claim breakdown questions, show the other known amounts too. For a
    // policy premium/deductible/limit question, don't mix unrelated claim totals
    // into the answer.
    if (const ['claimed', 'approved', 'pending'].contains(kind)) {
      if (kind != 'claimed' && claimed != null) {
        additionalFacts.add('${_amountLabel('claimed', language)} ${_formatLocalMoney(claimed)}');
      }
      if (kind != 'approved' && approved != null) {
        additionalFacts.add('${_amountLabel('approved', language)} ${_formatLocalMoney(approved)}');
      }
      if (kind != 'pending' && pending != null) {
        additionalFacts.add('${_amountLabel('pending', language)} ${_formatLocalMoney(pending)}');
      }
    }

    final mainAmount = _formatLocalMoney(amount);
    final related = additionalFacts.isEmpty ? '' : '\n${additionalFacts.join('\n')}';
    final answer = switch (language) {
      SathiLanguageMode.hinglish => (switch (kind) {
          'claimed' => 'Aapke phone par saved document ke mutabik, claim ki amount $mainAmount thi.$related',
          'approved' => 'Aapke phone par saved document ke mutabik, approved amount $mainAmount hai.$related',
          'pending' => 'Aapke phone par saved document ke mutabik, review ke liye pending amount $mainAmount hai.$related',
          'deducted' => 'Saved document ke mutabik, deducted/disallowed amount $mainAmount hai.',
          'sum_insured' => 'Saved policy text ke mutabik, sum insured/cover limit $mainAmount hai.',
          'premium' => 'Saved policy text ke mutabik, premium amount $mainAmount hai.',
          'copay' => 'Saved document mein co-pay amount $mainAmount diya gaya hai. Co-pay percentage/conditions alag se verify karein.',
          'deductible' => 'Saved document mein deductible amount $mainAmount diya gaya hai. Exact application policy wording se verify karein.',
          'bill_total' => 'Saved document ke mutabik, total bill amount $mainAmount hai.',
          'paid' => 'Saved document ke mutabik, paid/settled amount $mainAmount hai.',
          _ => 'Aapke phone par saved document ke mutabik, review ke liye pending amount $mainAmount hai.$related',
        }) + '\n\nYeh jawab sirf saved document se locally nikala gaya hai; live insurer record verify nahi hua.',
      SathiLanguageMode.hindi => '${_amountLabel(kind, language)} $mainAmount.$related\n\nयह जवाब केवल स्थानीय OCR टेक्स्ट पर आधारित है; बीमा कंपनी का लाइव रिकॉर्ड सत्यापित नहीं हुआ है।',
      SathiLanguageMode.english => '${_amountLabel(kind, language)} $mainAmount.$related\n\nThis answer was extracted from locally saved document; no live insurer record was checked.',
    };

    final facts = <String>['${_amountLabel(kind, language)} $mainAmount'];
    facts.addAll(additionalFacts);
    return SathiAgentReply(
      answer: answer,
      intent: '${kind}_amount',
      actionIndex: 1,
      actionLabel: language == SathiLanguageMode.hindi ? 'क्लेम देखें' : 'Review claim',
      mode: 'local_document_fact',
      notice: 'ON DEVICE · Amounts extracted from saved document. No question or document was sent online.',
      evidenceUsed: facts,
    );
  }

  String? _amountQuestionType(String question) {
    final q = question.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

    // Time/deadline questions can contain words such as "claim" and "kitne";
    // don't misclassify "claim kitne din mein aayega" as a money question.
    final asksTime = _hasAny(q, const [
      'how many days', 'how long', 'within how many days', 'deadline', 'last date',
      'kab tak', 'kitne din', 'kitni der', 'when will', 'date of', 'date:',
      'कितने दिन', 'कब तक', 'अंतिम तारीख', 'समय-सीमा',
    ]);
    final directMoneyWording = _hasAny(q, const [
      'how much', 'kitne ka', 'kitna ka', 'kitna tha', 'kitni thi',
      'kitna amount', 'kitni amount', 'kitne rupees', 'kitne rupay', 'rupees',
      'rs ', 'inr', '₹', 'deducted amount', 'deduction amount', 'kitna deduct', 'deduction', 'deducted',
      'kitni cut', 'how much did they cut', 'amount cut', 'amount reduced', 'shortfall', 'disallowed amount', 'how much paid', 'paid by insurer', 'total bill', 'bill amount', 'sum insured', 'sum assured',
      'co-pay', 'copay', 'deductible', 'premium amount', 'राशि', 'कितने का',
      'कितना था', 'कितनी राशि', 'क्लेम कितना', 'क्लेम की राशि', 'दावा की गई राशि',
    ]);
    if (asksTime && !directMoneyWording) return null;
    final explicitMoney = directMoneyWording || _hasAny(q, const ['amount', 'amount kitna', 'claim ki amount']);

    final asksAmount = explicitMoney ||
        (_hasAny(q, const ['kitna', 'kitne', 'kitni', 'कितना', 'कितने', 'कितनी']) &&
            _hasAny(q, const ['claim', 'approved', 'pending', 'mila', 'rashi', 'राशि', 'क्लेम', 'स्वीकृत', 'मंजूर', 'deduct', 'bill']));
    if (!asksAmount) return null;

    if (_hasAny(q, const ['deducted', 'deduction', 'deduct', 'cut hua', 'cut kiya', 'cut', 'reduced', 'shortfall', 'disallowed', 'not paid', 'less amount', 'कम काट', 'काटे'])) return 'deducted';
    if (_hasAny(q, const ['sum insured', 'sum assured', 'policy limit', 'coverage limit', 'total cover', 'बीमा राशि'])) return 'sum_insured';
    if (_hasAny(q, const ['premium', 'policy ka charge', 'premium kitna', 'प्रीमियम'])) return 'premium';
    if (_hasAny(q, const ['co-pay', 'copay', 'co pay', 'copayment'])) return 'copay';
    if (_hasAny(q, const ['deductible'])) return 'deductible';
    if (_hasAny(q, const ['total bill', 'hospital bill', 'bill amount', 'total charges', 'invoice amount', 'कुल बिल'])) return 'bill_total';
    if (_hasAny(q, const ['paid amount', 'amount paid', 'kitna pay hua', 'kitna payment hua', 'paid by insurer', 'how much paid', 'how much did insurer pay', 'insurer paid', 'payment received'])) return 'paid';
    if (_hasAny(q, const [
      'approved', 'approve hua', 'approve amount', 'settled', 'sanctioned',
      'kitna mila', 'kitni amount mili', 'मंजूर', 'स्वीकृत', 'मिला', 'पास हुआ',
    ])) return 'approved';
    if (_hasAny(q, const [
      'pending', 'remaining', 'balance', 'baaki', 'baki', 'bachi hui',
      'kitna pending', 'बाकी', 'लंबित', 'शेष राशि', 'रुका हुआ',
    ])) return 'pending';
    return 'claimed';
  }

  String? _extractLabeledAmount(String source, String kind) {
    final text = source
        .replaceAll(RegExp(r'[\r\n\t]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final amount = r'(?:(?:\(?\s*(?:rs\.?|inr|₹)\s*\)?\s*)?)([0-9][0-9,]*(?:\.\d{1,2})?)';
    final patterns = switch (kind) {
      'claimed' => <RegExp>[
          RegExp(r'\b(?:amount\s+claimed|claimed\s+amount|requested\s+amount|amount\s+requested|claim\s+amount|total\s+claim\s+amount|total\s+amount\s+claimed)\b\s*[:=\-]?\s*' + amount, caseSensitive: false),
          RegExp(r'\bclaim\s+(?:for|of)\s*(?:rs\.?|inr|₹)\s*([0-9][0-9,]*(?:\.\d{1,2})?)', caseSensitive: false),
        ],
      'approved' => <RegExp>[
          RegExp(r'\b(?:amount\s+approved|approved\s+amount|amount\s+sanctioned|sanctioned\s+amount|settled\s+amount|amount\s+settled)\b\s*[:=\-]?\s*' + amount, caseSensitive: false),
          RegExp(r'\bamount\s+(?:(?:rs\.?|inr)\s*|₹\s*)?([0-9][0-9,]*(?:\.\d{1,2})?)\s+approved\b', caseSensitive: false),
        ],
      'sum_insured' => <RegExp>[
          RegExp(r'\b(?:sum\s+insured|sum\s+assured|coverage\s+limit|policy\s+limit|total\s+cover|base\s+cover)\b\s*[:=\-]?\s*' + amount, caseSensitive: false),
        ],
      'premium' => <RegExp>[
          RegExp(r'\b(?:premium\s+amount|annual\s+premium|policy\s+premium|premium)\b\s*[:=\-]?\s*' + amount, caseSensitive: false),
        ],
      'copay' => <RegExp>[
          RegExp(r'\b(?:co[- ]?pay(?:ment)?\s+amount|co[- ]?pay|copay)\b\s*[:=\-]?\s*' + amount, caseSensitive: false),
        ],
      'deductible' => <RegExp>[
          RegExp(r'\b(?:deductible\s+amount|deductible)\b\s*[:=\-]?\s*' + amount, caseSensitive: false),
        ],
      'bill_total' => <RegExp>[
          RegExp(r'\b(?:total\s+hospital\s+bill|total\s+bill|bill\s+amount|hospital\s+bill\s+amount|total\s+charges|invoice\s+amount)\b\s*[:=\-]?\s*' + amount, caseSensitive: false),
        ],
      'paid' => <RegExp>[
          RegExp(r'\b(?:amount\s+paid|paid\s+amount|paid\s+by\s+insurer|insurer\s+paid|payment\s+amount|settled\s+amount)\b\s*[:=\-]?\s*' + amount, caseSensitive: false),
        ],
      'deducted' => <RegExp>[
          RegExp(r'\b(?:amount\s+deducted|deduction\s+amount|total\s+deduction|deducted\s+amount|disallowed\s+amount|non[- ]payable\s+amount|shortfall\s+amount)\b\s*[:=\-]?\s*' + amount, caseSensitive: false),
          RegExp(r'\b(?:deducted|disallowed|non[- ]payable)\s+(?:amount\s+)?(?:(?:rs\.?|inr)\s*|₹\s*)?([0-9][0-9,]*(?:\.\d{1,2})?)', caseSensitive: false),
        ],
      _ => <RegExp>[
          RegExp(r'\b(?:amount\s+pending|pending\s+amount|remaining\s+amount|amount\s+remaining|balance\s+pending|pending\s+review)\b\s*[:=\-]?\s*' + amount, caseSensitive: false),
          RegExp(r'\b(?:amount|balance)\s+(?:(?:rs\.?|inr)\s*|₹\s*)?([0-9][0-9,]*(?:\.\d{1,2})?)\s+(?:pending|remaining)\b', caseSensitive: false),
        ],
    };
    for (final pattern in patterns) {
      final match = pattern.firstMatch(text);
      if (match != null) return match.group(1)?.replaceAll(',', '');
    }
    return null;
  }

  String _formatLocalMoney(String raw) {
    final clean = raw.replaceAll(',', '');
    final pieces = clean.split('.');
    final whole = int.tryParse(pieces.first);
    if (whole == null) return '₹$raw';
    final digits = whole.toString();
    String grouped;
    if (digits.length <= 3) {
      grouped = digits;
    } else {
      final lastThree = digits.substring(digits.length - 3);
      var leading = digits.substring(0, digits.length - 3);
      final groups = <String>[];
      while (leading.length > 2) {
        groups.insert(0, leading.substring(leading.length - 2));
        leading = leading.substring(0, leading.length - 2);
      }
      if (leading.isNotEmpty) groups.insert(0, leading);
      grouped = '${groups.join(',')},$lastThree';
    }
    return pieces.length > 1 ? '₹$grouped.${pieces[1]}' : '₹$grouped';
  }

  String _amountLabel(String kind, SathiLanguageMode language) => switch (language) {
        SathiLanguageMode.hinglish => switch (kind) {
            'claimed' => 'Claim amount:',
            'approved' => 'Approved amount:',
            'pending' => 'Amount pending review:',
            'deducted' => 'Amount deducted/disallowed:',
            'sum_insured' => 'Sum insured / cover limit:',
            'premium' => 'Premium amount:',
            'copay' => 'Co-pay amount:',
            'deductible' => 'Deductible amount:',
            'bill_total' => 'Total bill amount:',
            'paid' => 'Amount paid/settled:',
            _ => 'Amount:',
          },
        SathiLanguageMode.hindi => switch (kind) {
            'claimed' => 'दावा की गई राशि:',
            'approved' => 'स्वीकृत राशि:',
            'pending' => 'लंबित राशि:',
            'deducted' => 'काटी/अस्वीकृत राशि:',
            'sum_insured' => 'बीमा राशि / कवर सीमा:',
            'premium' => 'प्रीमियम राशि:',
            'copay' => 'को-पे राशि:',
            'deductible' => 'डिडक्टिबल राशि:',
            'bill_total' => 'कुल बिल राशि:',
            'paid' => 'भुगतान/सेटल राशि:',
            _ => 'राशि:',
          },
        SathiLanguageMode.english => switch (kind) {
            'claimed' => 'Claimed amount:',
            'approved' => 'Approved amount:',
            'pending' => 'Amount pending review:',
            'deducted' => 'Amount deducted/disallowed:',
            'sum_insured' => 'Sum insured / coverage limit:',
            'premium' => 'Premium amount:',
            'copay' => 'Co-pay amount:',
            'deductible' => 'Deductible amount:',
            'bill_total' => 'Total bill amount:',
            'paid' => 'Amount paid/settled:',
            _ => 'Amount:',
          },
      };

  List<_LocalExcerpt> _findRelevantExcerpts(String question, List<_LocalDocument> docs) {
    if (docs.isEmpty) return const [];
    final terms = _keywords(question);
    if (terms.isEmpty) return const [];
    final expanded = _expandQuery(question, terms);
    final results = <_LocalExcerpt>[];

    for (final doc in docs) {
      final chunks = _documentChunks(doc.text);
      final titleTerms = _keywords(doc.title);
      for (final chunk in chunks) {
        final contentTerms = _keywords(chunk);
        final exactMatches = contentTerms.intersection(terms).length;
        final expandedMatches = contentTerms.intersection(expanded).length;
        // Prefer actual words from the question. Synonym expansions broaden
        // retrieval, but cannot dominate the score by themselves.
        var score = exactMatches * 4 + (expandedMatches - exactMatches).clamp(0, 100).toInt();
        score += titleTerms.intersection(terms).length;

        final q = question.toLowerCase();
        if (_hasAny(q, const ['why', 'reason', 'kyun', 'kyu', 'kis wajah', 'क्यों', 'कारण']) &&
            _hasAny(chunk.toLowerCase(), const ['reason', 'because', 'reject', 'rejection', 'partial', 'denied', 'denial', 'not payable', 'excluded', 'missing', 'required', 'insufficient', 'कारण', 'अस्वीकृत'])) {
          score += 3;
        }
        if (_hasAny(q, const ['status', 'kaha tak', 'kahan tak', 'स्थित', 'स्थिति']) &&
            _hasAny(chunk.toLowerCase(), const ['status', 'pending', 'partially approved', 'approved', 'rejected', 'under review', 'settled', 'स्टेटस', 'स्थिति'])) {
          score += 3;
        }
        if (_hasAny(q, const ['deadline', 'last date', 'kab tak', 'कब तक', 'appeal', 'reconsider']) &&
            _hasAny(chunk.toLowerCase(), const ['within', 'days', 'deadline', 'last date', 'appeal', 'reconsider', 'submit by', 'time limit', 'समय-सीमा'])) {
          score += 3;
        }
        if (score > 0) results.add(_LocalExcerpt(title: doc.title, text: chunk, score: score));
      }
    }

    // For explicit document-summary requests, return local excerpts even if the
    // question has few matching terms. This is retrieval, not model-generated QA.
    final q = question.toLowerCase();
    final asksToSummarise = _hasAny(q, const [
      'summarise this', 'summarize this', 'summarise', 'summarize', 'summary',
      'explain this document', 'what does this say', 'is letter mein',
      'yeh letter', 'ye letter', 'document samjhao', 'letter samjhao',
      'short mein batao', 'samjha do', 'summary batao', 'what should i do', 'what do i do next', 'next step', 'next steps', 'ab kya karu', 'agla step', 'aage kya', 'अगला कदम', 'इस पत्र का मतलब',
      'इस दस्तावेज़ को समझाओ', 'सारांश',
    ]);
    if (results.isEmpty && asksToSummarise) {
      for (final doc in docs.take(2)) {
        for (final chunk in _documentChunks(doc.text).take(4)) {
          results.add(_LocalExcerpt(title: doc.title, text: chunk, score: 1));
        }
      }
    }

    results.sort((a, b) => b.score.compareTo(a.score));
    final unique = <String>{};
    return results.where((item) => unique.add('${item.title}|${item.text}')).take(5).toList();
  }

  /// Creates overlapping local evidence windows so OCR layouts where labels and
  /// values land on adjacent lines (for example "Claim status" / "Partially
  /// approved") remain answerable. No network or model call occurs here.
  List<String> _documentChunks(String text) {
    final lines = text
        .replaceAll('\r', '')
        .split(RegExp(r'\n+|(?<=[.!?।])\s+'))
        .map((line) => line.replaceAll(RegExp(r'\s+'), ' ').trim())
        .where((line) => line.isNotEmpty)
        .toList();
    if (lines.isEmpty) return const [];

    final chunks = <String>{};
    for (var i = 0; i < lines.length; i++) {
      // Preserve every individual line, including short OCR labels, and add
      // 2- and 3-line windows to connect a label with its value/explanation.
      chunks.add(lines[i]);
      if (i + 1 < lines.length) chunks.add('${lines[i]} | ${lines[i + 1]}');
      if (i + 2 < lines.length) chunks.add('${lines[i]} | ${lines[i + 1]} | ${lines[i + 2]}');
    }
    return chunks.toList();
  }

  Set<String> _keywords(String input) {
    const stop = {
      'the', 'and', 'for', 'that', 'this', 'with', 'from', 'have', 'has', 'had', 'was', 'were',
      'what', 'when', 'where', 'why', 'how', 'can', 'could', 'should', 'would', 'will', 'does',
      'did', 'about', 'after', 'before', 'please', 'tell', 'me', 'my', 'is', 'are', 'a', 'an',
      'to', 'in', 'on', 'of', 'it', 'or', 'as', 'be', 'i', 'you', 'your', 'we', 'they',
      'hai', 'hain', 'ho', 'kya', 'ka', 'ki', 'ke', 'ko', 'se', 'mein', 'par', 'mere',
      'meri', 'mera', 'mujhe', 'ab', 'batao', 'bata', 'karo', 'karu', 'kare', 'kyu', 'kyun',
      'hua', 'hui', 'ye', 'yeh', 'iska', 'iski', 'iske', 'mila', 'gaya', 'gayi',
    };
    final tokens = input.toLowerCase().split(RegExp(r'[^a-z0-9\u0900-\u097F]+'));
    return tokens.where((token) => token.length > 1 && !stop.contains(token)).toSet();
  }

  Set<String> _expandQuery(String question, Set<String> terms) {
    final expanded = <String>{...terms};
    final text = question.toLowerCase();

    void addIf(bool condition, List<String> values) {
      if (condition) expanded.addAll(values);
    }

    addIf(_hasAny(text, const ['why', 'reason', 'kyun', 'kyu', 'kis wajah', 'partly approve', 'partly approved', 'partial approval', 'partially approve', 'partially approved', 'reject', 'rejected', 'rejection', 'deny', 'denied', 'declined', 'refused', 'not approved', 'रिजेक्ट', 'अस्वीकृत', 'अस्वीकार', 'आंशिक', 'क्यों', 'कारण']), const [
      'reject', 'rejected', 'rejection', 'deny', 'denied', 'declined', 'refused',
      'reason', 'because', 'partial', 'partially', 'partial approval', 'partly approve', 'partially approve', 'kyun', 'kyu', 'kis wajah', 'क्यों', 'कारण', 'not payable', 'disallowed',
      'excluded', 'exclusion', 'shortfall', 'insufficient', 'mismatch', 'missing',
      'additional information', 'required', 'waiting period', 'sub-limit', 'deduction',
      'रिजेक्ट', 'अस्वीकृत', 'अस्वीकार', 'कारण', 'आंशिक', 'कमी', 'दस्तावेज',
    ]);
    addIf(_hasAny(text, const ['document', 'documents', 'docs', 'kagaz', 'कागज', 'दस्तावेज', 'paper', 'bill', 'report', 'what should i submit', 'kya dena']), const [
      'document', 'documents', 'docs', 'bill', 'itemised', 'itemized', 'invoice',
      'discharge', 'summary', 'prescription', 'report', 'diagnostic', 'submitted',
      'missing', 'required', 'additional', 'provide', 'submit', 'attach', 'कागज',
      'दस्तावेज', 'बिल', 'रिपोर्ट', 'जमा', 'जरूरी',
    ]);
    addIf(_hasAny(text, const ['waiting period', 'waiting', 'प्रतीक्षा अवधि', 'वेटिंग']), const [
      'waiting', 'period', 'months', 'years', 'pre-existing', 'waiting-period',
      'illness', 'treatment', 'covered', 'exclusion',
    ]);
    addIf(_hasAny(text, const ['coverage', 'covered', 'cover', 'policy', 'कवर', 'पॉलिसी', 'कवरेज', 'exclusion', 'excluded']), const [
      'coverage', 'covered', 'cover', 'exclusion', 'excluded', 'limit', 'sub-limit',
      'policy', 'sum insured', 'waiting', 'room rent', 'co-pay', 'deductible',
      'कवरेज', 'पॉलिसी', 'कवर', 'अपवाद',
    ]);
    addIf(_hasAny(text, const ['status', 'kaha tak', 'kahan tak', 'abhi kya status', 'स्टेटस', 'स्थिति']), const [
      'status', 'pending', 'processing', 'under review', 'approved', 'partially approved',
      'rejected', 'settled', 'paid', 'decision', 'स्टेटस', 'स्थिति', 'लंबित',
    ]);
    addIf(_hasAny(text, const ['when', 'date', 'deadline', 'last date', 'kab', 'kab tak', 'कब', 'तारीख', 'समय-सीमा', 'within how many days']), const [
      'date', 'dated', 'deadline', 'due', 'within', 'days', 'last date', 'submit by',
      'appeal', 'reconsideration', 'admission', 'discharge', 'filed', 'received', 'तारीख', 'दिन',
    ]);
    addIf(_hasAny(text, const ['insurer', 'insurance company', 'hospital name', 'which hospital', 'kis hospital', 'company name', 'बीमा कंपनी', 'अस्पताल']), const [
      'insurer', 'insurance company', 'hospital', 'provider', 'name', 'बीमा कंपनी', 'अस्पताल',
    ]);
    addIf(_hasAny(text, const ['diagnosis', 'treatment', 'illness', 'disease', 'operation', 'surgery', 'diagnostic', 'इलाज', 'बीमारी', 'निदान']), const [
      'diagnosis', 'treatment', 'illness', 'disease', 'condition', 'procedure', 'surgery',
      'admission', 'discharge', 'prescription', 'निदान', 'इलाज', 'बीमारी',
    ]);
    addIf(_hasAny(text, const ['policy number', 'policy no', 'claim number', 'claim no', 'claim id', 'reference number', 'reference id', 'पॉलिसी नंबर', 'क्लेम नंबर']), const [
      'policy', 'number', 'no', 'claim', 'reference', 'id', 'policy number', 'claim number',
      'पॉलिसी', 'क्लेम', 'नंबर',
    ]);
    addIf(_hasAny(text, const ['amount', 'how much', 'kitna', 'kitne', 'kitni', 'राशि', 'कितना', 'कितनी', 'कितने']), const [
      'amount', 'claimed', 'requested', 'approved', 'sanctioned', 'settled', 'pending',
      'remaining', 'balance', 'paid', 'deduction', 'disallowed', 'bill', 'charges', 'rs', 'inr',
      'राशि', 'दावा', 'स्वीकृत', 'मंजूर', 'बाकी',
    ]);
    addIf(_hasAny(text, const ['who', 'which', 'what is written', 'kya likha', 'kaun', 'kya hai', 'क्या लिखा', 'कौन']), const [
      'name', 'details', 'written', 'document', 'letter', 'claim', 'policy', 'hospital', 'insurer',
    ]);
    return expanded;
  }

  bool _asksForRequiredDocuments(String question) {
    final q = question.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

    // Deadline questions often mention the documents being submitted. Resolve
    // the requested information type first so wording such as "What is the
    // final date to submit supporting documents?" is not treated as a request
    // for a checklist merely because it contains both "submit" and "documents".
    final asksDeadline = _hasAny(q, const [
      'deadline', 'last date', 'final date', 'due date', 'submission date',
      'expiry date', 'expiration date', 'by what date', 'date to submit',
      'when do i need to', 'how long do i have', 'within how many days',
      'how many days', 'time limit', 'submit by', 'appeal deadline',
      'अंतिम तारीख', 'आखिरी तारीख', 'समय-सीमा', 'समय सीमा', 'कब तक',
    ]);
    if (asksDeadline) return false;

    final directChecklistRequest = _hasAny(q, const [
      'which papers', 'what papers', 'papers should i', 'papers do i need',
      'papers needed', 'what paper', 'which document', 'which documents',
      'what document', 'what documents', 'which docs', 'what docs',
      'required documents', 'documents required', 'documents needed',
      'what should i upload', 'what do i upload', 'which files should i upload',
      'which document should i attach', 'missing papers', 'papers required',
      'kaun se kagaz', 'kaunse kagaz', 'kaun se document', 'kaunse document',
      'kya docs chahiye', 'kya kya chahiye', 'कौन से दस्तावेज', 'कौन से कागज',
      'कौन से काग़ज़', 'कौन से पेपर', 'कौन से कागजात', 'क्या अपलोड', 'क्या जमा',
    ]);
    final actionAndDocument =
        _hasAny(q, const ['upload', 'attach', 'submit', 'provide', 'send', 'jama', 'अपलोड', 'जमा', 'भेज']) &&
        _hasAny(q, const ['paper', 'papers', 'document', 'docs', 'file', 'files', 'kagaz', 'कागज', 'काग़ज़', 'दस्तावेज', 'फाइल', 'बिल', 'रिपोर्ट']);
    return directChecklistRequest || actionAndDocument;
  }

  String? _localFactKind(String question) {
    final q = question.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

    // Recognise a wide range of ways customers ask for a written response.
    // The resulting draft is created locally from retrieved excerpts; it is
    // never submitted to an insurer automatically.
    if (_hasAny(q, const [
      'prepare a reconsideration', 'prepare reconsideration',
      'write a reconsideration', 'reconsideration letter', 'appeal letter',
      'write an appeal', 'write appeal', 'draft an appeal', 'draft appeal',
      'make an appeal', 'make a reply', 'write a reply', 'draft a reply',
      'reply to this letter', 'respond to this letter', 'response to rejection',
      'reply to rejection', 'respond to insurer', 'write back', 'help me respond',
      'reply draft', 'letter bana', 'reply likh', 'draft bana',
      'appeal bana', 'jawab likho', 'अपील पत्र', 'अपील लिखो', 'ड्राफ्ट बनाओ',
      'जवाब लिखो', 'पुनर्विचार पत्र',
    ])) return 'prepare_reconsideration';

    final hasDeadlineTerm = _hasAny(q, const [
      'deadline', 'last date', 'final date', 'due date', 'submission date',
      'expiry date', 'expiration date', 'by what date', 'when do i need to',
      'how long do i have', 'when is the deadline', 'reconsider kab',
      'अंतिम तारीख', 'समय-सीमा', 'आखिरी तारीख', 'समय सीमा',
    ]);
    final mentionsSubmission = _hasAny(q, const [
      'submit', 'submission', 'upload', 'send documents', 'provide documents',
      'appeal', 'reconsideration', 'resubmit', 'jama', 'जमा', 'भेजना',
    ]);
    final asksTime = _hasAny(q, const [
      'within how many days', 'how many days', 'kitne din', 'kitne dino',
      'kab tak', 'date to submit', 'कितने दिन', 'कब तक',
    ]);
    if (hasDeadlineTerm || (mentionsSubmission && asksTime)) return 'deadline';

    if (_hasAny(q, const [
      'missing document', 'documents missing', 'document required',
      'documents required', 'what documents', 'which documents', 'what docs',
      'which docs', 'docs needed', 'documents do i need', 'what do i need to submit',
      'what should i upload', 'what do i need to upload', 'which document should i attach',
      'which papers', 'what papers', 'missing papers', 'papers required',
      'papers should i', 'which files', 'what files', 'which document do i attach',
      'kaun se document', 'kaunse document', 'kaun se kagaz', 'kaunse kagaz',
      'kya docs chahiye', 'kya kya chahiye', 'kya dena padega', 'kya submit karu',
      'kya jama karu', 'कौन से दस्तावेज', 'कौन से कागज', 'कौन से काग़ज़',
      'क्या जमा', 'क्या अपलोड', 'कौन से पेपर', 'कौन से कागजात',
    ])) return 'required_documents';

    if (_hasAny(q, const [
      'why', 'reason', 'kis wajah', 'kyun', 'kyu', 'how come',
      'what caused', 'why was it', 'why did they', 'why is it',
      'why not paid', 'why did they not pay', 'why not approved',
      'why was the full amount', 'partly approve kyun', 'partially approve kyun',
      'reject kyun', 'reject kyu', 'partial rejection', 'partial approval reason',
      'क्यों', 'कारण', 'वजह', 'रिजेक्ट', 'अस्वीकृत क्यों', 'क्यों काटा',
    ])) return 'reason';

    if (_hasAny(q, const [
      'claim status', 'status kya', 'status kya hai', 'kaha tak', 'kahan tak',
      'abhi status', 'current status', 'is my claim pending', 'claim pending',
      'pending hai', 'is claim still pending', 'is my claim approved',
      'has my claim been approved', 'was my claim approved', 'claim approved',
      'what was approved', 'what did the insurer approve', 'did insurer approve',
      'has insurer approved', 'approval decision', 'claim outcome', 'claim accepted',
      'approve hua kya', 'approve hua hai', 'reject hua kya', 'claim ka result',
      'claim process hua', 'has the claim been processed', 'claim decision',
      'क्या क्लेम मंजूर', 'क्लेम स्वीकृत', 'क्लेम की स्थिति', 'स्टेटस', 'स्थिति क्या',
    ])) return 'status';

    if (_hasAny(q, const [
      'policy number', 'policy no', 'policy id', 'policy reference',
      'पॉलिसी नंबर', 'पॉलिसी संख्या', 'पॉलिसी आईडी',
    ])) return 'policy_number';
    if (_hasAny(q, const [
      'claim id', 'claim number', 'claim no', 'claim reference',
      'reference number', 'reference id', 'claim reference number',
      'क्लेम नंबर', 'क्लेम आईडी', 'दावा नंबर',
    ])) return 'claim_id';
    if (_hasAny(q, const [
      'insurer name', 'who is the insurer', 'who is my insurer',
      'what is my insurer', 'which insurance company', 'insurance company',
      'which insurer', 'which company', 'insurer ka naam', 'insurance company ka naam',
      'kaunsi company', 'kaun si company', 'बीमा कंपनी', 'इंश्योरर',
    ])) return 'insurer';
    if (_hasAny(q, const [
      'hospital name', 'what is the hospital', 'which hospital',
      'hospital ka naam', 'hospital kaun sa', 'kis hospital',
      'which hospital treated', 'hospital mentioned', 'अस्पताल का नाम',
    ])) return 'hospital';
    if (_hasAny(q, const [
      'admission date', 'admitted when', 'date of admission', 'discharge date',
      'date of discharge', 'claim date', 'letter date', 'when was the letter',
      'letter kab aaya', 'kab aaya', 'decision date', 'kab admit', 'kab discharge',
      'expiry date', 'policy expiry', 'policy expires', 'date of treatment',
      'तारीख', 'किस तारीख', 'कब जारी',
    ])) return 'date';
    if (_hasAny(q, const [
      'diagnosis', 'what treatment', 'treatment mentioned', 'which illness',
      'what illness', 'medical condition', 'what procedure', 'kya treatment',
      'kaunsi bimari', 'किस बीमारी', 'निदान', 'इलाज', 'बीमारी',
    ])) return 'treatment';
    if (_hasAny(q, const [
      'covered', 'coverage', 'excluded', 'exclusion', 'policy mein cover',
      'cover hai', 'does my policy cover', 'does the policy cover',
      'is this treatment covered', 'will policy pay', 'is it covered',
      'room rent limit', 'sub-limit', 'sublimit', 'waiting period',
      'policy terms', 'कवर है', 'कवरेज', 'अपवाद', 'वेटिंग पीरियड',
    ])) return 'coverage';
    if (_hasAny(q, const [
      'summarise', 'summarize', 'summary', 'short mein', 'document ka summary',
      'letter summarize', 'letter summarise', 'important points', 'key points',
      'main points', 'what does this letter mean', 'what is this letter saying',
      'explain this letter', 'explain this document', 'letter ka matlab',
      'letter samjhao', 'document samjhao', 'padh ke batao', 'सारांश',
      'मुख्य बातें', 'इस पत्र का मतलब', 'समझाओ',
    ])) return 'summary';
    if (_hasAny(q, const [
      'contact', 'phone number', 'helpline', 'customer care', 'email address',
      'support number', 'contact details', 'ग्राहक सेवा', 'हेल्पलाइन',
    ])) return 'contact';
    if (_hasAny(q, const [
      'what should i do', 'what do i do next', 'next step', 'next steps',
      'what now', 'what do i do now', 'how should i proceed', 'how do i proceed',
      'ab kya karu', 'ab kya karna', 'agla step', 'aage kya', 'ab kya hoga',
      'आगे क्या', 'अगला कदम', 'अब क्या करूं',
    ])) return 'next_steps';
    return null;
  }

  SathiAgentReply? _answerLocalLabeledFact(
    String question,
    List<_LocalDocument> docs,
    SathiLanguageMode language,
    String kind,
  ) {
    final chunks = docs.expand((doc) => _documentChunks(doc.text).map((chunk) => _LocalExcerpt(title: doc.title, text: chunk, score: 0))).toList();
    final patterns = <String, List<String>>{
      'reason': ['reason', 'because', 'partially approved', 'partial approval', 'rejected', 'rejection', 'denied', 'denial', 'not payable', 'disallowed', 'excluded', 'missing', 'required', 'insufficient', 'additional information', 'shortfall', 'deducted', 'कारण', 'अस्वीकृत'],
      'status': ['current status', 'claim status', 'partially approved', 'partly approved', 'pending', 'under review', 'under process', 'approved', 'rejected', 'settled', 'status', 'लंबित', 'स्थिति'],
      'required_documents': ['required documents', 'documents required', 'missing documents', 'additional documents', 'itemised bill', 'itemized bill', 'discharge summary', 'diagnostic report', 'prescription', 'submit', 'provide', 'attach', 'required', 'missing', 'documents', 'दस्तावेज', 'बिल', 'रिपोर्ट'],
      'deadline': ['deadline', 'last date', 'within', 'days', 'submit by', 'appeal', 'reconsideration', 'time limit', 'due date', 'दिन के भीतर', 'समय-सीमा'],
      'policy_number': ['policy number', 'policy no', 'policy id', 'policy:'],
      'claim_id': ['claim id', 'claim number', 'claim no', 'reference number', 'reference id'],
      'insurer': ['insurer', 'insurance company', 'insurance provider', 'assurance company'],
      'hospital': ['hospital name', 'hospital:', 'hospital '],
      'date': ['date of admission', 'admission date', 'date of discharge', 'discharge date', 'claim date', 'decision date', 'letter date', 'dated', 'date:'],
      'treatment': ['diagnosis', 'treatment', 'procedure', 'admitted for', 'discharge summary', 'prescription', 'investigation'],
      'coverage': ['covered', 'coverage', 'not covered', 'excluded', 'exclusion', 'waiting period', 'co-pay', 'copay', 'deductible', 'limit', 'sub-limit', 'policy wording'],
      'contact': ['helpline', 'customer care', 'contact', 'phone', 'email', 'call us', 'support number'],
      'next_steps': ['next step', 'submit', 'provide', 'required', 'within', 'additional information', 'appeal', 'reconsideration', 'document', 'bill', 'report'],
      'summary': [],
      'prepare_reconsideration': ['reason', 'rejection', 'partial approval', 'partially approved', 'claim decision', 'required', 'missing', 'additional information', 'deadline', 'submit', 'bill', 'report'],
    };
    final clues = patterns[kind] ?? const <String>[];
    final queryTerms = _expandQuery(question, _keywords(question));
    final ranked = <_LocalExcerpt>[];
    for (final chunk in chunks) {
      final lower = chunk.text.toLowerCase();
      var score = _keywords(chunk.text).intersection(queryTerms).length;
      for (final clue in clues) {
        if (lower.contains(clue)) score += 3;
      }
      if (kind == 'reason' && _hasAny(lower, const ['reason', 'because', 'partially approved', 'partial approval', 'not payable', 'missing', 'required', 'excluded', 'deducted'])) score += 5;
      if (kind == 'status' && _hasAny(lower, const ['current status', 'claim status', 'partially approved', 'under review', 'pending', 'rejected', 'settled'])) score += 5;
      final hasFieldAnchor = switch (kind) {
        'reason' => _hasAny(lower, const ['reason', 'because', 'partially approved', 'partial approval', 'rejection', 'rejected', 'denied', 'not payable', 'disallowed', 'excluded', 'missing', 'required', 'insufficient', 'additional information', 'shortfall', 'deducted', 'कारण', 'अस्वीकृत']),
        'status' => _hasAny(lower, const ['current status', 'claim status', 'partially approved', 'partly approved', 'pending', 'under review', 'under process', 'approved', 'rejected', 'settled', 'status', 'लंबित', 'स्थिति']),
        'required_documents' => _hasAny(lower, const ['document', 'docs', 'paper', 'bill', 'invoice', 'discharge', 'summary', 'prescription', 'report', 'submit', 'provide', 'attach', 'required', 'missing', 'कागज', 'दस्तावेज', 'बिल', 'रिपोर्ट']),
        'deadline' => _hasAny(lower, const ['deadline', 'last date', 'final date', 'within', 'days', 'submit by', 'appeal', 'reconsideration', 'time limit', 'due date', 'दिन के भीतर', 'समय-सीमा', 'आखिरी तारीख']),
        'policy_number' => _hasAny(lower, const ['policy number', 'policy no', 'policy id', 'policy reference', 'पॉलिसी नंबर', 'पॉलिसी संख्या']),
        'claim_id' => _hasAny(lower, const ['claim id', 'claim number', 'claim no', 'reference number', 'reference id', 'क्लेम नंबर', 'क्लेम आईडी']),
        'insurer' => _hasAny(lower, const ['insurer', 'insurance company', 'insurance provider', 'assurance company', 'बीमा कंपनी', 'इंश्योरर']),
        'hospital' => _hasAny(lower, const ['hospital', 'nursing home', 'clinic', 'अस्पताल']),
        'date' => _hasAny(lower, const ['date', 'dated', 'admission', 'discharge', 'expiry', 'issued on', 'तारीख', 'दिनांक']),
        'treatment' => _hasAny(lower, const ['diagnosis', 'treatment', 'procedure', 'admitted for', 'prescription', 'investigation', 'illness', 'disease', 'निदान', 'इलाज', 'बीमारी']),
        'coverage' => _hasAny(lower, const ['covered', 'coverage', 'not covered', 'excluded', 'exclusion', 'waiting period', 'co-pay', 'copay', 'deductible', 'room rent', 'limit', 'sub-limit', 'policy wording', 'कवरेज', 'कवर', 'अपवाद']),
        'contact' => _hasAny(lower, const ['helpline', 'customer care', 'contact', 'phone', 'email', 'call us', 'support number', 'संपर्क', 'हेल्पलाइन']),
        'next_steps' => _hasAny(lower, const ['next step', 'submit', 'provide', 'required', 'within', 'additional information', 'appeal', 'reconsideration', 'document', 'bill', 'report', 'अगला कदम']),
        'summary' => true,
        'prepare_reconsideration' => true,
        _ => true,
      };
      if (score > 0 && hasFieldAnchor) {
        ranked.add(_LocalExcerpt(title: chunk.title, text: chunk.text, score: score));
      }
    }
    ranked.sort((a, b) => b.score.compareTo(a.score));
    final seen = <String>{};
    final evidence = ranked.where((e) => seen.add('${e.title}|${e.text}')).take(kind == 'required_documents' || kind == 'reason' || kind == 'prepare_reconsideration' ? 5 : 3).toList();

    if (kind == 'summary' || (kind == 'prepare_reconsideration' && evidence.isEmpty)) {
      final summary = docs.expand((doc) => _documentChunks(doc.text).map((text) => _LocalExcerpt(title: doc.title, text: text, score: _keywords(text).length))).toList()
        ..sort((a, b) => b.score.compareTo(a.score));
      final unique = <String>{};
      evidence
        ..clear()
        ..addAll(summary.where((e) => unique.add('${e.title}|${e.text}')).take(4));
    }

    // If the field-specific matcher cannot find evidence, let the broader
    // ranked retriever make one pass before reporting no local answer.
    if (evidence.isEmpty) return null;
    final answer = _formatLocalEvidenceAnswer(kind, evidence, language);
    final draft = kind == 'prepare_reconsideration' ? _localDraft(evidence, language) : '';

    return SathiAgentReply(
      answer: answer,
      draft: draft,
      intent: kind,
      actionIndex: kind == 'prepare_reconsideration' ? 4 : (kind == 'required_documents' ? 2 : (kind == 'summary' || kind == 'reason' || kind == 'status' ? 1 : 2)),
      actionLabel: kind == 'prepare_reconsideration' ? 'Review local draft' : (kind == 'required_documents' ? 'Open documents' : 'Review local evidence'),
      mode: evidence.isEmpty ? 'local_fact_not_found' : 'local_document_fact',
      notice: 'ON DEVICE · Answer is based on locally saved document. No question or document was sent online.',
      evidenceUsed: evidence.map((e) => '${e.title}: ${e.text}').toList(),
    );
  }

  SathiAgentReply _localFactNotFound(
    String kind,
    SathiLanguageMode language,
  ) {
    final subject = switch (kind) {
      'reason' => switch (language) {
          SathiLanguageMode.hinglish => 'claim ke rejection/partial approval ka exact reason',
          SathiLanguageMode.hindi => 'क्लेम अस्वीकार/आंशिक स्वीकृति का सटीक कारण',
          SathiLanguageMode.english => 'the exact claim rejection/partial-approval reason',
        },
      'coverage' => switch (language) {
          SathiLanguageMode.hinglish => 'policy ka coverage clause',
          SathiLanguageMode.hindi => 'पॉलिसी का कवरेज क्लॉज़',
          SathiLanguageMode.english => 'the policy coverage clause',
        },
      'deadline' => switch (language) {
          SathiLanguageMode.hinglish => 'submit/appeal ki deadline',
          SathiLanguageMode.hindi => 'जमा करने/अपील की समय-सीमा',
          SathiLanguageMode.english => 'the submission/appeal deadline',
        },
      'required_documents' => switch (language) {
          SathiLanguageMode.hinglish => 'required ya missing documents ki list',
          SathiLanguageMode.hindi => 'ज़रूरी या बाकी दस्तावेज़ों की सूची',
          SathiLanguageMode.english => 'the required or missing documents list',
        },
      'status' => switch (language) {
          SathiLanguageMode.hinglish => 'claim status/decision',
          SathiLanguageMode.hindi => 'क्लेम की स्थिति/निर्णय',
          SathiLanguageMode.english => 'the claim status/decision',
        },
      _ => switch (language) {
          SathiLanguageMode.hinglish => 'is sawal ka exact jawab',
          SathiLanguageMode.hindi => 'इस सवाल का सटीक जवाब',
          SathiLanguageMode.english => 'the exact answer to this question',
        },
    };
    final answer = switch (language) {
      SathiLanguageMode.hinglish => 'Mujhe aapke document mein $subject nahi mila, isliye main andaza nahi lagaunga/lagaungi. Kripya us jaankari wala saaf document add karein.',
      SathiLanguageMode.hindi => 'मुझे आपके दस्तावेज़ में $subject नहीं मिला, इसलिए मैं अनुमान नहीं लगाऊँगा/लगाऊँगी। कृपया वह जानकारी साफ़ दिखाने वाला दस्तावेज़ जोड़ें।',
      SathiLanguageMode.english => 'I could not find $subject in your document, so I will not guess. Please add a clearer copy showing that information.',
    };
    return SathiAgentReply(
      answer: answer,
      intent: kind,
      actionIndex: 2,
      actionLabel: language == SathiLanguageMode.hindi ? 'दस्तावेज़ खोलें' : 'Open documents',
      mode: 'local_fact_not_found',
      notice: 'ON DEVICE · Requested field was not found in saved document. No cloud request was made.',
      evidenceUsed: const [],
    );
  }

  String _formatLocalEvidenceAnswer(String kind, List<_LocalExcerpt> evidence, SathiLanguageMode language) {
    final snippets = evidence.map((e) => '• ${e.text}').join('\n');
    return switch (language) {
      SathiLanguageMode.hinglish => switch (kind) {
          'reason' => 'Aapke saved document mein rejection/partial approval se related yeh wording mili:\n$snippets\n\nYeh explanation sirf document ke text par based hai. Insurer ka live record verify nahi hua.',
          'status' => 'Saved document mein status se related yeh wording hai:\n$snippets\n\nYeh document ka status text hai, live insurer status nahi.',
          'required_documents' => 'Saved document mein documents ya next steps ke baare mein yeh likha hai:\n$snippets\n\nExact checklist insurer ki official instructions se verify karein.',
          'prepare_reconsideration' => 'Maine saved document ki relevant lines ke basis par ek editable reconsideration draft taiyaar kiya hai. Yeh sirf draft hai—maine insurer ko kuch submit nahi kiya. Relevant lines:\n$snippets',
          'deadline' => 'Saved document mein deadline/appeal period se related yeh wording mili:\n$snippets\n\nAgar exact calendar date clear nahi hai, insurer se official deadline confirm karein.',
          'policy_number' => 'Saved document mein policy reference se related yeh text mila:\n$snippets',
          'claim_id' => 'Saved document mein claim/reference ID se related yeh text mila:\n$snippets',
          'insurer' => 'Saved document mein insurer/company se related yeh text mila:\n$snippets',
          'hospital' => 'Saved document mein hospital se related yeh text mila:\n$snippets',
          'date' => 'Saved document mein date se related yeh text mila:\n$snippets',
          'treatment' => 'Saved document mein treatment/diagnosis se related yeh text mila:\n$snippets',
          'coverage' => 'Saved document mein coverage/policy terms se related yeh text mila:\n$snippets\n\nCoverage ka final interpretation policy wording aur insurer se verify karein.',
          'contact' => 'Saved document mein contact details se related yeh text mila:\n$snippets\n\nNumber/email ko use karne se pehle document se verify karein.',
          'next_steps' => 'Aapke saved document ke mutabik, agle steps se related yeh wording mili:\n$snippets\n\nSubmission aur deadline official insurer channel se verify karein.',
          _ => 'Aapke saved document ka short summary:\n$snippets\n\nYeh summary sirf locally saved text par based hai.',
        },
      SathiLanguageMode.hindi => kind == 'prepare_reconsideration'
          ? 'सेव दस्तावेज़ की संबंधित पंक्तियों के आधार पर एक संपादन योग्य पुनर्विचार ड्राफ्ट बनाया है। यह केवल ड्राफ्ट है; बीमा कंपनी को कुछ भी जमा नहीं किया गया।\n$snippets'
          : 'आपके फोन पर सेव दस्तावेज़ में यह संबंधित टेक्स्ट मिला:\n$snippets\n\nयह उत्तर केवल स्थानीय OCR टेक्स्ट पर आधारित है; बीमा कंपनी का लाइव रिकॉर्ड सत्यापित नहीं हुआ।',
      SathiLanguageMode.english => kind == 'prepare_reconsideration'
          ? 'I prepared an editable reconsideration draft using relevant lines from your saved document. This is only a draft; nothing was submitted to the insurer.\n$snippets'
          : 'I found this relevant wording in the document saved on your phone:\n$snippets\n\nThis answer is based only on local OCR text; no live insurer record was verified.',
    };
  }

  SathiAgentReply _documentAnswer(
    String question,
    List<_LocalExcerpt> excerpts,
    SathiLanguageMode language,
    String intent,
  ) {
    final evidence = excerpts.map((e) => '${e.title}: “${e.text}”').toList();
    final snippets = excerpts.take(3).map((e) => '• ${e.text}').join('\n');
    final answer = switch (language) {
      SathiLanguageMode.hinglish => 'Maine aapke phone par saved document ka relevant text dhoonda. Yeh summary usi text par based hai, live insurer record par nahi:\n$snippets\n\nNext step: decision letter ke exact reason ko bill/discharge summary se compare karein. Agar aapka sawal current claim status ke baare mein hai, woh insurer se live verify nahi hua hai.',
      SathiLanguageMode.hindi => 'मुझे आपके फोन पर सेव दस्तावेज़ में यह संबंधित टेक्स्ट मिला। यह उत्तर उसी टेक्स्ट पर आधारित है, बीमा कंपनी के लाइव रिकॉर्ड पर नहीं:\n$snippets\n\nअगला कदम: निर्णय-पत्र में बताए गए कारण को बिल और डिस्चार्ज समरी से मिलाएँ। वर्तमान क्लेम स्टेटस बीमा कंपनी से लाइव सत्यापित नहीं हुआ है।',
      SathiLanguageMode.english => 'I found relevant text in a document saved on this phone. This answer is based only on that text, not a live insurer record:\n$snippets\n\nNext step: compare the reason in the decision letter with your bill and discharge summary. The current claim status has not been verified with the insurer.',
    };
    final draft = intent == 'prepare_reconsideration' ? _localDraft(excerpts, language) : '';
    return SathiAgentReply(
      answer: answer,
      intent: intent,
      actionIndex: intent == 'prepare_reconsideration' ? 4 : (intent == 'required_documents' || intent == 'document_review' ? 2 : 1),
      actionLabel: intent == 'prepare_reconsideration' ? (language == SathiLanguageMode.hindi ? 'ड्राफ्ट देखें' : 'Review local draft') : (intent == 'required_documents' || intent == 'document_review' ? 'Open documents' : 'Review claim'),
      mode: 'local_document_search',
      notice: 'ON DEVICE · Search ran locally. No document text or question was sent online.',
      draft: draft,
      evidenceUsed: evidence,
    );
  }

  String _ensureRequestForReview(String draft) {
    final clean = draft.trim();
    if (clean.isEmpty) return clean;
    if (RegExp(r'\brequest\s+for\s+review\b', caseSensitive: false).hasMatch(clean)) {
      return clean;
    }
    final normalised = clean.replaceAll(
      RegExp(r'\brequest\s+to\s+review\b', caseSensitive: false),
      'request for review',
    );
    if (RegExp(r'\brequest\s+for\s+review\b', caseSensitive: false).hasMatch(normalised)) {
      return normalised;
    }
    return 'Subject: Request for review of health insurance claim [Claim Reference]\n\n$clean';
  }

  String _localDraft(List<_LocalExcerpt> excerpts, SathiLanguageMode language) {
    final supportingText = excerpts.take(2).map((e) => e.text).join('\n');
    return switch (language) {
      SathiLanguageMode.hinglish => '''Subject: Request for review of health insurance claim [Claim Reference]

Dear Claims Team,

I request a review of the decision on claim [Claim Reference]. The decision letter/document saved with me contains the following relevant wording:
"$supportingText"

Please clarify the exact policy wording relied upon, identify any remaining documents required, and confirm the official process and deadline for reconsideration. I will provide supporting records through your official secure channel.

This is an editable draft. Please verify all facts, replace bracketed fields, and attach the correct evidence before sending.

Regards,
[Name]''',
      SathiLanguageMode.hindi => '''विषय: स्वास्थ्य बीमा क्लेम [क्लेम रेफरेंस] की दोबारा समीक्षा का अनुरोध

आदरणीय क्लेम टीम,

कृपया मेरे क्लेम [क्लेम रेफरेंस] पर दिए गए निर्णय की समीक्षा करें। मेरे पास सुरक्षित निर्णय-पत्र/दस्तावेज़ में यह संबंधित टेक्स्ट है:
"$supportingText"

कृपया लागू पॉलिसी की सटीक शर्त, यदि कोई दस्तावेज़ बाकी है, और दोबारा समीक्षा की आधिकारिक प्रक्रिया व समय-सीमा स्पष्ट करें। आवश्यक दस्तावेज़ मैं आपके आधिकारिक सुरक्षित माध्यम से दूँगा/दूँगी।

भेजने से पहले सभी तथ्यों की जाँच करें, खाली स्थान भरें और सही प्रमाण जोड़ें। यह केवल ड्राफ्ट है, भेजा नहीं गया है।

सादर,
[नाम]''',
      SathiLanguageMode.english => '''Subject: Request for review of health insurance claim [Claim Reference]

Dear Claims Team,

I request a review of the decision on claim [Claim Reference]. The relevant wording from the document saved on my device is:
"$supportingText"

Please identify the exact policy wording relied upon, any additional documents needed, and the official reconsideration procedure and deadline. I will provide supporting records through your official secure channel.

This is an editable draft. Verify every fact, replace bracketed fields, and attach the correct evidence before sending.

Regards,
[Name]''',
    };
  }

  SathiAgentReply? _offlineFaq(String question, SathiLanguageMode language) {
    final q = question.toLowerCase();
    String? answer;
    if (_hasAny(q, const ['waiting period', 'waiting-period', 'वेटिंग पीरियड', 'प्रतीक्षा अवधि'])) {
      answer = switch (language) {
        SathiLanguageMode.hinglish => 'Waiting period policy mein diya gaya woh time hota hai jisme kuch illnesses ya treatments cover nahi hote, ya limited cover mil sakta hai. Exact duration, exceptions aur pre-existing disease rules aapki policy wording par depend karte hain. Isliye apni policy ka clause locally check karein.',
        SathiLanguageMode.hindi => 'वेटिंग पीरियड पॉलिसी में दिया गया समय है, जिसके दौरान कुछ बीमारियाँ या उपचार कवर नहीं होते या सीमित कवर मिल सकता है। सही अवधि और अपवाद आपकी पॉलिसी की शर्तों पर निर्भर करते हैं।',
        SathiLanguageMode.english => 'A waiting period is a period specified by a policy during which certain illnesses or treatments may not be covered, or may have limited cover. The exact period and exceptions depend on your own policy wording.',
      };
    } else if (_hasAny(q, const ['co-pay', 'copay', 'co pay', 'सह भुगतान'])) {
      answer = switch (language) {
        SathiLanguageMode.hinglish => 'Co-pay ka matlab hai eligible bill ka ek hissa aap pay karte hain aur baaki insurer policy ke rules ke hisaab se pay karta hai. Percentage aur kis expense par apply hota hai, woh aapke policy document se hi confirm karein.',
        SathiLanguageMode.hindi => 'को-पे का मतलब है कि पात्र बिल का एक हिस्सा आप देते हैं और बाकी पॉलिसी के नियमों के अनुसार बीमा कंपनी देती है। प्रतिशत और लागू खर्च पॉलिसी में जाँचें।',
        SathiLanguageMode.english => 'A co-pay is the share of an eligible bill that you pay yourself; the insurer considers the remaining eligible amount under the policy terms. Check your policy for the percentage and which expenses it applies to.',
      };
    } else if (_hasAny(q, const ['deductible', 'डिडक्टिबल'])) {
      answer = switch (language) {
        SathiLanguageMode.hinglish => 'Deductible woh amount hai jo policy ke rules ke mutabik insurer ke pay karne se pehle aapko khud bear karna pad sakta hai. Iski calculation aur co-pay se difference policy mein check karein.',
        SathiLanguageMode.hindi => 'डिडक्टिबल वह राशि है जिसे पॉलिसी के नियमों के अनुसार बीमा कंपनी के भुगतान से पहले आपको खुद वहन करना पड़ सकता है। इसकी गणना पॉलिसी में जाँचें।',
        SathiLanguageMode.english => 'A deductible is an amount you may need to pay before the insurer pays eligible expenses, as defined by the policy. Check the wording to understand how it differs from a co-pay.',
      };
    } else if (_hasAny(q, const ['cashless', 'reimbursement', 'कैशलेस', 'रीइम्बर्स'])) {
      answer = switch (language) {
        SathiLanguageMode.hinglish => 'Cashless mein, eligible treatment network hospital mein insurer/TPA ki approval process ke through settle ho sakta hai. Reimbursement mein aam taur par aap pehle bill pay karte hain aur baad mein documents ke saath claim submit karte hain. Network, pre-authorisation aur policy terms zaroor check karein.',
        SathiLanguageMode.hindi => 'कैशलेस में नेटवर्क अस्पताल पर पात्र खर्च बीमा कंपनी/TPA की मंज़ूरी प्रक्रिया के ज़रिए सेटल हो सकता है। रीइम्बर्समेंट में आम तौर पर पहले बिल दिया जाता है और बाद में दस्तावेज़ों के साथ दावा किया जाता है।',
        SathiLanguageMode.english => 'With cashless treatment, eligible costs at a network hospital may be settled through the insurer/TPA approval process. With reimbursement, you usually pay first and submit a claim with supporting documents. Network status, pre-authorisation and policy terms still matter.',
      };
    } else if (_hasAny(q, const ['what documents', 'required documents', 'documents needed', 'kaun se document', 'kaunse document', 'kaun se kagaz', 'कौन से दस्तावेज', 'कौन से कागज'])) {
      answer = switch (language) {
        SathiLanguageMode.hinglish => 'General starter checklist: claim form, policy/e-card details, itemised hospital bill, payment receipts (if paid), discharge summary, prescriptions and relevant test reports. Exact list cashless/reimbursement, insurer, hospital and policy ke hisaab se badal sakti hai. Apne decision letter aur insurer ki official checklist ko priority dein.',
        SathiLanguageMode.hindi => 'सामान्य सूची: क्लेम फॉर्म, पॉलिसी/ई-कार्ड, मदवार अस्पताल बिल, भुगतान रसीदें (यदि भुगतान किया है), डिस्चार्ज समरी, प्रिस्क्रिप्शन और संबंधित जाँच रिपोर्ट। सही सूची बीमा कंपनी, पॉलिसी और क्लेम के प्रकार पर निर्भर करती है।',
        SathiLanguageMode.english => 'A general starter checklist includes the claim form, policy/e-card details, itemised hospital bill, receipts if you paid, discharge summary, prescriptions and relevant test reports. The exact list depends on the insurer, policy and claim type; use the insurer’s own checklist first.',
      };
    } else if (_hasAny(q, const ['why do claims get rejected', 'why are claims rejected', 'common reasons claims reject', 'claim rejection reasons generally', 'claims reject kyun hote', 'क्लेम क्यों रिजेक्ट होते हैं'])) {
      answer = switch (language) {
        SathiLanguageMode.hinglish => 'Common general reasons can include missing paperwork, mismatch in submitted information, exclusions, waiting periods, limits, or insufficient supporting records. Yeh general examples hain—not an explanation of your own claim. Apne case ka reason samajhne ke liye decision letter ka text locally add karein.',
        SathiLanguageMode.hindi => 'सामान्य कारणों में अधूरे दस्तावेज़, जानकारी में अंतर, पॉलिसी अपवाद, वेटिंग पीरियड, सीमा या पर्याप्त प्रमाण न होना शामिल हो सकता है। ये सामान्य उदाहरण हैं, आपके क्लेम का सत्यापित कारण नहीं।',
        SathiLanguageMode.english => 'Common general reasons can include missing paperwork, mismatched information, exclusions, waiting periods, limits, or insufficient supporting records. These are examples, not an explanation of your specific claim. To discuss your case, add the decision-letter text locally.',
      };
    }
    if (answer == null) return null;
    return SathiAgentReply(
      answer: answer,
      intent: 'general_help',
      actionIndex: _hasAny(q, const ['document', 'kagaz', 'दस्तावेज']) ? 2 : 1,
      actionLabel: _hasAny(q, const ['document', 'kagaz', 'दस्तावेज']) ? 'Open documents' : 'Back to Sathi',
      mode: 'local_faq',
      notice: 'OFFLINE GUIDE · Answer used a built-in general guide, not your policy or an insurer record.',
    );
  }

  String _intent(String question) {
    final q = question.toLowerCase();
    if (_hasAny(q, const ['draft', 'appeal', 'reconsider', 'letter bana', 'reply likh', 'अपील', 'ड्राफ्ट'])) return 'prepare_reconsideration';
    if (_hasAny(q, const ['document', 'docs', 'kagaz', 'दस्तावेज', 'bill', 'missing', 'submit', 'jama'])) return 'required_documents';
    if (_hasAny(q, const ['status', 'track', 'kaha tak', 'kahan tak', 'स्टेटस', 'स्थिति'])) return 'claim_status';
    if (_hasAny(q, const ['summarise', 'summarize', 'summary', 'explain this', 'document mein', 'letter mein', 'short mein'])) return 'document_review';
    if (_hasAny(q, const ['why', 'reason', 'kyun', 'kyu', 'kis wajah', 'क्यों', 'कारण'])) return 'explain_rejection';
    if (_hasAny(q, const ['when', 'date', 'kab', 'deadline', 'last date', 'कब', 'तारीख'])) return 'claim_date_or_deadline';
    if (_hasAny(q, const ['policy', 'covered', 'coverage', 'exclusion', 'पॉलिसी', 'कवरेज'])) return 'policy_terms';
    if (_hasAny(q, const ['hospital', 'insurer', 'company name', 'अस्पताल', 'बीमा कंपनी'])) return 'document_identity';
    return 'document_question';
  }

  bool _looksPersonalOrSensitive(String input) {
    if (PiiMasker.mask(input) != input) return true;
    if (RegExp(r'\b\d{4,}\b').hasMatch(input)) return true;
    final q = input.toLowerCase();
    const personalTerms = [
      'my ', 'my claim', 'my policy', 'my document', 'my hospital', 'my bill',
      'mera ', 'meri ', 'mere ', 'mujhe ', 'maine ', 'hamara ', 'hamari ',
      'claim status', 'claim number', 'claim id', 'policy number', 'policy id',
      'claim reject', 'claim rejected', 'claim rejection', 'claim partly paid',
      'approved amount', 'requested amount', 'my insurer', 'my decision letter',
      'this document', 'this letter', 'attached document', 'uploaded document',
      'according to my', 'according to this', 'is letter mein', 'mere document',
      'meri policy', 'mera claim', 'claim ka status', 'claim ka reason', 'policy mein',
      'policy me', 'hospital bill', 'decision letter', 'rejection letter',
      'क्लेम स्टेटस', 'मेरा क्लेम', 'मेरी पॉलिसी', 'मेरे दस्तावेज', 'इस पत्र', 'इस दस्तावेज',
    ];
    if (_hasAny(q, personalTerms)) return true;
    // Medical/financial facts written in first person are private even if they
    // contain no phone number, email, or government identifier.
    final firstPerson = _hasAny(q, const [
      'i have ', 'i had ', 'i was diagnosed', 'i take ', 'my diagnosis', 'my treatment',
      'my medication', 'my surgery', 'my medical', 'my lab report', 'my test result',
      'my prescription', 'my health', 'my admission', 'my discharge', 'my premium',
      'i paid ', 'i was admitted', 'mujhe diabetes', 'mujhe cancer', 'mujhe heart',
      'mujhe kidney', 'mujhe operation', 'mujhe surgery', 'mera ilaaj', 'meri bimari',
      'meri report', 'meri dawa', 'meri surgery', 'meri diagnosis', 'mere treatment',
      'मुझे डायबिटीज', 'मुझे कैंसर', 'मेरा इलाज', 'मेरी बीमारी', 'मेरी रिपोर्ट',
      'मेरी दवा', 'मेरी सर्जरी', 'मेरी जांच', 'मेरी जाँच', 'मेरी मेडिकल',
    ]);
    final firstPersonMedical = _hasAny(q, const [
      'i have ', 'i had ', 'i was diagnosed', 'i take ', 'i paid ', 'i was admitted',
      'my diagnosis', 'my treatment', 'my medication', 'my surgery', 'my medical',
      'my test result', 'mujhe diabetes', 'mujhe cancer', 'mujhe kidney',
      'mujhe surgery', 'mera ilaaj', 'meri bimari', 'meri report', 'meri dawa',
      'मुझे डायबिटीज', 'मुझे कैंसर', 'मेरा इलाज', 'मेरी बीमारी', 'मेरी रिपोर्ट', 'मेरी दवा',
    ]);
    final healthOrFinance = _hasAny(q, const [
      'diabetes', 'cancer', 'kidney disease', 'heart disease', 'diagnosis', 'medication',
      'medicine', 'treatment', 'surgery', 'medical report', 'lab report', 'test result',
      'prescription', 'hospitalized', 'hospitalised', 'admitted', 'premium amount',
      'loan amount', 'medical bill', 'इलाज', 'बीमारी', 'दवा', 'रिपोर्ट', 'सर्जरी', 'अस्पताल',
    ]);
    if (firstPersonMedical && healthOrFinance) return true;
    final medicalOrFinancial = _hasAny(q, const [
      'diabetes', 'cancer', 'hiv', 'kidney disease', 'heart disease', 'diagnosis',
      'medication', 'medicine', 'treatment', 'surgery', 'medical report', 'lab report',
      'test result', 'prescription', 'hospitalized', 'hospitalised', 'admitted',
      'premium amount', 'loan amount', 'medical bill', 'इलाज', 'बीमारी', 'दवा', 'रिपोर्ट',
    ]);
    if (firstPerson && medicalOrFinancial) return true;
    // Claim-specific decisions, dates, and amounts are private by default unless
    // locally answered from the user's saved text. General definitions can use FAQ/cloud.
    if (q.contains('claim') && _hasAny(q, const ['reject', 'rejected', 'rejection', 'approved', 'status', 'amount', 'reason', 'when will', 'why was'])) return true;
    return false;
  }

  SathiAgentReply _localOnlyNotFound(SathiLanguageMode language, {required bool sensitive}) {
    return SathiAgentReply(
      answer: switch (language) {
        SathiLanguageMode.hinglish => sensitive
            ? 'Mujhe is sawal ka jawab aapke jode gaye documents mein nahi mila. Aap sambandhit letter ya bill bhi add kar sakte hain; main usmein dobara dhoondhunga/dhoondhungi.'
            : 'Local data mein abhi jawab nahi mila. Is Private mode mein kuch bhi online nahi bheja gaya. Agar yeh general sawal hai, “General information” mode select karke online lookup ko alag se allow karein.',
        SathiLanguageMode.hindi => sensitive
            ? 'आपके जोड़े गए दस्तावेज़ों में इस सवाल का जवाब नहीं मिला। आप संबंधित पत्र या बिल भी जोड़ सकते हैं; मैं उसमें फिर से खोजूँगा/खोजूँगी।'
            : 'स्थानीय डेटा में जवाब नहीं मिला और इस मोड में कुछ भी ऑनलाइन नहीं भेजा गया। अगर सवाल सामान्य जानकारी के बारे में है, तो “General information” मोड चुनें और ऑनलाइन खोज की अनुमति दें।',
        SathiLanguageMode.english => sensitive
            ? 'I could not find the answer in the documents you added. You can add the relevant letter or bill, and I will look for the answer again.'
            : 'I could not find an offline answer. Nothing was sent online in Private mode. If this is a general-information question, select “General information” and separately allow online lookup.',
      },
      intent: 'general_help',
      actionIndex: 2,
      actionLabel: language == SathiLanguageMode.hindi ? 'दस्तावेज़ खोलें' : 'Open documents',
      mode: 'local_private_no_match',
      notice: 'PRIVATE · LOCAL ONLY · No private data was sent online.',
    );
  }

  bool _hasAny(String input, List<String> terms) => terms.any(input.contains);
}

class _LocalDocument {
  const _LocalDocument({required this.title, required this.text});
  final String title;
  final String text;
}

class _LocalExcerpt {
  const _LocalExcerpt({required this.title, required this.text, required this.score});
  final String title;
  final String text;
  final int score;
}
