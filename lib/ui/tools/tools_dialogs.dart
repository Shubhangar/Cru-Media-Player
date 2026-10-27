import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../player/media_loader.dart';
import '../../player/player_controller.dart';
import '../../settings/prefs.dart';
import '../../theme.dart';
import '../../tools/cast_session.dart';
import '../../tools/converter.dart';
import '../../tools/dlna.dart';
import '../inspector/widgets.dart';

String _name(String p) => Uri.decodeComponent(p.split(RegExp(r'[/\\]')).last);

/// Shared frame for the utility dialogs.
class _ToolDialog extends StatelessWidget {
  final String title;
  final IconData filled, outlined;
  final String? info;
  final Widget child;
  final double width;
  const _ToolDialog({
    required this.title,
    required this.filled,
    required this.outlined,
    required this.child,
    this.info,
    this.width = 560,
  });

  @override
  Widget build(BuildContext context) => Dialog(
    child: SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 16, 12, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                TwoToneIcon(filled, outlined),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (info != null) InfoTip(info!),
                const Spacer(),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Padding(padding: const EdgeInsets.only(right: 10), child: child),
          ],
        ),
      ),
    ),
  );
}

// ---- Open & tools hub ------------------------------------------------------

/// One place for every way to bring media in, and the tools around it.
Future<void> showMediaHub(
  BuildContext context,
  PlayerController c,
  MediaLoader loader,
  CastSession cast,
) => showDialog(
  context: context,
  builder: (ctx) {
    void go(VoidCallback f) {
      Navigator.pop(ctx);
      f();
    }

    final cards = <(IconData, String, String, VoidCallback)>[
      (
        Icons.insert_drive_file_outlined,
        'Open file',
        'Video, audio or playlist',
        () => go(loader.openFiles),
      ),
      (
        Icons.folder_open_outlined,
        'Open folder',
        'Everything inside, in order',
        () => go(loader.openFolder),
      ),
      (
        Icons.language,
        'Network stream',
        'Links, HLS/DASH, M3U / IPTV',
        () => go(() => loader.openStream(context)),
      ),
      (
        Icons.videocam_outlined,
        'Capture device',
        'IP cameras and live feeds',
        () => go(() => showCaptureDialog(context, c)),
      ),
      (
        Icons.content_paste,
        'From clipboard',
        'Play a copied link or path',
        () => go(() => showClipboardDialog(context, c)),
      ),
      (
        Icons.transform,
        'Convert',
        'Save as MP4, HEVC or audio',
        () => go(() => showConvertDialog(context, c)),
      ),
      (
        Icons.cast,
        'Cast',
        'Play on a TV or speaker',
        () => go(() => showCastDialog(context, c, cast)),
      ),
    ];
    return _ToolDialog(
      title: 'Open & tools',
      filled: Icons.apps,
      outlined: Icons.apps_outlined,
      width: 640,
      child: GridView.count(
        crossAxisCount: 3,
        shrinkWrap: true,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.7,
        children: [
          for (final (icon, title, sub, f) in cards)
            Material(
              color: ConeColors.canvas,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(ConeRadius.md),
                side: BorderSide(color: ConeColors.border),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(ConeRadius.md),
                onTap: f,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(icon, color: ConeColors.accent),
                      const Spacer(),
                      Text(
                        title,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: ConeColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  },
);

// ---- Capture device -------------------------------------------------------

const _captureKinds = [
  (
    'rtsp',
    'RTSP',
    'rtsp://192.168.1.50:554/stream1',
    'Most IP / security cameras.',
  ),
  (
    'srt',
    'SRT',
    'srt://192.168.1.10:9000?mode=caller',
    'Low-latency feeds from OBS or encoders.',
  ),
  ('rtmp', 'RTMP', 'rtmp://server/live/key', 'Streaming servers and encoders.'),
  (
    'udp',
    'UDP',
    'udp://@239.0.0.1:1234',
    'Multicast / broadcast transport streams.',
  ),
  (
    'http',
    'HTTP',
    'http://192.168.1.50:8080/video',
    'MJPEG and HTTP camera streams.',
  ),
];

Future<void> showCaptureDialog(BuildContext context, PlayerController c) =>
    showDialog(
      context: context,
      builder: (_) => _CaptureDialog(c: c),
    );

class _CaptureDialog extends StatefulWidget {
  final PlayerController c;
  const _CaptureDialog({required this.c});

  @override
  State<_CaptureDialog> createState() => _CaptureDialogState();
}

class _CaptureDialogState extends State<_CaptureDialog> {
  String _kind = 'rtsp';
  bool _lowLatency = true;
  final _url = TextEditingController();

  List<String> get _saved => Prefs.captureSources
      .of(widget.c.settings)
      .split(';')
      .where((s) => s.isNotEmpty)
      .toList();

  Future<void> _open(String url) async {
    final saved = [url, ..._saved.where((s) => s != url)].take(8);
    Prefs.captureSources.set(widget.c.settings, saved.join(';'));
    Navigator.pop(context);
    await widget.c.openCapture(url, lowLatency: _lowLatency);
  }

  @override
  Widget build(BuildContext context) {
    final kind = _captureKinds.firstWhere((k) => k.$1 == _kind);
    return _ToolDialog(
      title: 'Capture device',
      filled: Icons.videocam,
      outlined: Icons.videocam_outlined,
      info:
          'Plays live network sources. Built-in webcams and capture cards '
          'are not supported by the bundled playback engine; stream them '
          'over the network instead (for example from OBS via SRT).',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            children: [
              for (final (id, label, _, _) in _captureKinds)
                ConeChip(
                  label: label,
                  selected: _kind == id,
                  onTap: () => setState(() => _kind = id),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            kind.$4,
            style: const TextStyle(fontSize: 12, color: ConeColors.textMuted),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _url,
            autofocus: true,
            decoration: InputDecoration(hintText: kind.$3),
            onSubmitted: (v) => v.trim().isEmpty ? null : _open(v.trim()),
          ),
          SettingRow(
            label: 'Low latency',
            info:
                'Plays as close to live as possible by skipping buffering. '
                'Turn off if the picture stutters.',
            child: ConeSwitch(
              value: _lowLatency,
              onChanged: (v) => setState(() => _lowLatency = v),
            ),
          ),
          if (_saved.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text(
              'Recent sources',
              style: TextStyle(fontSize: 12, color: ConeColors.textMuted),
            ),
            for (final s in _saved)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  Icons.sensors,
                  size: 18,
                  color: ConeColors.accent,
                ),
                title: Text(s, maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: () => _open(s),
              ),
          ],
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: () {
                final v = _url.text.trim();
                if (v.isNotEmpty) _open(v);
              },
              child: const Text('Connect'),
            ),
          ),
        ],
      ),
    );
  }
}

// ---- Clipboard -----------------------------------------------------------

/// Links (with a scheme) and existing file paths found in [text].
List<String> mediaRefsIn(String text) => [
  for (final raw in text.split(RegExp(r'[\s"<>]+')))
    if (raw.contains('://') ||
        (raw.startsWith('/') && File(raw).existsSync()) ||
        (RegExp(r'^[A-Za-z]:[\\/]').hasMatch(raw) && File(raw).existsSync()))
      raw,
];

Future<void> showClipboardDialog(
  BuildContext context,
  PlayerController c,
) async {
  final text = (await Clipboard.getData('text/plain'))?.text ?? '';
  final refs = mediaRefsIn(text);
  if (!context.mounted) return;
  await showDialog(
    context: context,
    builder: (ctx) => _ToolDialog(
      title: 'From clipboard',
      filled: Icons.content_paste,
      outlined: Icons.content_paste_outlined,
      child: refs.isEmpty
          ? const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                'No link or file path in the clipboard. Copy a video link or '
                'a file path, then try again.',
                style: TextStyle(color: ConeColors.textMuted),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final r in refs.take(8))
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      r.contains('://')
                          ? Icons.link
                          : Icons.insert_drive_file_outlined,
                      color: ConeColors.accent,
                    ),
                    title: Text(
                      r,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        c.openAll(refs, append: true);
                      },
                      child: const Text('Add to queue'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        c.openAll(refs);
                      },
                      child: Text(
                        refs.length == 1 ? 'Play' : 'Play ${refs.length}',
                      ),
                    ),
                  ],
                ),
              ],
            ),
    ),
  );
}

