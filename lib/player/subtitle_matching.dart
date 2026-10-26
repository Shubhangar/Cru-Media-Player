import 'dart:io';

const subtitleExts = {'srt', 'vtt', 'ass', 'ssa', 'sub'};

String _base(String path) {
  final name = path.split(RegExp(r'[/\\]')).last;
  final dot = name.lastIndexOf('.');
  return (dot > 0 ? name.substring(0, dot) : name).toLowerCase();
}

String _ext(String path) => path.split('.').last.toLowerCase();

final _episode = RegExp(
  r's(\d{1,2})[ ._-]?e(\d{1,3})|(\d{1,2})x(\d{2,3})',
  caseSensitive: false,
);

/// "S01E02" / "1x02" -> "1:2"; null when the name has no episode tag.
String? episodeKey(String path) {
  final m = _episode.firstMatch(path.split(RegExp(r'[/\\]')).last);
  if (m == null) return null;
  final s = int.parse(m[1] ?? m[3]!), e = int.parse(m[2] ?? m[4]!);
  return '$s:$e';
}

/// Subtitle for one media file: same base name (optionally with a language
/// suffix like `.en`), else the same episode tag.
String? matchOne(String media, Iterable<String> subs) {
  final base = _base(media);
  final candidates = subs.where((s) => subtitleExts.contains(_ext(s)));
  final exact = candidates.where((s) => _base(s) == base);
  if (exact.isNotEmpty) return exact.first;
  final prefixed = candidates.where((s) => _base(s).startsWith('$base.'));
  if (prefixed.isNotEmpty) return prefixed.first;
  final ep = episodeKey(media);
  if (ep != null) {
    final byEp = candidates.where((s) => episodeKey(s) == ep);
    if (byEp.isNotEmpty) return byEp.first;
  }
  return null;
}

/// Pairs every media file with a subtitle from [subs] where possible.
Map<String, String> matchSubtitles(List<String> media, List<String> subs) => {
  for (final m in media) m: ?matchOne(m, subs),
};

/// Subtitle files next to [mediaPath] (and in Subs/ or Subtitles/) that
/// belong to it.
List<String> sidecarCandidates(String mediaPath) {
  final file = File(mediaPath);
  final dirs = [
    file.parent,
    Directory('${file.parent.path}/Subs'),
    Directory('${file.parent.path}/Subtitles'),
  ];
  final base = _base(mediaPath);
  final out = <String>[];
  for (final d in dirs) {
    if (!d.existsSync()) continue;
    for (final e in d.listSync().whereType<File>()) {
      if (!subtitleExts.contains(_ext(e.path))) continue;
      final b = _base(e.path);
      final inSubsDir = d.path != file.parent.path;
      if (b == base || b.startsWith('$base.') || inSubsDir) out.add(e.path);
    }
  }
  return out..sort();
}

/// Search text from a file name: "The.Movie.2019.1080p.x264" -> "The Movie 2019".
String queryFromFileName(String path) {
  final file = path.split(RegExp(r'[/\\]')).last;
  final dot = file.lastIndexOf('.');
  var name = (dot > 0 ? file.substring(0, dot) : file).replaceAll(
    RegExp(r'[._]+'),
    ' ',
  );
  final cut = RegExp(
    r'\b(2160p|1080p|720p|480p|x26[45]|h ?26[45]|hevc|bluray|web ?dl|webrip|hdtv|dvdrip|brrip|aac|ac3|dts|proper|repack)\b',
    caseSensitive: false,
  ).firstMatch(name);
  if (cut != null) name = name.substring(0, cut.start);
  return name.replaceAll(RegExp(r'\s+'), ' ').trim();
}
