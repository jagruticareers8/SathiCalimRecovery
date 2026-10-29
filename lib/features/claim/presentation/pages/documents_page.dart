import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/security/pii_masker.dart';
import '../../../../core/services/on_device_ocr_service.dart';
import '../../../../core/widgets/sathi_card.dart';
import '../../domain/models/claim_models.dart';
import '../providers/claim_controller.dart';

class DocumentsPage extends StatelessWidget {
  DocumentsPage({super.key});

  final ImagePicker _imagePicker = ImagePicker();
  final OnDeviceOcrService _ocrService = OnDeviceOcrService();

  @override
  Widget build(BuildContext context) {
    final claim = context.watch<ClaimCubit>().state;
    final savedCount = claim.documents.where((d) => d.uploaded).length;
    final decisionRows = claim.documents.where((d) => d.id == 'decision');
    final decisionLetter = decisionRows.isEmpty ? null : decisionRows.first;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('DOCUMENT CHECKLIST', style: TextStyle(fontSize: 11, color: AppColors.teal, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
        const SizedBox(height: 7),
        Text('Bring your evidence together', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 8),
        const Text('Start with the insurer’s decision or rejection letter. Add other records only when they help explain the claim or the insurer requests them.', style: TextStyle(color: AppColors.muted, height: 1.45)),
        const SizedBox(height: 12),
        SathiCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('FIRST STEP: DECISION LETTER', style: TextStyle(fontSize: 10, color: AppColors.teal, fontWeight: FontWeight.w900, letterSpacing: 1.2)),
          const SizedBox(height: 6),
          Text((decisionLetter?.uploaded ?? false) ? ((decisionLetter?.extractedText ?? '').trim().isNotEmpty ? 'Decision letter text is saved locally.' : 'Decision letter saved. Next, read its text or paste text from the PDF.') : 'Add the rejection or partial-approval letter so Sathi can answer from its wording.', style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.navy, height: 1.4)),
          const SizedBox(height: 6),
          const Text('Automatic OCR currently reads images on-device. For PDFs, open the PDF, copy the relevant text, then choose “Paste document text”. No file is submitted to an insurer.', style: TextStyle(fontSize: 11, color: AppColors.muted, height: 1.4)),
          const SizedBox(height: 10),
          Row(children: [
            const Icon(Icons.folder_outlined, color: AppColors.teal, size: 18),
            const SizedBox(width: 7),
            Expanded(child: Text('$savedCount file(s) saved in your local workspace', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.navy))),
          ]),
          if (decisionLetter != null) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () async {
                  if (!decisionLetter.uploaded) {
                    await _showPicker(context, decisionLetter);
                  } else if ((decisionLetter.extractedText ?? '').trim().isNotEmpty) {
                    await _pasteDocumentText(context, decisionLetter);
                  } else if (_canRunOcr(decisionLetter)) {
                    await _readOcr(context, decisionLetter);
                  } else {
                    await _pasteDocumentText(context, decisionLetter);
                  }
                },
                icon: Icon(
                  !decisionLetter.uploaded
                      ? Icons.add_circle_outline
                      : (decisionLetter.extractedText ?? '').trim().isNotEmpty
                          ? Icons.edit_note_outlined
                          : _canRunOcr(decisionLetter)
                              ? Icons.document_scanner_outlined
                              : Icons.content_paste_go_outlined,
                ),
                label: Text(
                  !decisionLetter.uploaded
                      ? 'Add decision letter'
                      : (decisionLetter.extractedText ?? '').trim().isNotEmpty
                          ? 'Review or edit saved text'
                          : _canRunOcr(decisionLetter)
                              ? 'Read text on device'
                              : 'Paste document text',
                ),
              ),
            ),
          ],
        ])),
        const SizedBox(height: 14),
        ...claim.documents.map((document) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _documentCard(context, document),
        )),
        const SizedBox(height: 4),
        Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: AppColors.mint, borderRadius: BorderRadius.circular(16)), child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.privacy_tip_outlined, color: AppColors.teal, size: 20),
          SizedBox(width: 9),
          Expanded(child: Text('Privacy: OCR runs on your device. Sathi stores its app copy in an encrypted local vault. Document text is searched locally and is never attached to the online Gemini request. Only a separate, confirmed general question may be sent online.', style: TextStyle(fontSize: 11, color: AppColors.tealDark, height: 1.45))),
        ])),
      ]),
    );
  }

  Widget _documentCard(BuildContext context, ClaimDocument document) {
    final icon = _iconFor(document.id);
    return SathiCard(
      padding: const EdgeInsets.all(14),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(width: 42, height: 42, decoration: BoxDecoration(color: document.uploaded ? AppColors.greenBg : AppColors.page, borderRadius: BorderRadius.circular(13)), child: Icon(document.uploaded ? Icons.check_rounded : icon, color: document.uploaded ? AppColors.green : AppColors.teal, size: 22)),
        const SizedBox(width: 11),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(document.title, style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.navy, fontSize: 13))),
            if (document.required) const Text('REQUIRED', style: TextStyle(fontSize: 8, color: AppColors.amber, fontWeight: FontWeight.w900, letterSpacing: .6)),
          ]),
          const SizedBox(height: 4),
          Text(document.description, style: const TextStyle(fontSize: 11, color: AppColors.muted, height: 1.4)),
          const SizedBox(height: 7),
          if (document.uploaded) ...[
            Row(children: [
              const Icon(Icons.attach_file, size: 14, color: AppColors.green),
              const SizedBox(width: 4),
              Expanded(child: Text(document.fileName ?? 'Attached', style: const TextStyle(color: AppColors.green, fontSize: 10, fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis)),
            ]),
            const SizedBox(height: 4),
            Text(
              (document.extractedText ?? '').trim().isNotEmpty
                  ? 'Text ready for private questions · ${(document.extractedText ?? '').trim().length} characters saved locally'
                  : _canRunOcr(document)
                      ? 'Image saved. Tap “Read text on device” before asking questions about its contents.'
                      : 'File saved. For a PDF, copy its text and use “Paste document text”.',
              style: const TextStyle(color: AppColors.muted, fontSize: 10, height: 1.35),
            ),
            const SizedBox(height: 7),
            Wrap(spacing: 10, runSpacing: 0, children: [
              TextButton.icon(onPressed: () => _showPicker(context, document), icon: const Icon(Icons.change_circle_outlined, size: 16), label: const Text('Replace'), style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact)),
              if (_canRunOcr(document)) TextButton.icon(onPressed: () => _readOcr(context, document), icon: const Icon(Icons.document_scanner_outlined, size: 16), label: const Text('Read text on device'), style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact)),
              TextButton.icon(onPressed: () => _pasteDocumentText(context, document), icon: const Icon(Icons.content_paste_go_outlined, size: 16), label: const Text('Paste document text'), style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact)),
              TextButton.icon(onPressed: () async => context.read<ClaimCubit>().removeDocument(document.id), icon: const Icon(Icons.delete_outline, size: 16), label: const Text('Remove'), style: TextButton.styleFrom(foregroundColor: AppColors.red, padding: EdgeInsets.zero, visualDensity: VisualDensity.compact)),
            ]),
          ] else ...[
            const SizedBox(height: 6),
            OutlinedButton.icon(onPressed: () => _showPicker(context, document), icon: const Icon(Icons.add_rounded, size: 18), label: const Text('Attach document'), style: OutlinedButton.styleFrom(minimumSize: const Size(0, 38), padding: const EdgeInsets.symmetric(horizontal: 12))),
          ],
        ])),
      ]),
    );
  }

  IconData _iconFor(String id) => switch (id) {
    'discharge' => Icons.medical_information_outlined,
    'itemised_bill' => Icons.receipt_long_outlined,
    'prescriptions' => Icons.medication_outlined,
    'reports' => Icons.biotech_outlined,
    'policy' => Icons.health_and_safety_outlined,
    'decision' => Icons.mail_outline_rounded,
    _ => Icons.description_outlined,
  };

  bool _canRunOcr(ClaimDocument document) {
    final sourceName = (document.localPath ?? document.fileName ?? '').toLowerCase();
    final imageType = sourceName.endsWith('.png') || sourceName.endsWith('.jpg') ||
        sourceName.endsWith('.jpeg') || sourceName.endsWith('.webp');
    return imageType && (document.localPath != null || document.storedLocally);
  }

  Future<void> _readOcr(BuildContext context, ClaimDocument document) async {
    String? temporaryPath;
    var loadingDialogOpen = true;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => const AlertDialog(
        content: Row(children: [CircularProgressIndicator(), SizedBox(width: 16), Expanded(child: Text('Decrypting if needed, then reading this image on your phone…'))]),
      ),
    );
    try {
      final cubit = context.read<ClaimCubit>();
      final path = await cubit.pathForOnDeviceOcr(document.id);
      if (path == null) {
        throw StateError('This image is not available in Sathi local storage. Please attach it again.');
      }
      if (path != document.localPath) temporaryPath = path;
      final text = await _ocrService.readImageText(path);
      final maskedText = PiiMasker.mask(text);
      await cubit.saveExtractedText(document.id, maskedText);
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        loadingDialogOpen = false;
      }
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Text found on your device'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: SelectableText(maskedText.isEmpty ? 'No readable text was found. Try a clearer photo with good lighting.' : maskedText),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: maskedText));
                if (dialogContext.mounted) Navigator.pop(dialogContext);
                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Masked text copied.')));
              },
              child: const Text('Copy masked text'),
            ),
            FilledButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Done')),
          ],
        ),
      );
    } catch (error) {
      if (context.mounted && loadingDialogOpen) Navigator.of(context, rootNavigator: true).pop();
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not read image locally: $error')));
    } finally {
      if (temporaryPath != null) {
        try { await File(temporaryPath).delete(); } catch (_) {}
      }
    }
  }

  Future<void> _pasteDocumentText(BuildContext context, ClaimDocument document) async {
    final textController = TextEditingController(text: document.extractedText ?? '');
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('Add text from ${document.title}'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text(
                  'For a PDF or a scanned document, copy the relevant decision-letter/policy text and paste it here. It is saved in Sathi’s encrypted local vault. Private-file questions use this text locally and do not send it to Gemini.',
                  style: TextStyle(fontSize: 12, height: 1.45),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: textController,
                  minLines: 8,
                  maxLines: 14,
                  keyboardType: TextInputType.multiline,
                  decoration: const InputDecoration(
                    hintText: 'Paste a redacted excerpt from the insurer letter…',
                    alignLabelWithHint: true,
                  ),
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Save text')),
          ],
        ),
      );
      if (confirmed != true || !context.mounted) return;
      final masked = PiiMasker.mask(textController.text.trim());
      await context.read<ClaimCubit>().saveExtractedText(document.id, masked);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(masked.isEmpty ? 'No text saved.' : 'Masked text saved in Sathi’s encrypted local vault. Private-file questions keep it on this device.')),
      );
    } finally {
      textController.dispose();
    }
  }

  Future<void> _showPicker(BuildContext context, ClaimDocument document) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Align(alignment: Alignment.centerLeft, child: Text('Attach a document', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: AppColors.navy))),
          const SizedBox(height: 6),
          const Align(alignment: Alignment.centerLeft, child: Text('The file stays on this device. This screen does not submit it to the insurer.', style: TextStyle(color: AppColors.muted, fontSize: 12))),
          const SizedBox(height: 14),
          ListTile(leading: const Icon(Icons.photo_camera_outlined, color: AppColors.teal), title: const Text('Take a photo'), onTap: () => Navigator.pop(context, 'camera')),
          ListTile(leading: const Icon(Icons.photo_library_outlined, color: AppColors.teal), title: const Text('Choose a photo'), onTap: () => Navigator.pop(context, 'gallery')),
          ListTile(leading: const Icon(Icons.picture_as_pdf_outlined, color: AppColors.teal), title: const Text('Choose PDF or image file'), onTap: () => Navigator.pop(context, 'file')),
        ]),
      )),
    );
    if (choice == null || !context.mounted) return;
    try {
      String? fileName;
      String? localPath;
      if (choice == 'camera' || choice == 'gallery') {
        final file = await _imagePicker.pickImage(source: choice == 'camera' ? ImageSource.camera : ImageSource.gallery, imageQuality: 85, maxWidth: 1800);
        fileName = file?.name;
        localPath = file?.path;
      } else {
        // file_picker v12+ removed FilePicker.platform and FilePickerResult.
        // Use pickFile() for a single selection; it returns PlatformFile?.
        final file = await FilePicker.pickFile(
          type: FileType.custom,
          allowedExtensions: const ['pdf', 'png', 'jpg', 'jpeg'],
        );
        fileName = file?.name;
        localPath = file?.path;
      }
      if (fileName == null) return;
      await context.read<ClaimCubit>().attachDocument(document.id, fileName, localPath: localPath);
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${document.title} encrypted and saved on this device.')));
    } catch (error) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Unable to choose file: $error')));
    }
  }
}
