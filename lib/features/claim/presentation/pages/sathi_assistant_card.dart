import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../../../../core/security/privacy_settings_store.dart';
import '../../../../core/security/pii_masker.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/sathi_card.dart';
import '../../data/sathi_agent_service.dart';

/// Voice/text entry for Sathi.
/// - Default: device speech recognition, with Hindi-first locale for Hinglish.
/// - If the user explicitly enables cloud voice transcription and a backend URL
///   is configured, records a short WAV and sends it to the configured Sathi API.
/// - Text goes to Gemini only when the separate cloud-text preference is enabled.
class SathiAssistantCard extends StatefulWidget {
  const SathiAssistantCard({super.key, required this.onNavigate});
  final ValueChanged<int> onNavigate;

  @override
  State<SathiAssistantCard> createState() => _SathiAssistantCardState();
}

class _SathiAssistantCardState extends State<SathiAssistantCard> {
  final _textController = TextEditingController();
  final _speech = stt.SpeechToText();
  final _recorder = AudioRecorder();
  final _agent = SathiAgentService();
  final _privacyStore = PrivacySettingsStore();

  SathiLanguageMode _language = SathiLanguageMode.hinglish;
  bool _speechReady = false;
  Future<void>? _speechInitFuture;
  bool _listening = false;
  bool _startingDeviceSpeech = false;
  bool _deviceSpeechNeedsReset = false;
  bool _receivedSpeechResult = false;
  bool _recordingForCloud = false;
  bool _busy = false;
  bool _allowCloudText = false;
  bool _allowCloudVoice = false;
  String? _recordingPath;
  String? _answer;
  String? _statusMessage;
  String? _replyMode;
  String? _replyModel;
  String _actionLabel = 'Review my claim';
  int _actionIndex = 1;

  @override
  void initState() {
    super.initState();
    unawaited(_initialiseSpeech());
    unawaited(_loadPrivacySettings());
  }

  Future<void> _loadPrivacySettings() async {
    try {
      final values = await Future.wait<bool>([
        _privacyStore.readCloudConsent(),
        _privacyStore.readVoiceConsent(),
      ]);
      if (!mounted) return;
      setState(() {
        _allowCloudText = values[0];
        _allowCloudVoice = values[1];
      });
    } catch (_) {
      // Safe defaults remain off if secure storage is unavailable.
    }
  }

  Future<void> _initialiseSpeech() => _speechInitFuture ??= _doInitialiseSpeech();

