// Pure-logic voice command parser. No I/O, no Flutter — easy to unit test.
//
import 'dart:developer' as developer;

// Translates a transcription like "claim alert one thousand twenty five"
// into a structured [VoiceCommand]. Knows how to:
//   1. Map English number words ("one thousand twenty five") to digits (1025).
//   2. Extract the intent verb (claim / resolve / escalate / show ...).
//   3. Pull a free-text "reason" segment for resolve commands.
//   4. Detect yes/no confirmations (used by the notification claim flow).
//
// Two parse modes:
//   - [parseBest] / [parse]: lenient legacy path used by the always-listening
//     FAB. Accepts loose phrasing like "I will take alert 1025".
//   - [parseCanonical]: notification-driven flow. Requires an action-first
//     alert command with a number, but accepts common STT verb variants like
//     "clean alert 1025" or "result alert 1025".

enum VoiceIntent {
  claim,
  resolve,
  suspend,
  escalate,
  showDashboard,
  showAlerts,
  showFixed,
  // Shift commands.
  joinShift,
  shiftReady,
  shiftHandover,
  unknown,
}

/// One transcript that the parser failed to interpret. Surfaced via
/// [VoiceCommandParser.recentUnparsed] so the alias lists / intent rules can
/// be tuned against real user speech rather than guesses.
class UnparsedSample {
  final DateTime at;
  final String text;
  const UnparsedSample({required this.at, required this.text});
}

class VoiceCommand {
  final VoiceIntent intent;
  final int? alertNumber;
  final String? reason;
  final String rawText;

  const VoiceCommand({
    required this.intent,
    required this.rawText,
    this.alertNumber,
    this.reason,
  });

  bool get isValid => intent != VoiceIntent.unknown;

  @override
  String toString() =>
      'VoiceCommand(intent: $intent, alertNumber: $alertNumber, reason: $reason)';
}

class VoiceCommandParser {
  /// In-memory ring of recent transcripts that the parser could not interpret.
  /// Bounded to [_unparsedCapacity] to avoid leaking memory in long sessions.
  /// Surfaced for diagnostics so the alias lists / intent rules can be tuned
  /// based on real-world misses rather than guesswork.
  static const int _unparsedCapacity = 50;
  static final List<UnparsedSample> _unparsed = <UnparsedSample>[];

  /// Snapshot of the most recently observed unparsed transcripts (newest
  /// last). Returns an unmodifiable copy.
  static List<UnparsedSample> recentUnparsed() => List.unmodifiable(_unparsed);

  static void clearUnparsedLog() => _unparsed.clear();

  static void _logUnparsed(String raw) {
    if (raw.isEmpty) return;
    _unparsed.add(UnparsedSample(at: DateTime.now(), text: raw));
    if (_unparsed.length > _unparsedCapacity) {
      _unparsed.removeRange(0, _unparsed.length - _unparsedCapacity);
    }
    assert(() {
      // Only emits in debug builds.
      developer.log('unparsed transcript: "$raw"', name: 'VoiceCommandParser');
      return true;
    }());
  }

