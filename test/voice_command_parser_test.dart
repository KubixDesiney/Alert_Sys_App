import 'package:alertsysapp/services/voice_command_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VoiceCommandParser', () {
    test('understands plain claim alert without a number', () {
      final command = VoiceCommandParser.parse('claim alert');

      expect(command.intent, VoiceIntent.claim);
      expect(command.alertNumber, isNull);
    });

    test('understands natural claim phrases', () {
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

    test('chooses a complete command from recognition alternatives', () {
      final command = VoiceCommandParser.parseBest([
        'clean alert',
        'claim alert ten twenty five',
      ]);

      expect(command.intent, VoiceIntent.claim);
      expect(command.alertNumber, 1025);
    });

    test('accepts punctuated confirmation phrases', () {
      expect(VoiceCommandParser.isYes('Yes, claim it.'), isTrue);
    });
  });
}