  Future<void> _doInitialiseSpeech() async {
    try {
      final available = await _speech.initialize(
        onStatus: (status) {
          if (!mounted) return;
          if (status == 'done' || status == 'notListening') {
            setState(() => _listening = false);
          } else if (status == 'listening') {
            setState(() {
              _listening = true;
              _statusMessage = 'Listening… Speak now, then pause when you finish.';
            });
          }
        },
        onError: (error) {
          if (!mounted) return;
          final rawMessage = error.errorMsg.toLowerCase();
          final normalized = rawMessage.replaceAll(RegExp(r'[^a-z0-9]'), '');
          final isNoMatch = normalized.contains('nomatch') ||
              normalized.contains('speechtimeout') ||
              normalized.contains('nospeech');
          setState(() {
            _listening = false;
            // Only reset after a recognition timeout/no-match. Do not mark a
            // fresh app launch as stale because of unrelated service errors.
            if (isNoMatch) _deviceSpeechNeedsReset = true;
            if (isNoMatch) {
              _statusMessage = _receivedSpeechResult
                  ? 'I caught some words but could not finish recognising the sentence. Please review the text or tap the mic to try again.'
                  : 'I did not catch that. Tap the mic again, wait for Listening, then speak a short sentence.';
            } else if (normalized.contains('permission')) {
              _statusMessage = 'Microphone permission is needed. Allow it in your phone settings and try again.';
            } else if (normalized.contains('locale') || normalized.contains('language')) {
              _statusMessage = 'This speech language is not installed on your phone. Install Hindi/English speech support or change the language.';
            } else {
              _statusMessage = 'Device speech recognition stopped ($rawMessage). Tap the microphone to retry, enable AI Hinglish voice in How Sathi works, or type your question.';
            }
          });
        },
      );
      if (!mounted) return;
      setState(() {
        _speechReady = available;
        if (!available) {
          _statusMessage = 'Speech service is unavailable. Check microphone permission and install/enable a speech recognition service.';
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _speechReady = false;
        _statusMessage = 'Could not initialise the device speech service. You can still type your question.';
      });
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    unawaited(_speech.stop());
    unawaited(_recorder.dispose());
    super.dispose();
  }

  String? _bestLocale(List<stt.LocaleName> locales) {
    final languageCodes = switch (_language) {
      SathiLanguageMode.hinglish => ['en-in', 'en', 'hi-in', 'hi'],
      SathiLanguageMode.hindi => ['hi-in', 'hi'],
      SathiLanguageMode.english => ['en-in', 'en-gb', 'en-us', 'en'],
    };
    for (final wanted in languageCodes) {
      for (final locale in locales) {
        final id = locale.localeId.toLowerCase().replaceAll('_', '-');
        if (id == wanted || (wanted.length == 2 && id.startsWith('$wanted-'))) {
          return locale.localeId;
        }
      }
    }
    return null;
  }

  Future<void> _toggleVoice() async {
    if (_busy || _startingDeviceSpeech) return;
    if (_recordingForCloud) {
      // Re-check consent at stop time too. If the user revoked consent mid-recording,
      // discard the clip instead of uploading it.
      try {
        _allowCloudVoice = await _privacyStore.readVoiceConsent();
      } catch (_) {
        _allowCloudVoice = false;
      }
      if (!_allowCloudVoice) {
        final path = _recordingPath;
        try { await _recorder.cancel(); } catch (_) {}
        if (path != null) { try { await File(path).delete(); } catch (_) {} }
        if (mounted) setState(() {
          _recordingForCloud = false;
          _recordingPath = null;
          _statusMessage = 'Cloud voice consent was turned off. The recording was discarded and not sent.';
        });
        return;
      }
      await _stopCloudRecordingAndTranscribe();
      return;
    }
    // Re-read after returning from the privacy settings screen; Home may stay alive in the navigation stack.
    try {
      _allowCloudVoice = await _privacyStore.readVoiceConsent();
    } catch (_) {
      _allowCloudVoice = false;
    }
    if (_deviceSpeechNeedsReset) {
      // Recover only after a previous no-match/timeout. Do not cancel the
      // recognizer on a normal first microphone tap; Android can race startup.
      try { await _speech.cancel(); } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 250));
      _deviceSpeechNeedsReset = false;
      if (mounted) setState(() => _listening = false);
    } else if (_speech.isListening || _listening) {
      await _speech.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }

    // Cloud audio has its own explicit consent, separate from cloud text analysis.
    if (_allowCloudVoice && _agent.isConfigured) {
      await _startCloudRecording();
    } else {
      await _startDeviceSpeech();
    }
  }

