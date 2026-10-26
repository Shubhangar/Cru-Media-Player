import 'dart:convert';
import 'dart:io';

/// One timed subtitle line.
class Cue {
  final Duration start, end;
  final String text;
  const Cue(this.start, this.end, this.text);

  @override
  String toString() => 'Cue($start → $end: $text)';
}

final _srtTime = RegExp(
  r'(\d+):(\d{1,2}):(\d{1,2})[,.](\d{1,3})\s*-->\s*(\d+):(\d{1,2}):(\d{1,2})[,.](\d{1,3})',
);
final _vttShort = RegExp(
  r'(?:(\d+):)?(\d{1,2}):(\d{1,2})\.(\d{1,3})\s*-->\s*(?:(\d+):)?(\d{1,2}):(\d{1,2})\.(\d{1,3})',
);

Duration _t(String? h, String m, String s, String ms) => Duration(
  hours: int.parse(h ?? '0'),
  minutes: int.parse(m),
  seconds: int.parse(s),
  milliseconds: int.parse(ms.padRight(3, '0')),
);

String _cleanTags(String s) => s
    .replaceAll(RegExp(r'<[^>]+>'), '') // <i>, <font …>, <c.yellow>
    .replaceAll(RegExp(r'\{[^}]*\}'), '') // {\an8}, ASS overrides
    .replaceAll(r'\N', '\n')
    .replaceAll(r'\n', '\n')
    .replaceAll(r'\h', ' ')
    .trim();

/// SubRip (.srt) and WebVTT (.vtt).
List<Cue> parseSrtOrVtt(String text) {
  final cues = <Cue>[];
  final blocks = text.replaceAll('\r', '').split(RegExp(r'\n\s*\n'));
  for (final block in blocks) {
    final lines = block.split('\n');
    final i = lines.indexWhere((l) => l.contains('-->'));
    if (i < 0) continue;
    final m = _srtTime.firstMatch(lines[i]);
    Duration start, end;
    if (m != null) {
      start = _t(m[1], m[2]!, m[3]!, m[4]!);
      end = _t(m[5], m[6]!, m[7]!, m[8]!);
    } else {
      final v = _vttShort.firstMatch(lines[i]);
      if (v == null) continue;
      start = _t(v[1], v[2]!, v[3]!, v[4]!);
      end = _t(v[5], v[6]!, v[7]!, v[8]!);
    }
    final body = _cleanTags(lines.sublist(i + 1).join('\n'));
    if (body.isNotEmpty) cues.add(Cue(start, end, body));
  }
  cues.sort((a, b) => a.start.compareTo(b.start));
  return cues;
}

/// Advanced SubStation Alpha (.ass / .ssa) `Dialogue:` lines.
List<Cue> parseAss(String text) {
  final cues = <Cue>[];
  var fields = <String>[];
  for (final raw in text.replaceAll('\r', '').split('\n')) {
    final line = raw.trim();
    if (line.startsWith('Format:') && fields.isEmpty) {
      fields = line.substring(7).split(',').map((f) => f.trim()).toList();
    } else if (line.startsWith('Dialogue:')) {
      final names = fields.isEmpty
          ? [
              'Layer',
              'Start',
              'End',
              'Style',
              'Name',
              'MarginL',
              'MarginR',
              'MarginV',
              'Effect',
              'Text',
            ]
          : fields;
      final parts = line.substring(9).split(',');
      if (parts.length < names.length) continue;
      // Text is the last field and may itself contain commas.
      final values = [
        ...parts.sublist(0, names.length - 1),
        parts.sublist(names.length - 1).join(','),
      ];
      Duration? parse(String v) {
        final m = RegExp(r'(\d+):(\d{2}):(\d{2})[.:](\d{1,3})')
            .firstMatch(v.trim());
        if (m == null) return null;
        // ASS uses centiseconds.
        return Duration(
          hours: int.parse(m[1]!),
          minutes: int.parse(m[2]!),
          seconds: int.parse(m[3]!),
          milliseconds: int.parse(m[4]!.padRight(2, '0').substring(0, 2)) * 10,
        );
      }

      final start = parse(values[names.indexOf('Start')]);
      final end = parse(values[names.indexOf('End')]);
      final body = _cleanTags(values[names.indexOf('Text')]);
      if (start != null && end != null && body.isNotEmpty) {
        cues.add(Cue(start, end, body));
      }
    }
  }
  cues.sort((a, b) => a.start.compareTo(b.start));
  return cues;
}

/// Parses a subtitle file by extension; null when unsupported/unreadable.
Future<List<Cue>?> loadCues(String path) async {
  try {
    final bytes = await File(path).readAsBytes();
    // Most subtitles are UTF-8; fall back to Latin-1 for legacy files.
    String text;
    try {
      text = utf8.decode(bytes);
    } on FormatException {
      text = latin1.decode(bytes);
    }
    if (text.startsWith('﻿')) text = text.substring(1);
    final ext = path.split('.').last.toLowerCase();
    return switch (ext) {
      'srt' || 'vtt' => parseSrtOrVtt(text),
      'ass' || 'ssa' => parseAss(text),
      _ => null,
    };
  } catch (_) {
    return null;
  }
}
