// Bridges parsed voice commands to AlertProvider actions.
//
// This layer intentionally speaks only the command responses supported by the
// factory voice contract so noisy/partial speech never leaks internal errors to
// the supervisor.

import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

import '../models/alert_model.dart';
import '../providers/alert_provider.dart';
import 'voice_auth_service.dart';
import 'voice_command_parser.dart';
import 'voice_service.dart';

class VoiceCommandDispatcher {
  final AlertProvider provider;
  VoiceCommandDispatcher(this.provider);

  static const String unrecognizedVoice = 'Unrecognized voice';
  static const String enrollVoice = 'Please enroll your voice';
  static const String alertNotFound = 'Alert not found';
  static const String noCommandHeard = 'no command was heard';

  Future<VoiceCommandExecutionResult> execute(
    VoiceCommand cmd, {
    Uint8List? rawAudio,
    int rawAudioSampleRate = 16000,
    bool voiceAlreadyVerified = false,
    String? fallbackAlertId,
  }) async {
    final voiceOk = await _checkVoiceAccess(
      rawAudio: rawAudio,
      rawAudioSampleRate: rawAudioSampleRate,
      voiceAlreadyVerified: voiceAlreadyVerified,
    );
    if (voiceOk != null) return voiceOk;

    switch (cmd.intent) {
      case VoiceIntent.claim:
        return _handleClaim(cmd);
      case VoiceIntent.resolve:
        return _handleActiveAlertCommand(
          cmd,
          action: (alert) =>
              provider.resolveAlert(alert.id, 'Resolved by voice command'),
          successMessage: (number) => 'Alert $number resolved',
        );
      case VoiceIntent.suspend:
        return _handleActiveAlertCommand(
          cmd,
          action: (alert) => provider.returnToQueue(
            alert.id,
            reason: 'Suspended by voice command',
          ),
          successMessage: (number) => 'Alert $number suspended',
        );
      case VoiceIntent.escalate:
        return _handleActiveAlertCommand(
          cmd,
          action: (alert) => provider.toggleCritical(
            alert.id,
            true,
            note: 'Marked critical by voice command',
          ),
          successMessage: (number) =>
              'Alert $number has been marked as critical',
        );
      default:
        return _speakResult(false, unrecognizedVoice);
    }
  }

  Future<VoiceCommandExecutionResult?> _checkVoiceAccess({
    Uint8List? rawAudio,
    required int rawAudioSampleRate,
    required bool voiceAlreadyVerified,
  }) async {
    if (VoiceService.instance.requiresVoiceEnrollment) {
      try {
        final state = await VoiceAuthService.instance.enrollmentState();
        if (state != VoiceEnrollmentState.enrolled) {
          return _speakResult(false, enrollVoice);
        }
      } catch (_) {
        return _speakResult(false, enrollVoice);
      }
    }

    if (voiceAlreadyVerified) return null;

    final hasAudio = rawAudio != null && rawAudio.lengthInBytes >= 1600;
    if (!hasAudio) return _speakResult(false, unrecognizedVoice);

    final auth = await VoiceAuthService.instance.verifyCurrentUser(
      rawAudio: rawAudio,
      sampleRate: rawAudioSampleRate,
    );
    if (!auth.verified) {
      return _speakResult(false, authFailureMessage(auth));
    }
    return null;
  }

