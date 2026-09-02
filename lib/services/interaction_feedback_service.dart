import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'active_call_service.dart';

/// A small, consistent feedback vocabulary for meaningful Tranviko actions.
class TranvikoInteractionFeedback {
  const TranvikoInteractionFeedback._();

  static final AudioPlayer _player = AudioPlayer(
    playerId: 'tranviko-interaction-feedback',
  );
  static final Map<String, String> _tonePaths = <String, String>{};
  static bool _soundEnabled = true;
  static bool _hapticsEnabled = true;
  static DateTime _lastSoundAt = DateTime.fromMillisecondsSinceEpoch(0);

  static bool get soundEnabled => _soundEnabled;
  static bool get hapticsEnabled => _hapticsEnabled;

  static Future<void> configure({SharedPreferences? preferences}) async {
    final prefs = preferences ?? await SharedPreferences.getInstance();
    _soundEnabled = prefs.getBool('interaction_sounds_enabled') ?? true;
    _hapticsEnabled = prefs.getBool('interaction_haptics_enabled') ?? true;
  }

  static Future<void> warmUp() async {
    if (!_soundEnabled) return;
    try {
      await _writeTone('selection_v2', const <_Note>[_Note(760, .028, .035)]);
      await _writeTone('form_invalid_v2', const <_Note>[
        _Note(330, .052, .065),
        _Note(270, .075, .055),
      ]);
    } catch (_) {}
  }

  static Future<void> setSoundEnabled(bool value) async {
    _soundEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('interaction_sounds_enabled', value);
    if (value) await success();
  }

  static Future<void> setHapticsEnabled(bool value) async {
    _hapticsEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('interaction_haptics_enabled', value);
    if (value) await HapticFeedback.selectionClick();
  }

  static Future<void> selection() async {
    await _feedback(
      haptic: HapticFeedback.selectionClick,
      name: 'selection_v2',
      notes: const <_Note>[_Note(760, .028, .035)],
    );
  }

  static Future<void> primaryAction() async {
    await _feedback(
      haptic: HapticFeedback.lightImpact,
      name: 'primary_v2',
      notes: const <_Note>[_Note(540, .038, .06), _Note(810, .055, .07)],
    );
  }

  static Future<void> navigation() async {
    await _feedback(
      haptic: HapticFeedback.selectionClick,
      name: 'navigation_v2',
      notes: const <_Note>[_Note(630, .032, .04)],
    );
  }

  static Future<void> toggle(bool enabled) async {
    await _feedback(
      haptic: HapticFeedback.selectionClick,
      name: enabled ? 'toggle_on_v2' : 'toggle_off_v2',
      notes: enabled
          ? const <_Note>[_Note(610, .03, .05), _Note(820, .045, .065)]
          : const <_Note>[_Note(480, .05, .05)],
    );
  }

  static Future<void> formInvalid() async {
    await _feedback(
      haptic: HapticFeedback.mediumImpact,
      name: 'form_invalid_v2',
      notes: const <_Note>[_Note(330, .052, .065), _Note(270, .075, .055)],
    );
  }

  static Future<void> success() async {
    await _feedback(
      haptic: HapticFeedback.lightImpact,
      name: 'success_v2',
      notes: const <_Note>[
        _Note(520, .05, .075),
        _Note(690, .055, .085),
        _Note(920, .075, .07),
      ],
    );
  }

  static Future<void> warning() async {
    await _feedback(
      haptic: HapticFeedback.mediumImpact,
      name: 'warning_v2',
      notes: const <_Note>[_Note(420, .07, .07), _Note(360, .09, .06)],
    );
  }

  static Future<void> error() async {
    await _feedback(
      haptic: HapticFeedback.heavyImpact,
      name: 'error_v2',
      notes: const <_Note>[_Note(315, .07, .08), _Note(238, .1, .07)],
    );
  }

  static Future<void> welcome() async {
    await _feedback(
      haptic: HapticFeedback.lightImpact,
      name: 'welcome_v2',
      notes: const <_Note>[
        _Note(392, .055, .055),
        _Note(523, .06, .065),
        _Note(784, .11, .075),
      ],
    );
  }

  static Future<void> messageSent() async {
    await _feedback(
      haptic: HapticFeedback.lightImpact,
      name: 'message_sent_v2',
      notes: const <_Note>[_Note(640, .025, .045), _Note(940, .045, .06)],
    );
  }

  static Future<void> mediaSent() async {
    await _feedback(
      haptic: HapticFeedback.lightImpact,
      name: 'media_sent_v2',
      notes: const <_Note>[_Note(500, .035, .05), _Note(750, .055, .065)],
    );
  }

  static Future<void> voiceStart() async {
    await _feedback(
      haptic: HapticFeedback.selectionClick,
      name: 'voice_start_v2',
      notes: const <_Note>[_Note(465, .055, .06)],
    );
  }

  static Future<void> voicePause() async {
    await _feedback(
      haptic: HapticFeedback.selectionClick,
      name: 'voice_pause_v2',
      notes: const <_Note>[_Note(350, .06, .055)],
    );
  }

  static Future<void> voiceResume() async {
    await _feedback(
      haptic: HapticFeedback.selectionClick,
      name: 'voice_resume_v2',
      notes: const <_Note>[_Note(440, .03, .05), _Note(600, .045, .06)],
    );
  }

  static Future<void> voiceCancel() async {
    await _feedback(
      haptic: HapticFeedback.mediumImpact,
      name: 'voice_cancel_v2',
      notes: const <_Note>[_Note(370, .04, .055), _Note(280, .07, .055)],
    );
  }

  static Future<void> _feedback({
    required Future<void> Function() haptic,
    required String name,
    required List<_Note> notes,
  }) async {
    if (_hapticsEnabled) {
      try {
        await haptic();
      } catch (_) {}
    }
    if (!_soundEnabled || ActiveCallService.instance.active) return;
    await _play(name, notes);
  }

  static Future<void> _play(String name, List<_Note> notes) async {
    try {
      final now = DateTime.now();
      if (now.difference(_lastSoundAt) < const Duration(milliseconds: 70)) {
        return;
      }
      _lastSoundAt = now;
      final existing = _tonePaths[name];
      final path = existing ?? await _writeTone(name, notes);
      await _player.stop();
      await _player.setReleaseMode(ReleaseMode.stop);
      await _player.play(DeviceFileSource(path), volume: .34);
    } catch (_) {
      if (_soundEnabled && !ActiveCallService.instance.active) {
        await SystemSound.play(SystemSoundType.click);
      }
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
    for (var noteIndex = 0; noteIndex < notes.length; noteIndex += 1) {
      final note = notes[noteIndex];
      final count = (note.seconds * sampleRate).round();
      for (var index = 0; index < count; index += 1) {
        final position = index / sampleRate;
        final attack = math.min(1.0, index / (sampleRate * .006));
        final release = math.min(1.0, (count - index) / (sampleRate * .035));
        final edge = math.sin(math.pi * math.min(1.0, attack * release) / 2);
        final fundamental = math.sin(2 * math.pi * note.frequency * position);
        final harmonic = math.sin(2 * math.pi * note.frequency * 2 * position);
        final shimmer = math.sin(2 * math.pi * note.frequency * 1.5 * position);
        final wave = fundamental * .76 + harmonic * .15 + shimmer * .09;
        samples.add((wave * note.volume * edge * 32767).round());
      }
      if (noteIndex < notes.length - 1) {
        samples.addAll(List<int>.filled((sampleRate * .012).round(), 0));
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
