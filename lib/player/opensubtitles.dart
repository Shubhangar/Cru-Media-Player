import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Minimal HTTP seam so the client can be tested without the network.
typedef HttpFetch = Future<(int status, String body)> Function(
  String method,
  Uri url,
  Map<String, String> headers, [
  String? body,
]);

Future<(int, String)> _ioFetch(
  String method,
  Uri url,
  Map<String, String> headers, [
  String? body,
]) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
  try {
    final req = await client.openUrl(method, url);
    headers.forEach(req.headers.set);
    if (body != null) req.write(body);
    final res = await req.close().timeout(const Duration(seconds: 30));
    return (res.statusCode, await res.transform(utf8.decoder).join());
  } finally {
    client.close();
  }
}

/// OpenSubtitles "movie hash": file size plus the 64-bit little-endian
/// word sums of the first and last 64 KiB, as 16 hex digits.
String openSubtitlesHash(String path) {
  const chunk = 65536;
  final raf = File(path).openSync();
  try {
    final size = raf.lengthSync();
    var h = BigInt.from(size);
    final mask = (BigInt.one << 64) - BigInt.one;
    void add(Uint8List bytes) {
      final view = ByteData.sublistView(bytes);
      for (var i = 0; i + 8 <= bytes.length; i += 8) {
        h =
            (h + BigInt.from(view.getUint64(i, Endian.little)).toUnsigned(64)) &
            mask;
      }
    }

    add(raf.readSync(chunk));
    raf.setPositionSync(size > chunk ? size - chunk : 0);
    add(raf.readSync(chunk));
    return h.toRadixString(16).padLeft(16, '0');
  } finally {
    raf.closeSync();
  }
}

class SubtitleResult {
  final int fileId;
  final String fileName;
  final String language;
  final String release;
  final int downloads;
  final bool hearingImpaired;
  final bool hashMatch;
  const SubtitleResult({
    required this.fileId,
    required this.fileName,
    required this.language,
    required this.release,
    required this.downloads,
    required this.hearingImpaired,
    required this.hashMatch,
  });
}

class OpenSubtitlesException implements Exception {
  final String message;
  OpenSubtitlesException(this.message);
  @override
  String toString() => message;
}

/// OpenSubtitles.com REST API (v1). Needs a free consumer API key.
class OpenSubtitlesClient {
  final String apiKey;
  final HttpFetch _fetch;
  OpenSubtitlesClient(this.apiKey, {HttpFetch? fetch})
    : _fetch = fetch ?? _ioFetch;

  static final base = Uri.parse('https://api.opensubtitles.com/api/v1/');

  Map<String, String> get _headers => {
    'Api-Key': apiKey,
    'User-Agent': 'ConePlayer v1.0',
    'Accept': 'application/json',
    'Content-Type': 'application/json',
  };

  Never _fail(int status, String body) {
    String msg;
    try {
      msg = (jsonDecode(body) as Map)['message']?.toString() ?? body;
    } catch (_) {
      msg = body;
    }
    throw OpenSubtitlesException(switch (status) {
      401 || 403 => 'OpenSubtitles rejected the API key ($msg)',
      406 || 429 => 'OpenSubtitles download limit reached ($msg)',
      _ => 'OpenSubtitles error $status: $msg',
    });
  }

  /// Searches by file hash and/or text query; best matches first.
  Future<List<SubtitleResult>> search({
    String? hash,
    String? query,
    String languages = 'en',
  }) async {
    final url = base
        .resolve('subtitles')
        .replace(
          queryParameters: {
            'moviehash': ?hash,
            if (query != null && query.isNotEmpty) 'query': query,
            if (languages.isNotEmpty)
              'languages': languages.replaceAll(' ', ''),
          },
        );
    final (status, body) = await _fetch('GET', url, _headers);
    if (status != 200) _fail(status, body);
    final data = (jsonDecode(body) as Map)['data'] as List? ?? const [];
    final out = <SubtitleResult>[];
    for (final d in data) {
      final a = (d as Map)['attributes'] as Map? ?? const {};
      final files = a['files'] as List? ?? const [];
      if (files.isEmpty) continue;
      final f = files.first as Map;
      out.add(
        SubtitleResult(
          fileId: (f['file_id'] as num).toInt(),
          fileName: f['file_name']?.toString() ?? 'subtitle.srt',
          language: a['language']?.toString() ?? '',
          release: a['release']?.toString() ?? '',
          downloads: (a['download_count'] as num?)?.toInt() ?? 0,
          hearingImpaired: a['hearing_impaired'] == true,
          hashMatch: a['moviehash_match'] == true,
        ),
      );
    }
    out.sort((a, b) {
      if (a.hashMatch != b.hashMatch) return a.hashMatch ? -1 : 1;
      return b.downloads.compareTo(a.downloads);
    });
    return out;
  }

  /// Downloads a result and saves it as [target]; returns the saved path.
  Future<String> download(SubtitleResult r, String target) async {
    final (status, body) = await _fetch(
      'POST',
      base.resolve('download'),
      _headers,
      jsonEncode({'file_id': r.fileId}),
    );
    if (status != 200) _fail(status, body);
    final link = (jsonDecode(body) as Map)['link']?.toString();
    if (link == null) throw OpenSubtitlesException('No download link returned');
    final (s2, text) = await _fetch('GET', Uri.parse(link), const {});
    if (s2 != 200) _fail(s2, text);
    await File(target).writeAsString(text);
    return target;
  }
}
