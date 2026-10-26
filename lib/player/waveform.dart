import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

/// Audio overview: [buckets] peaks in 0..1 spread evenly over the file.
class Waveform {
  final Float32List peaks;
  const Waveform(this.peaks);

  /// Peak around a fraction 0..1 of the file.
  double at(double f) => peaks.isEmpty
      ? 0
      : peaks[(f * (peaks.length - 1)).round().clamp(0, peaks.length - 1)];
}

/// Builds waveforms by letting a hidden mpv decode the audio to a low-rate
/// mono WAV (very fast with `untimed`), then reducing it to peaks.
class WaveformService {
  final Directory cacheDir;
  WaveformService(this.cacheDir);

  static const buckets = 1600;
  static const sampleRate = 4000;
  final _memory = <String, Waveform>{};
  final _pending = <String, Future<Waveform?>>{};

  Waveform? cached(String uri) => _memory[uri];

  Future<Waveform?> load(String uri) {
    if (_memory[uri] != null) return Future.value(_memory[uri]);
    // Block body on purpose: returning the removed future from whenComplete
    // would make the future wait on itself forever.
    return _pending[uri] ??= _load(uri).whenComplete(() {
      _pending.remove(uri);
    });
  }

  Future<Waveform?> _load(String uri) async {
    // Local files only: decoding a network stream would download it all.
    if (uri.contains('://') && !uri.startsWith('file://')) return null;
    final file = File(
      uri.startsWith('file://') ? Uri.parse(uri).toFilePath() : uri,
    );
    if (!file.existsSync()) return null;
    final st = file.statSync();
    final key =
        '${uri.hashCode.toUnsigned(32)}-${st.size}-'
        '${st.modified.millisecondsSinceEpoch}';
    final disk = File('${cacheDir.path}/$key.peaks');
    if (disk.existsSync()) {
      final bytes = disk.readAsBytesSync();
      final w = Waveform(
        Float32List.fromList([for (final b in bytes) b / 255]),
      );
      return _memory[uri] = w;
    }

    await cacheDir.create(recursive: true);
    final wav = File('${cacheDir.path}/$key.wav');
    final ok = await _dumpPcm(file.path, wav.path);
    if (!ok || !wav.existsSync()) {
      debugPrint('waveform: decode failed for $uri (ok=$ok)');
      return null;
    }
    try {
      final path = wav.path;
      final peaks = await Isolate.run(() => peaksFromWav(path, buckets));
      if (peaks == null) {
        debugPrint('waveform: unreadable PCM for $uri');
        return null;
      }
      await disk.writeAsBytes([for (final p in peaks) (p * 255).round()]);
      return _memory[uri] = Waveform(peaks);
    } finally {
      try {
        wav.deleteSync();
      } catch (_) {}
    }
  }

  static Future<bool> _dumpPcm(String path, String out) async {
    final p = Player();
    try {
      final mpv = p.platform as NativePlayer;
      for (final e in {
        'ao': 'pcm',
        'ao-pcm-file': out,
        'untimed': 'yes',
        'vid': 'no',
        'sid': 'no',
        'audio-display': 'no',
        'audio-channels': 'mono',
        'audio-samplerate': '$sampleRate',
        'audio-format': 's16',
        'af': '',
      }.entries) {
        await mpv.setProperty(e.key, e.value);
      }
      final done = Completer<bool>();
      final sub = p.stream.completed.listen((c) {
        if (c && !done.isCompleted) done.complete(true);
      });
      final err = p.stream.error.listen((e) => debugPrint('waveform: mpv: $e'));
      await p.open(Media(path));
      // Generous: hours of audio decode in seconds, but be safe.
      final ok = await done.future.timeout(
        const Duration(minutes: 3),
        onTimeout: () => false,
      );
      await sub.cancel();
      await err.cancel();
      return ok;
    } catch (e) {
      debugPrint('waveform: $e');
      return false;
    } finally {
      await p.dispose();
    }
  }
}

/// Reads a 16-bit mono PCM WAV in chunks and returns [buckets] normalised
/// peak values (perceptually scaled). Runs on a background isolate.
Float32List? peaksFromWav(String path, int buckets) {
  final raf = File(path).openSync();
  try {
    final header = raf.readSync(12);
    if (header.length < 12 ||
        String.fromCharCodes(header.sublist(0, 4)) != 'RIFF') {
      return null;
    }
    // Walk chunks to "data".
    int? dataStart, dataLen;
    var pos = 12;
    final fileLen = raf.lengthSync();
    while (pos + 8 <= fileLen) {
      raf.setPositionSync(pos);
      final h = raf.readSync(8);
      final id = String.fromCharCodes(h.sublist(0, 4));
      var len = ByteData.sublistView(h).getUint32(4, Endian.little);
      if (id == 'data') {
        dataStart = pos + 8;
        // Streaming writers may leave the size as 0 or 0xFFFFFFFF.
        if (len == 0 || len == 0xFFFFFFFF || dataStart + len > fileLen) {
          len = fileLen - dataStart;
        }
        dataLen = len;
        break;
      }
      pos += 8 + len + (len.isOdd ? 1 : 0);
    }
    if (dataStart == null || dataLen == null || dataLen < 2) return null;

    final samples = dataLen ~/ 2;
    final peaks = Float32List(buckets);
    final perBucket = samples / buckets;
    raf.setPositionSync(dataStart);
    const chunk = 1 << 16;
    var index = 0;
    while (index < samples) {
      final bytes = raf.readSync(math.min(chunk, (samples - index) * 2));
      if (bytes.isEmpty) break;
      final view = ByteData.sublistView(bytes);
      for (var i = 0; i + 1 < bytes.length; i += 2, index++) {
        final v = view.getInt16(i, Endian.little).abs() / 32768;
        final b = math.min(buckets - 1, index ~/ perBucket);
        if (v > peaks[b]) peaks[b] = v;
      }
    }
    var max = 0.0;
    for (final p in peaks) {
      if (p > max) max = p;
    }
    if (max <= 0) return peaks;
    for (var i = 0; i < buckets; i++) {
      peaks[i] = math.sqrt(peaks[i] / max); // lift quiet passages
    }
    return peaks;
  } finally {
    raf.closeSync();
  }
}
