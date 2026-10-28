import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/sathi_card.dart';
import '../providers/claim_controller.dart';
import 'sathi_assistant_card.dart';
import 'technology_page.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.onNavigate});
  final ValueChanged<int> onNavigate;

  @override
  Widget build(BuildContext context) {
    final claim = context.watch<ClaimCubit>().state;
    final controller = context.read<ClaimCubit>();
    final attachedCount = claim.documents.where((document) => document.uploaded).length;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                height: 46,
                width: 46,
                decoration: BoxDecoration(color: AppColors.mint, borderRadius: BorderRadius.circular(15)),
                child: const Icon(Icons.support_agent_rounded, color: AppColors.teal, size: 27),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Sathi', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: AppColors.navy)),
                  Text('Your claim companion', style: TextStyle(fontSize: 12, color: AppColors.muted)),
                ]),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(color: AppColors.mint, borderRadius: BorderRadius.circular(30)),
                child: const Text('AI SUPPORT', style: TextStyle(fontSize: 10, color: AppColors.tealDark, fontWeight: FontWeight.w800)),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text('Namaste 👋', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.muted)),
          const SizedBox(height: 6),
          Text('Let’s make your claim\nclearer and easier.', style: Theme.of(context).textTheme.headlineLarge),
          const SizedBox(height: 10),
          Text('Ask a question in Hindi, English or Hinglish. Add your own decision-letter text when you need an explanation grounded in your case.', style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: AppColors.muted)),
          const SizedBox(height: 14),
          SathiCard(
            padding: const EdgeInsets.all(13),
            child: Row(children: [
              Container(width: 38, height: 38, decoration: BoxDecoration(color: AppColors.mint, borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.shield_outlined, color: AppColors.teal)),
              const SizedBox(width: 10),
              const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Simple steps. Privacy by design.', style: TextStyle(color: AppColors.navy, fontWeight: FontWeight.w800, fontSize: 12)),
                SizedBox(height: 3),
                Text('Choose whether to send masked text to cloud AI. Your files are not automatically uploaded.', style: TextStyle(color: AppColors.muted, fontSize: 10, height: 1.35)),
              ])),
              IconButton(
                tooltip: 'How Sathi works',
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TechnologyPage())),
                icon: const Icon(Icons.arrow_forward_ios_rounded, size: 17, color: AppColors.teal),
              ),
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
          const SizedBox(height: 16),
          SathiCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(width: 42, height: 42, decoration: BoxDecoration(color: AppColors.mint, borderRadius: BorderRadius.circular(13)), child: const Icon(Icons.description_outlined, color: AppColors.teal)),
                const SizedBox(width: 11),
                const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Your claim workspace', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: AppColors.navy)),
                  SizedBox(height: 3),
                  Text('No insurer account is connected', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.amber)),
                ])),
              ]),
              const SizedBox(height: 10),
              const Text('Sathi cannot fetch a live claim status, policy coverage, requested amount or approved amount yet. Add your actual decision letter or paste a redacted excerpt so the AI can explain what the text says.', style: TextStyle(color: AppColors.muted, fontSize: 12, height: 1.5)),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: Text('$attachedCount of ${claim.documents.length} common document types attached on this device', style: const TextStyle(fontSize: 11, color: AppColors.navy, fontWeight: FontWeight.w700))),
                TextButton(onPressed: () => onNavigate(2), child: const Text('Documents')),
              ]),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: claim.documents.isEmpty ? 0 : attachedCount / claim.documents.length,
                  minHeight: 6,
                  backgroundColor: AppColors.border,
                  color: AppColors.teal,
                ),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: OutlinedButton.icon(onPressed: () => onNavigate(1), icon: const Icon(Icons.fact_check_outlined), label: const Text('Review explanation'))),
                const SizedBox(width: 10),
                Expanded(child: FilledButton.icon(onPressed: () => onNavigate(2), icon: const Icon(Icons.add_photo_alternate_outlined), label: const Text('Add documents'))),
              ]),
            ]),
          ),
          const SizedBox(height: 22),
          const SectionHeading('Your next steps'),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _actionCard(context, icon: Icons.folder_copy_outlined, title: 'Documents', subtitle: '$attachedCount attached', onTap: () => onNavigate(2))),
            const SizedBox(width: 10),
            Expanded(child: _actionCard(context, icon: Icons.timeline_rounded, title: 'Activity log', subtitle: 'Your local actions', onTap: () => onNavigate(3))),
          ]),
          const SizedBox(height: 10),
          SathiCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(width: 42, height: 42, decoration: BoxDecoration(color: AppColors.mint, borderRadius: BorderRadius.circular(13)), child: const Icon(Icons.auto_awesome, color: AppColors.teal)),
                const SizedBox(width: 12),
                const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Explain your actual documents', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppColors.navy)),
                  SizedBox(height: 4),
                  Text('Use only the text you have attached and reviewed. Sathi does not guess the insurer’s reason.', style: TextStyle(color: AppColors.muted, fontSize: 12, height: 1.4)),
                ])),
              ]),
              const SizedBox(height: 12),
              if (claim.isAnalyzing)
                const LinearProgressIndicator(minHeight: 3)
              else
                FilledButton.tonalIcon(
                  onPressed: () async {
                    await controller.analyzeClaim();
                    if (context.mounted) onNavigate(1);
                  },
                  icon: const Icon(Icons.lightbulb_outline),
                  label: const Text('Explain my claim'),
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 42), padding: const EdgeInsets.symmetric(horizontal: 12)),
                ),
              if (claim.analysisError != null) ...[
                const SizedBox(height: 8),
                Text(claim.analysisError!, style: const TextStyle(color: AppColors.red, fontSize: 12)),
              ],
            ]),
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.white, border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(16)),
            child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.lock_outline_rounded, color: AppColors.teal, size: 20),
              SizedBox(width: 10),
              Expanded(child: Text('Your files stay on this device. If you enable cloud analysis and ask Sathi, masked OCR text from documents you read may be sent to the configured AI backend. No insurer or TPA status connection is active.', style: TextStyle(color: AppColors.muted, fontSize: 11, height: 1.45))),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _actionCard(BuildContext context, {required IconData icon, required String title, required String subtitle, required VoidCallback onTap}) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(18),
    child: SathiCard(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, color: AppColors.teal, size: 24),
      const SizedBox(height: 10),
      Text(title, style: const TextStyle(color: AppColors.navy, fontSize: 13, fontWeight: FontWeight.w900)),
      const SizedBox(height: 3),
      Text(subtitle, style: const TextStyle(color: AppColors.muted, fontSize: 10)),
    ])),
  );
}