  // Single-word values: 0..19 + tens.
  static const Map<String, int> _ones = {
    'zero': 0,
    'oh': 0,
    'o': 0,
    'owe': 0,
    'one': 1,
    'won': 1,
    'two': 2,
    'to': 2,
    'too': 2,
    'three': 3,
    'four': 4,
    'for': 4,
    'five': 5,
    'six': 6,
    'seven': 7,
    'eight': 8,
    'ate': 8,
    'nine': 9,
    'ten': 10,
    'eleven': 11,
    'twelve': 12,
    'thirteen': 13,
    'fourteen': 14,
    'fifteen': 15,
    'sixteen': 16,
    'seventeen': 17,
    'eighteen': 18,
    'nineteen': 19,
  };
  static const Map<String, int> _tens = {
    'twenty': 20,
    'thirty': 30,
    'forty': 40,
    'fourty': 40,
    'fifty': 50,
    'sixty': 60,
    'seventy': 70,
    'eighty': 80,
    'ninety': 90,
  };
  static const Map<String, int> _scales = {'hundred': 100, 'thousand': 1000};
  static const Set<String> _numberFillers = {
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

  /// Parser used by the notification-driven claim flow. It keeps the safety
  /// rule that the command must be action-first and include an alert number,
  /// while still accepting common STT variants like "clean alert 1025" and
  /// "result alert 1025".
  ///
  /// Tries every hypothesis in order and returns the first one that parses to
  /// a supported action command. Claim requires an alert number; resolve,
  /// suspend, and critical commands can use the supervisor's active alert. Some
  /// recognizers include the right phrase as a later alternative, so iterating
  /// hypotheses keeps the command flow from failing on the first noisy guess.
  static VoiceCommand parseCanonical(Iterable<String> transcripts) {
    for (final transcript in transcripts) {
      final cmd = _parseCanonicalSingle(transcript);
      if (cmd.isValid &&
          (!_requiresAlertNumber(cmd.intent) || cmd.alertNumber != null)) {
        return cmd;
      }
    }
    return const VoiceCommand(intent: VoiceIntent.unknown, rawText: '');
  }

  static VoiceCommand _parseCanonicalSingle(String transcript) {
    final raw = transcript.trim();
    if (raw.isEmpty) {
      return VoiceCommand(intent: VoiceIntent.unknown, rawText: raw);
    }

    final normalized = _normalize(raw);

    // Strip a single leading filler ("please claim alert 1025"). After this
    // the string must start with an action-like command word.
    final cleaned = normalized
        .replaceFirst(RegExp(r'^(please|hey|ok|okay|alert system)\s+'), '')
        .trim();

    if (!_looksLikeCanonicalAction(cleaned)) {
      return VoiceCommand(intent: VoiceIntent.unknown, rawText: raw);
    }

    final command = parse(raw);
    if (!_isActionIntent(command.intent) ||
        (_requiresAlertNumber(command.intent) && command.alertNumber == null)) {
      return VoiceCommand(intent: VoiceIntent.unknown, rawText: raw);
    }
    return command;
  }

  /// Parse several recognizer hypotheses and return the best command.
  ///
  /// Android/iOS recognizers often include the right command as the second or
  /// third alternative when the first hypothesis turns "claim" into "clean" or
  /// drops part of a spoken alert number. Prefer a complete command with an
  /// alert number, then fall back to the first valid command.
  static VoiceCommand parseBest(Iterable<String> transcripts) {
    final unique = <String>[];
    final seen = <String>{};
    for (final transcript in transcripts) {
      final trimmed = transcript.trim();
      if (trimmed.isEmpty) continue;
      final key = _normalize(trimmed);
      if (seen.add(key)) unique.add(trimmed);
    }

    if (unique.isEmpty) {
      return const VoiceCommand(intent: VoiceIntent.unknown, rawText: '');
    }

    final candidates = _withClaimContinuations(unique);
    VoiceCommand? firstValid;
    VoiceCommand? bestClaim;
    var bestClaimScore = -1;
    for (final transcript in candidates) {
      final command = parse(transcript);
      if (!command.isValid) continue;
      firstValid ??= command;

      if (command.intent == VoiceIntent.claim && command.alertNumber != null) {
        final score = _claimCompletenessScore(command);
        if (score > bestClaimScore) {
          bestClaim = command;
          bestClaimScore = score;
        }
        continue;
      }

      if (!_requiresAlertNumber(command.intent)) {
        return command;
      }
    }
    return bestClaim ?? firstValid ?? parse(unique.first);
  }

  /// Returns true when a claim transcript ends at a point where native speech
  /// recognition commonly finalizes too early, such as "twenty one thousand".
  static bool claimMayNeedMoreSpeech(VoiceCommand command) {
    if (command.intent != VoiceIntent.claim) return false;
    final alertNumber = command.alertNumber;
    if (alertNumber == null) return true;

    final tokens = _normalizedTokens(command.rawText);
    for (var i = tokens.length - 1; i >= 0; i--) {
      final token = tokens[i];
      if (_numberFillers.contains(token)) continue;
      if (token == 'hundred') return alertNumber >= 1000;
      if (token == 'thousand') return alertNumber >= 10000;
      if (_isNumberComponent(token)) return false;
      return false;
    }
    return false;
  }

  static bool claimMayBeEarlyPartialDuringCapture(VoiceCommand command) {
    if (command.intent != VoiceIntent.claim) return false;
    if (command.alertNumber == null) return true;
    if (claimMayNeedMoreSpeech(command)) return true;

    final digitSequence = _digitSequenceInfo(command.rawText);
    if (!digitSequence.isDigitSequence) return false;
    return digitSequence.count < 4 && !digitSequence.endsAsSpokenHundred;
  }

  static bool claimIsStableForAutoStop(VoiceCommand command) {
    if (command.intent != VoiceIntent.claim || command.alertNumber == null) {
      return false;
    }
    if (claimMayNeedMoreSpeech(command)) return false;

    final digitSequence = _digitSequenceInfo(command.rawText);
    if (!digitSequence.isDigitSequence) return true;
    return digitSequence.count >= 4 || digitSequence.endsAsSpokenHundred;
  }

  /// Parse a finalized transcription string into a [VoiceCommand].
  /// Returns a command with `intent = unknown` if the verb is not recognized.
  static VoiceCommand parse(String transcript) {
    final raw = transcript.trim();
    if (raw.isEmpty) {
      return VoiceCommand(intent: VoiceIntent.unknown, rawText: raw);
    }

    // Normalize: lowercase, collapse whitespace, strip punctuation.
    final normalized = _normalize(raw);
    final tokens = normalized.isEmpty
        ? const <String>[]
        : normalized.split(' ').where((t) => t.isNotEmpty).toList();

    // Multi-word navigation commands first (they have no number).
    if (normalized.contains('show dashboard') ||
        normalized.contains('open dashboard') ||
        normalized.contains('go to dashboard')) {
      return VoiceCommand(intent: VoiceIntent.showDashboard, rawText: raw);
    }
    if (normalized.contains('show alerts') ||
        normalized.contains('open alerts') ||
        normalized.contains('list alerts')) {
      return VoiceCommand(intent: VoiceIntent.showAlerts, rawText: raw);
    }
    if (normalized.contains('show fixed') ||
        normalized.contains('show resolved') ||
        normalized.contains('show validated')) {
      return VoiceCommand(intent: VoiceIntent.showFixed, rawText: raw);
    }

    final intent = _detectIntent(normalized, tokens);
    if (intent == VoiceIntent.unknown) {
      _logUnparsed(raw);
      return VoiceCommand(intent: VoiceIntent.unknown, rawText: raw);
    }

    // Split off the resolve reason if present, before number extraction —
    // otherwise digits inside the reason ("error 5") would leak into alertNumber.
    String beforeReason = normalized;
    String? reason;
    if (intent == VoiceIntent.resolve) {
      final reasonMatch = RegExp(
        r'\bwith reason\b\s*(.*)$',
      ).firstMatch(normalized);
      if (reasonMatch != null) {
        reason = reasonMatch.group(1)?.trim();
        if (reason != null && reason.isEmpty) reason = null;
        beforeReason = normalized.substring(0, reasonMatch.start).trim();
      }
    }

    final number = _extractNumber(beforeReason);
    return VoiceCommand(
      intent: intent,
      alertNumber: number,
      reason: reason,
      rawText: raw,
    );
  }

  /// Affirmative-response check for the confirmation step. Accepts "yes",
  /// "yeah", "yep", "confirm", "confirmed", "ok", "okay", "go", "go ahead",
  /// "claim", "do it". Anything else (including silence / empty) is "no".
  static bool isYes(String transcript) {
    final t = transcript
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r"[^a-z0-9\s]"), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (t.isEmpty) return false;
    const positives = {
      'yes',
      'yeah',
      'yep',
      'yup',
      'sure',
      'confirm',
      'confirmed',
      'ok',
      'okay',
      'go',
      'go ahead',
      'do it',
      'do that',
      'claim',
      'claim it',
      'accept',
      'affirmative',
      'correct',
    };
    if (positives.contains(t)) return true;
    // Phrase forms: "yes confirm", "yes do it", "claim it" etc.
    for (final p in positives) {
      if (t.startsWith('$p ') || t.endsWith(' $p') || t.contains(' $p ')) {
        return true;
      }
    }
    return false;
  }

