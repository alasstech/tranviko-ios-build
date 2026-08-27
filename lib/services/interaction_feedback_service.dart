import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// A small, consistent feedback vocabulary for meaningful Tranviko actions.
class TranvikoInteractionFeedback {
  const TranvikoInteractionFeedback._();

  static final AudioPlayer _player = AudioPlayer(
    playerId: 'tranviko-interaction-feedback',
  );
  static final Map<String, String> _tonePaths = <String, String>{};

  static Future<void> selection() async {
    await HapticFeedback.selectionClick();
    await _play('selection', const <_Note>[_Note(740, 0.035, .09)]);
  }

  static Future<void> success() async {
    await HapticFeedback.lightImpact();
    await _play('success', const <_Note>[
      _Note(523, .055, .10),
      _Note(659, .07, .12),
    ]);
  }

  static Future<void> warning() async {
    await HapticFeedback.mediumImpact();
    await _play('warning', const <_Note>[_Note(392, .11, .12)]);
  }

  static Future<void> error() async {
    await HapticFeedback.heavyImpact();
    await _play('error', const <_Note>[
      _Note(330, .08, .12),
      _Note(262, .13, .10),
    ]);
  }

  static Future<void> welcome() async {
    await HapticFeedback.lightImpact();
    await _play('welcome', const <_Note>[
      _Note(392, .07, .075),
      _Note(523, .075, .085),
      _Note(659, .15, .10),
    ]);
  }

  static Future<void> messageSent() async {
    await HapticFeedback.lightImpact();
    await _play('message_sent', const <_Note>[
      _Note(620, .035, .065),
      _Note(880, .045, .075),
    ]);
  }

  static Future<void> mediaSent() async {
    await HapticFeedback.lightImpact();
    await _play('media_sent', const <_Note>[
      _Note(494, .04, .065),
      _Note(740, .065, .085),
    ]);
  }

  static Future<void> voiceStart() async {
    await HapticFeedback.selectionClick();
    await _play('voice_start', const <_Note>[_Note(440, .055, .075)]);
  }

  static Future<void> voicePause() async {
    await HapticFeedback.selectionClick();
    await _play('voice_pause', const <_Note>[_Note(370, .06, .07)]);
  }

  static Future<void> voiceResume() async {
    await HapticFeedback.selectionClick();
    await _play('voice_resume', const <_Note>[
      _Note(440, .035, .065),
      _Note(554, .045, .075),
    ]);
  }

  static Future<void> voiceCancel() async {
    await HapticFeedback.mediumImpact();
    await _play('voice_cancel', const <_Note>[
      _Note(370, .045, .065),
      _Note(294, .075, .07),
    ]);
  }

  static Future<void> _play(String name, List<_Note> notes) async {
    try {
      final existing = _tonePaths[name];
      final path = existing ?? await _writeTone(name, notes);
      await _player.stop();
      await _player.setReleaseMode(ReleaseMode.stop);
      await _player.play(DeviceFileSource(path), volume: .42);
    } catch (_) {
      // A system click is still better than silent feedback on restricted devices.
      await SystemSound.play(SystemSoundType.click);
    }
  }

  static Future<String> _writeTone(String name, List<_Note> notes) async {
    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/tranviko_$name.wav');
    if (await file.exists()) {
      _tonePaths[name] = file.path;
      return file.path;
    }
    const sampleRate = 22050;
    final samples = <int>[];
    for (final note in notes) {
      final count = (note.seconds * sampleRate).round();
      for (var index = 0; index < count; index += 1) {
        final position = index / sampleRate;
        final edge = math.min(1, math.min(index / 280, (count - index) / 420));
        final wave = math.sin(2 * math.pi * note.frequency * position);
        samples.add((wave * note.volume * edge * 32767).round());
      }
    }
    final data = ByteData(44 + samples.length * 2);
    void writeAscii(int offset, String value) {
      for (var index = 0; index < value.length; index += 1) {
        data.setUint8(offset + index, value.codeUnitAt(index));
      }
    }

    writeAscii(0, 'RIFF');
    data.setUint32(4, 36 + samples.length * 2, Endian.little);
    writeAscii(8, 'WAVEfmt ');
    data.setUint32(16, 16, Endian.little);
    data.setUint16(20, 1, Endian.little);
    data.setUint16(22, 1, Endian.little);
    data.setUint32(24, sampleRate, Endian.little);
    data.setUint32(28, sampleRate * 2, Endian.little);
    data.setUint16(32, 2, Endian.little);
    data.setUint16(34, 16, Endian.little);
    writeAscii(36, 'data');
    data.setUint32(40, samples.length * 2, Endian.little);
    for (var index = 0; index < samples.length; index += 1) {
      data.setInt16(44 + index * 2, samples[index], Endian.little);
    }
    await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
    _tonePaths[name] = file.path;
    return file.path;
  }
}

class _Note {
  final double frequency;
  final double seconds;
  final double volume;

  const _Note(this.frequency, this.seconds, this.volume);
}