// ---- Convert -----------------------------------------------------------------

Future<void> showConvertDialog(
  BuildContext context,
  PlayerController c, {
  Future<Converter?> Function()? detect,
}) => showDialog(
  context: context,
  barrierDismissible: false,
  builder: (_) => _ConvertDialog(c: c, detect: detect ?? Converter.detect),
);

class _ConvertDialog extends StatefulWidget {
  final PlayerController c;
  final Future<Converter?> Function() detect;
  const _ConvertDialog({required this.c, required this.detect});

  @override
  State<_ConvertDialog> createState() => _ConvertDialogState();
}

class _ConvertDialogState extends State<_ConvertDialog> {
  Converter? _conv;
  bool _detecting = true;
  late String? _source = (widget.c.currentUri?.contains('://') ?? true)
      ? null
      : widget.c.currentUri;
  ConvertPreset _preset = convertPresets.first;
  String? _output;
  double? _progress;
  String? _status;
  String? _result;
  StreamSubscription<ConvertUpdate>? _sub;

  @override
  void initState() {
    super.initState();
    widget.detect().then((c) {
      if (!mounted) return;
      setState(() {
        _conv = c;
        _detecting = false;
        _suggest();
      });
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _conv?.cancel();
    super.dispose();
  }

  void _suggest() {
    if (_conv != null && _source != null) {
      _output = _conv!.suggestOutput(_source!, _preset);
    }
  }

  Future<void> _start() async {
    setState(() {
      _progress = 0;
      _status = null;
      _result = null;
    });
    final total = widget.c.currentUri == _source
        ? widget.c.player.state.duration
        : Duration.zero;
    _sub = _conv!.convert(_source!, _output!, _preset, total: total).listen((
      u,
    ) {
      if (!mounted) return;
      setState(() {
        _progress = u.progress;
        if (u.output != null) {
          _result = u.output;
          _progress = null;
        }
        if (u.error != null) {
          _status = u.error;
          _progress = null;
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final conv = _conv;
    final busy = _progress != null;
    return _ToolDialog(
      title: 'Convert',
      filled: Icons.transform,
      outlined: Icons.transform_outlined,
      info:
          'Converts with your system\'s converter (avconvert on macOS, or '
          'ffmpeg if installed). The original file is never changed.',
      child: _detecting
          ? const Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          : conv == null
          ? const Text(
              'No converter found. Install ffmpeg (for example from '
              'ffmpeg.org or your package manager) and reopen this dialog.',
              style: TextStyle(color: ConeColors.textMuted),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'Source',
                      style: TextStyle(color: ConeColors.textMuted),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _source == null ? 'None chosen' : _name(_source!),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    TextButton(
                      onPressed: busy
                          ? null
                          : () async {
                              final r = await FilePicker.platform.pickFiles();
                              final p = r?.files.single.path;
                              if (p != null) {
                                setState(() {
                                  _source = p;
                                  _suggest();
                                });
                              }
                            },
                      child: const Text('Choose…'),
                    ),
                  ],
                ),
                if (_source != null && !conv.canRead(_source!))
                  const Padding(
                    padding: EdgeInsets.only(bottom: 6),
                    child: Text(
                      'avconvert cannot read this format (e.g. MKV/WebM). '
                      'Install ffmpeg to convert it.',
                      style: TextStyle(fontSize: 12, color: Color(0xFFFF8A65)),
                    ),
                  ),
                const SizedBox(height: 6),
                for (final p in convertPresets)
                  RadioListTile<String>(
                    value: p.id,
                    // ignore: deprecated_member_use
                    groupValue: _preset.id,
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(p.label),
                    subtitle: Text(
                      p.description,
                      style: const TextStyle(fontSize: 11),
                    ),
                    // ignore: deprecated_member_use
                    onChanged: busy
                        ? null
                        : (_) => setState(() {
                            _preset = p;
                            _suggest();
                          }),
                  ),
                if (_output != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Saves as ${_name(_output!)} next to the original.',
                      style: const TextStyle(
                        fontSize: 12,
                        color: ConeColors.textMuted,
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                if (busy) ...[
                  LinearProgressIndicator(
                    value: _progress,
                    color: ConeColors.accent,
                    backgroundColor: ConeColors.border,
                  ),
                  const SizedBox(height: 6),
                  Text('${((_progress ?? 0) * 100).round()}%'),
                ],
                if (_status != null)
                  Text(
                    _status!,
                    style: const TextStyle(color: Color(0xFFFF8A65)),
                  ),
                if (_result != null)
                  Text(
                    'Done: ${_name(_result!)}',
                    style: TextStyle(color: ConeColors.accent),
                  ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (busy)
                      OutlinedButton(
                        onPressed: () => conv.cancel(),
                        child: const Text('Cancel'),
                      )
                    else if (_result != null)
                      FilledButton(
                        onPressed: () {
                          Navigator.pop(context);
                          widget.c.openAll([_result!]);
                        },
                        child: const Text('Play result'),
                      )
                    else
                      FilledButton(
                        onPressed: _source == null || !conv.canRead(_source!)
                            ? null
                            : _start,
                        child: const Text('Convert'),
                      ),
                  ],
                ),
              ],
            ),
    );
  }
}

// ---- Cast ----------------------------------------------------------------------

Future<void> showCastDialog(
  BuildContext context,
  PlayerController c,
  CastSession cast, {
  String? serveHost,
}) => showDialog(
  context: context,
  builder: (_) => _CastDialog(c: c, cast: cast, serveHost: serveHost),
);

class _CastDialog extends StatefulWidget {
  final PlayerController c;
  final CastSession cast;
  final String? serveHost;
  const _CastDialog({required this.c, required this.cast, this.serveHost});

  @override
  State<_CastDialog> createState() => _CastDialogState();
}

class _CastDialogState extends State<_CastDialog> {
  final List<DlnaDevice> _devices = [];
  bool _searching = false;
  String? _status;

  PlayerController get c => widget.c;

  @override
  void initState() {
    super.initState();
    _loadSaved();
  }

  Future<void> _loadSaved() async {
    for (final u in Prefs.castDevices.of(c.settings).split(';')) {
      if (u.isEmpty) continue;
      try {
        final d = await deviceAt(Uri.parse(u));
        if (d != null && mounted) setState(() => _addDevice(d));
      } catch (_) {}
    }
  }

  void _addDevice(DlnaDevice d) {
    if (!_devices.any((x) => x.controlUrl == d.controlUrl)) _devices.add(d);
  }

  Future<void> _search() async {
    setState(() {
      _searching = true;
      _status = null;
    });
    try {
      final found = await discoverRenderers();
      setState(() {
        found.forEach(_addDevice);
        _status = found.isEmpty
            ? 'No TVs or speakers found. Make sure they are on and on the '
                  'same network, or add one by address.'
            : null;
      });
    } catch (e) {
      setState(() => _status = 'Search failed: $e');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _addByAddress() async {
    final ctrl = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add device by address'),
        content: SizedBox(
          width: 420,
          child: TextField(
            controller: ctrl,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'http://192.168.1.20:49152/description.xml',
            ),
            onSubmitted: (v) => Navigator.pop(ctx, v),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (url == null || url.trim().isEmpty) return;
    try {
      final d = await deviceAt(Uri.parse(url.trim()));
      if (d == null) throw const FormatException('not a media renderer');
      final saved = {
        ...Prefs.castDevices
            .of(c.settings)
            .split(';')
            .where((s) => s.isNotEmpty),
        url.trim(),
      };
      Prefs.castDevices.set(c.settings, saved.join(';'));
      setState(() => _addDevice(d));
    } catch (e) {
      setState(() => _status = 'Could not add that device: $e');
    }
  }

  Future<void> _castTo(DlnaDevice d) async {
    final uri = c.currentUri;
    if (uri == null) return;
    setState(() => _status = 'Connecting to ${d.name}…');
    try {
      await widget.cast.start(
        d,
        uri,
        title: c.title,
        start: c.player.state.position,
        serveHost: widget.serveHost,
      );
      await c.player.pause();
      c.notify('Casting to ${d.name}');
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() => _status = '$e');
    }
  }

  @override
  Widget build(BuildContext context) => _ToolDialog(
    title: 'Cast',
    filled: Icons.cast,
    outlined: Icons.cast,
    info:
        'Plays on TVs, speakers and receivers that support DLNA/UPnP. '
        'Local files are streamed from this computer, so keep it awake.',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (c.currentUri == null)
          const Text(
            'Open something to cast first.',
            style: TextStyle(color: ConeColors.textMuted),
          ),
        for (final d in _devices)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.tv, color: ConeColors.accent),
            title: Text(d.name),
            subtitle: Text(
              d.location.host,
              style: const TextStyle(fontSize: 11, color: ConeColors.textMuted),
            ),
            trailing: FilledButton(
              onPressed: c.currentUri == null ? null : () => _castTo(d),
              child: const Text('Cast'),
            ),
          ),
        if (_status != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(
              _status!,
              style: const TextStyle(color: ConeColors.textMuted),
            ),
          ),
        const SizedBox(height: 8),
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: _searching ? null : _search,
              icon: _searching
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.search, size: 18),
              label: const Text('Search network'),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: _addByAddress,
              child: const Text('Add by address…'),
            ),
          ],
        ),
      ],
    ),
  );
}

