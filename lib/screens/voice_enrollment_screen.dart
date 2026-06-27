import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/voice_auth_service.dart';
import '../services/voice_service.dart';
import '../l10n/app_strings.dart';
import '../theme.dart';

class VoiceEnrollmentScreen extends StatefulWidget {
  const VoiceEnrollmentScreen({super.key});

  @override
  State<VoiceEnrollmentScreen> createState() => _VoiceEnrollmentScreenState();
}

class _VoiceEnrollmentScreenState extends State<VoiceEnrollmentScreen> {
  static const _phrases = <String>[
    'Alert system, verify my voice',
    'I am the assigned supervisor',
    'Confirm this maintenance command',
  ];

  final List<List<double>?> _embeddings =
      List<List<double>?>.filled(_phrases.length, null);

  int? _recordingIndex;
  bool _saving = false;
  bool _consent = false;
  bool _alreadyEnrolled = false;
  String? _error;

  bool get _complete => _embeddings.every((embedding) => embedding != null);

  @override
  void initState() {
    super.initState();
    VoiceAuthService.instance.enrollmentState().then((s) {
      if (mounted) {
        setState(() => _alreadyEnrolled = s == VoiceEnrollmentState.enrolled);
      }
    }).catchError((_) {});
  }

  Future<void> _deleteEnrollment() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await VoiceAuthService.instance.deleteEnrollment();
      if (!mounted) return;
      setState(() {
        _alreadyEnrolled = false;
        for (var i = 0; i < _embeddings.length; i++) {
          _embeddings[i] = null;
        }
        _consent = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('Voiceprint deleted.'))),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _recordSample(int index) async {
    if (_recordingIndex != null || _saving) return;
    setState(() {
      _recordingIndex = index;
      _error = null;
    });

    try {
      await VoiceService.instance.init();
      await VoiceService.instance.speak('Say phrase ${index + 1}.');
      final Uint8List? audio = await VoiceService.instance.captureRawAudio(
        duration: const Duration(seconds: 3),
        sampleRate: 16000,
      );
      if (audio == null || audio.isEmpty) {
        throw StateError('No audio was captured. Check microphone permission.');
      }
      final embedding = await VoiceAuthService.instance.extractEmbedding(
        audio,
        sampleRate: 16000,
      );
      if (!mounted) return;
      setState(() => _embeddings[index] = embedding);
      await VoiceService.instance.speak('Sample ${index + 1} saved.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _recordingIndex = null);
    }
  }

  Future<void> _saveEnrollment() async {
    if (!_complete || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final embeddings = _embeddings.whereType<List<double>>().toList();
      await VoiceAuthService.instance
          .enrollCurrentUser(embeddings, consentGiven: _consent);
      await VoiceService.instance.speak('Voice enrollment complete.');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('Voiceprint enrolled.'))),
      );
      Navigator.of(context).maybePop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return Scaffold(
      backgroundColor: t.scaffold,
      appBar: AppBar(
        backgroundColor: t.card,
        foregroundColor: t.text,
        elevation: 0,
        title: Text(context.tr('Voice Enrollment')),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Record each phrase in a normal speaking voice.',
              style: TextStyle(color: t.muted, fontSize: 13),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: t.navyLt,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: t.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.privacy_tip_outlined, size: 18, color: t.navy),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          context.tr('Biometric consent'),
                          style: TextStyle(
                            color: t.text,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.tr(
                      'Voice enrolment creates a voiceprint — biometric data used only to verify it is you when you claim or resolve alerts by voice. It is stored encrypted in transit, never shared, and you can delete it at any time. Voice control is optional; you can use the app fully without it.',
                    ),
                    style: TextStyle(color: t.muted, fontSize: 12.5, height: 1.4),
                  ),
                  const SizedBox(height: 6),
                  CheckboxListTile(
                    value: _consent,
                    onChanged: _saving
                        ? null
                        : (v) => setState(() => _consent = v ?? false),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(
                      context.tr(
                        'I consent to my voiceprint being collected and stored for voice verification.',
                      ),
                      style: TextStyle(color: t.text, fontSize: 12.5),
                    ),
                  ),
                  if (_alreadyEnrolled) ...[
                    const Divider(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            context.tr('A voiceprint is currently enrolled.'),
                            style: TextStyle(color: t.muted, fontSize: 12),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: _saving ? null : _deleteEnrollment,
                          icon: Icon(Icons.delete_outline,
                              size: 16, color: t.red),
                          label: Text(
                            context.tr('Delete my voiceprint'),
                            style: TextStyle(color: t.red, fontSize: 12.5),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),
            for (var i = 0; i < _phrases.length; i++) ...[
              _PhraseCard(
                index: i,
                phrase: _phrases[i],
                recorded: _embeddings[i] != null,
                recording: _recordingIndex == i,
                disabled: _recordingIndex != null || _saving,
                onRecord: () => _recordSample(i),
              ),
              const SizedBox(height: 10),
            ],
            if (_error != null) ...[
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: t.redLt,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: t.red.withValues(alpha: 0.25)),
                ),
                child: Text(
                  _error!,
                  style: TextStyle(color: t.red, fontSize: 12.5),
                ),
              ),
            ],
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed:
                  _complete && _consent && !_saving ? _saveEnrollment : null,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.verified_user),
              label: Text(_saving ? 'Saving...' : 'Save Voiceprint'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhraseCard extends StatelessWidget {
  final int index;
  final String phrase;
  final bool recorded;
  final bool recording;
  final bool disabled;
  final VoidCallback onRecord;

  const _PhraseCard({
    required this.index,
    required this.phrase,
    required this.recorded,
    required this.recording,
    required this.disabled,
    required this.onRecord,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    final tone = recorded ? t.green : t.navy;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: recorded ? t.green : t.border),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: recorded ? t.greenLt : t.navyLt,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              recorded ? Icons.check_circle : Icons.mic,
              color: tone,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Phrase ${index + 1}',
                  style: TextStyle(
                    color: t.muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  phrase,
                  style: TextStyle(
                    color: t.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filledTonal(
            tooltip: recording ? 'Recording' : 'Record phrase',
            onPressed: disabled ? null : onRecord,
            icon: recording
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.fiber_manual_record),
          ),
        ],
      ),
    );
  }
}
