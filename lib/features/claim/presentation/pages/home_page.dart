import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/sathi_card.dart';
import '../providers/claim_controller.dart';
import 'sathi_assistant_card.dart';
import 'technology_page.dart';

/// Simple home flow: add the decision letter -> read it locally -> ask Sathi.
/// The UI never presents the list of optional document types as a required checklist.
class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.onNavigate});
  final ValueChanged<int> onNavigate;

  @override
  Widget build(BuildContext context) {
    final claim = context.watch<ClaimCubit>().state;
    final attachedCount = claim.documents.where((document) => document.uploaded).length;
    final readableDocuments = claim.documents
        .where((document) => (document.extractedText ?? '').trim().isNotEmpty)
        .toList();
    final decisionRows = claim.documents.where((document) => document.id == 'decision');
    final decisionLetter = decisionRows.isEmpty ? null : decisionRows.first;
    final decisionTextReady = (decisionLetter?.extractedText ?? '').trim().isNotEmpty;
    final decisionAttached = decisionLetter?.uploaded ?? false;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            height: 46,
            width: 46,
            decoration: BoxDecoration(color: AppColors.mint, borderRadius: BorderRadius.circular(15)),
            child: const Icon(Icons.support_agent_rounded, color: AppColors.teal, size: 27),
          ),
          const SizedBox(width: 12),
          const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Sathi', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: AppColors.navy)),
            Text('Your private claim companion', style: TextStyle(fontSize: 12, color: AppColors.muted)),
          ])),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(color: AppColors.mint, borderRadius: BorderRadius.circular(30)),
            child: const Text('LOCAL FIRST', style: TextStyle(fontSize: 10, color: AppColors.tealDark, fontWeight: FontWeight.w800)),
          ),
        ]),
        const SizedBox(height: 22),
        Text('Namaste 👋', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.muted)),
        const SizedBox(height: 6),
        Text('Understand your health-insurance claim.', style: Theme.of(context).textTheme.headlineLarge),
        const SizedBox(height: 9),
        Text(
          'Add your decision letter, read the text on this phone, then ask questions in Hindi, English or Hinglish.',
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: AppColors.muted),
        ),
        const SizedBox(height: 14),
        SathiCard(
          padding: const EdgeInsets.all(13),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(width: 38, height: 38, decoration: BoxDecoration(color: AppColors.mint, borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.shield_outlined, color: AppColors.teal)),
            const SizedBox(width: 10),
            const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Your private files stay on this phone', style: TextStyle(color: AppColors.navy, fontWeight: FontWeight.w800, fontSize: 13)),
              SizedBox(height: 4),
              Text('Sathi searches saved document text locally first. Gemini is optional and is only used for a separate general question after you confirm it.', style: TextStyle(color: AppColors.muted, fontSize: 11, height: 1.4)),
            ])),
            IconButton(
              tooltip: 'Privacy and offline AI settings',
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TechnologyPage())),
              icon: const Icon(Icons.arrow_forward_ios_rounded, size: 17, color: AppColors.teal),
            ),
          ]),
        ),
        const SizedBox(height: 14),
        SathiCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('START HERE', style: TextStyle(fontSize: 10, color: AppColors.teal, fontWeight: FontWeight.w900, letterSpacing: 1.3)),
            const SizedBox(height: 7),
            Text(
              decisionTextReady ? 'Your decision-letter text is ready' : decisionAttached ? 'Next: read the decision letter' : '1. Add your decision letter',
              style: const TextStyle(fontSize: 16, color: AppColors.navy, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 5),
            Text(
              decisionTextReady
                  ? 'Text is saved in the encrypted local vault. Ask Sathi below about the wording, amounts or next steps.'
                  : decisionAttached
                      ? 'The file is saved locally. For an image, choose “Read text on device”. For a PDF, open it in your PDF app, copy the relevant text and choose “Paste document text”.'
                      : 'Choose the insurer’s rejection or partial-approval letter first. Other documents are optional unless the letter or your insurer asks for them.',
              style: const TextStyle(color: AppColors.muted, fontSize: 12, height: 1.45),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => onNavigate(2),
                icon: const Icon(Icons.folder_open_outlined),
                label: Text('Open documents'),
              ),
            ),
            if (attachedCount > 0 || readableDocuments.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('$attachedCount file(s) saved · ${readableDocuments.length} with readable text', style: const TextStyle(color: AppColors.muted, fontSize: 11)),
            ],
          ]),
        ),
        const SizedBox(height: 14),
        SathiAssistantCard(
          onNavigate: onNavigate,
          claimContext: {
            'attachedDocumentNames': claim.documents
                .where((document) => document.uploaded && document.localPath != null)
                .map((document) => document.fileName ?? document.title)
                .toList(),
            'documentTexts': claim.documents
                .where((document) => (document.extractedText ?? '').trim().isNotEmpty)
                .map((document) => {'title': document.title, 'text': document.extractedText})
                .toList(),
          },
        ),
        const SizedBox(height: 12),
        SathiCard(
          padding: const EdgeInsets.all(13),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.info_outline_rounded, color: AppColors.amber, size: 20),
              SizedBox(width: 9),
              Expanded(child: Text('What Sathi cannot do yet', style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.navy, fontSize: 13))),
            ]),
            const SizedBox(height: 5),
            const Text('Sathi is not connected to an insurer or TPA. It cannot fetch live claim status or submit a claim. Its tracker records your actions on this device only.', style: TextStyle(color: AppColors.muted, fontSize: 11, height: 1.45)),
            const SizedBox(height: 8),
            Align(alignment: Alignment.centerLeft, child: TextButton.icon(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TechnologyPage())),
              icon: const Icon(Icons.settings_outlined, size: 17),
              label: const Text('Privacy and offline AI settings'),
            )),
          ]),
        ),
      ]),
    );
  }
}
