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
    final money = (int value) => '₹${value.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',')}';

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
                decoration: BoxDecoration(color: AppColors.amberBg, borderRadius: BorderRadius.circular(30)),
                child: const Text('DEMO DATA', style: TextStyle(fontSize: 10, color: AppColors.amber, fontWeight: FontWeight.w800)),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text('Namaste, Jagruti 👋', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.muted)),
          const SizedBox(height: 6),
          Text('Let’s make your claim\nclearer and easier.', style: Theme.of(context).textTheme.headlineLarge),
          const SizedBox(height: 10),
          Text('Understand the decision, gather the right documents, and prepare your next step with confidence.', style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: AppColors.muted)),
          const SizedBox(height: 14),
          SathiCard(
            padding: const EdgeInsets.all(13),
            child: Row(children: [
              Container(width: 38, height: 38, decoration: BoxDecoration(color: AppColors.mint, borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.shield_outlined, color: AppColors.teal)),
              const SizedBox(width: 10),
              const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Simple steps. Privacy by design.', style: TextStyle(color: AppColors.navy, fontWeight: FontWeight.w800, fontSize: 12)),
                SizedBox(height: 3),
                Text('See how Sathi reads documents and handles your data.', style: TextStyle(color: AppColors.muted, fontSize: 10, height: 1.35)),
              ])),
              IconButton(
                tooltip: 'How Sathi works',
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TechnologyPage())),
                icon: const Icon(Icons.arrow_forward_ios_rounded, size: 17, color: AppColors.teal),
              ),
            ]),
          ),
          const SizedBox(height: 14),
          SathiAssistantCard(onNavigate: onNavigate),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: const LinearGradient(colors: [AppColors.navy, Color(0xFF145B66)], begin: Alignment.topLeft, end: Alignment.bottomRight),
              boxShadow: [BoxShadow(color: AppColors.navy.withValues(alpha: 0.12), blurRadius: 18, offset: const Offset(0, 8))],
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.health_and_safety_rounded, color: Colors.white, size: 22),
                const SizedBox(width: 8),
                const Expanded(child: Text('Your health claim needs attention', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700))),
                _statusPill(claim.claimStatus),
              ]),
              const SizedBox(height: 20),
              const Text('Amount not yet approved', style: TextStyle(color: Color(0xFFC7E4E6), fontSize: 12)),
              const SizedBox(height: 2),
              Text(money(claim.unpaidAmount), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 34)),
              const SizedBox(height: 12),
              Row(children: [
                _amountColumn('Requested', money(claim.requestedAmount)),
                const SizedBox(width: 26),
                _amountColumn('Approved', money(claim.approvedAmount)),
              ]),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: () => onNavigate(1),
                style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: AppColors.navy),
                icon: const Icon(Icons.arrow_forward_rounded),
                label: const Text('Review my claim'),
              ),
              const SizedBox(height: 6),
              const Text('Demo scenario only — not a real insurance record.', style: TextStyle(color: Color(0xFFC7E4E6), fontSize: 10)),
            ]),
          ),
          const SizedBox(height: 23),
          const SectionHeading('Your next steps'),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _actionCard(context, icon: Icons.folder_copy_outlined, title: 'Documents', subtitle: '${claim.uploadedDocuments} attached', onTap: () => onNavigate(2))),
            const SizedBox(width: 10),
            Expanded(child: _actionCard(context, icon: Icons.timeline_rounded, title: 'Claim tracker', subtitle: 'View timeline', onTap: () => onNavigate(3))),
          ]),
          const SizedBox(height: 10),
          SathiCard(
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(width: 42, height: 42, decoration: BoxDecoration(color: AppColors.mint, borderRadius: BorderRadius.circular(13)), child: const Icon(Icons.auto_awesome, color: AppColors.teal)),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Make sense of the insurer’s reason', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppColors.navy)),
                const SizedBox(height: 4),
                const Text('Check your required documents and get a plain-language next-step checklist.', style: TextStyle(color: AppColors.muted, fontSize: 12, height: 1.4)),
                const SizedBox(height: 10),
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
              ])),
            ]),
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.white, border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(16)),
            child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.lock_outline_rounded, color: AppColors.teal, size: 20),
              SizedBox(width: 10),
              Expanded(child: Text('Privacy-first prototype: selected files are not uploaded or analysed by a live AI service. The app shows sample guidance only.', style: TextStyle(color: AppColors.muted, fontSize: 11, height: 1.45))),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _amountColumn(String label, String amount) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(label, style: const TextStyle(color: Color(0xFFC7E4E6), fontSize: 11)),
    const SizedBox(height: 3),
    Text(amount, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
  ]);

  Widget _statusPill(String value) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(color: const Color(0xFFFFE7B2), borderRadius: BorderRadius.circular(20)),
    child: Text(value, style: const TextStyle(color: AppColors.amber, fontSize: 10, fontWeight: FontWeight.w800)),
  );

  Widget _actionCard(BuildContext context, {required IconData icon, required String title, required String subtitle, required VoidCallback onTap}) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(18),
    child: SathiCard(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(width: 38, height: 38, decoration: BoxDecoration(color: AppColors.mint, borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: AppColors.teal)),
        const SizedBox(height: 12),
        Text(title, style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.navy)),
        const SizedBox(height: 3),
        Text(subtitle, style: const TextStyle(color: AppColors.muted, fontSize: 11)),
      ]),
    ),
  );
}
