import '../player/format.dart';

/// One entry of an M3U / M3U8 (IPTV) playlist.
class Channel {
  final String name;
  final String url;
  final String group;
  final String? logo;
  const Channel({
    required this.name,
    required this.url,
    this.group = '',
    this.logo,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'url': url,
    'group': group,
    if (logo != null) 'logo': logo,
  };

  factory Channel.fromJson(Map<String, dynamic> j) => Channel(
    name: j['name'] as String,
    url: j['url'] as String,
    group: j['group'] as String? ?? '',
    logo: j['logo'] as String?,
  );
}

final _attr = RegExp(r'([\w-]+)="([^"]*)"');

/// An absolute local path: POSIX, a Windows drive (`C:\` or `C:/`) or UNC.
/// (`Uri.parse` would read `C:\x` as a URL with the scheme `c`.)
bool isLocalPath(String s) =>
    s.startsWith('/') ||
    s.startsWith(r'\\') ||
    RegExp(r'^[A-Za-z]:[\\/]').hasMatch(s);

/// What relative entries of the playlist at [location] resolve against.
Uri? playlistBase(String location) => isLocalPath(location)
    ? Uri.file(location, windows: !location.startsWith('/'))
    : Uri.tryParse(location);

/// Parses extended M3U (`#EXTINF:-1 tvg-logo="…" group-title="…",Name`)
/// as well as plain lists of URLs. Relative entries resolve against [base].
List<Channel> parseM3u(String text, {Uri? base}) {
  final out = <Channel>[];
  String? name, group, logo;
  for (var line in text.split(RegExp(r'\r?\n'))) {
    line = line.trim();
    if (line.isEmpty) continue;
    if (line.startsWith('#EXTINF')) {
      final comma = _lastUnquotedComma(line);
      name = comma >= 0 ? line.substring(comma + 1).trim() : null;
      final attrs = {
        for (final m in _attr.allMatches(line)) m.group(1)!: m.group(2)!,
      };
      group = attrs['group-title'];
      logo = attrs['tvg-logo'];
      if ((name == null || name.isEmpty) && attrs['tvg-name'] != null) {
        name = attrs['tvg-name'];
      }
      continue;
    }
    if (line.startsWith('#EXTGRP:')) {
      group = line.substring(8).trim();
      continue;
    }
    if (line.startsWith('#')) continue;
    final String url;
    if (base == null || line.contains('://') || isLocalPath(line)) {
      url = line;
    } else if (base.scheme == 'file') {
      url = base.resolve(line.replaceAll(r'\', '/')).toFilePath();
    } else {
      url = base.resolve(line).toString();
    }
    out.add(
      Channel(
        name: (name == null || name.isEmpty) ? _nameFromUrl(url) : name,
        url: url,
        group: group ?? '',
        logo: (logo == null || logo.isEmpty) ? null : logo,
      ),
    );
    name = group = logo = null;
  }
  return out;
}

int _lastUnquotedComma(String s) {
  var inQuotes = false;
  var last = -1;
  for (var i = 0; i < s.length; i++) {
    if (s[i] == '"') inQuotes = !inQuotes;
    if (s[i] == ',' && !inQuotes) last = i;
  }
  return last;
}

String _nameFromUrl(String url) {
  final name = fileNameOf(url);
  return name.isEmpty ? url : name;
}
