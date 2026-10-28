import 'package:flutter/material.dart';

import '../../../../core/security/privacy_settings_store.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/sathi_card.dart';

class TechnologyPage extends StatefulWidget {
  const TechnologyPage({super.key});

  @override
  State<TechnologyPage> createState() => _TechnologyPageState();
}

class _TechnologyPageState extends State<TechnologyPage> {
  final _privacyStore = PrivacySettingsStore();
  bool _consentLoading = true;
  bool _allowCloudConsent = false;
  bool _allowVoiceConsent = false;
  bool _savingConsent = false;
  bool _savingVoiceConsent = false;
  static const _apiBaseUrl = String.fromEnvironment('SATHI_API_BASE_URL', defaultValue: '');
  bool get _backendConfigured => _apiBaseUrl.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _loadConsent();
  }

  Future<void> _loadConsent() async {
    try {
      final values = await Future.wait<bool>([
        _privacyStore.readCloudConsent(),
        _privacyStore.readVoiceConsent(),
      ]);
      if (!mounted) return;
      setState(() {
        _allowCloudConsent = values[0];
        _allowVoiceConsent = values[1];
        _consentLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _consentLoading = false);
    }
  }

  Future<void> _saveConsent(bool value) async {
    setState(() {
      _savingConsent = true;
      _allowCloudConsent = value;
    });
    try {
      await _privacyStore.writeCloudConsent(value);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(value
            ? (_backendConfigured ? 'Cloud text analysis enabled. The backend still needs a valid Gemini key to use the model.' : 'Preference saved, but no backend URL is configured. Sathi will continue using local demo rules.')
            : 'Cloud text analysis switched off. Local demo rules will be used.'),
      ));
    } catch (error) {
      if (!mounted) return;
      setState(() => _allowCloudConsent = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save privacy preference: $error')),
      );
    } finally {
      if (mounted) setState(() => _savingConsent = false);
    }
  }


  Future<void> _saveVoiceConsent(bool value) async {
    setState(() {
      _savingVoiceConsent = true;
      _allowVoiceConsent = value;
    });
    try {
      await _privacyStore.writeVoiceConsent(value);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(value
            ? (_backendConfigured ? 'AI Hinglish voice enabled. Short recordings will be sent to your configured Sathi backend for transcription.' : 'Preference saved, but no backend URL is configured. Device speech will be used instead.')
            : 'Cloud voice transcription switched off. Device speech will be used instead.'),
      ));
    } catch (error) {
      if (!mounted) return;
      setState(() => _allowVoiceConsent = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save voice preference: $error')),
      );
    } finally {
      if (mounted) setState(() => _savingVoiceConsent = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('How Sathi works')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        children: [
          Text('TECHNOLOGY AND PRIVACY', style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: AppColors.teal, fontWeight: FontWeight.w900, letterSpacing: 1.4,
          )),
          const SizedBox(height: 8),
          Text('Private by default. Cloud AI only when you choose.', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 8),
          const Text('You do not need to understand AI to use Sathi. Add your document, check the highlighted text, read the explanation, and choose the next step yourself.', style: TextStyle(color: AppColors.muted, height: 1.5)),
          const SizedBox(height: 18),
          const _StackLayer(
            title: 'Client app', icon: Icons.phone_android_rounded, subtitle: 'What you use',
            chips: ['Flutter', 'Dart', 'Platform Channels', 'BLoC', 'Secure storage'],
            note: 'The app screens and state use Flutter + BLoC. Secure storage is used for the privacy preference, not for claim files.',
            active: {'Flutter', 'Dart', 'BLoC', 'Secure storage'},
          ),
          const SizedBox(height: 12),
          const _StackLayer(
            title: 'On-device AI', icon: Icons.memory_rounded, subtitle: 'Work that can stay on your phone',
            chips: ['Google Gemma', 'MediaPipe LLM*', 'On-device OCR', 'PII masking', 'Voice input'],
            note: 'Device speech input is wired with locale discovery and Hindi-first Hinglish fallback. For better Hindi-English code-switching, an optional Gemini transcription endpoint records a short WAV only after separate voice consent. OCR defaults to Latin script; Devanagari OCR needs additional native model configuration. On-device Gemma is not bundled.',
            active: {'On-device OCR', 'PII masking', 'Voice input'},
          ),
          const SizedBox(height: 12),
          const _StackLayer(
            title: 'Cloud AI', icon: Icons.cloud_outlined, subtitle: 'Explain using verified policy sources',
            chips: ['LLM API', 'RAG pipeline', 'Vector search', 'Clause citations', 'Guardrails'],
            note: 'A real Gemini-backed agent service is included in backend/main.py. It uses a model planning step and executes only four allow-listed demo tools. Gemini is active only when you configure GEMINI_API_KEY and run the backend. RAG, vector search, verified clause retrieval and live insurer APIs are not connected yet.',
            active: <String>{},
          ),
          const SizedBox(height: 12),
          const _StackLayer(
            title: 'Platform', icon: Icons.hub_outlined, subtitle: 'Connect to insurer systems safely',
            chips: ['REST + WebSocket', 'Firebase', 'Partner APIs', 'Analytics', 'CI/CD'],
            note: 'A REST adapter and WebSocket example are supplied. Firebase and partner APIs need project credentials, sandbox access, consent rules and server-side authorisation. A GitHub Actions workflow is included.',
            active: {'REST + WebSocket', 'CI/CD'},
          ),
          const SizedBox(height: 14),
          SathiCard(color: const Color(0xFFFFF5DD), child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.info_outline_rounded, color: Color(0xFF9A6700)),
            SizedBox(width: 10),
            Expanded(child: Text('Model status: the cloud Gemini agent code is included, but it runs only when you start the backend and configure a valid GEMINI_API_KEY. On-device Gemma is not bundled. MediaPipe LLM Inference is in maintenance-only mode; evaluate LiteRT-LM for a new on-device model. The current demo agent uses fictional claim data and no real policy retrieval.', style: TextStyle(color: AppColors.ink, fontSize: 12, height: 1.5))),
          ])),
          const SizedBox(height: 16),
          SathiCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Row(children: [Icon(Icons.lock_outline_rounded, color: AppColors.teal), SizedBox(width: 8), Expanded(child: Text('Your privacy choice', style: TextStyle(color: AppColors.navy, fontWeight: FontWeight.w900, fontSize: 16)))]),
            const SizedBox(height: 8),
            Text(_backendConfigured
                ? 'The app can call the configured Sathi backend. Text goes to Gemini only when this switch is on and the backend has a valid API key. The backend uses fictional demo claim data; no live insurer is connected.'
                : 'A backend URL is not configured. Turning this on stores your preference only; the app will continue using local demo rules until SATHI_API_BASE_URL is set.', style: const TextStyle(color: AppColors.muted, fontSize: 12, height: 1.5)),
            const SizedBox(height: 10),
            if (_consentLoading)
              const LinearProgressIndicator()
            else
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Allow redacted cloud analysis', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                subtitle: Text(_allowCloudConsent ? (_backendConfigured ? 'On · backend URL configured; Gemini key still required server-side' : 'On · no backend URL yet, local rules remain active') : 'Off · use local demo guidance'),
                value: _allowCloudConsent,
                onChanged: _savingConsent ? null : _saveConsent,
              ),
            if (_savingConsent) const LinearProgressIndicator(),
            const Divider(height: 24),
            const Text('AI Hinglish voice transcription', style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.navy, fontSize: 14)),
            const SizedBox(height: 5),
            const Text('When enabled and a backend is configured, a short microphone recording is uploaded to the Sathi backend and transcribed by Gemini with Hindi-English code-switching instructions. The app does not deliberately persist recordings, but upload frameworks may buffer them temporarily while processing. Do not use real health documents or sensitive identifiers in the hackathon demo.', style: TextStyle(color: AppColors.muted, fontSize: 12, height: 1.5)),
            const SizedBox(height: 8),
            if (_consentLoading)
              const LinearProgressIndicator()
            else
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Allow cloud voice transcription', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                subtitle: Text(_allowVoiceConsent ? (_backendConfigured ? 'On · recording sent to configured backend when you tap the microphone' : 'On · no backend URL, device speech will be used') : 'Off · microphone uses device speech recognition'),
                value: _allowVoiceConsent,
                onChanged: _savingVoiceConsent ? null : _saveVoiceConsent,
              ),
            if (_savingVoiceConsent) const LinearProgressIndicator(),
            const SizedBox(height: 8),
            Text('Backend status: ${_backendConfigured ? _apiBaseUrl : 'not configured'}', style: const TextStyle(color: AppColors.muted, fontSize: 10)),
          ])),
          const SizedBox(height: 14),
          const Text('Easy-to-follow journey', style: TextStyle(color: AppColors.navy, fontWeight: FontWeight.w900, fontSize: 17)),
          const SizedBox(height: 10),
          const _StepLine(number: '1', title: 'Add a document', description: 'Take a photo or choose an image/PDF from your phone.'),
          const _StepLine(number: '2', title: 'Read and check', description: 'For images, on-device OCR can extract text. Common identifiers are masked in the preview.'),
          const _StepLine(number: '3', title: 'Understand the reason', description: 'With the backend running and API key configured, the Gemini agent selects a safe demo tool and explains its result. Without that setup, local rules are used. Verified policy RAG is not yet connected.'),
          const _StepLine(number: '4', title: 'Review the next step', description: 'Edit your draft, submit it through the insurer’s official channel, then record your progress.'),
          const SizedBox(height: 12),
          FilledButton.icon(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back_rounded), label: const Text('Back to Sathi')),
        ],
      ),
    );
  }
}

