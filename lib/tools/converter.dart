import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// A target format, expressed for each backend.
class ConvertPreset {
  final String id, label, description, ext;
  final String avconvert; // macOS avconvert preset name
  final List<String> ffmpeg; // ffmpeg output arguments
  const ConvertPreset(
    this.id,
    this.label,
    this.description,
    this.ext,
    this.avconvert,
    this.ffmpeg,
  );
}

const convertPresets = [
  ConvertPreset(
    'mp4-1080',
    'MP4 · 1080p',
    'H.264, plays everywhere.',
    'mp4',
    'Preset1920x1080',
    [
      '-vf',
      'scale=-2:min(1080\\,ih)',
      '-c:v',
      'libx264',
      '-crf',
      '21',
      '-c:a',
      'aac',
    ],
  ),
  ConvertPreset(
    'mp4-720',
    'MP4 · 720p (smaller)',
    'H.264 at 720p for phones and sharing.',
    'mp4',
    'Preset1280x720',
    [
      '-vf',
      'scale=-2:min(720\\,ih)',
      '-c:v',
      'libx264',
      '-crf',
      '23',
      '-c:a',
      'aac',
    ],
  ),
  ConvertPreset(
    'hevc-1080',
    'HEVC · 1080p',
    'About half the size of H.264 at the same quality.',
    'mp4',
    'PresetHEVC1920x1080',
    [
      '-vf',
      'scale=-2:min(1080\\,ih)',
      '-c:v',
      'libx265',
      '-crf',
      '24',
      '-tag:v',
      'hvc1',
      '-c:a',
      'aac',
    ],
  ),
  ConvertPreset(
    'm4a',
    'Audio only · M4A',
    'Extract the sound as AAC audio.',
    'm4a',
    'PresetAppleM4A',
    ['-vn', '-c:a', 'aac', '-b:a', '192k'],
  ),
];

/// Progress 0..1, or a final result.
class ConvertUpdate {
  final double progress;
  final String? output; // set when done
  final String? error;
  const ConvertUpdate(this.progress, {this.output, this.error});
}

/// "avconvert progress:  42.50% complete" -> 0.425
double? parseAvconvertProgress(String chunk) {
  final m = RegExp(r'progress:\s*([\d.]+)%').allMatches(chunk);
  if (m.isEmpty) return null;
  return (double.tryParse(m.last.group(1)!) ?? 0) / 100;
}

/// ffmpeg `-progress pipe:1` emits "out_time_us=12345678" lines.
double? parseFfmpegProgress(String chunk, Duration total) {
  final m = RegExp(r'out_time_us=(\d+)').allMatches(chunk);
  if (m.isEmpty || total <= Duration.zero) return null;
  final us = int.parse(m.last.group(1)!);
  return (us / total.inMicroseconds).clamp(0.0, 1.0);
}

/// Converts with the OS's tools: avconvert on macOS (built in) or ffmpeg
/// when installed. The bundled player engine ships without encoders.
class Converter {
  final String backend; // 'avconvert' | 'ffmpeg'
  final String executable;
  Converter._(this.backend, this.executable);

  /// Finds a usable backend, or null when none is installed.
  static Future<Converter?> detect() async {
    if (Platform.isMacOS && File('/usr/bin/avconvert').existsSync()) {
      return Converter._('avconvert', '/usr/bin/avconvert');
    }
    final which = Platform.isWindows ? 'where' : 'which';
    try {
      final r = await Process.run(which, ['ffmpeg']);
      final path = (r.stdout as String).trim().split(RegExp(r'\r?\n')).first;
      if (r.exitCode == 0 && path.isNotEmpty) {
        return Converter._('ffmpeg', path);
      }
    } catch (_) {}
    return null;
  }

  /// avconvert reads what AVFoundation can (MP4, MOV, M4A …), not MKV/WebM.
  bool canRead(String path) {
    if (backend == 'ffmpeg') return true;
    const ok = {'mp4', 'm4v', 'mov', 'm4a', 'mp3', 'wav', 'aiff', 'aac', '3gp'};
    return ok.contains(path.split('.').last.toLowerCase());
  }

  String suggestOutput(String input, ConvertPreset p) {
    final dot = input.lastIndexOf('.');
    final base = dot > 0 ? input.substring(0, dot) : input;
    var out = '$base (${p.id}).${p.ext}';
    var i = 2;
    while (File(out).existsSync()) {
      out = '$base (${p.id} $i).${p.ext}';
      i++;
    }
    return out;
  }

  Process? _proc;

  /// Runs the conversion, emitting progress and a final update.
  Stream<ConvertUpdate> convert(
    String input,
    String output,
    ConvertPreset preset, {
    Duration total = Duration.zero,
  }) async* {
    final args = backend == 'avconvert'
        ? [
            '-s',
            input,
            '-p',
            preset.avconvert,
            '-o',
            output,
            '--replace',
            '--progress',
          ]
        : [
            '-y',
            '-i',
            input,
            ...preset.ffmpeg,
            '-progress',
            'pipe:1',
            '-nostats',
            output,
          ];
    final p = await Process.start(executable, args);
    _proc = p;
    final updates = StreamController<ConvertUpdate>();
    var last = 0.0;
    final err = StringBuffer();
    void onChunk(String s) {
      final v = backend == 'avconvert'
          ? parseAvconvertProgress(s)
          : parseFfmpegProgress(s, total);
      if (v != null && v >= last) {
        last = v;
        updates.add(ConvertUpdate(v));
      }
    }

    p.stdout.transform(utf8.decoder).listen(onChunk);
    p.stderr.transform(utf8.decoder).listen((s) {
      err.write(s);
      if (backend == 'avconvert') onChunk(s);
    });
    unawaited(
      p.exitCode.then((code) {
        final ok =
            code == 0 &&
            File(output).existsSync() &&
            !err.toString().contains('completed with error:1');
        updates.add(
          ok
              ? ConvertUpdate(1, output: output)
              : ConvertUpdate(
                  last,
                  error: code == -15 || code == 143
                      ? 'Cancelled'
                      : 'Conversion failed (exit $code). ${_tail(err.toString())}',
                ),
        );
        updates.close();
      }),
    );
    yield* updates.stream;
    _proc = null;
  }

  void cancel() => _proc?.kill();

  static String _tail(String s) {
    final lines = s.trim().split('\n');
    return lines.isEmpty ? '' : lines.last.trim();
  }
}