  static VoiceIntent _detectIntent(String normalized, List<String> tokens) {
    if (tokens.isEmpty) return VoiceIntent.unknown;

    // Shift commands — must be checked before claim/resolve so the verbs
    // "take" / "join" don't get re-interpreted as alert claims.
    if (_containsAnyPhrase(normalized, const {
      'start shift handover',
      'start handover',
      'shift handover',
      'generate handover',
      'do handover',
      'begin handover',
    })) {
      return VoiceIntent.shiftHandover;
    }
    if (_containsAnyPhrase(normalized, const {
      'i am ready for shift',
      'im ready for shift',
      'mark me ready',
      'ready for shift',
      'shift ready',
    })) {
      return VoiceIntent.shiftReady;
    }
    if (_containsAnyPhrase(normalized, const {
      'assign me to the morning shift',
      'assign me to morning shift',
      'assign me to the evening shift',
      'assign me to evening shift',
      'assign me to the afternoon shift',
      'assign me to afternoon shift',
      'assign me to the night shift',
      'assign me to night shift',
      'join morning shift',
      'join the morning shift',
      'join evening shift',
      'join the evening shift',
      'join afternoon shift',
      'join the afternoon shift',
      'join night shift',
      'join the night shift',
      'add me to the shift',
      'put me on the shift',
    })) {
      return VoiceIntent.joinShift;
    }

    if (_containsAnyPhrase(normalized, const {
          'mark alert as critical',
          'mark the alert as critical',
          'make alert critical',
          'make the alert critical',
          'set alert critical',
          'set the alert critical',
          'mark critical',
          'make critical',
          'set critical',
          'alert critical',
          'critical alert',
          'raise priority',
        }) ||
        (tokens.contains('critical') && _mentionsAlert(tokens)) ||
        _containsAnyToken(tokens, const {
          'escalate',
          'escalated',
          'escalating',
          'escalation',
          'escalade',
        })) {
      return VoiceIntent.escalate;
    }

    if (_containsAnyPhrase(normalized, const {
          'suspend alert',
          'suspend the alert',
          'pause alert',
          'pause the alert',
          'hold alert',
          'hold the alert',
          'return alert',
          'return the alert',
          'send alert back',
          'send the alert back',
          'put alert back',
          'put the alert back',
        }) ||
        _containsAnyToken(tokens, const {
          'suspend',
          'suspended',
          'suspending',
          'pause',
          'paused',
          'hold',
          'return',
        })) {
      return VoiceIntent.suspend;
    }

    if (_containsAnyPhrase(normalized, const {
          'close alert',
          'finish alert',
          'fix alert',
          'mark fixed',
          'mark resolved',
          'validate alert',
        }) ||
        _containsAnyToken(tokens, const {
          'resolve',
          'resolves',
          'resolved',
          'resolver',
          'resolving',
          'result',
          'results',
          'reserve',
          'reserved',
          'dissolve',
          'dissolved',
          'revolve',
          'revolved',
          'solve',
          'solved',
          'close',
          'closed',
          'finish',
          'finished',
          'fix',
          'fixed',
          'done',
          'validate',
          'validated',
        })) {
      return VoiceIntent.resolve;
    }

    if (_containsAnyPhrase(normalized, const {
          'claim alert',
          'claim the alert',
          'claim alarm',
          'claim ticket',
          'take alert',
          'take the alert',
          'grab alert',
          'grab the alert',
          'accept assignment',
          'accept the assignment',
          'accept this assignment',
          'assign it to me',
          'assign to me',
          'i will take',
          'ill take',
          'i ll take',
          'pick up',
          'take this',
        }) ||
        _containsAnyToken(tokens, const {
          'claim',
          'claimed',
          'claiming',
          'take',
          'taking',
          'accept',
          'accepted',
          'grab',
          'handle',
          'mine',
        })) {
      return VoiceIntent.claim;
    }

    if (_mentionsAlert(tokens) &&
        _containsAnyToken(tokens, const {
          'clean',
          'climb',
          'clim',
          'client',
          'clam',
          'plane',
          'plain',
        })) {
      return VoiceIntent.claim;
    }

    // Last-chance heuristic: bare verb followed by a number, no "alert"
    // wrapper. Matches "claim 1025", "resolve 1025", "escalate 1025", and
    // their common STT misrecognitions when the supervisor speaks fast.
    if (tokens.length >= 2) {
      final first = tokens.first;
      final hasNumber =
          RegExp(r'\d').hasMatch(normalized) || _hasNumberWord(tokens);
      if (hasNumber) {
        final intentFromFirst = _canonicalIntentFromFirstToken(first);
        if (_isActionIntent(intentFromFirst)) return intentFromFirst;
      }
    }

    return VoiceIntent.unknown;
  }