class _StackLayer extends StatelessWidget {
  const _StackLayer({required this.title, required this.icon, required this.subtitle, required this.chips, required this.note, required this.active});

  final String title;
  final IconData icon;
  final String subtitle;
  final List<String> chips;
  final String note;
  final Set<String> active;


  // Future<void> _saveVoiceConsent(bool value) async {
  //   setState(() {
  //     _savingVoiceConsent = true;
  //     _allowVoiceConsent = value;
  //   });
  //   try {
  //     await _privacyStore.writeVoiceConsent(value);
  //     if (!mounted) return;
  //     ScaffoldMessenger.of(context).showSnackBar(SnackBar(
  //       content: Text(value
  //           ? (_backendConfigured ? 'AI Hinglish voice enabled. Short recordings will be sent to your configured Sathi backend for transcription.' : 'Preference saved, but no backend URL is configured. Device speech will be used instead.')
  //           : 'Cloud voice transcription switched off. Device speech will be used instead.'),
  //     ));
  //   } catch (error) {
  //     if (!mounted) return;
  //     setState(() => _allowVoiceConsent = false);
  //     ScaffoldMessenger.of(context).showSnackBar(
  //       SnackBar(content: Text('Could not save voice preference: $error')),
  //     );
  //   } finally {
  //     if (mounted) setState(() => _savingVoiceConsent = false);
  //   }
  // }

