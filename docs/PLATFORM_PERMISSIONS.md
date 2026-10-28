# Native setup for voice, audio recording, camera and OCR

This source archive does not include generated Android/iOS runner folders. After extraction, run `flutter create . --platforms=android,ios` if they are missing. Then merge the following settings into the generated native files.

## Android — `android/app/src/main/AndroidManifest.xml`

Place these permissions and the speech recognizer query as children of `<manifest>` and **outside** `<application>`:

```xml
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.READ_MEDIA_IMAGES" />
<queries>
    <intent>
        <action android:name="android.speech.RecognitionService" />
    </intent>
</queries>
```

The `speech_to_text` plugin uses the installed Android speech-recognition service. It can fail if no recognizer or Hindi speech pack is available. Open the device's Google/Android speech services settings, install Hindi language support if needed, and allow microphone permission.

For **local development only** when using `http://10.0.2.2:8000`, add this attribute to the generated `<application>` tag:

```xml
android:usesCleartextTraffic="true"
```

Remove that attribute for HTTPS deployments. If `flutter create` generated a newer Android configuration with a network security config, follow that config rather than adding duplicate attributes.

Use a `minSdk` compatible with the selected `flutter_secure_storage`, `record`, and ML Kit package versions (at least 23 for this stack), and accept the compile SDK version required by the plugins.

## iOS — `ios/Runner/Info.plist`

Merge these entries inside the top-level `<dict>`:

```xml
<key>NSMicrophoneUsageDescription</key>
<string>Record a short question only when you choose AI Hinglish voice transcription.</string>
<key>NSSpeechRecognitionUsageDescription</key>
<string>Convert your spoken question into text so you can review it before continuing.</string>
<key>NSCameraUsageDescription</key>
<string>Take a photo of a document you choose to attach to your claim checklist.</string>
<key>NSPhotoLibraryUsageDescription</key>
<string>Select a document image you choose to read on your device.</string>
```

Voice recognition availability depends on the iOS speech service and downloaded languages. Check iOS Settings → Privacy & Security → Speech Recognition and Microphone when testing.

## Important voice distinction

- **Device speech:** the `speech_to_text` plugin asks the OS speech engine to produce text. Sathi does not upload its own audio file in this mode, though the operating-system provider may use network services according to device settings.
- **AI Hinglish voice:** `record` records a short WAV. With the separate **Allow cloud voice transcription** switch turned on and `SATHI_API_BASE_URL` configured, the app uploads the audio to `/v1/voice/transcribe`, and the backend requests a transcript from Gemini. This is explicit cloud processing and must not be used with real health/identity data in the demo.

After editing native permissions, stop and rebuild the app. Hot reload does not apply manifest or Info.plist changes.
