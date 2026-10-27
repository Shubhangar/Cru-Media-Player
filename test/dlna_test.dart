import 'dart:convert';
import 'dart:io';

import 'package:cone_player/tools/dlna.dart';
import 'package:flutter_test/flutter_test.dart';

const _description = '''<?xml version="1.0"?>
<root xmlns="urn:schemas-upnp-org:device-1-0">
  <device>
    <deviceType>urn:schemas-upnp-org:device:MediaRenderer:1</deviceType>
    <friendlyName>Living Room TV</friendlyName>
    <serviceList>
      <service>
        <serviceType>urn:schemas-upnp-org:service:RenderingControl:1</serviceType>
        <controlURL>/rc</controlURL>
      </service>
      <service>
        <serviceType>urn:schemas-upnp-org:service:AVTransport:1</serviceType>
        <controlURL>/upnp/control/AVTransport</controlURL>
      </service>
    </serviceList>
  </device>
</root>''';

/// Minimal renderer: serves the description and records SOAP actions.
Future<(HttpServer, List<(String, String)>)> fakeRenderer() async {
  final calls = <(String, String)>[];
  final s = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  s.listen((req) async {
    if (req.uri.path == '/desc.xml') {
      req.response.write(_description);
    } else {
      final action = req.headers
          .value('soapaction')!
          .split('#')
          .last
          .replaceAll('"', '');
      calls.add((action, await utf8.decoder.bind(req).join()));
      req.response.write(
        action == 'GetPositionInfo'
            ? '<s:Envelope><s:Body><u:GetPositionInfoResponse>'
                  '<TrackDuration>0:01:30</TrackDuration><RelTime>0:00:42</RelTime>'
                  '</u:GetPositionInfoResponse></s:Body></s:Envelope>'
            : '<s:Envelope><s:Body/></s:Envelope>',
      );
    }
    await req.response.close();
  });
  return (s, calls);
}

void main() {
  test('ssdp location and description parsing', () {
    expect(
      parseSsdpLocation(
        'HTTP/1.1 200 OK\r\nCACHE-CONTROL: max-age=1800\r\n'
        'Location: http://192.168.1.20:49152/desc.xml\r\n\r\n',
      ),
      Uri.parse('http://192.168.1.20:49152/desc.xml'),
    );
    final d = parseDescription(
      _description,
      Uri.parse('http://10.0.0.5:8080/desc.xml'),
    )!;
    expect(d.name, 'Living Room TV');
    expect(
      d.controlUrl.toString(),
      'http://10.0.0.5:8080/upnp/control/AVTransport',
    );
  });

  test('time format round trip', () {
    const d = Duration(hours: 1, minutes: 2, seconds: 3);
    expect(upnpTime(d), '1:02:03');
    expect(parseUpnpTime('1:02:03.000'), d);
  });

  test('casts a local file to a renderer and controls it', () async {
    final (renderer, calls) = await fakeRenderer();
    final server = CastFileServer();
    final tmp = await Directory.systemTemp.createTemp('cast');
    final file = File('${tmp.path}/movie.mp4')
      ..writeAsBytesSync(List.generate(1000, (i) => i % 256));
    try {
      final device = await deviceAt(
        Uri.parse('http://127.0.0.1:${renderer.port}/desc.xml'),
      );
      expect(device!.name, 'Living Room TV');
      final url = await server.serve(file.path, host: '127.0.0.1');
      final ctl = DlnaController(device);
      await ctl.load(url, title: 'Movie & Co');
      await ctl.play();
      await ctl.seek(const Duration(seconds: 75));
      final (pos, dur) = await ctl.position();
      expect(pos, const Duration(seconds: 42));
      expect(dur, const Duration(minutes: 1, seconds: 30));
      expect(calls.map((c) => c.$1), [
        'SetAVTransportURI',
        'Play',
        'Seek',
        'GetPositionInfo',
      ]);
      expect(calls.first.$2, contains('<CurrentURI>$url</CurrentURI>'));
      expect(
        calls.first.$2,
        contains('Movie &amp;amp; Co'),
      ); // escaped twice in DIDL
      expect(calls[2].$2, contains('<Target>0:01:15</Target>'));

      // The renderer can fetch the file, including byte ranges.
      final c = HttpClient();
      final req = await c.getUrl(Uri.parse(url));
      req.headers.set('Range', 'bytes=10-19');
      final res = await req.close();
      expect(res.statusCode, 206);
      expect(res.headers.value('content-range'), 'bytes 10-19/1000');
      final bytes = await res.fold<List<int>>([], (a, b) => a..addAll(b));
      expect(bytes, List.generate(10, (i) => 10 + i));
      // Wrong token is refused.
      final bad = await (await c.getUrl(
        Uri.parse(
          url.replaceFirst(RegExp(r'/[0-9a-f]{16}/'), '/0000000000000000/'),
        ),
      )).close();
      expect(bad.statusCode, 404);
      c.close();
    } finally {
      await server.close();
      await renderer.close(force: true);
      await tmp.delete(recursive: true);
    }
  });
}
