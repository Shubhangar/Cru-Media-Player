import 'dart:convert';
import 'dart:io';

/// Human-friendly formatting for technical values reported by mpv.

/// "30.000000" -> "30", "23.976024" -> "23.976".
String trimNumber(String v, {int maxDecimals = 3}) {
  final n = double.tryParse(v);
  if (n == null) return v;
  var s = n.toStringAsFixed(maxDecimals);
  if (s.contains('.')) s = s.replaceFirst(RegExp(r'\.?0+$'), '');
  return s;
}

String formatBytes(String v) {
  final n = double.tryParse(v);
  if (n == null) return v;
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var x = n;
  var i = 0;
  while (x >= 1024 && i < units.length - 1) {
    x /= 1024;
    i++;
  }
  return '${i == 0 ? x.round() : x.toStringAsFixed(1)} ${units[i]}';
}

String formatBitrate(String v) {
  final n = double.tryParse(v);
  if (n == null) return v;
  if (n >= 1e6) return '${(n / 1e6).toStringAsFixed(1)} Mbps';
  return '${(n / 1e3).round()} kbps';
}

String formatSeconds(String v) {
  final n = double.tryParse(v);
  if (n == null) return v;
  final d = Duration(milliseconds: (n * 1000).round());
  final h = d.inHours,
      m = d.inMinutes.remainder(60),
      s = d.inSeconds.remainder(60);
  final mm = m.toString().padLeft(h > 0 ? 2 : 1, '0');
  return '${h > 0 ? '$h:' : ''}$mm:${s.toString().padLeft(2, '0')}';
}

String formatHz(String v) {
  final n = double.tryParse(v);
  if (n == null) return v;
  return n >= 1000
      ? '${trimNumber('${n / 1000}', maxDecimals: 1)} kHz'
      : '${n.round()} Hz';
}

/// mpv sometimes appends "(null)" when a long name is missing.
String stripNull(String v) =>
    v.replaceAll(RegExp(r'\s*\(\(?null\)?\)'), '').trim();

/// mpv's `metadata` property is a JSON object of tags.
Map<String, String> parseTags(String json) {
  try {
    final m = jsonDecode(json);
    if (m is! Map) return {};
    return {
      for (final e in m.entries)
        if ('${e.value}'.isNotEmpty) _tagLabel('${e.key}'): '${e.value}',
    };
  } catch (_) {
    return {};
  }
}

String _tagLabel(String k) {
  final words = k.replaceAll('_', ' ').toLowerCase();
  return words.isEmpty ? k : words[0].toUpperCase() + words.substring(1);
}

/// media_kit rewrites Windows paths with forward slashes (`C:/x/a.mp4`);
/// everything else in the app (scanner, pickers, drops, history keys) uses
/// the native form, so paths read back from the player are converted.
String nativeMediaPath(String uri, {bool? windows}) {
  if (!(windows ?? Platform.isWindows)) return uri;
  if (RegExp(r'^[A-Za-z]:/').hasMatch(uri) || uri.startsWith('//')) {
    return uri.replaceAll('/', r'\');
  }
  return uri;
}

/// Last path component of a file path or URL, for display. URL escapes are
/// decoded leniently (a stray `%` must not throw); local file names are shown
/// exactly as they are on disk.
String fileNameOf(String uri) {
  final last = uri
      .split(RegExp(r'[/\\]'))
      .lastWhere((s) => s.isNotEmpty, orElse: () => uri);
  if (!uri.contains('://')) return last;
  final noQuery = last.split('?').first;
  try {
    return Uri.decodeComponent(noQuery);
  } on ArgumentError {
    return noQuery;
  }
}