  static bool _hasNumberWord(List<String> tokens) {
    for (final t in tokens) {
      if (_ones.containsKey(t) ||
          _tens.containsKey(t) ||
          _scales.containsKey(t)) {
        return true;
      }
    }
    return false;
  }

  static List<String> _withClaimContinuations(List<String> unique) {
    final merged = <String>[];
    for (var i = 0; i < unique.length; i++) {
      final base = unique[i];
      final baseIntent = _intentOf(base);
      if (baseIntent != VoiceIntent.claim) continue;

      for (var j = i + 1; j < unique.length; j++) {
        final continuation = unique[j];
        if (!_looksLikeNumberOnlyContinuation(continuation)) continue;
        merged.add('$base $continuation');
      }
    }

    if (merged.isEmpty) return unique;
    return [...merged, ...unique];
  }

  static VoiceIntent _intentOf(String text) {
    final tokens = _normalizedTokens(text);
    if (tokens.isEmpty) return VoiceIntent.unknown;
    return _detectIntent(tokens.join(' '), tokens);
  }

  static bool _looksLikeNumberOnlyContinuation(String text) {
    final tokens = _normalizedTokens(text);
    if (tokens.isEmpty) return false;
    if (_isActionIntent(_detectIntent(tokens.join(' '), tokens))) {
      return false;
    }
    return RegExp(r'\d').hasMatch(text) || _hasNumberWord(tokens);
  }

