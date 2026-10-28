import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/security/privacy_settings_store.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/sathi_card.dart';
import '../providers/claim_controller.dart';

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
            ? (_backendConfigured ? 'Online general-information lookup enabled. Sathi still checks local data first and asks before each online question.' : 'Preference saved, but no backend URL is configured. Live AI will return a connection error until configured.')
            : 'Online lookup switched off. Sathi will stay on-device.'),
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
            ? (_backendConfigured ? 'Cloud voice enabled for General information mode. Sathi asks before every recording upload; Private mode stays device-only.' : 'Preference saved, but no backend URL is configured. Device speech will be used instead.')
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
          Text('Local-first. Online only when you choose.', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 8),
          const Text('You do not need to understand AI to use Sathi. Add your document, check the highlighted text, read the explanation, and choose the next step yourself.', style: TextStyle(color: AppColors.muted, height: 1.5)),
          const SizedBox(height: 18),
          const _StackLayer(
            title: 'Client app', icon: Icons.phone_android_rounded, subtitle: 'What you use',
            chips: ['Flutter', 'Dart', 'Platform Channels', 'BLoC', 'Secure storage'],
            note: 'The app screens and state use Flutter + BLoC. Claim text, drafts, timeline and app-copied documents are encrypted with AES-GCM in app-private storage; the encryption key is held in Android Keystore/iOS Keychain through secure storage.',
            active: {'Flutter', 'Dart', 'BLoC', 'Secure storage'},
          ),
          const SizedBox(height: 12),
          const _StackLayer(
            title: 'Local processing', icon: Icons.memory_rounded, subtitle: 'Private work that stays on your phone',
            chips: ['AES-GCM encrypted vault', 'Local document search', 'Offline FAQ', 'On-device OCR', 'Device speech'],
            note: 'The app stores copied attachments, PII-masked OCR text, draft letters and activity notes in an AES-GCM encrypted app-private vault. Local document search and a small offline guide work without the Gemini API. OCR runs on supported images on-device. Device speech is provided by Android/iOS; whether the OS speech service itself uses a network depends on device settings. No on-device generative Gemma model is installed in this build.',
            active: {'AES-GCM encrypted vault', 'Local document search', 'Offline FAQ', 'On-device OCR', 'Device speech'},
          ),
          const SizedBox(height: 12),
          const _StackLayer(
            title: 'Optional online information', icon: Icons.cloud_outlined, subtitle: 'Only for a general question after local lookup',
            chips: ['Gemini API', 'Question confirmation', 'No files attached', 'No chat history', 'No claim context'],
            note: 'The app searches the encrypted local vault and offline guide first. If nothing is found, it asks you to confirm the exact general question before sending it to Gemini. The online request contains only that question. OCR text, file names, document contents, claimContext and previous chat turns are never attached. Personal or claim-specific questions remain local-only. Verified policy RAG and insurer APIs are not connected.',
            active: {'Gemini API', 'Question confirmation', 'No files attached', 'No chat history', 'No claim context'},
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
            Expanded(child: Text('Model status: local document search and the offline FAQ work without internet; this is retrieval/rules, not an on-device generative LLM. Gemini is called only for a general-information question after local lookup, online consent, and a per-question confirmation. Only that question is sent; docs, OCR, claim context and chat history are excluded. If Gemini is unavailable, Sathi shows an error instead of inventing a response. On-device Gemma and insurer integrations are not bundled.', style: TextStyle(color: AppColors.ink, fontSize: 12, height: 1.5))),
          ])),
          const SizedBox(height: 16),
          SathiCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Row(children: [Icon(Icons.lock_outline_rounded, color: AppColors.teal), SizedBox(width: 8), Expanded(child: Text('Your privacy choice', style: TextStyle(color: AppColors.navy, fontWeight: FontWeight.w900, fontSize: 16)))]),
            const SizedBox(height: 8),
            Text(_backendConfigured
                ? 'This switch allows optional online lookup for a general-information question only. Sathi searches local data first and asks you to confirm the exact question before sending it. Only that question is sent to Gemini—no attachments, OCR text, claim details or chat history. Personal and claim-specific questions stay local even when this switch is on.'
                : 'A backend URL is not configured. Turning this on stores your preference only. Online general information also requires SATHI_API_BASE_URL, a running backend and a valid backend API key.', style: const TextStyle(color: AppColors.muted, fontSize: 12, height: 1.5)),
            const SizedBox(height: 10),
            if (_consentLoading)
              const LinearProgressIndicator()
            else
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Allow online general-information lookup', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                subtitle: Text(_allowCloudConsent ? (_backendConfigured ? 'On · backend URL set; Gemini key required server-side' : 'On · no backend URL; live answers unavailable') : 'Off · cloud AI is disabled'),
                value: _allowCloudConsent,
                onChanged: _savingConsent ? null : _saveConsent,
              ),
            if (_savingConsent) const LinearProgressIndicator(),
            const Divider(height: 24),
            const Text('AI Hinglish voice transcription', style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.navy, fontSize: 14)),
            const SizedBox(height: 5),
            const Text('Voice transcription is a separate, optional cloud feature. It is used only in General information mode, and Sathi shows a confirmation before each recording is uploaded for transcription. The audio itself leaves the device; never use this for names, diagnoses, policy/claim numbers, bills or private case details. In Private files mode, Sathi does not upload audio. Device speech recognition behaviour still depends on Android/iOS speech-service settings.', style: TextStyle(color: AppColors.muted, fontSize: 12, height: 1.5)),
            const SizedBox(height: 8),
            if (_consentLoading)
              const LinearProgressIndicator()
            else
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Allow optional cloud voice transcription', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                subtitle: Text(_allowVoiceConsent ? (_backendConfigured ? 'On · requires online-information consent too, General information mode, and a confirmation for each recording'  : 'On · no backend URL, device speech will be used') : 'Off · microphone uses device speech recognition'),
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
          const _StepLine(number: '3', title: 'Understand the reason', description: 'Sathi checks encrypted local documents and the offline guide first. For a general question only, online lookup requires consent and a confirmation showing exactly what will be sent. No files, OCR, claim context or chat history are attached. Verified policy retrieval and insurer status APIs are not yet connected.'),
          const _StepLine(number: '4', title: 'Review the next step', description: 'Edit your draft, submit it through the insurer’s official channel, then record your progress.'),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _consentLoading ? null : () => _confirmClearLocalData(context),
            icon: const Icon(Icons.delete_forever_outlined),
            label: const Text('Delete all Sathi local data'),
            style: OutlinedButton.styleFrom(foregroundColor: AppColors.red),
          ),
          const SizedBox(height: 8),
          const Text('This deletes Sathi’s encrypted app copies, saved OCR text, drafts, and local activity. It does not delete the original files in Photos or Downloads.', style: TextStyle(color: AppColors.muted, fontSize: 10, height: 1.45)),
          const SizedBox(height: 12),
                    FilledButton.icon(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back_rounded), label: const Text('Back to Sathi')),
        ],
      ),
    );
  }

  Future<void> _confirmClearLocalData(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete all local Sathi data?'),
        content: const Text('This permanently removes Sathi’s encrypted copies of documents, saved OCR text, drafts and local activity from this app on this device. It does not affect the original files in Photos/Downloads. This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
            child: const Text('Delete local data'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await context.read<ClaimCubit>().clearAllLocalData();
      await _privacyStore.writeCloudConsent(false);
      await _privacyStore.writeVoiceConsent(false);
      if (!mounted) return;
      setState(() {
        _allowCloudConsent = false;
        _allowVoiceConsent = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sathi local data and online-consent settings were cleared.')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not clear all local data. Check device storage and try again.')));
    }
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
