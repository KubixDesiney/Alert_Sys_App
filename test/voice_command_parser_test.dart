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
        'please claim the alert number one zero two five',
      );

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
      final command = VoiceCommandParser.parse(
        'claim alert one zero twenty five',
      );

      expect(command.intent, VoiceIntent.claim);
      expect(command.alertNumber, 1025);
    });

    test('understands take as a claim synonym', () {
      final command = VoiceCommandParser.parse(
        'can you take alert twenty four',
      );

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

    test('accepts resolve alert without a number', () {
      final command = VoiceCommandParser.parse('resolve alert');

      expect(command.intent, VoiceIntent.resolve);
      expect(command.alertNumber, isNull);
    });

    test('accepts suspend alert without a number', () {
      final command = VoiceCommandParser.parse('suspend alert');

      expect(command.intent, VoiceIntent.suspend);
      expect(command.alertNumber, isNull);
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

    test('detects mark alert as critical without a number', () {
      final command = VoiceCommandParser.parse('mark alert as critical');
      expect(command.intent, VoiceIntent.escalate);
      expect(command.alertNumber, isNull);
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
      final command = VoiceCommandParser.parse(
        'claim alert one thousand two hundred',
      );
      expect(command.intent, VoiceIntent.claim);
      expect(command.alertNumber, 1200);
    });

    test('understands exact thousand alerts', () {
      final command = VoiceCommandParser.parse('claim alert one thousand');

      expect(command.intent, VoiceIntent.claim);
      expect(command.alertNumber, 1000);
    });

    test('understands long natural alert numbers', () {
      final command = VoiceCommandParser.parse(
        'claim alert twenty one thousand eight hundred and twenty',
      );

      expect(command.intent, VoiceIntent.claim);
      expect(command.alertNumber, 21820);
    });

    test('understands long natural alert numbers ending in ones', () {
      final command = VoiceCommandParser.parse(
        'claim alert twenty one thousand eight hundred twenty one',
      );

      expect(command.intent, VoiceIntent.claim);
      expect(command.alertNumber, 21821);
    });

    test('understands long natural alert numbers ending in ones with and', () {
      final command = VoiceCommandParser.parse(
        'claim alert twenty one thousand eight hundred and twenty one',
      );

      expect(command.intent, VoiceIntent.claim);
      expect(command.alertNumber, 21821);
    });

    test('understands long alert numbers spoken digit by digit', () {
      final command = VoiceCommandParser.parse(
        'claim alert two one eight two zero',
      );

      expect(command.intent, VoiceIntent.claim);
      expect(command.alertNumber, 21820);
    });

    test('understands mixed natural prefix and digit sequence', () {
      final command = VoiceCommandParser.parse(
        'claim alert twenty one eight two zero',
      );

      expect(command.intent, VoiceIntent.claim);
      expect(command.alertNumber, 21820);
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

    test('can complete claim when the alert number is heard separately', () {
      final command = VoiceCommandParser.parseBest([
        'claim alert',
        'one zero two five',
        'claim alert one zero two five',
      ]);

      expect(command.intent, VoiceIntent.claim);
      expect(command.alertNumber, 1025);
    });

    test('prefers the longer complete long-number claim', () {
      final command = VoiceCommandParser.parseBest([
        'claim alert twenty one thousand',
        'claim alert twenty one thousand eight hundred and twenty',
      ]);

      expect(command.intent, VoiceIntent.claim);
      expect(command.alertNumber, 21820);
    });

    test('prefers complete natural long-number claim ending in ones', () {
      final command = VoiceCommandParser.parseBest([
        'claim alert twenty one thousand eight hundred twenty',
        'claim alert twenty one thousand eight hundred twenty one',
      ]);

      expect(command.intent, VoiceIntent.claim);
      expect(command.alertNumber, 21821);
    });

    test('merges a natural long-number continuation', () {
      final command = VoiceCommandParser.parseBest([
        'claim alert twenty one thousand',
        'eight hundred and twenty',
      ]);

      expect(command.intent, VoiceIntent.claim);
      expect(command.alertNumber, 21820);
    });

    test('merges a digit-by-digit long-number continuation', () {
      final command = VoiceCommandParser.parseBest([
        'claim alert two one',
        'eight two zero',
      ]);

      expect(command.intent, VoiceIntent.claim);
      expect(command.alertNumber, 21820);
    });

    test('merges mixed natural prefix and digit continuation', () {
      final command = VoiceCommandParser.parseBest([
        'claim alert twenty one',
        'eight two zero',
      ]);

      expect(command.intent, VoiceIntent.claim);
      expect(command.alertNumber, 21820);
    });

    test('merges short digit prefix and continuation', () {
      final command = VoiceCommandParser.parseBest([
        'claim alert one one',
        'zero zero',
      ]);

      expect(command.intent, VoiceIntent.claim);
      expect(command.alertNumber, 1100);
    });

    test('merges single digit prefix and continuation', () {
      final command = VoiceCommandParser.parseBest([
        'claim alert nine',
        'zero zero',
      ]);

      expect(command.intent, VoiceIntent.claim);
      expect(command.alertNumber, 900);
    });

    test('returns first valid when no complete command exists', () {
      final command = VoiceCommandParser.parseBest(['clean alert', 'noise']);

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
      final command = VoiceCommandParser.parseCanonical([
        'claim alert one thousand twenty five',
      ]);
      expect(command.intent, VoiceIntent.claim);
      expect(command.alertNumber, 1025);
    });

    test('accepts canonical resolve with reason', () {
      final command = VoiceCommandParser.parseCanonical([
        'resolve alert ten twenty five with reason fixed motor',
      ]);
      expect(command.intent, VoiceIntent.resolve);
      expect(command.alertNumber, 1025);
      expect(command.reason, 'fixed motor');
    });

    test('accepts common canonical claim misrecognitions', () {
      final command = VoiceCommandParser.parseCanonical([
        'clean alert one zero two five',
      ]);
      expect(command.intent, VoiceIntent.claim);
      expect(command.alertNumber, 1025);
    });

    test('accepts common canonical resolve misrecognitions', () {
      final command = VoiceCommandParser.parseCanonical([
        'result alert ten two five',
      ]);
      expect(command.intent, VoiceIntent.resolve);
      expect(command.alertNumber, 1025);
    });

    test('accepts canonical no-number active-alert commands', () {
      final resolve = VoiceCommandParser.parseCanonical(['resolve alert']);
      final suspend = VoiceCommandParser.parseCanonical(['suspend alert']);
      final critical = VoiceCommandParser.parseCanonical([
        'mark alert as critical',
      ]);

      expect(resolve.intent, VoiceIntent.resolve);
      expect(resolve.alertNumber, isNull);
      expect(suspend.intent, VoiceIntent.suspend);
      expect(suspend.alertNumber, isNull);
      expect(critical.intent, VoiceIntent.escalate);
      expect(critical.alertNumber, isNull);
    });

    test('accepts polite action-first commands', () {
      final command = VoiceCommandParser.parseCanonical([
        'please claim the alert number one zero two five',
      ]);
      expect(command.intent, VoiceIntent.claim);
      expect(command.alertNumber, 1025);
    });

    test('accepts canonical escalate alert NUMBER', () {
      final command = VoiceCommandParser.parseCanonical([
        'escalate alert one zero two five',
      ]);
      expect(command.intent, VoiceIntent.escalate);
      expect(command.alertNumber, 1025);
    });

    test('rejects loose phrasings the lenient parser would accept', () {
      final command = VoiceCommandParser.parseCanonical([
        'I will take alert one zero two five',
      ]);
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
    test('detects claim phrases that commonly continue after a scale word', () {
      final command = VoiceCommandParser.parse(
        'claim alert twenty one thousand',
      );

      expect(VoiceCommandParser.claimMayNeedMoreSpeech(command), isTrue);
    });

    test('does not hold the mic open for exact one thousand', () {
      final command = VoiceCommandParser.parse('claim alert one thousand');

      expect(VoiceCommandParser.claimMayNeedMoreSpeech(command), isFalse);
      expect(VoiceCommandParser.claimIsStableForAutoStop(command), isTrue);
    });

    test('does not hold the mic open for a complete long claim number', () {
      final command = VoiceCommandParser.parse(
        'claim alert twenty one thousand eight hundred and twenty',
      );

      expect(VoiceCommandParser.claimMayNeedMoreSpeech(command), isFalse);
    });

    test(
      'does not hold the mic open for complete long claim ending in ones',
      () {
        final command = VoiceCommandParser.parse(
          'claim alert twenty one thousand eight hundred twenty one',
        );

        expect(VoiceCommandParser.claimMayNeedMoreSpeech(command), isFalse);
      },
    );

    test('does not auto-stop live capture on a single digit claim prefix', () {
      final command = VoiceCommandParser.parse('claim alert one');

      expect(
        VoiceCommandParser.claimMayBeEarlyPartialDuringCapture(command),
        isTrue,
      );
      expect(VoiceCommandParser.claimIsStableForAutoStop(command), isFalse);
    });

    test(
      'does not auto-stop live capture on a short digit sequence prefix',
      () {
        final command = VoiceCommandParser.parse('claim alert one one');

        expect(
          VoiceCommandParser.claimMayBeEarlyPartialDuringCapture(command),
          isTrue,
        );
        expect(VoiceCommandParser.claimIsStableForAutoStop(command), isFalse);
      },
    );

    test('auto-stops live capture for four digit digit-by-digit alert', () {
      final command = VoiceCommandParser.parse('claim alert one one zero zero');

      expect(command.alertNumber, 1100);
      expect(
        VoiceCommandParser.claimMayBeEarlyPartialDuringCapture(command),
        isFalse,
      );
      expect(VoiceCommandParser.claimIsStableForAutoStop(command), isTrue);
    });

    test('auto-stops live capture for spoken hundred digit sequence', () {
      final command = VoiceCommandParser.parse('claim alert nine zero zero');

      expect(command.alertNumber, 900);
      expect(
        VoiceCommandParser.claimMayBeEarlyPartialDuringCapture(command),
        isFalse,
      );
      expect(VoiceCommandParser.claimIsStableForAutoStop(command), isTrue);
    });

    test('does not auto-stop live capture on twenty one prefix', () {
      final command = VoiceCommandParser.parse('claim alert twenty one');

      expect(command.alertNumber, 21);
      expect(
        VoiceCommandParser.claimMayBeEarlyPartialDuringCapture(command),
        isTrue,
      );
      expect(VoiceCommandParser.claimIsStableForAutoStop(command), isFalse);
    });

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
      const cmd = VoiceCommand(intent: VoiceIntent.unknown, rawText: 'nope');
      expect(cmd.isValid, isFalse);
    });
  });
}
