// Pure-logic voice command parser. No I/O, no Flutter — easy to unit test.
//
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
  escalate,
  showDashboard,
  showAlerts,
  showFixed,
  unknown,
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
  static const Map<String, int> _scales = {
    'hundred': 100,
    'thousand': 1000,
  };
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
  /// a complete action command (claim/resolve/escalate + alertNumber). Some
  /// recognizers include the right phrase as a later alternative, so iterating
  /// hypotheses keeps the command flow from failing on the first noisy guess.
  static VoiceCommand parseCanonical(Iterable<String> transcripts) {
    for (final transcript in transcripts) {
      final cmd = _parseCanonicalSingle(transcript);
      if (cmd.isValid && cmd.alertNumber != null) return cmd;
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
    if (!_isActionIntent(command.intent) || command.alertNumber == null) {
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

    VoiceCommand? firstValid;
    for (final transcript in unique) {
      final command = parse(transcript);
      if (!command.isValid) continue;
      firstValid ??= command;
      if (!_requiresAlertNumber(command.intent) ||
          command.alertNumber != null) {
        return command;
      }
    }
    return firstValid ?? parse(unique.first);
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
      return VoiceCommand(intent: VoiceIntent.unknown, rawText: raw);
    }

    // Split off the resolve reason if present, before number extraction —
    // otherwise digits inside the reason ("error 5") would leak into alertNumber.
    String beforeReason = normalized;
    String? reason;
    if (intent == VoiceIntent.resolve) {
      final reasonMatch =
          RegExp(r'\bwith reason\b\s*(.*)$').firstMatch(normalized);
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

    if (_containsAnyPhrase(normalized, const {
          'mark critical',
          'make critical',
          'set critical',
          'raise priority',
        }) ||
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
          'take the alert',
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
      if (_ones.containsKey(t) || _tens.containsKey(t) ||
          _scales.containsKey(t)) {
        return true;
      }
    }
    return false;
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
      'escalate',
      'escalated',
      'escalating',
      'escalation',
      'escalade',
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
    final chunkedAlertNumber = _extractChunkedNumber(tokens);
    if (chunkedAlertNumber != null) {
      return chunkedAlertNumber;
    }

    final digitSequence = _extractSpokenDigitSequence(tokens);
    if (digitSequence != null) {
      return digitSequence;
    }

    int total = 0; // accumulated value of finished segments
    int current = 0; // current segment being built
    bool sawAny = false; // did we ever consume a number word?

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

  static bool _requiresAlertNumber(VoiceIntent intent) {
    return intent == VoiceIntent.claim ||
        intent == VoiceIntent.resolve ||
        intent == VoiceIntent.escalate;
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
