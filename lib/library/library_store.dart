import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';

import 'm3u.dart';

const videoExtensions = {
  'mp4', 'mkv', 'webm', 'mov', 'avi', 'wmv', 'flv', 'm4v', 'mpg', 'mpeg', 'ts',
  'm2ts', '3gp', 'ogv', //
};
const audioExtensions = {
  'mp3', 'flac', 'wav', 'm4a', 'aac', 'ogg', 'opus', 'wma', 'alac', 'aiff', //
};

String extOf(String p) {
  final i = p.lastIndexOf('.');
  return i < 0 ? '' : p.substring(i + 1).toLowerCase();
}

bool isAudioPath(String p) => audioExtensions.contains(extOf(p));

String displayName(String uri) {
  final last = uri
      .split(RegExp(r'[/\\]'))
      .lastWhere((s) => s.isNotEmpty, orElse: () => uri);
  final name = Uri.decodeComponent(last);
  final dot = name.lastIndexOf('.');
  return dot > 0 && !uri.contains('://') ? name.substring(0, dot) : name;
}

/// Playback history for one file or stream.
class HistoryEntry {
  final String uri;
  String title;
  int positionMs, durationMs;
  DateTime lastPlayed;
  bool watched;
  bool isAudio;
  String? thumb;

  HistoryEntry({
    required this.uri,
    required this.title,
    this.positionMs = 0,
    this.durationMs = 0,
    DateTime? lastPlayed,
    this.watched = false,
    this.isAudio = false,
    this.thumb,
  }) : lastPlayed = lastPlayed ?? DateTime.now();

  double get progress =>
      durationMs <= 0 ? 0 : (positionMs / durationMs).clamp(0.0, 1.0);

  /// Worth offering to resume: meaningfully started, not finished.
  /// Short clips use a proportionally shorter threshold.
  bool get resumable =>
      !watched &&
      durationMs > 0 &&
      positionMs > (durationMs * 0.05).clamp(3000, 10000);

  Map<String, dynamic> toJson() => {
    'uri': uri,
    'title': title,
    'pos': positionMs,
    'dur': durationMs,
    'last': lastPlayed.toIso8601String(),
    'watched': watched,
    'audio': isAudio,
    if (thumb != null) 'thumb': thumb,
  };

  factory HistoryEntry.fromJson(Map<String, dynamic> j) => HistoryEntry(
    uri: j['uri'] as String,
    title: j['title'] as String? ?? displayName(j['uri'] as String),
    positionMs: (j['pos'] as num?)?.toInt() ?? 0,
    durationMs: (j['dur'] as num?)?.toInt() ?? 0,
    lastPlayed: DateTime.tryParse(j['last'] as String? ?? ''),
    watched: j['watched'] as bool? ?? false,
    isAudio: j['audio'] as bool? ?? false,
    thumb: j['thumb'] as String?,
  );
}

enum PinKind { folder, stream, playlist }

class Pin {
  final String label;
  final String target; // folder path, stream URL or playlist id
  final PinKind kind;
  const Pin(this.label, this.target, this.kind);

  Map<String, dynamic> toJson() => {
    'label': label,
    'target': target,
    'kind': kind.name,
  };
  factory Pin.fromJson(Map<String, dynamic> j) => Pin(
    j['label'] as String,
    j['target'] as String,
    PinKind.values.byName(j['kind'] as String),
  );
}

class UserPlaylist {
  final String id;
  String name;
  final List<String> items;
  final DateTime created;
  UserPlaylist(this.id, this.name, this.items, [DateTime? created])
    : created = created ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'items': items,
    'created': created.toIso8601String(),
  };
  factory UserPlaylist.fromJson(Map<String, dynamic> j) => UserPlaylist(
    j['id'] as String,
    j['name'] as String,
    [...(j['items'] as List).cast<String>()],
    DateTime.tryParse(j['created'] as String? ?? ''),
  );
}

enum FolderKind { video, music }

class LibraryFolder {
  final String path;
  final FolderKind kind;
  const LibraryFolder(this.path, this.kind);
  Map<String, dynamic> toJson() => {'path': path, 'kind': kind.name};
  factory LibraryFolder.fromJson(Map<String, dynamic> j) => LibraryFolder(
    j['path'] as String,
    FolderKind.values.byName(j['kind'] as String),
  );
}

/// An IPTV / M3U source whose channel list is cached and refreshed.
class StreamSource {
  final String id;
  String name;
  final String url;
  List<Channel> channels;
  DateTime? fetchedAt;
  String? error;
  StreamSource(this.id, this.name, this.url, [this.channels = const []]);

