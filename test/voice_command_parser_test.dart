import 'package:alertsysapp/services/voice_command_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VoiceCommandParser.parse', () {
    test('understands plain claim alert without a number', () {
      final command = VoiceCommandParser.parse('claim alert');

      expect(command.intent, VoiceIntent.claim);
      expect(command.alertNumber, isNull);
      expect(command.isValid, isTrue);
    });

    test('understands natural claim phrases with number words', () {
      final command = VoiceCommandParser.parse(
          'please claim the alert number one zero two five');

      expect(command.intent, VoiceIntent.claim);
      expect(command.alertNumber, 1025);
    });

    test('understands exact full commands with hash numbers', () {
      final command = VoiceCommandParser.parse('Claim alert #1025');

      expect(command.intent, VoiceIntent.claim);
      expect(command.alertNumber, 1025);
    });

    test('understands four digit alert numbers spoken as pairs', () {
      final command = VoiceCommandParser.parse('claim alert ten twenty five');

      expect(command.intent, VoiceIntent.claim);
      expect(command.alertNumber, 1025);
    });

    test('understands mixed digit and pair alert numbers', () {
      final command =
          VoiceCommandParser.parse('claim alert one zero twenty five');

      expect(command.intent, VoiceIntent.claim);
      expect(command.alertNumber, 1025);
    });

    test('understands take as a claim synonym', () {
      final command =
          VoiceCommandParser.parse('can you take alert twenty four');

      expect(command.intent, VoiceIntent.claim);
      expect(command.alertNumber, 24);
    });

    test('handles common claim misrecognitions when alert is mentioned', () {
      final command = VoiceCommandParser.parse('clean alert two five');

      expect(command.intent, VoiceIntent.claim);
      expect(command.alertNumber, 25);
    });

    test('keeps resolve reason separate from alert number', () {
      final command = VoiceCommandParser.parse(
        'resolve alert 12 with reason belt replaced at station five',
      );

      expect(command.intent, VoiceIntent.resolve);
      expect(command.alertNumber, 12);
      expect(command.reason, 'belt replaced at station five');
    });

    test('handles common resolve misrecognitions when alert is mentioned', () {
      final command = VoiceCommandParser.parse('result alert ten two five');

      expect(command.intent, VoiceIntent.resolve);
      expect(command.alertNumber, 1025);
    });

    test('detects escalate intent', () {
      final command = VoiceCommandParser.parse('escalate alert 42');
      expect(command.intent, VoiceIntent.escalate);
      expect(command.alertNumber, 42);
    });

    test('detects escalate from "mark critical" phrasing', () {
      final command = VoiceCommandParser.parse('mark critical alert 42');
      expect(command.intent, VoiceIntent.escalate);
      expect(command.alertNumber, 42);
    });

    test('navigation: show dashboard', () {
      final command = VoiceCommandParser.parse('show dashboard');
      expect(command.intent, VoiceIntent.showDashboard);
    });

    test('navigation: open dashboard maps to showDashboard', () {
      final command = VoiceCommandParser.parse('open dashboard');
      expect(command.intent, VoiceIntent.showDashboard);
    });

    test('navigation: show alerts', () {
      final command = VoiceCommandParser.parse('show alerts');
      expect(command.intent, VoiceIntent.showAlerts);
    });

    test('navigation: show fixed', () {
      final command = VoiceCommandParser.parse('show fixed');
      expect(command.intent, VoiceIntent.showFixed);
    });

    test('navigation: show validated', () {
      final command = VoiceCommandParser.parse('show validated');
      expect(command.intent, VoiceIntent.showFixed);
    });

    test('returns unknown for unrelated speech', () {
      final command = VoiceCommandParser.parse('what time is it');
      expect(command.intent, VoiceIntent.unknown);
      expect(command.isValid, isFalse);
    });

    test('returns unknown for empty input', () {
      final command = VoiceCommandParser.parse('');
      expect(command.intent, VoiceIntent.unknown);
    });

    test('returns unknown for whitespace only', () {
      final command = VoiceCommandParser.parse('   ');
      expect(command.intent, VoiceIntent.unknown);
    });

    test('lenient: bare "claim 1025" without alert word is recognized', () {
      final command = VoiceCommandParser.parse('claim 1025');
      expect(command.intent, VoiceIntent.claim);
      expect(command.alertNumber, 1025);
    });

    test('lenient: bare "resolve 1025" without alert word is recognized', () {
      final command = VoiceCommandParser.parse('resolve 1025');
      expect(command.intent, VoiceIntent.resolve);
      expect(command.alertNumber, 1025);
    });

    test('lenient: bare "escalate 1025" without alert word is recognized', () {
      final command = VoiceCommandParser.parse('escalate 1025');
      expect(command.intent, VoiceIntent.escalate);
      expect(command.alertNumber, 1025);
    });

    test('punctuation does not break parsing', () {
      final command = VoiceCommandParser.parse('Claim alert, 1025!');
      expect(command.intent, VoiceIntent.claim);
      expect(command.alertNumber, 1025);
    });

    test('large numbers are parsed correctly', () {
      final command =
          VoiceCommandParser.parse('claim alert one thousand two hundred');
      expect(command.intent, VoiceIntent.claim);
      expect(command.alertNumber, 1200);
    });
  });

  group('VoiceCommandParser.parseBest', () {
    test('chooses a complete command from recognition alternatives', () {
      final command = VoiceCommandParser.parseBest([
        'clean alert',
        'claim alert ten twenty five',
      ]);

      expect(command.intent, VoiceIntent.claim);
      expect(command.alertNumber, 1025);
    });

    test('returns first valid when no complete command exists', () {
      final command = VoiceCommandParser.parseBest([
        'clean alert',
        'noise',
      ]);

      expect(command.intent, VoiceIntent.claim);
      expect(command.alertNumber, isNull);
    });

    test('returns unknown when no transcripts are valid', () {
      final command = VoiceCommandParser.parseBest([
        'random noise',
        'gibberish',
      ]);
      expect(command.intent, VoiceIntent.unknown);
    });

    test('handles empty transcript list', () {
      final command = VoiceCommandParser.parseBest(<String>[]);
      expect(command.intent, VoiceIntent.unknown);
      expect(command.rawText, isEmpty);
    });

    test('deduplicates identical transcripts', () {
      final command = VoiceCommandParser.parseBest([
        'claim alert 100',
        'claim alert 100',
      ]);
      expect(command.intent, VoiceIntent.claim);
      expect(command.alertNumber, 100);
    });
  });

  group('VoiceCommandParser.parseCanonical', () {
    test('accepts canonical claim alert NUMBER', () {
      final command = VoiceCommandParser.parseCanonical(
        ['claim alert one thousand twenty five'],
      );
      expect(command.intent, VoiceIntent.claim);
      expect(command.alertNumber, 1025);
    });

    test('accepts canonical resolve with reason', () {
      final command = VoiceCommandParser.parseCanonical(
        ['resolve alert ten twenty five with reason fixed motor'],
      );
      expect(command.intent, VoiceIntent.resolve);
      expect(command.alertNumber, 1025);
      expect(command.reason, 'fixed motor');
    });

    test('accepts common canonical claim misrecognitions', () {
      final command = VoiceCommandParser.parseCanonical(
        ['clean alert one zero two five'],
      );
      expect(command.intent, VoiceIntent.claim);
      expect(command.alertNumber, 1025);
    });

    test('accepts common canonical resolve misrecognitions', () {
      final command = VoiceCommandParser.parseCanonical(
        ['result alert ten two five'],
      );
      expect(command.intent, VoiceIntent.resolve);
      expect(command.alertNumber, 1025);
    });

    test('accepts polite action-first commands', () {
      final command = VoiceCommandParser.parseCanonical(
        ['please claim the alert number one zero two five'],
      );
      expect(command.intent, VoiceIntent.claim);
      expect(command.alertNumber, 1025);
    });

    test('accepts canonical escalate alert NUMBER', () {
      final command = VoiceCommandParser.parseCanonical(
        ['escalate alert one zero two five'],
      );
      expect(command.intent, VoiceIntent.escalate);
      expect(command.alertNumber, 1025);
    });

    test('rejects loose phrasings the lenient parser would accept', () {
      final command = VoiceCommandParser.parseCanonical(
        ['I will take alert one zero two five'],
      );
      expect(command.intent, VoiceIntent.unknown);
    });

    test('rejects partial commands without a number', () {
      final command = VoiceCommandParser.parseCanonical(['claim alert']);
      expect(command.intent, VoiceIntent.unknown);
      expect(command.alertNumber, isNull);
    });

    test('falls through to a later alternative when first is junk', () {
      final command = VoiceCommandParser.parseCanonical([
        'clean alert',
        'claim alert ten twenty five',
      ]);
      expect(command.intent, VoiceIntent.claim);
      expect(command.alertNumber, 1025);
    });

    test('lenient: accepts "claim 1025" without the alert word', () {
      final command = VoiceCommandParser.parseCanonical(['claim 1025']);
      expect(command.intent, VoiceIntent.claim);
      expect(command.alertNumber, 1025);
    });
  });

  group('VoiceCommandParser.isYes', () {
    test('accepts plain affirmatives', () {
      for (final v in ['yes', 'yeah', 'yep', 'yup', 'sure', 'ok', 'okay']) {
        expect(VoiceCommandParser.isYes(v), isTrue, reason: v);
      }
    });

    test('accepts punctuated confirmation phrases', () {
      expect(VoiceCommandParser.isYes('Yes, claim it.'), isTrue);
    });

    test('accepts mixed-case affirmatives', () {
      expect(VoiceCommandParser.isYes('YES'), isTrue);
      expect(VoiceCommandParser.isYes('CoNfIrM'), isTrue);
    });

    test('rejects empty input', () {
      expect(VoiceCommandParser.isYes(''), isFalse);
      expect(VoiceCommandParser.isYes('   '), isFalse);
    });

    test('rejects negatives', () {
      expect(VoiceCommandParser.isYes('no'), isFalse);
      expect(VoiceCommandParser.isYes('cancel'), isFalse);
      expect(VoiceCommandParser.isYes('stop'), isFalse);
    });
  });

  group('VoiceCommand', () {
    test('toString produces a readable form', () {
      const cmd = VoiceCommand(
        intent: VoiceIntent.claim,
        alertNumber: 42,
        rawText: 'claim alert 42',
      );
      final s = cmd.toString();
      expect(s, contains('claim'));
      expect(s, contains('42'));
    });

    test('isValid is false for unknown intent', () {
      const cmd = VoiceCommand(
        intent: VoiceIntent.unknown,
        rawText: 'nope',
      );
      expect(cmd.isValid, isFalse);
    });
  });
}
