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
    final requiredCount = claim.documents.where((d) => d.required).length;
    final completedCount = claim.documents.where((d) => d.required && d.uploaded).length;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('DOCUMENT CHECKLIST', style: TextStyle(fontSize: 11, color: AppColors.teal, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
        const SizedBox(height: 7),
        Text('Bring your evidence together', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 8),
        const Text('Use the insurer’s letter to confirm exactly which documents are needed. This list is a starting point, not a guarantee of coverage.', style: TextStyle(color: AppColors.muted, height: 1.45)),
        const SizedBox(height: 18),
        SathiCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('$completedCount of $requiredCount required categories attached', style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.navy))),
            Text('${(claim.documentProgress * 100).round()}%', style: const TextStyle(color: AppColors.teal, fontWeight: FontWeight.w900)),
          ]),
          const SizedBox(height: 10),
          ClipRRect(borderRadius: BorderRadius.circular(8), child: LinearProgressIndicator(value: claim.documentProgress, minHeight: 7, backgroundColor: AppColors.border, color: AppColors.teal)),
        ])),
        const SizedBox(height: 15),
        ...claim.documents.map((document) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _documentCard(context, document),
        )),
        const SizedBox(height: 4),
        Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: AppColors.mint, borderRadius: BorderRadius.circular(16)), child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.privacy_tip_outlined, color: AppColors.teal, size: 20),
          SizedBox(width: 9),
          Expanded(child: Text('Privacy: image text is read on your device only when you tap ‘Read text on device’. Text is masked in the preview. This prototype does not upload documents to the cloud.', style: TextStyle(fontSize: 11, color: AppColors.tealDark, height: 1.45))),
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
            const SizedBox(height: 7),
            Wrap(spacing: 10, runSpacing: 0, children: [
              TextButton.icon(onPressed: () => _showPicker(context, document), icon: const Icon(Icons.change_circle_outlined, size: 16), label: const Text('Replace'), style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact)),
              if (_canRunOcr(document)) TextButton.icon(onPressed: () => _readOcr(context, document), icon: const Icon(Icons.document_scanner_outlined, size: 16), label: const Text('Read text on device'), style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact)),
              TextButton.icon(onPressed: () => context.read<ClaimCubit>().removeDocument(document.id), icon: const Icon(Icons.delete_outline, size: 16), label: const Text('Remove'), style: TextButton.styleFrom(foregroundColor: AppColors.red, padding: EdgeInsets.zero, visualDensity: VisualDensity.compact)),
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
    final path = document.localPath?.toLowerCase();
    return path != null && (path.endsWith('.png') || path.endsWith('.jpg') || path.endsWith('.jpeg') || path.endsWith('.webp'));
  }

  Future<void> _readOcr(BuildContext context, ClaimDocument document) async {
    final path = document.localPath;
    if (path == null) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => const AlertDialog(
        content: Row(children: [CircularProgressIndicator(), SizedBox(width: 16), Expanded(child: Text('Reading this image on your phone…'))]),
      ),
    );
    try {
      final text = await _ocrService.readImageText(path);
      final maskedText = PiiMasker.mask(text);
      if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
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
      if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not read image: $error')));
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
          const Align(alignment: Alignment.centerLeft, child: Text('Demo only: the file will not be uploaded.', style: TextStyle(color: AppColors.muted, fontSize: 12))),
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
      context.read<ClaimCubit>().attachDocument(document.id, fileName, localPath: localPath);
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${document.title} attached in demo.')));
    } catch (error) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Unable to choose file: $error')));
    }
  }
}
