import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/sathi_card.dart';
import '../../domain/models/claim_models.dart';
import '../providers/claim_controller.dart';

class ClaimPage extends StatelessWidget {
  const ClaimPage({super.key, required this.onNavigate});
  final ValueChanged<int> onNavigate;

  @override
  Widget build(BuildContext context) {
    final claim = context.watch<ClaimCubit>().state;
    final controller = context.read<ClaimCubit>();
    final money = (int value) => '₹${value.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',')}';

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('MY CLAIM', style: TextStyle(fontSize: 11, color: AppColors.teal, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
        const SizedBox(height: 7),
        Text('Understand the decision', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 7),
        const Text('Review what the decision letter says and identify the next useful step.', style: TextStyle(color: AppColors.muted, height: 1.45)),
        const SizedBox(height: 18),
        SathiCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Expanded(child: Text('Health insurance claim', style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.navy))),
            _tag('PARTIAL APPROVAL', AppColors.amberBg, AppColors.amber),
          ]),
          const SizedBox(height: 12),
          _detailRow('Claim reference', claim.claimId),
          _detailRow('Insurer', claim.insurerName),
          _detailRow('Hospital', claim.hospitalName),
          _detailRow('Submitted', claim.claimDate),
          const Divider(height: 24, color: AppColors.border),
          Row(children: [
            Expanded(child: _amount('Requested', money(claim.requestedAmount))),
            Expanded(child: _amount('Approved', money(claim.approvedAmount))),
            Expanded(child: _amount('Difference', money(claim.unpaidAmount), highlight: true)),
          ]),
        ])),
        const SizedBox(height: 16),
        const SectionHeading('What the decision says'),
        const SizedBox(height: 10),
        SathiCard(
          color: const Color(0xFFFFFBF1),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.info_outline_rounded, color: AppColors.amber),
              const SizedBox(width: 8),
              const Expanded(child: Text('Stated reason in this sample', style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.navy))),
            ]),
            const SizedBox(height: 9),
            Text(claim.insurerReason, style: const TextStyle(fontSize: 13, height: 1.5, color: AppColors.ink)),
            const SizedBox(height: 9),
            const Text('Important: this is mock decision text for a hackathon demo, not an assessment of a real policy or claim.', style: TextStyle(fontSize: 11, color: AppColors.muted, height: 1.4)),
          ]),
        ),
        const SizedBox(height: 16),
        const SectionHeading('Sathi’s document review'),
        const SizedBox(height: 10),
        SathiCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(width: 42, height: 42, decoration: BoxDecoration(color: AppColors.mint, borderRadius: BorderRadius.circular(13)), child: const Icon(Icons.auto_awesome_rounded, color: AppColors.teal)),
            const SizedBox(width: 11),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Check likely missing evidence', style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.navy)),
              const SizedBox(height: 3),
              Text('${claim.uploadedRequiredDocuments} of ${claim.requiredDocuments} required document categories attached', style: const TextStyle(color: AppColors.muted, fontSize: 11)),
            ])),
          ]),
          const SizedBox(height: 13),
          ClipRRect(borderRadius: BorderRadius.circular(10), child: LinearProgressIndicator(value: claim.documentProgress, minHeight: 7, backgroundColor: AppColors.border, color: AppColors.teal)),
          const SizedBox(height: 12),
          if (claim.isAnalyzing)
            const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator()))
          else
            FilledButton.icon(onPressed: () => controller.analyzeClaim(), icon: const Icon(Icons.fact_check_outlined), label: const Text('Review checklist and explain')),
          if (claim.analysisError != null) ...[
            const SizedBox(height: 8),
            Text(claim.analysisError!, style: const TextStyle(color: AppColors.red, fontSize: 12)),
          ],
          if (claim.analysis != null) ...[
            const SizedBox(height: 14),
            Container(padding: const EdgeInsets.all(13), decoration: BoxDecoration(color: AppColors.mint, borderRadius: BorderRadius.circular(14)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Plain-language explanation', style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.tealDark)),
              const SizedBox(height: 5),
              Text(claim.analysis!.summary, style: const TextStyle(fontSize: 12, height: 1.45, color: AppColors.ink)),
              const SizedBox(height: 9),
              if (claim.analysis!.citations.isNotEmpty) ...[
                const Text('Sources used', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: AppColors.navy)),
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
              ] else
                const Text('No policy-clause citations are available in demo mode. A connected RAG service must cite verified source text.', style: TextStyle(fontSize: 10, color: AppColors.muted, height: 1.4)),
              if (claim.analysis!.missingDocuments.isNotEmpty) ...[
                const SizedBox(height: 9),
                const Text('Still to collect', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: AppColors.navy)),
                const SizedBox(height: 4),
                ...claim.analysis!.missingDocuments.map((item) => Padding(padding: const EdgeInsets.only(bottom: 3), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [const Icon(Icons.circle, size: 5, color: AppColors.teal), const SizedBox(width: 7), Expanded(child: Text(item, style: const TextStyle(fontSize: 12)))]))),
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
          Expanded(child: FilledButton.icon(onPressed: () => onNavigate(4), icon: const Icon(Icons.edit_document), label: const Text('Draft response'))),
        ]),
        const SizedBox(height: 14),
        const Text('Sathi supports your understanding and preparation. It cannot confirm policy coverage, guarantee reimbursement, or replace the insurer’s grievance process.', style: TextStyle(color: AppColors.muted, fontSize: 11, height: 1.45)),
      ]),
    );
  }

  Widget _detailRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: 105, child: Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 12))),
      Expanded(child: Text(value, style: const TextStyle(color: AppColors.ink, fontSize: 12, fontWeight: FontWeight.w600))),
    ]),
  );

  Widget _amount(String label, String value, {bool highlight = false}) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(label, style: const TextStyle(fontSize: 10, color: AppColors.muted)),
    const SizedBox(height: 5),
    Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: highlight ? AppColors.amber : AppColors.navy)),
  ]);

  Widget _tag(String label, Color bg, Color fg) => Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6), decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)), child: Text(label, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: fg)));
}