/// Top-bar pill while casting: device, time, play/pause, stop.
class CastPill extends StatelessWidget {
  final CastSession cast;
  const CastPill({super.key, required this.cast});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: cast,
    builder: (context, _) {
      if (!cast.active) return const SizedBox.shrink();
      final pos = cast.position, dur = cast.duration;
      return Container(
        padding: const EdgeInsets.only(left: 10),
        decoration: BoxDecoration(
          color: ConeColors.surface,
          borderRadius: BorderRadius.circular(ConeRadius.lg),
          border: Border.all(color: ConeColors.accent),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cast_connected, size: 16, color: ConeColors.accent),
            const SizedBox(width: 8),
            Text(
              'Casting to ${cast.device!.name}'
              '${pos == null ? '' : ' · ${formatDuration(pos)}${dur == null ? '' : ' / ${formatDuration(dur)}'}'}',
              style: const TextStyle(fontSize: 12),
            ),
            IconButton(
              tooltip: cast.playing ? 'Pause on TV' : 'Play on TV',
              iconSize: 18,
              onPressed: cast.togglePlay,
              icon: Icon(cast.playing ? Icons.pause : Icons.play_arrow),
            ),
            IconButton(
              tooltip: 'Stop casting',
              iconSize: 18,
              onPressed: cast.stop,
              icon: const Icon(Icons.stop),
            ),
          ],
        ),
      );
    },
  );
}