  static int _claimCompletenessScore(VoiceCommand command) {
    final tokens = _normalizedTokens(command.rawText);
    var numberTokenCount = 0;
    for (final token in tokens) {
      if (_isNumberComponent(token) || RegExp(r'^\d{1,7}$').hasMatch(token)) {
        numberTokenCount++;
      }
    }
    final digitCount = command.alertNumber?.toString().length ?? 0;
    return numberTokenCount * 1000 + digitCount * 10 + tokens.length;
  }

  static bool _isNumberComponent(String token) {
    return _ones.containsKey(token) ||
        _tens.containsKey(token) ||
        _scales.containsKey(token);
  }

  static _DigitSequenceInfo _digitSequenceInfo(String text) {
    final tokens = _normalizedTokens(text);
    var started = false;
    var count = 0;
    var sawNonDigitNumber = false;
    final digitWords = <String>[];

    for (final token in tokens) {
      if (_numberFillers.contains(token)) continue;

      final digit = _digitWordValue(token);
      if (digit != null) {
        started = true;
        count++;
        digitWords.add(token);
        continue;
      }

      if (!started) continue;

      if (_isNumberComponent(token)) {
        sawNonDigitNumber = true;
      }
      break;
    }

    final endsAsSpokenHundred =
        digitWords.length == 3 &&
        _digitWordValue(digitWords[digitWords.length - 1]) == 0 &&
        _digitWordValue(digitWords[digitWords.length - 2]) == 0;

    return _DigitSequenceInfo(
      isDigitSequence: started && count > 0 && !sawNonDigitNumber,
      count: count,
      endsAsSpokenHundred: endsAsSpokenHundred,
    );
  }

  static bool _containsAnyPhrase(String text, Set<String> phrases) {
    for (final phrase in phrases) {
      if (text.contains(phrase)) return true;
    }
    return false;
  }

  static bool _containsAnyToken(List<String> tokens, Set<String> choices) {
    for (final token in tokens) {
      if (choices.contains(token)) return true;
    }
    return false;
  }

  static bool _mentionsAlert(List<String> tokens) {
    return _containsAnyToken(tokens, const {
      'alert',
      'alerts',
      'alarm',
      'alarms',
      'assignment',
      'case',
      'lert',
      'ticket',
    });
  }