  @override
  Widget build(BuildContext context) {
    return SathiCard(padding: const EdgeInsets.all(15), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(width: 38, height: 38, decoration: BoxDecoration(color: AppColors.mint, borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: AppColors.teal)),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(color: AppColors.navy, fontWeight: FontWeight.w900, fontSize: 15)),
          Text(subtitle, style: const TextStyle(color: AppColors.muted, fontSize: 11)),
        ])),
      ]),
      const SizedBox(height: 12),
      Wrap(spacing: 7, runSpacing: 7, children: chips.map((chip) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(color: active.contains(chip) ? AppColors.mint : const Color(0xFFF1EBDD), borderRadius: BorderRadius.circular(22)),
        child: Text(chip, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: active.contains(chip) ? AppColors.tealDark : AppColors.navy)),
      )).toList()),
      const SizedBox(height: 12),
      Text(note, style: const TextStyle(color: AppColors.muted, fontSize: 11, height: 1.5)),
    ]));
  }
}

class _StepLine extends StatelessWidget {
  const _StepLine({required this.number, required this.title, required this.description});
  final String number;
  final String title;
  final String description;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(width: 28, height: 28, alignment: Alignment.center, decoration: const BoxDecoration(color: AppColors.mint, shape: BoxShape.circle), child: Text(number, style: const TextStyle(color: AppColors.tealDark, fontWeight: FontWeight.w900))),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(color: AppColors.navy, fontWeight: FontWeight.w800, fontSize: 13)),
        const SizedBox(height: 3),
        Text(description, style: const TextStyle(color: AppColors.muted, height: 1.45, fontSize: 12)),
      ])),
    ]),
  );
}
