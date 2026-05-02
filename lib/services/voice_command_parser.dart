// Pure-logic voice command parser. No I/O, no Flutter — easy to unit test.
//
// Translates a transcription like "claim alert one thousand twenty five"
// into a structured [VoiceCommand]. Knows how to:
//   1. Map English number words ("one thousand twenty five") to digits (1025).
//   2. Extract the intent verb (claim / resolve / escalate / show ...).
//   3. Pull a free-text "reason" segment for resolve commands.
//   4. Detect yes/no confirmations (used by the notification claim flow).

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
    'alarm',
    'case',
    'id',
    'no',
    'number',
    'num',
    'please',
    'the',
  };

  /// Parse a finalized transcription string into a [VoiceCommand].
  /// Returns a command with `intent = unknown` if the verb is not recognized.
  static VoiceCommand parse(String transcript) {
    final raw = transcript.trim();
    if (raw.isEmpty) {
      return VoiceCommand(intent: VoiceIntent.unknown, rawText: raw);
    }

    // Normalize: lowercase, collapse whitespace, strip punctuation.
    final normalized = raw
        .toLowerCase()
        .replaceAll(RegExp(r"[^a-z0-9\s]"), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
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
          'resolved',
          'resolving',
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
          'client',
          'clam',
          'plane',
          'plain',
        })) {
      return VoiceIntent.claim;
    }

    return VoiceIntent.unknown;
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
      'ticket',
    });
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
}
