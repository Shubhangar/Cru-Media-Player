import 'dart:async';

import 'package:flutter/foundation.dart';

import 'dlna.dart';

/// The active cast: which renderer, what it plays, and its reported time.
/// Lives on the player screen so casting continues after the dialog closes.
class CastSession extends ChangeNotifier {
  DlnaController? _ctl;
  final _server = CastFileServer();
  Timer? _poll;
  String? title;
  bool playing = false;
  Duration? position, duration;
  String? error;

  DlnaDevice? get device => _ctl?.device;
  bool get active => _ctl != null;

  /// Starts [uri] on [device] at [start]. Local files are served over HTTP.
  Future<void> start(
    DlnaDevice device,
    String uri, {
    required String title,
    Duration start = Duration.zero,
    String? serveHost,
  }) async {
    await stop();
    final ctl = DlnaController(device);
    final url = uri.contains('://')
        ? uri
        : await _server.serve(uri, host: serveHost);
    try {
      await ctl.load(url, title: title, mime: mimeFor(uri));
      await ctl.play();
      if (start > const Duration(seconds: 2)) {
        // Some renderers need a moment before they accept a seek.
        await Future<void>.delayed(const Duration(milliseconds: 600));
        await ctl.seek(start);
      }
    } catch (e) {
      error = 'Could not cast: $e';
      await _server.close();
      notifyListeners();
      rethrow;
    }
    _ctl = ctl;
    this.title = title;
    playing = true;
    error = null;
    _poll = Timer.periodic(const Duration(seconds: 2), (_) => _refresh());
    notifyListeners();
  }

  Future<void> _refresh() async {
    final ctl = _ctl;
    if (ctl == null || _disposed) return;
    try {
      final (p, d) = await ctl.position();
      position = p;
      duration = d;
      if (!_disposed) notifyListeners();
    } catch (_) {}
  }

  Future<void> togglePlay() async {
    final ctl = _ctl;
    if (ctl == null) return;
    playing ? await ctl.pause() : await ctl.play();
    playing = !playing;
    notifyListeners();
  }

  Future<void> seek(Duration to) async {
    await _ctl?.seek(to);
    position = to;
    notifyListeners();
  }

  Future<void> stop() async {
    _poll?.cancel();
    _poll = null;
    final ctl = _ctl;
    _ctl = null;
    if (ctl != null) {
      try {
        await ctl.stop();
      } catch (_) {}
    }
    await _server.close();
    playing = false;
    position = duration = null;
    if (!_disposed) notifyListeners();
  }

  bool _disposed = false;

  @override
  void dispose() {
    // Tell the TV to stop, without notifying the (gone) listeners.
    _disposed = true;
    stop();
    super.dispose();
  }
}
