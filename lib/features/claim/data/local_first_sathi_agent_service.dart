import '../../../core/security/pii_masker.dart';
import '../../../core/storage/local_private_vault.dart';
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
        _vault = vault ?? LocalPrivateVault();

  final SathiAgentService _cloudService;
  final LocalPrivateVault _vault;

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

  List<_LocalExcerpt> _findRelevantExcerpts(String question, List<_LocalDocument> docs) {
    if (docs.isEmpty) return const [];
    final terms = _keywords(question);
    if (terms.isEmpty) return const [];
    final expanded = _expandQuery(question, terms);
    final results = <_LocalExcerpt>[];
    final sentences = RegExp(r'(?<=[.!?।])\s+|\n+');

    for (final doc in docs) {
      final lines = doc.text.split(sentences).map((s) => s.trim()).where((s) => s.length > 18).toList();
      for (final line in lines) {
        final contentTerms = _keywords(line);
        var score = contentTerms.intersection(expanded).length;
        final titleTerms = _keywords(doc.title);
        score += titleTerms.intersection(terms).length;
        if (score > 0) results.add(_LocalExcerpt(title: doc.title, text: line, score: score));
      }
    }

    // For explicit document-summary requests, return local excerpts even if the
    // question has few matching terms. This is retrieval, not model-generated QA.
    final asksToSummarise = _hasAny(question.toLowerCase(), const [
      'summarise this', 'summarize this', 'explain this document', 'what does this say',
      'is letter mein', 'yeh letter', 'ye letter', 'document samjhao', 'letter samjhao',
      'इस पत्र का मतलब', 'इस दस्तावेज़ को समझाओ',
    ]);
    if (results.isEmpty && asksToSummarise) {
      for (final doc in docs.take(2)) {
        for (final line in doc.text.split(sentences).map((s) => s.trim()).where((s) => s.length > 18).take(3)) {
          results.add(_LocalExcerpt(title: doc.title, text: line, score: 1));
        }
      }
    }

    results.sort((a, b) => b.score.compareTo(a.score));
    final unique = <String>{};
    return results.where((item) => unique.add('${item.title}|${item.text}')).take(4).toList();
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
    if (_hasAny(text, const ['reject', 'rejected', 'rejection', 'deny', 'denied', 'declined', 'रिजेक्ट', 'अस्वीकृत', 'क्यों नहीं'])) {
      expanded.addAll(const ['reject', 'rejected', 'rejection', 'deny', 'denied', 'declined', 'reason', 'repudiated', 'disallowed', 'not payable', 'missing', 'shortfall', 'रिजेक्ट', 'अस्वीकृत', 'कारण', 'अस्वीकार']);
    }
    if (_hasAny(text, const ['document', 'documents', 'docs', 'kagaz', 'कागज', 'दस्तावेज', 'paper', 'bill'])) {
      expanded.addAll(const ['document', 'documents', 'bill', 'discharge', 'summary', 'invoice', 'submitted', 'missing', 'required', 'कागज', 'दस्तावेज', 'बिल', 'रिपोर्ट']);
    }
    if (_hasAny(text, const ['waiting period', 'waiting', 'प्रतीक्षा अवधि', 'वेटिंग'])) {
      expanded.addAll(const ['waiting', 'period', 'months', 'years', 'pre-existing', 'waiting-period']);
    }
    if (_hasAny(text, const ['coverage', 'covered', 'cover', 'policy', 'कवर', 'पॉलिसी', 'कवरेज'])) {
      expanded.addAll(const ['coverage', 'covered', 'cover', 'exclusion', 'limit', 'sub-limit', 'policy', 'कवरेज', 'पॉलिसी']);
    }
    return expanded;
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

  String _localDraft(List<_LocalExcerpt> excerpts, SathiLanguageMode language) {
    final supportingText = excerpts.take(2).map((e) => e.text).join('\n');
    return switch (language) {
      SathiLanguageMode.hinglish => '''Subject: Request to review health insurance claim [Claim Reference]

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
    if (_hasAny(q, const ['document', 'docs', 'kagaz', 'दस्तावेज', 'bill', 'missing'])) return 'required_documents';
    if (_hasAny(q, const ['status', 'track', 'kaha tak', 'kahan tak', 'स्टेटस', 'स्थिति'])) return 'claim_status';
    if (_hasAny(q, const ['summarise', 'summarize', 'explain this', 'document mein', 'letter mein'])) return 'document_review';
    return 'explain_rejection';
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
            ? 'Mujhe is private sawal ka jawab aapke phone par saved text mein nahi mila. Privacy ke liye maine aapka sawal, document ya OCR text online nahi bheja. Decision letter ko attach karke “Read text on device” karein, ya relevant text paste karein; phir main local text mein dhoondh sakta/sakti hoon.'
            : 'Local data mein abhi jawab nahi mila. Is Private mode mein kuch bhi online nahi bheja gaya. Agar yeh general sawal hai, “General information” mode select karke online lookup ko alag se allow karein.',
        SathiLanguageMode.hindi => sensitive
            ? 'आपके फोन पर सेव टेक्स्ट में इस निजी सवाल का जवाब नहीं मिला। आपकी गोपनीयता के लिए सवाल, दस्तावेज़ या OCR टेक्स्ट ऑनलाइन नहीं भेजा गया। निर्णय-पत्र जोड़कर “Read text on device” चलाएँ या संबंधित टेक्स्ट पेस्ट करें।'
            : 'स्थानीय डेटा में जवाब नहीं मिला और इस मोड में कुछ भी ऑनलाइन नहीं भेजा गया। अगर सवाल सामान्य जानकारी के बारे में है, तो “General information” मोड चुनें और ऑनलाइन खोज की अनुमति दें।',
        SathiLanguageMode.english => sensitive
            ? 'I could not find the answer in text saved on this phone. For privacy, I did not send your question, document, or OCR text online. Attach your decision letter and use “Read text on device”, or paste the relevant excerpt; I can then search it locally.'
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
