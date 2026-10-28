import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// Runs OCR on a local image path through the native ML Kit APIs.
/// The image/text is not uploaded by this service.
class OnDeviceOcrService {
  Future<String> readImageText(String imagePath) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final image = InputImage.fromFilePath(imagePath);
      final result = await recognizer.processImage(image);
      return result.text.trim();
    } finally {
      await recognizer.close();
    }
  }
}