  bool get stale =>
      fetchedAt == null ||
      DateTime.now().difference(fetchedAt!) > const Duration(hours: 6);

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'url': url,
    'channels': [for (final c in channels) c.toJson()],
    if (fetchedAt != null) 'fetched': fetchedAt!.toIso8601String(),
  };
  factory StreamSource.fromJson(Map<String, dynamic> j) =>
      StreamSource(j['id'] as String, j['name'] as String, j['url'] as String, [
        for (final c in (j['channels'] as List? ?? []))
          Channel.fromJson(Map<String, dynamic>.from(c as Map)),
      ])..fetchedAt = DateTime.tryParse(j['fetched'] as String? ?? '');
}

/// A media file found by scanning a library folder.
class MediaFile {
  final String path;
  final int size;
  final DateTime modified;
  const MediaFile(this.path, this.size, this.modified);
  String get name => displayName(path);
  bool get isAudio => isAudioPath(path);
}

/// Everything the library remembers, stored as JSON in [dir].
class LibraryStore extends ChangeNotifier {
  final Directory dir;
  LibraryStore(this.dir);

  final Map<String, HistoryEntry> history = {};
  final List<Pin> pins = [];
  final List<UserPlaylist> playlists = [];
  final List<LibraryFolder> folders = [];
  final List<StreamSource> sources = [];
  Timer? _saveTimer;

  File get _file => File('${dir.path}/library.json');
  Directory get thumbsDir => Directory('${dir.path}/thumbs');