  Future<VoiceCommandExecutionResult> _handleClaim(VoiceCommand cmd) async {
    final alert = await _findAvailableForClaim(cmd);
    if (alert == null) {
      return _speakResult(false, _alertNotFoundMessage(cmd.alertNumber));
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return _speakResult(false, unrecognizedVoice);

    final name =
        await _displayName(user.uid) ?? provider.currentSuperviseurName;
    try {
      await provider.takeAlert(alert.id, user.uid, name);
      return _speakResult(true, 'Alert ${alert.alertNumber} claimed');
    } catch (_) {
      return _speakResult(false, _alertNotFoundMessage(alert.alertNumber));
    }
  }

  Future<VoiceCommandExecutionResult> _handleActiveAlertCommand(
    VoiceCommand cmd, {
    required Future<void> Function(AlertModel alert) action,
    required String Function(int number) successMessage,
  }) async {
    final alert = _findActiveAlert(cmd.alertNumber);
    if (alert == null) {
      return _speakResult(false, _alertNotFoundMessage(cmd.alertNumber));
    }

    try {
      await action(alert);
      return _speakResult(true, successMessage(alert.alertNumber));
    } catch (_) {
      return _speakResult(
        false,
        _alertNotFoundMessage(cmd.alertNumber ?? alert.alertNumber),
      );
    }
  }

  String _alertNotFoundMessage(int? number) {
    return number == null ? alertNotFound : 'Alert $number not found';
  }

  Future<AlertModel?> _findAvailableForClaim(VoiceCommand cmd) async {
    final number = cmd.alertNumber;
    if (number == null) return null;

    final exact = _findLocalAvailableByNumber(number);
    if (exact != null) return exact;

    final databaseExact = await _findAvailableByNumber(number);
    if (databaseExact != null) return databaseExact;

    if (!VoiceCommandParser.claimMayBeEarlyPartialDuringCapture(cmd)) {
      return null;
    }

    for (final prefix in _claimCompletionPrefixes(cmd)) {
      final match = _findUniqueAvailablePrefix(prefix);
      if (match != null) return match;
    }
    return null;
  }

  AlertModel? _findLocalAvailableByNumber(int number) {
    for (final alert in provider.availableAlerts) {
      if (alert.alertNumber == number) return alert;
    }
    return null;
  }

  Iterable<String> _claimCompletionPrefixes(VoiceCommand cmd) sync* {
    final number = cmd.alertNumber;
    if (number == null) return;

    final scalePrefix = _incompleteScalePrefix(cmd);
    if (scalePrefix != null) yield scalePrefix;

    yield number.toString();
  }

  String? _incompleteScalePrefix(VoiceCommand cmd) {
    final number = cmd.alertNumber;
    if (number == null) return null;

    final tokens = cmd.rawText
        .toLowerCase()
        .replaceAll(RegExp(r"[^a-z0-9\s]"), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .split(' ')
        .where((token) => token.isNotEmpty)
        .toList();
    if (tokens.isEmpty) return null;

    for (var i = tokens.length - 1; i >= 0; i--) {
      final token = tokens[i];
      if (_claimPrefixFillers.contains(token)) continue;
      if (token == 'thousand' && number >= 10000 && number % 1000 == 0) {
        return (number ~/ 1000).toString();
      }
      if (token == 'hundred' && number >= 1000 && number % 100 == 0) {
        return (number ~/ 100).toString();
      }
      return null;
    }
    return null;
  }

  static const Set<String> _claimPrefixFillers = {
    'a',
    'an',
    'and',
    'alert',
    'alerts',
    'alarm',
    'alarms',
    'case',
    'hash',
    'hashtag',
    'id',
    'no',
    'number',
    'num',
    'pound',
    'please',
    'sharp',
    'the',
  };

  AlertModel? _findUniqueAvailablePrefix(String prefix) {
    if (prefix.isEmpty) return null;

    AlertModel? match;
    for (final alert in provider.availableAlerts) {
      final candidate = alert.alertNumber.toString();
      if (candidate == prefix || !candidate.startsWith(prefix)) continue;
      if (match != null) return null;
      match = alert;
    }
    return match;
  }

  Future<AlertModel?> _findAvailableByNumber(int? number) async {
    if (number == null) return null;
    try {
      final snap = await FirebaseDatabase.instance
          .ref('alerts')
          .orderByChild('alertNumber')
          .equalTo(number)
          .limitToFirst(5)
          .get();
      final raw = snap.value;
      if (raw is! Map) return null;

      for (final entry in raw.entries) {
        final id = entry.key?.toString();
        final value = entry.value;
        if (id == null || id.isEmpty || value is! Map) continue;

        final data = Map<String, dynamic>.from(
          value.map((key, value) => MapEntry(key.toString(), value)),
        );
        final rawNumber = data['alertNumber'];
        final alertNumber = rawNumber is num
            ? rawNumber.toInt()
            : int.tryParse(rawNumber?.toString() ?? '');
        final status = data['status']?.toString() ?? 'disponible';
        if (alertNumber == number && status == 'disponible') {
          return _minimalAlertFromMap(id, number, data);
        }
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  AlertModel _minimalAlertFromMap(
    String id,
    int alertNumber,
    Map<String, dynamic> data,
  ) {
    final timestampText = data['timestamp']?.toString();
    return AlertModel(
      id: id,
      alertNumber: alertNumber,
      type: data['type']?.toString() ?? 'alert',
      usine: data['usine']?.toString() ?? 'Usine A',
      convoyeur: _intValue(data['convoyeur']) ?? 1,
      poste: _intValue(data['poste']) ?? 1,
      adresse: data['adresse']?.toString() ?? '',
      timestamp: timestampText == null
          ? DateTime.now()
          : DateTime.tryParse(timestampText) ?? DateTime.now(),
      description: data['description']?.toString() ?? '',
      status: data['status']?.toString() ?? 'disponible',
    );
  }

  int? _intValue(Object? raw) {
    if (raw is num) return raw.toInt();
    return int.tryParse(raw?.toString() ?? '');
  }

  AlertModel? _findActiveAlert(int? number) {
    final uid = provider.currentSuperviseurId;
    if (uid.isEmpty) return null;

    final active = provider.inProgressAlerts(uid);
    if (number != null) {
      for (final alert in active) {
        if (alert.alertNumber == number) return alert;
      }
      return null;
    }

    return active.isEmpty ? null : active.first;
  }

  Future<String?> _displayName(String uid) async {
    try {
      final snap = await FirebaseDatabase.instance.ref('users/$uid').get();
      if (!snap.exists) return null;
      final m = Map<String, dynamic>.from(snap.value as Map);
      return (m['fullName'] ?? m['name'] ?? m['email'])?.toString();
    } catch (_) {
      return null;
    }
  }

  static String authFailureMessage(VoiceVerificationResult auth) {
    return auth.unenrolled ? enrollVoice : unrecognizedVoice;
  }

  Future<VoiceCommandExecutionResult> _speakResult(
    bool success,
    String message,
  ) async {
    await VoiceService.instance.speak(message);
    return VoiceCommandExecutionResult(success: success, message: message);
  }
}

class VoiceCommandExecutionResult {
  final bool success;
  final String message;

  const VoiceCommandExecutionResult({
    required this.success,
    required this.message,
  });
}