  static bool _looksLikeCanonicalAction(String normalized) {
    final tokens = normalized.isEmpty
        ? const <String>[]
        : normalized.split(' ').where((t) => t.isNotEmpty).toList();
    if (tokens.isEmpty) return false;

    final intent = _canonicalIntentFromFirstToken(tokens.first);
    if (!_isActionIntent(intent)) return false;

    // "claim alert 1025" — the original strict shape.
    final alertIndex = tokens.indexWhere(_isAlertToken);
    if (alertIndex > 0 && alertIndex <= 4) return true;

    // "claim 1025" — supervisor skips the word "alert". Accept any action
    // verb followed by a digit run within the first few tokens, since this
    // is the most common phrasing in field tests.
    for (var i = 1; i < tokens.length && i <= 4; i++) {
      if (RegExp(r'^\d{1,7}$').hasMatch(tokens[i])) return true;
      if (_ones.containsKey(tokens[i]) || _tens.containsKey(tokens[i])) {
        return true;
      }
    }
    return false;
  }

  static VoiceIntent _canonicalIntentFromFirstToken(String token) {
    if (const {
      'claim',
      'claimed',
      'claiming',
      'clean',
      'climb',
      'clim',
      'client',
      'clam',
      'plane',
      'plain',
    }.contains(token)) {
      return VoiceIntent.claim;
    }

    if (const {
      'resolve',
      'resolves',
      'resolved',
      'resolver',
      'resolving',
      'result',
      'results',
      'reserve',
      'reserved',
      'dissolve',
      'dissolved',
      'revolve',
      'revolved',
      'solve',
      'solved',
      'close',
      'closed',
      'finish',
      'finished',
      'fix',
      'fixed',
      'done',
      'validate',
      'validated',
    }.contains(token)) {
      return VoiceIntent.resolve;
    }

    if (const {
      'suspend',
      'suspended',
      'suspending',
      'pause',
      'paused',
      'hold',
      'return',
    }.contains(token)) {
      return VoiceIntent.suspend;
    }

    if (const {
      'escalate',
      'escalated',
      'escalating',
      'escalation',
      'escalade',
      'mark',
      'make',
      'set',
      'critical',
    }.contains(token)) {
      return VoiceIntent.escalate;
    }

    return VoiceIntent.unknown;
  }

  static bool _isAlertToken(String token) {
    return const {
      'alert',
      'alerts',
      'alarm',
      'alarms',
      'assignment',
      'case',
      'lert',
      'ticket',
    }.contains(token);
  }

  static bool _isActionIntent(VoiceIntent intent) {
    return intent == VoiceIntent.claim ||
        intent == VoiceIntent.resolve ||
        intent == VoiceIntent.suspend ||
        intent == VoiceIntent.escalate;
  }

  /// Extracts the first number found in [text]. Recognizes both digit
  /// runs ("1025") and English number words ("one thousand twenty five").
  static int? _extractNumber(String text) {
    // Digit run wins immediately if present.
    final digitMatch = RegExp(r'\b(\d{1,7})\b').firstMatch(text);
    if (digitMatch != null) {
      return int.tryParse(digitMatch.group(1)!);
    }

    final tokens = text.split(' ');
    if (tokens.any(_scales.containsKey)) {
      final scaledNumber = _extractScaledNumber(tokens);
      if (scaledNumber != null) {
        return scaledNumber;
      }
    }

    final chunkedAlertNumber = _extractChunkedNumber(tokens);
    if (chunkedAlertNumber != null) {
      return chunkedAlertNumber;
    }

    final digitSequence = _extractSpokenDigitSequence(tokens);
    if (digitSequence != null) {
      return digitSequence;
    }

    return _extractScaledNumber(tokens);
  }

  static int? _extractScaledNumber(List<String> tokens) {
    var total = 0;
    var current = 0;
    var sawAny = false;

    for (final t in tokens) {
      if (_ones.containsKey(t)) {
        current += _ones[t]!;
        sawAny = true;
      } else if (_tens.containsKey(t)) {
        current += _tens[t]!;
        sawAny = true;
      } else if (t == 'hundred') {
        // "two hundred" → current = 2 → 200. "hundred" alone → 100.
        current = (current == 0 ? 1 : current) * _scales[t]!;
        sawAny = true;
      } else if (t == 'thousand') {
        current = (current == 0 ? 1 : current) * _scales[t]!;
        total += current;
        current = 0;
        sawAny = true;
      } else if (_numberFillers.contains(t)) {
        continue;
      } else if (sawAny && current > 0) {
        // Filler word after we already started — flush and stop. Prevents
        // "claim alert 1025 please" from greedily consuming "please".
        break;
      }
    }
    final result = total + current;
    return sawAny ? result : null;
  }

