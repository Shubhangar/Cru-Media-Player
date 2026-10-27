import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:xml/xml.dart';

/// A UPnP/DLNA media renderer (TV, speaker, receiver).
class DlnaDevice {
  final String name;
  final Uri location; // device description URL
  final Uri controlUrl; // AVTransport control endpoint
  const DlnaDevice(this.name, this.location, this.controlUrl);
}

const _avTransport = 'urn:schemas-upnp-org:service:AVTransport:1';

/// `LOCATION:` header of an SSDP response, if any.
Uri? parseSsdpLocation(String response) {
  for (final line in response.split(RegExp(r'\r?\n'))) {
    final i = line.indexOf(':');
    if (i > 0 && line.substring(0, i).trim().toLowerCase() == 'location') {
      return Uri.tryParse(line.substring(i + 1).trim());
    }
  }
  return null;
}

/// Reads a device description; null if it has no AVTransport service.
DlnaDevice? parseDescription(String xmlText, Uri location) {
  final doc = XmlDocument.parse(xmlText);
  String? text(XmlElement e, String tag) =>
      e.findAllElements(tag).firstOrNull?.innerText.trim();
  final base = text(doc.rootElement, 'URLBase');
  final baseUri = base != null && base.isNotEmpty ? Uri.parse(base) : location;
  for (final s in doc.findAllElements('service')) {
    if (text(s, 'serviceType') == _avTransport) {
      final ctrl = text(s, 'controlURL') ?? '';
      return DlnaDevice(
        text(doc.rootElement, 'friendlyName') ?? location.host,
        location,
        baseUri.resolve(ctrl),
      );
    }
  }
  return null;
}

/// "hh:mm:ss" as used by AVTransport.
String upnpTime(Duration d) =>
    '${d.inHours}:${(d.inMinutes % 60).toString().padLeft(2, '0')}:'
    '${(d.inSeconds % 60).toString().padLeft(2, '0')}';

Duration? parseUpnpTime(String? s) {
  if (s == null) return null;
  final m = RegExp(r'^(\d+):(\d{2}):(\d{2})').firstMatch(s.trim());
  if (m == null) return null;
  return Duration(
    hours: int.parse(m[1]!),
    minutes: int.parse(m[2]!),
    seconds: int.parse(m[3]!),
  );
}

Future<String> _httpGet(Uri url) async {
  final c = HttpClient()..connectionTimeout = const Duration(seconds: 5);
  try {
    final res = await (await c.getUrl(url))
        .close()
        .timeout(const Duration(seconds: 8));
    return await res.transform(utf8.decoder).join();
  } finally {
    c.close();
  }
}

/// Finds renderers with SSDP multicast (asks the OS for local-network
/// access the first time) and reads their descriptions.
Future<List<DlnaDevice>> discoverRenderers({
  Duration timeout = const Duration(seconds: 3),
}) async {
  final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
  final locations = <Uri>{};
  socket.listen((e) {
    if (e != RawSocketEvent.read) return;
    final d = socket.receive();
    if (d == null) return;
    final loc = parseSsdpLocation(utf8.decode(d.data, allowMalformed: true));
    if (loc != null) locations.add(loc);
  });
  const msg =
      'M-SEARCH * HTTP/1.1\r\n'
      'HOST: 239.255.255.250:1900\r\n'
      'MAN: "ssdp:discover"\r\n'
      'MX: 2\r\n'
      'ST: urn:schemas-upnp-org:device:MediaRenderer:1\r\n\r\n';
  for (var i = 0; i < 2; i++) {
    socket.send(utf8.encode(msg), InternetAddress('239.255.255.250'), 1900);
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }
  await Future<void>.delayed(timeout);
  socket.close();
  final out = <DlnaDevice>[];
  for (final l in locations) {
    try {
      final d = parseDescription(await _httpGet(l), l);
      if (d != null && !out.any((x) => x.controlUrl == d.controlUrl)) {
        out.add(d);
      }
    } catch (_) {}
  }
  return out;
}

/// Reads one device from its description URL ("Add by address").
Future<DlnaDevice?> deviceAt(Uri descriptionUrl) async =>
    parseDescription(await _httpGet(descriptionUrl), descriptionUrl);

/// Sends AVTransport commands to one renderer.
class DlnaController {
  final DlnaDevice device;
  DlnaController(this.device);

