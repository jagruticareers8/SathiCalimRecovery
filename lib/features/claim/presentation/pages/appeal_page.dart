import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/sathi_card.dart';
import '../../domain/models/claim_models.dart';
import '../providers/claim_controller.dart';

class AppealPage extends StatefulWidget {
  const AppealPage({super.key});

  @override
  State<AppealPage> createState() => _AppealPageState();
}

class _AppealPageState extends State<AppealPage> {
  late final TextEditingController _draftController;
  String _lastSyncedDraft = '';

  @override
  void initState() {
    super.initState();
    final claim = context.read<ClaimCubit>().state;
    _draftController = TextEditingController(
      text: claim.appealDraft.isNotEmpty
          ? claim.appealDraft
          : _makeDraft(claim),
    );
    _lastSyncedDraft = claim.appealDraft;
  }

  @override
  void dispose() {
    _draftController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final claim = context.watch<ClaimCubit>().state;
    final controller = context.read<ClaimCubit>();
    // Sathi may generate a fresh AI draft while this page remains mounted inside
    // IndexedStack. Sync only when the Cubit draft changed externally; user typing
    // updates _lastSyncedDraft before saving so the cursor is not reset each keystroke.
    if (claim.appealDraft.isNotEmpty && claim.appealDraft != _lastSyncedDraft) {
      _lastSyncedDraft = claim.appealDraft;
      _draftController.value = TextEditingValue(
        text: claim.appealDraft,
        selection: TextSelection.collapsed(offset: claim.appealDraft.length),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'RECONSIDERATION DRAFT',
            style: TextStyle(
              fontSize: 11,
              color: AppColors.teal,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            'Your words. Your evidence.',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          const Text(
            'Start with a clear, polite request. Review and edit every sentence before using it.',
            style: TextStyle(color: AppColors.muted, height: 1.45),
          ),
          const SizedBox(height: 18),
          SathiCard(
            color: AppColors.mint,
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.edit_note_rounded, color: AppColors.teal, size: 25),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'This is a draft, not an automatic appeal. Sathi does not send it to the insurer. Add only documents you actually have and verify the policy clause, facts and submission deadline.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.tealDark,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SathiCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Editable message',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          color: AppColors.navy,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () {
                        _draftController.text = _makeDraft(claim);
                        _lastSyncedDraft = _draftController.text;
                        controller.saveDraft(_draftController.text);
                      },
                      icon: const Icon(Icons.refresh_rounded, size: 16),
                      label: const Text('Refresh'),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'Tap anywhere in the message to edit it. Your changes are saved on this phone.',
                  style: TextStyle(
                    color: AppColors.muted,
                    fontSize: 11,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _draftController,
                  onChanged: (text) {
                    _lastSyncedDraft = text;
                    controller.saveDraft(text);
                  },
                  minLines: 12,
                  maxLines: 20,
                  keyboardType: TextInputType.multiline,
                  textAlignVertical: TextAlignVertical.top,
                  autocorrect: true,
                  enableSuggestions: true,
                  scrollPadding: const EdgeInsets.all(24),
                  decoration: InputDecoration(
                    hintText: 'Review and edit your reconsideration request…',
                    alignLabelWithHint: true,
                    filled: true,
                    fillColor: AppColors.page,
                    contentPadding: const EdgeInsets.all(14),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(
                        color: AppColors.teal,
                        width: 1.5,
                      ),
                    ),
                  ),
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.5,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(
                      ClipboardData(text: _draftController.text),
                    );
                    if (context.mounted)
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Draft copied. Paste it into the insurer’s official channel after reviewing.',
                          ),
                        ),
                      );
                  },
                  icon: const Icon(Icons.copy_all_outlined),
                  label: const Text('Copy draft'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 15),
          SathiCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Have you submitted it?',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                    color: AppColors.navy,
                  ),
                ),
                const SizedBox(height: 5),
                const Text(
                  'After you submit it yourself via the insurer’s official website, email or grievance channel, you can record that step in this app’s local activity log.',
                  style: TextStyle(
                    color: AppColors.muted,
                    fontSize: 11,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 12),
                if (claim.reconsiderationMarkedSubmitted)
                  const Row(
                    children: [
                      Icon(Icons.check_circle, color: AppColors.green),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Marked as submitted by you. This is not a confirmation from the insurer.',
                          style: TextStyle(
                            color: AppColors.green,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  )
                else
                  OutlinedButton.icon(
                    onPressed: () =>
                        _confirmMarkedSubmitted(context, controller),
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text('I have submitted this draft'),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Please verify all facts, dates, amounts and attachments. This template is general informational support and is not legal advice or a guarantee of recovery.',
            style: TextStyle(color: AppColors.muted, fontSize: 10, height: 1.5),
          ),
        ],
      ),
    );
  }

  String _makeDraft(ClaimState claim) {
    final uploaded = claim.documents
        .where((d) => d.uploaded && (d.localPath != null || d.storedLocally))
        .map(
          (d) => '• ${d.title}${d.fileName == null ? '' : ' (${d.fileName})'}',
        )
        .toList();
    final attachments = uploaded.isEmpty
        ? '• [List only the documents you are actually attaching]'
        : uploaded.join('\n');
    return '''
Subject: Request for review of health insurance claim — [Claim reference]

Dear Claims Review Team,

I am requesting a review of the decision for my health insurance claim [claim reference], dated [decision date].

The decision letter states: “[Paste the exact reason from the insurer's letter.]”

Please provide an itemised explanation of the amount approved and any amount not approved, including the policy clause, benefit limit, exclusion, co-payment, sub-limit or other deduction relied upon. Please confirm which additional documents or information you require for reconsideration.

Documents I am actually attaching:
$attachments

Please confirm receipt, provide a reference number, and explain the next steps and applicable timelines. I understand that any review is subject to the policy terms and your formal assessment.

Regards,
[Policyholder name]
[Registered contact details, if required]
[Claim reference]

Note: Replace every bracketed field and remove any statement that does not apply. Verify the letter against your real documents before sending.
''';
  }

  Future<void> _confirmMarkedSubmitted(
    BuildContext context,
    ClaimCubit controller,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Record submission?'),
        content: const Text(
          'This records your confirmation locally only. Sathi will not send the draft or contact the insurer. Have you already submitted it through the insurer’s official channel?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Not yet'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Yes, I submitted it'),
          ),
        ],
      ),
    );
    if (confirmed == true) controller.markReconsiderationSubmitted();
  }
}