  static int? _extractSpokenDigitSequence(List<String> tokens) {
    final digits = <int>[];
    for (final token in tokens) {
      final digit = _ones[token];
      if (digit != null && digit >= 0 && digit <= 9) {
        digits.add(digit);
      } else if (_numberFillers.contains(token)) {
        continue;
      } else if (digits.isNotEmpty) {
        break;
      }
    }

    if (digits.length < 2) return null;
    return int.tryParse(digits.join());
  }

  static String _normalize(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r"[^a-z0-9\s]"), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static List<String> _normalizedTokens(String text) {
    final normalized = _normalize(text);
    return normalized.isEmpty
        ? const <String>[]
        : normalized.split(' ').where((t) => t.isNotEmpty).toList();
  }

  static bool _requiresAlertNumber(VoiceIntent intent) {
    return intent == VoiceIntent.claim;
  }

  static int? _extractChunkedNumber(List<String> tokens) {
    for (var start = 0; start < tokens.length; start++) {
      final chunks = <_NumberChunk>[];
      var index = start;

      while (index < tokens.length) {
        final token = tokens[index];
        if (_numberFillers.contains(token)) {
          index++;
          continue;
        }

        final chunk = _readNumberChunk(tokens, index);
        if (chunk == null) break;
        chunks.add(chunk);
        index += chunk.tokenCount;
      }

      final value = _numberFromChunks(chunks);
      if (value != null) return value;
    }
    return null;
  }

  static _NumberChunk? _readNumberChunk(List<String> tokens, int index) {
    final token = tokens[index];

    if (_tens.containsKey(token)) {
      final tens = _tens[token]!;
      final nextIndex = index + 1;
      if (nextIndex < tokens.length) {
        final nextDigit = _digitWordValue(tokens[nextIndex]);
        if (nextDigit != null && nextDigit > 0) {
          return _NumberChunk(tens + nextDigit, 2, 2);
        }
      }
      return _NumberChunk(tens, 2, 1);
    }

    final value = _ones[token];
    if (value == null) return null;
    if (value >= 0 && value <= 9) {
      return _NumberChunk(value, 1, 1);
    }
    return _NumberChunk(value, 2, 1);
  }

  static int? _numberFromChunks(List<_NumberChunk> chunks) {
    if (chunks.isEmpty) return null;

    if (chunks.every((chunk) => chunk.width == 1) && chunks.length >= 2) {
      return int.tryParse(chunks.map((chunk) => chunk.value).join());
    }

    if (chunks.length >= 3 &&
        chunks[0].width == 2 &&
        chunks.skip(1).every((chunk) => chunk.width == 1)) {
      final digits = chunks
          .map((chunk) => chunk.value.toString().padLeft(chunk.width, '0'))
          .join();
      return int.tryParse(digits);
    }

    if (chunks.length == 2 && chunks[0].width == 1 && chunks[1].width == 2) {
      return chunks[0].value * 100 + chunks[1].value;
    }

    if (chunks.length == 2 && chunks[0].width == 2 && chunks[1].width == 2) {
      return chunks[0].value * 100 + chunks[1].value;
    }

    if (chunks.length == 3 &&
        chunks[0].width == 2 &&
        chunks[1].width == 1 &&
        chunks[2].width == 1) {
      return chunks[0].value * 100 + chunks[1].value * 10 + chunks[2].value;
    }

    if (chunks.length == 3 &&
        chunks[0].width == 1 &&
        chunks[1].width == 1 &&
        chunks[2].width == 2) {
      return chunks[0].value * 1000 + chunks[1].value * 100 + chunks[2].value;
    }

    return null;
  }

  static int? _digitWordValue(String token) {
    final value = _ones[token];
    if (value == null || value < 0 || value > 9) return null;
    return value;
  }
}

class _NumberChunk {
  final int value;
  final int width;
  final int tokenCount;

  const _NumberChunk(this.value, this.width, this.tokenCount);
}

class _DigitSequenceInfo {
  final bool isDigitSequence;
  final int count;
  final bool endsAsSpokenHundred;

  const _DigitSequenceInfo({
    required this.isDigitSequence,
    required this.count,
    required this.endsAsSpokenHundred,
  });
}