  Future<void> _startDeviceSpeech() async {
    if (_startingDeviceSpeech || _busy || _recordingForCloud) return;
    _startingDeviceSpeech = true;
    _receivedSpeechResult = false;
    _deviceSpeechNeedsReset = false;
    if (mounted) {
      setState(() {
        _listening = false;
        _statusMessage = 'Preparing microphone…';
      });
    }

    try {
      // speech_to_text should be initialized once per app session.
      await _initialiseSpeech();
      if (!mounted) return;
      if (!_speechReady) {
        setState(() => _statusMessage = 'Device speech is unavailable. Check microphone permission and your emulator speech service, or enable AI Hinglish voice in How Sathi works.');
        return;
      }

      final locales = await _speech.locales();
      final localeId = _bestLocale(locales);
      if (localeId == null) {
        setState(() {
          _statusMessage = _language == SathiLanguageMode.english
              ? 'English speech support is not installed. Install it in your device speech settings.'
              : 'Hindi/English speech support is not installed. Install it in your device speech settings or enable AI Hinglish voice.';
        });
        return;
      }

      setState(() => _statusMessage = 'Starting microphone (${localeId.replaceAll('_', '-')})… Wait for “Listening…” before speaking.');
      await _speech.listen(
        onResult: (result) {
          if (!mounted) return;
          final words = result.recognizedWords.trim();
          if (words.isNotEmpty) _receivedSpeechResult = true;
          setState(() {
            // Keep prior partial text if Android returns an empty final event.
            if (words.isNotEmpty) {
              _textController.value = TextEditingValue(
                text: result.recognizedWords,
                selection: TextSelection.collapsed(offset: result.recognizedWords.length),
              );
            }
            _listening = !result.finalResult;
            if (result.finalResult && words.isNotEmpty) {
              _listening = false;
              _deviceSpeechNeedsReset = false;
              _statusMessage = 'Voice captured. Review the transcript, then tap “Help me with this”.';
            }
          });
        },
        listenOptions: stt.SpeechListenOptions(
          localeId: localeId,
          listenFor: const Duration(seconds: 25),
          pauseFor: const Duration(seconds: 4),
          partialResults: true,
          cancelOnError: true,
          listenMode: stt.ListenMode.dictation,
        ),
      );

      // The listen Future completing does not always mean the native service
      // is already in listening state. Re-check its real state instead of
      // forcing _listening=true and leaving the UI stuck after a fast failure.
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (!mounted) return;
      final active = _speech.isListening;
      setState(() {
        _listening = active;
        if (active) {
          _statusMessage = 'Listening… Speak now, then pause when you finish.';
        } else if (!_receivedSpeechResult && !_deviceSpeechNeedsReset) {
          _statusMessage = 'The speech service did not start. Check the emulator microphone and speech service, then tap to retry.';
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _listening = false;
        _statusMessage = 'Could not start the microphone. Check microphone permission and speech service settings. Details: $error';
      });
    } finally {
      _startingDeviceSpeech = false;
    }
  }

  Future<void> _startCloudRecording() async {
    try {
      final allowed = await _recorder.hasPermission();
      if (!allowed) {
        if (mounted) setState(() => _statusMessage = 'Microphone permission was denied. Allow it in Settings to use AI Hinglish voice.');
        return;
      }
      final directory = await getTemporaryDirectory();
      final path = '${directory.path}/sathi_voice_${DateTime.now().microsecondsSinceEpoch}.wav';
      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.wav, sampleRate: 16000, numChannels: 1),
        path: path,
      );
      if (!mounted) return;
      setState(() {
        _recordingPath = path;
        _recordingForCloud = true;
        _statusMessage = 'AI Hinglish voice is recording. Tap stop when finished. Audio will be sent to your configured Sathi backend for transcription.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _recordingForCloud = false;
        _statusMessage = 'Could not start audio recording. Check microphone permissions. Details: $error';
      });
    }
  }

  Future<void> _stopCloudRecordingAndTranscribe() async {
    setState(() {
      _recordingForCloud = false;
      _busy = true;
      _statusMessage = 'Transcribing your Hinglish question…';
    });
    String? path;
    try {
      path = await _recorder.stop() ?? _recordingPath;
      if (path == null) throw StateError('No recording was created.');
      final transcript = await _agent.transcribeHinglishAudio(path);
      if (!mounted) return;
      setState(() {
        _textController.value = TextEditingValue(
          text: transcript,
          selection: TextSelection.collapsed(offset: transcript.length),
        );
        _statusMessage = 'AI transcription complete. Check the words before sending your question to Sathi.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _statusMessage = 'AI transcription failed: $error. You can try device speech or type your question.');
    } finally {
      if (path != null) {
        try { await File(path).delete(); } catch (_) {}
      }
      if (mounted) setState(() {
        _recordingPath = null;
        _recordingForCloud = false;
        _busy = false;
      });
    }
  }

  Future<void> _askSathi() async {
    final input = _textController.text.trim();
    if (input.isEmpty) {
      setState(() => _statusMessage = 'Type a question or tap the microphone to speak.');
      return;
    }
    setState(() {
      _busy = true;
      _statusMessage = 'Understanding your question…';
    });
    try {
      // Read the latest stored preference before each request; a UI switch can
      // never send text if the user's separate cloud-analysis preference is off.
      _allowCloudText = await _privacyStore.readCloudConsent();
      final reply = await _agent.ask(
        message: PiiMasker.mask(input),
        language: _language,
        allowCloudAnalysis: _allowCloudText,
      );
      if (!mounted) return;
      setState(() {
        _answer = reply.answer;
        _actionIndex = reply.actionIndex;
        _actionLabel = reply.actionLabel;
        _replyMode = reply.mode;
        _replyModel = reply.model;
        _statusMessage = [reply.notice, if (reply.mode == 'gemini_agent') 'Live model: ${reply.model}.'].where((item) => item.trim().isNotEmpty).join(' ');
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _statusMessage = 'I could not process that request. Please try again or use the local helper. Details: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _fillExample(String phrase) {
    setState(() {
      _textController.text = phrase;
      _textController.selection = TextSelection.collapsed(offset: phrase.length);
      _statusMessage = 'Example added. Tap “Help me with this”.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final isMicActive = _listening || _startingDeviceSpeech || _recordingForCloud;
    return SathiCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(width: 42, height: 42, decoration: BoxDecoration(color: AppColors.mint, borderRadius: BorderRadius.circular(13)), child: const Icon(Icons.forum_outlined, color: AppColors.teal)),
        const SizedBox(width: 10),
        const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Ask Sathi', style: TextStyle(color: AppColors.navy, fontWeight: FontWeight.w900, fontSize: 16)),
          Text('Hindi, English ya Hinglish mein poochhein', style: TextStyle(color: AppColors.muted, fontSize: 11)),
        ])),
        DropdownButtonHideUnderline(child: DropdownButton<SathiLanguageMode>(
          value: _language,
          borderRadius: BorderRadius.circular(12),
          items: SathiLanguageMode.values.map((value) => DropdownMenuItem(value: value, child: Text(value.label))).toList(),
          onChanged: (value) => setState(() => _language = value ?? SathiLanguageMode.hinglish),
        )),
      ]),
      const SizedBox(height: 12),
      TextField(
        controller: _textController,
        minLines: 1,
        maxLines: 4,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(
          hintText: switch (_language) {
            SathiLanguageMode.hinglish => 'Jaise: Mera claim reject ho gaya, ab kya karu?',
            SathiLanguageMode.hindi => 'जैसे: मेरा क्लेम रिजेक्ट हो गया, अब क्या करूँ?',
            SathiLanguageMode.english => 'E.g. Why was my claim partly paid?',
          },
          prefixIcon: const Icon(Icons.chat_bubble_outline),
          suffixIcon: IconButton(
            tooltip: _recordingForCloud ? 'Stop AI transcription' : ((_listening || _startingDeviceSpeech) ? 'Stop device speech' : 'Speak your question'),
            onPressed: (_busy || _startingDeviceSpeech) ? null : _toggleVoice,
            icon: Icon(isMicActive ? Icons.stop_circle_outlined : Icons.mic_none_rounded, color: isMicActive ? AppColors.red : AppColors.teal),
          ),
        ),
      ),
      const SizedBox(height: 7),
      Wrap(spacing: 6, runSpacing: 4, children: [
        ActionChip(label: const Text('Claim reject kyun hua?'), onPressed: _busy ? null : () => _fillExample('Mera claim reject kyun hua?')),
        ActionChip(label: const Text('Kaun se documents chahiye?'), onPressed: _busy ? null : () => _fillExample('Kaun se documents chahiye?')),
        ActionChip(label: const Text('Claim ka status kya hai?'), onPressed: _busy ? null : () => _fillExample('Mera claim ka status kya hai?')),
      ]),
      const SizedBox(height: 10),
      SizedBox(width: double.infinity, child: FilledButton.icon(
        onPressed: _busy ? null : _askSathi,
        icon: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.auto_awesome),
        label: Text(_busy ? 'Please wait…' : 'Help me with this'),
      )),
      if (_statusMessage != null) ...[
        const SizedBox(height: 8),
        Text(_statusMessage!, style: const TextStyle(fontSize: 10, color: AppColors.muted, height: 1.4)),
      ],
      if (_answer != null) ...[
        const SizedBox(height: 12),
        Container(width: double.infinity, padding: const EdgeInsets.all(13), decoration: BoxDecoration(color: AppColors.mint, borderRadius: BorderRadius.circular(14)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.lightbulb_outline, size: 18, color: AppColors.tealDark),
            const SizedBox(width: 6),
            const Expanded(child: Text('Suggested next step', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: AppColors.tealDark))),
            _modeBadge(_replyMode),
          ]),
          const SizedBox(height: 7),
          Text(_answer!, style: const TextStyle(fontSize: 12, color: AppColors.ink, height: 1.5)),
          if (_replyModel != null && _replyModel!.isNotEmpty) ...[
            const SizedBox(height: 5),
            Text('Model: $_replyModel', style: const TextStyle(fontSize: 9, color: AppColors.muted)),
          ],
          const SizedBox(height: 10),
          Align(alignment: Alignment.centerLeft, child: OutlinedButton.icon(onPressed: () => widget.onNavigate(_actionIndex), icon: const Icon(Icons.arrow_forward, size: 16), label: Text(_actionLabel), style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40)))),
        ])),
      ],
      const SizedBox(height: 8),
      const Text('Device voice uses your phone’s speech service. For better Hinglish code-switching, enable AI voice transcription in “How Sathi works”; the recording is sent to your configured backend only after separate consent. Do not speak Aadhaar, policy numbers or other sensitive identifiers.', style: TextStyle(color: AppColors.muted, fontSize: 10, height: 1.45)),
    ]));
  }

  Widget _modeBadge(String? mode) {
    final (label, color) = switch (mode) {
      'gemini_agent' => ('GEMINI AGENT', AppColors.tealDark),
      'offline_fallback' => ('OFFLINE FALLBACK', AppColors.amber),
      _ => ('LOCAL DEMO', AppColors.muted),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: TextStyle(color: color, fontSize: 8, fontWeight: FontWeight.w900)),
    );
  }
}
