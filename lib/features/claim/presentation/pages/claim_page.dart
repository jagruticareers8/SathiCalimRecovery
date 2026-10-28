import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/sathi_card.dart';
import '../providers/claim_controller.dart';

class ClaimPage extends StatelessWidget {
  const ClaimPage({super.key, required this.onNavigate});
  final ValueChanged<int> onNavigate;

  @override
  Widget build(BuildContext context) {
    final claim = context.watch<ClaimCubit>().state;
    final controller = context.read<ClaimCubit>();
    final attachedCount = claim.documents.where((document) => document.uploaded).length;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('MY CLAIM', style: TextStyle(fontSize: 11, color: AppColors.teal, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
        const SizedBox(height: 7),
        Text('Understand the decision', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 7),
        const Text('Sathi explains the actual wording you provide. It cannot access an insurer account or verify claim status until a real partner integration is connected.', style: TextStyle(color: AppColors.muted, height: 1.45)),
        const SizedBox(height: 18),
        SathiCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(width: 44, height: 44, decoration: BoxDecoration(color: AppColors.amberBg, borderRadius: BorderRadius.circular(13)), child: const Icon(Icons.link_off_rounded, color: AppColors.amber)),
            const SizedBox(width: 11),
            const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('No insurer account connected', style: TextStyle(fontWeight: FontWeight.w900, color: AppColors.navy, fontSize: 14)),
              SizedBox(height: 3),
              Text('No live claim details loaded', style: TextStyle(fontSize: 11, color: AppColors.amber, fontWeight: FontWeight.w700)),
            ])),
          ]),
          const SizedBox(height: 10),
          const Text('Claim reference, insurer, hospital, dates and amounts are not assumed. Add a redacted decision letter or policy excerpt to let Sathi explain the text without inventing personal claim details.', style: TextStyle(fontSize: 12, height: 1.5, color: AppColors.muted)),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: Text('$attachedCount document types attached on this device', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.navy))),
            OutlinedButton.icon(
              onPressed: () => onNavigate(2),
              style: OutlinedButton.styleFrom(
                // Do not inherit an infinite minimum width inside this Row.
                minimumSize: const Size(0, 46),
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              icon: const Icon(Icons.folder_open_outlined, size: 17),
              label: const Text('Documents'),
            ),
          ]),
        ])),
        const SizedBox(height: 16),
        const SectionHeading('AI explanation based on your documents'),
        const SizedBox(height: 10),
        SathiCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(width: 42, height: 42, decoration: BoxDecoration(color: AppColors.mint, borderRadius: BorderRadius.circular(13)), child: const Icon(Icons.auto_awesome_rounded, color: AppColors.teal)),
            const SizedBox(width: 11),
            const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Explain what the text says', style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.navy)),
              SizedBox(height: 3),
              Text('Only reviewed OCR text is shared, after cloud consent.', style: TextStyle(color: AppColors.muted, fontSize: 11)),
            ])),
          ]),
          const SizedBox(height: 12),
          if (claim.isAnalyzing)
            const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator()))
          else
            SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: () => controller.analyzeClaim(), icon: const Icon(Icons.fact_check_outlined), label: const Text('Analyze my provided text'))),
          if (claim.analysisError != null) ...[
            const SizedBox(height: 8),
            Text(claim.analysisError!, style: const TextStyle(color: AppColors.red, fontSize: 12, height: 1.4)),
          ],
          if (claim.analysis != null) ...[
            const SizedBox(height: 14),
            Container(padding: const EdgeInsets.all(13), decoration: BoxDecoration(color: AppColors.mint, borderRadius: BorderRadius.circular(14)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Plain-language explanation', style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.tealDark)),
              const SizedBox(height: 5),
              Text(claim.analysis!.summary, style: const TextStyle(fontSize: 12, height: 1.45, color: AppColors.ink)),
              if (claim.analysis!.evidenceUsed.isNotEmpty) ...[
                const SizedBox(height: 10),
                const Text('Evidence considered (user-provided, not insurer-verified)', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: AppColors.navy)),
                const SizedBox(height: 4),
                ...claim.analysis!.evidenceUsed.map((item) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Icon(Icons.description_outlined, size: 14, color: AppColors.teal),
                    const SizedBox(width: 6),
                    Expanded(child: Text(item, style: const TextStyle(fontSize: 11, height: 1.4, color: AppColors.ink))),
                  ]),
                )),
              ],
              if (claim.analysis!.citations.isNotEmpty) ...[
                const SizedBox(height: 10),
                const Text('Verified source citations', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: AppColors.navy)),
                const SizedBox(height: 5),
                ...claim.analysis!.citations.map((citation) => Padding(
                  padding: const EdgeInsets.only(bottom: 7),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.border)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${citation.sourceTitle} · ${citation.section}${citation.page == null ? '' : ' · page ${citation.page}'}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.tealDark)),
                      if (citation.excerpt.isNotEmpty) ...[const SizedBox(height: 3), Text('“${citation.excerpt}”', style: const TextStyle(fontSize: 11, height: 1.4, color: AppColors.ink))],
                    ]),
                  ),
                )),
              ] else ...[
                const SizedBox(height: 8),
                const Text('No verified policy database or insurer portal is connected. This explanation uses the text you supplied and general guidance; it is not an insurer decision.', style: TextStyle(fontSize: 10, color: AppColors.muted, height: 1.4)),
              ],
              if (claim.analysis!.missingDocuments.isNotEmpty) ...[
                const SizedBox(height: 9),
                const Text('Possible document gaps from the provided text', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: AppColors.navy)),
                const SizedBox(height: 4),
                ...claim.analysis!.missingDocuments.map((item) => Padding(padding: const EdgeInsets.only(bottom: 3), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [const Icon(Icons.circle, size: 5, color: AppColors.teal), const SizedBox(width: 7), Expanded(child: Text(item, style: const TextStyle(fontSize: 12)))]))),
              ],
              if (claim.analysis!.nextSteps.isNotEmpty) ...[
                const SizedBox(height: 9),
                const Text('Suggested next steps', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: AppColors.navy)),
                const SizedBox(height: 4),
                ...claim.analysis!.nextSteps.asMap().entries.map((entry) => Padding(padding: const EdgeInsets.only(bottom: 5), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('${entry.key + 1}. ', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)), Expanded(child: Text(entry.value, style: const TextStyle(fontSize: 12, height: 1.4)))]))),
              ],
              const SizedBox(height: 8),
              Text(claim.analysis!.disclaimer, style: const TextStyle(color: AppColors.muted, fontSize: 10, height: 1.4)),
            ])),
          ],
        ])),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: OutlinedButton.icon(onPressed: () => onNavigate(2), icon: const Icon(Icons.folder_open), label: const Text('Add documents'))),
          const SizedBox(width: 10),
          Expanded(child: FilledButton.icon(onPressed: () => onNavigate(4), icon: const Icon(Icons.edit_document), label: const Text('Draft response')),
          ),
        ]),
        const SizedBox(height: 14),
        const Text('AI output is guidance, not a verified insurer decision or legal advice. Confirm requirements and deadlines with your insurer.', style: TextStyle(color: AppColors.muted, fontSize: 11, height: 1.45)),
      ]),
    );
  }
}