  Future<XmlDocument> _soap(String action, Map<String, String> args) async {
    final body =
        '<?xml version="1.0" encoding="utf-8"?>'
        '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" '
        's:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">'
        '<s:Body><u:$action xmlns:u="$_avTransport">'
        '<InstanceID>0</InstanceID>'
        '${args.entries.map((e) => '<${e.key}>${_esc(e.value)}</${e.key}>').join()}'
        '</u:$action></s:Body></s:Envelope>';
    final c = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final req = await c.postUrl(device.controlUrl);
      req.headers
        ..set('Content-Type', 'text/xml; charset="utf-8"')
        ..set('SOAPACTION', '"$_avTransport#$action"');
      req.write(body);
      final res = await req.close().timeout(const Duration(seconds: 8));
      final text = await res.transform(utf8.decoder).join();
      if (res.statusCode != 200) {
        throw HttpException('$action failed (${res.statusCode})');
      }
      return XmlDocument.parse(text);
    } finally {
      c.close();
    }
  }

  static String _esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  Future<void> load(
    String url, {
    required String title,
    String mime = 'video/mp4',
  }) {
    final meta =
        '<DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/" '
        'xmlns:dc="http://purl.org/dc/elements/1.1/" '
        'xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/">'
        '<item id="0" parentID="-1" restricted="1">'
        '<dc:title>${_esc(title)}</dc:title>'
        '<upnp:class>object.item.videoItem</upnp:class>'
        '<res protocolInfo="http-get:*:$mime:*">${_esc(url)}</res>'
        '</item></DIDL-Lite>';
    return _soap('SetAVTransportURI', {
      'CurrentURI': url,
      'CurrentURIMetaData': meta,
    });
  }

  Future<void> play() => _soap('Play', {'Speed': '1'});
  Future<void> pause() => _soap('Pause', {});
  Future<void> stop() => _soap('Stop', {});
  Future<void> seek(Duration to) =>
      _soap('Seek', {'Unit': 'REL_TIME', 'Target': upnpTime(to)});

  /// (position, duration) as reported by the renderer.
  Future<(Duration?, Duration?)> position() async {
    final doc = await _soap('GetPositionInfo', {});
    String? t(String tag) => doc.findAllElements(tag).firstOrNull?.innerText;
    return (parseUpnpTime(t('RelTime')), parseUpnpTime(t('TrackDuration')));
  }
}

String mimeFor(String path) => switch (path.split('.').last.toLowerCase()) {
  'mp4' || 'm4v' => 'video/mp4',
  'mkv' => 'video/x-matroska',
  'webm' => 'video/webm',
  'mov' => 'video/quicktime',
  'avi' => 'video/x-msvideo',
  'mp3' => 'audio/mpeg',
  'm4a' || 'aac' => 'audio/mp4',
  'flac' => 'audio/flac',
  'wav' => 'audio/wav',
  _ => 'application/octet-stream',
};

/// Serves one local file to the LAN with HTTP range support, so a TV can
/// stream and seek it. The URL carries a random token.
class CastFileServer {
  HttpServer? _server;
  String? _path;
  final String _token = List.generate(
    16,
    (_) => Random.secure().nextInt(16).toRadixString(16),
  ).join();

  /// LAN address other devices can reach (first non-loopback IPv4).
  static Future<String> lanAddress() async {
    for (final i in await NetworkInterface.list(
      type: InternetAddressType.IPv4,
    )) {
      for (final a in i.addresses) {
        if (!a.isLoopback && !a.address.startsWith('169.254')) return a.address;
      }
    }
    return InternetAddress.loopbackIPv4.address;
  }

  /// Starts (or retargets) the server; returns the file's URL.
  Future<String> serve(String path, {String? host}) async {
    _path = path;
    _server ??= await HttpServer.bind(InternetAddress.anyIPv4, 0)
      ..listen(_handle);
    final name = Uri.encodeComponent(path.split(RegExp(r'[/\\]')).last);
    return 'http://${host ?? await lanAddress()}:${_server!.port}/$_token/$name';
  }

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    final p = _path;
    if (p == null || req.uri.pathSegments.firstOrNull != _token) {
      res.statusCode = HttpStatus.notFound;
      await res.close();
      return;
    }
    final file = File(p);
    final size = await file.length();
    res.headers
      ..contentType = ContentType.parse(mimeFor(p))
      ..set('Accept-Ranges', 'bytes')
      ..set('transferMode.dlna.org', 'Streaming');
    var start = 0, end = size - 1;
    final range = req.headers.value('range');
    final m = range == null
        ? null
        : RegExp(r'bytes=(\d*)-(\d*)').firstMatch(range);
    if (m != null) {
      if (m[1]!.isNotEmpty) start = int.parse(m[1]!);
      if (m[2]!.isNotEmpty) end = min(int.parse(m[2]!), size - 1);
      if (m[1]!.isEmpty && m[2]!.isNotEmpty) {
        start = size - int.parse(m[2]!);
        end = size - 1;
      }
      res.statusCode = HttpStatus.partialContent;
      res.headers.set('Content-Range', 'bytes $start-$end/$size');
    }
    res.contentLength = end - start + 1;
    if (req.method == 'HEAD') {
      await res.close();
      return;
    }
    await res.addStream(file.openRead(start, end + 1));
    await res.close();
  }

  Future<void> close() async {
    await _server?.close(force: true);
    _server = null;
  }
}
