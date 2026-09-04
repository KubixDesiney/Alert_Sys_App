// Pins the WAV -> PCM16 conversion behind Android voice verification.
//
// VoiceLockRecorderActivity writes a 16 kHz mono 16-bit RIFF/WAV file, but
// VoiceAuthService.verifyCurrentUser expects the same headerless PCM16 that
// the enrollment path (`recordPcm16`) produces. If the header is not removed
// exactly, the embedding is computed over 44 bytes of "RIFF...WAVEfmt " and
// every verification silently fails -- so this conversion is load-bearing.

import 'dart:typed_data';

import 'package:alertsysapp/services/voice_service_io.dart';
import 'package:flutter_test/flutter_test.dart';

/// Builds a RIFF/WAV container exactly as the native recorder does.
Uint8List wav(List<int> pcm, {int sampleRate = 16000, bool trailingChunk = false}) {
  final b = BytesBuilder();
  void ascii(String s) => b.add(s.codeUnits);
  void u32(int v) => b.add(Uint8List(4)..buffer.asByteData().setUint32(0, v, Endian.little));
  void u16(int v) => b.add(Uint8List(2)..buffer.asByteData().setUint16(0, v, Endian.little));

  ascii('RIFF');
  u32(pcm.length + 36);
  ascii('WAVE');
  ascii('fmt ');
  u32(16);
  u16(1);          // PCM
  u16(1);          // mono
  u32(sampleRate);
  u32(sampleRate * 2);
  u16(2);
  u16(16);
  if (trailingChunk) {
    // An odd-sized ancillary chunk before `data`, to prove the walker pads.
    ascii('LIST');
    u32(3);
    b.add([1, 2, 3]);
    b.add([0]); // pad byte
  }
  ascii('data');
  u32(pcm.length);
  b.add(pcm);
  return b.toBytes();
}

void main() {
  final pcm = List<int>.generate(3200, (i) => i % 256);

  group('VoiceService.pcmFromWav', () {
    test('strips the 44-byte header and returns the samples verbatim', () {
      final out = VoiceService.pcmFromWav(wav(pcm));
      expect(out, isNotNull);
      expect(out!.length, pcm.length);
      expect(out.toList(), pcm);
    });

    test('finds data even when another chunk precedes it', () {
      final out = VoiceService.pcmFromWav(wav(pcm, trailingChunk: true));
      expect(out, isNotNull);
      expect(out!.toList(), pcm);
    });

    test('passes headerless PCM straight through', () {
      final raw = Uint8List.fromList(pcm);
      expect(VoiceService.pcmFromWav(raw)!.toList(), pcm);
    });

    test('tolerates a data size longer than the file without overrunning', () {
      final bytes = wav(pcm);
      // Corrupt Subchunk2Size to claim far more data than is present.
      ByteData.sublistView(bytes).setUint32(bytes.length - pcm.length - 4, 1 << 20, Endian.little);
      final out = VoiceService.pcmFromWav(bytes);
      expect(out, isNotNull);
      expect(out!.length, pcm.length);
    });

    test('returns null for a RIFF file with no data chunk', () {
      final headerOnly = wav(const <int>[]).sublist(0, 36);
      expect(VoiceService.pcmFromWav(headerOnly), isNull);
    });

    test('returns null for anything too short to inspect', () {
      expect(VoiceService.pcmFromWav(Uint8List.fromList([1, 2, 3])), isNull);
    });

    test('an empty data chunk yields empty, which the caller rejects', () {
      final out = VoiceService.pcmFromWav(wav(const <int>[]));
      expect(out, isNotNull);
      expect(out!.lengthInBytes, 0);
      // The capture path requires >= 1600 bytes before attempting verification.
      expect(out.lengthInBytes < 1600, isTrue);
    });
  });
}