  Future<void> load() async {
    await dir.create(recursive: true);
    if (!await _file.exists()) return;
    try {
      final j = jsonDecode(await _file.readAsString()) as Map<String, dynamic>;
      Iterable<Map<String, dynamic>> list(String k) =>
          (j[k] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map));
      history
        ..clear()
        ..addEntries(
          list('history')
              .map(HistoryEntry.fromJson)
              .map((h) => MapEntry(h.uri, h)),
        );
      pins
        ..clear()
        ..addAll(list('pins').map(Pin.fromJson));
      playlists
        ..clear()
        ..addAll(list('playlists').map(UserPlaylist.fromJson));
      folders
        ..clear()
        ..addAll(list('folders').map(LibraryFolder.fromJson));
      sources
        ..clear()
        ..addAll(list('sources').map(StreamSource.fromJson));
    } catch (e) {
      debugPrint('library: could not read ${_file.path}: $e');
    }
    notifyListeners();
  }

  /// Saves soon, coalescing bursts of changes.
  void _changed() {
    notifyListeners();
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), save);
  }

  Future<void> _saving = Future.value();

  /// Writes atomically (temp file + rename). Saves are queued so two never
  /// race on the same temp file; failures are logged, not thrown.
  Future<void> save() {
    _saveTimer?.cancel();
    return _saving = _saving.then((_) => _write()).catchError((Object e) {
      debugPrint('library: save failed: $e');
    });
  }

  Future<void> _write() async {
    final json = jsonEncode({
      'history': [for (final h in history.values) h.toJson()],
      'pins': [for (final p in pins) p.toJson()],
      'playlists': [for (final p in playlists) p.toJson()],
      'folders': [for (final f in folders) f.toJson()],
      'sources': [for (final s in sources) s.toJson()],
    });
    await dir.create(recursive: true);
    final tmp = File('${_file.path}.tmp');
    await tmp.writeAsString(json);
    await tmp.rename(_file.path);
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    super.dispose();
  }

  // ---- History -----------------------------------------------------------

  List<HistoryEntry> recent({int limit = 20, bool unfinishedOnly = false}) {
    final l =
        history.values.where((h) => !unfinishedOnly || h.resumable).toList()
          ..sort((a, b) => b.lastPlayed.compareTo(a.lastPlayed));
    return l.take(limit).toList();
  }

  void recordProgress(
    String uri, {
    required String title,
    required Duration position,
    required Duration duration,
    required bool isAudio,
  }) {
    final h = history.putIfAbsent(
      uri,
      () => HistoryEntry(uri: uri, title: title),
    );
    h
      ..title = title
      ..positionMs = position.inMilliseconds
      ..durationMs = duration.inMilliseconds
      ..lastPlayed = DateTime.now()
      ..isAudio = isAudio;
    final d = duration.inMilliseconds;
    // Finished once past 92%, or in the final stretch (credits): the last
    // 30 s, but at most 5% of the length so short clips are not cut off.
    final tail = (d * 0.05).clamp(0, 30000);
    if (d > 0 &&
        (position.inMilliseconds >= d * 0.92 ||
            d - position.inMilliseconds < tail)) {
      h.watched = true;
    }
    _changed();
  }

  void setWatched(String uri, bool watched) {
    final h = history.putIfAbsent(
      uri,
      () => HistoryEntry(uri: uri, title: displayName(uri)),
    );
    h.watched = watched;
    if (!watched) h.positionMs = 0;
    _changed();
  }

  void forget(String uri) {
    history.remove(uri);
    _changed();
  }

  void clearHistory() {
    history.clear();
    _changed();
  }

  /// Stores a frame for the history card. Each save gets a new file name so
  /// image caches never show a stale frame; the previous file is removed.
  Future<void> saveThumb(String uri, Uint8List jpeg) async {
    final h = history[uri];
    if (h == null) return;
    await thumbsDir.create(recursive: true);
    final id = uri.hashCode.toUnsigned(32);
    final f = File(
      '${thumbsDir.path}/$id-${DateTime.now().millisecondsSinceEpoch}.jpg',
    );
    await f.writeAsBytes(jpeg);
    final old = h.thumb;
    h.thumb = f.path;
    if (old != null && old != f.path) {
      try {
        await File(old).delete();
      } catch (_) {}
    }
    _changed();
  }

  // ---- Pins, folders, playlists -----------------------------------------

  bool isPinned(String target) => pins.any((p) => p.target == target);

  void togglePin(Pin pin) {
    if (isPinned(pin.target)) {
      pins.removeWhere((p) => p.target == pin.target);
    } else {
      pins.add(pin);
    }
    _changed();
  }

  void addFolder(String path, FolderKind kind) {
    if (folders.any((f) => f.path == path && f.kind == kind)) return;
    folders.add(LibraryFolder(path, kind));
    _changed();
  }

  void removeFolder(LibraryFolder f) {
    folders.removeWhere((x) => x.path == f.path && x.kind == f.kind);
    _changed();
  }

  UserPlaylist createPlaylist(String name, [List<String> items = const []]) {
    final p = UserPlaylist(
      DateTime.now().microsecondsSinceEpoch.toRadixString(36),
      name,
      [...items],
    );
    playlists.add(p);
    _changed();
    return p;
  }

  void renamePlaylist(UserPlaylist p, String name) {
    p.name = name;
    _changed();
  }

  void deletePlaylist(UserPlaylist p) {
    playlists.remove(p);
    pins.removeWhere((x) => x.kind == PinKind.playlist && x.target == p.id);
    _changed();
  }

  void addToPlaylist(UserPlaylist p, List<String> uris) {
    p.items.addAll(uris);
    _changed();
  }

  void removeFromPlaylist(UserPlaylist p, int index) {
    p.items.removeAt(index);
    _changed();
  }

  // ---- Network streams / IPTV -------------------------------------------

  Future<StreamSource> addSource(String url, {String? name}) async {
    final s = StreamSource(
      DateTime.now().microsecondsSinceEpoch.toRadixString(36),
      name ?? displayName(url),
      url,
    );
    sources.add(s);
    _changed();
    await refreshSource(s);
    return s;
  }

  void removeSource(StreamSource s) {
    sources.remove(s);
    pins.removeWhere((p) => p.target == s.url);
    _changed();
  }

  /// Downloads and parses the playlist; keeps the old list on failure.
  Future<void> refreshSource(StreamSource s) async {
    try {
      final text = await _fetchText(s.url);
      s.channels = parseM3u(text, base: Uri.tryParse(s.url));
      s.fetchedAt = DateTime.now();
      s.error = s.channels.isEmpty ? 'No channels found' : null;
    } catch (e) {
      s.error = 'Could not load: $e';
    }
    _changed();
  }

  Future<void> refreshStaleSources() async {
    for (final s in sources.where((s) => s.stale).toList()) {
      await refreshSource(s);
    }
  }

  static Future<String> _fetchText(String url) async {
    final uri = Uri.parse(url);
    if (!uri.hasScheme || uri.scheme == 'file') {
      return File(uri.hasScheme ? uri.toFilePath() : url).readAsString();
    }
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15)
      ..userAgent = 'ConePlayer/1.0';
    try {
      final req = await client.getUrl(uri);
      final res = await req.close().timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode}');
      return await res.transform(utf8.decoder).join();
    } finally {
      client.close();
    }
  }
}

/// Recursively lists media files under [root] on a background isolate.
Future<List<MediaFile>> scanFolder(String root, {FolderKind? kind}) {
  return Isolate.run(() {
    final exts = switch (kind) {
      FolderKind.video => videoExtensions,
      FolderKind.music => audioExtensions,
      null => {...videoExtensions, ...audioExtensions},
    };
    final out = <MediaFile>[];
    final dir = Directory(root);
    if (!dir.existsSync()) return out;
    for (final e in dir.listSync(recursive: true, followLinks: false)) {
      if (e is! File || !exts.contains(extOf(e.path))) continue;
      if (e.path.split(Platform.pathSeparator).any((s) => s.startsWith('.'))) {
        continue; // hidden folders/files
      }
      final st = e.statSync();
      out.add(MediaFile(e.path, st.size, st.modified));
    }
    return out;
  });
}
