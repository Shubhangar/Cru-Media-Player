import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// Seek-bar hover previews from a hidden second player.
///
/// Frames are exact: the hidden player seeks precisely to the hovered time
/// and the frame is grabbed only once it has landed there. Only the most
/// recent request is served (older ones resolve with the frame that was
/// current), and frames are cached per half second.
class FramePreviewer {
  final Player _player = Player();
  late final VideoController video = VideoController(
    _player,
    configuration: const VideoControllerConfiguration(width: 320, height: 180),
  );

  String? _uri;
  final _cache = <int, Uint8List>{};
  bool _busy = false;
  Duration? _next;
  final _waiters = <Completer<Uint8List?>>[];
  Uint8List? _last;

  NativePlayer get _mpv => _player.platform as NativePlayer;

  static const _bucketMs = 500;
  static const _maxCached = 400; // ~4 MB of small JPEGs

  int _bucket(Duration t) => t.inMilliseconds ~/ _bucketMs;

  void _remember(int key, Uint8List img) {
    if (_cache.length >= _maxCached) _cache.remove(_cache.keys.first);
    _cache[key] = img;
  }

  Future<void> _prepare(String uri, Duration duration) async {
    if (_uri == uri) return;
    _uri = uri;
    _cache.clear();
    _last = null;
    await _mpv.setProperty('ao', 'null');
    await _mpv.setProperty('aid', 'no');
    await _mpv.setProperty('sid', 'no');
    await _mpv.setProperty('hr-seek', 'yes');
    await _player.open(Media(uri), play: false);
    // Seeks before the file is loaded are ignored, so wait for it.
    if (_player.state.duration <= Duration.zero) {
      await _player.stream.duration
          .firstWhere((d) => d > Duration.zero)
          .timeout(const Duration(seconds: 5), onTimeout: () => Duration.zero);
    }
  }

  /// Time of the frame most recently delivered (for diagnostics/tests).
  Duration? lastFrameAt;

  Future<Duration?> _timePos() async {
    final v = double.tryParse(await _mpv.getProperty('time-pos'));
    return v == null ? null : Duration(milliseconds: (v * 1000).round());
  }

  /// Exact seek, then waits until mpv has finished seeking and sits on
  /// [t] — grabbing earlier would capture the previous frame.
  Future<void> _seek(Duration t) async {
    await _mpv
        .command(['seek', '${t.inMilliseconds / 1000}', 'absolute+exact'])
        .timeout(const Duration(seconds: 2), onTimeout: () {});
    final end = DateTime.now().add(const Duration(milliseconds: 1500));
    while (DateTime.now().isBefore(end)) {
      final seeking = await _mpv.getProperty('seeking');
      final at = await _timePos();
      final landed =
          at != null && (at - t).abs() < const Duration(milliseconds: 120);
      if (seeking != 'yes' && landed) break;
      await Future<void>.delayed(const Duration(milliseconds: 15));
    }
  }

  /// Frame at [t] of [uri]. Network streams are skipped (too costly).
  Future<Uint8List?> frameAt(String uri, Duration duration, Duration t) async {
    if (uri.contains('://') && !uri.startsWith('file://')) return null;
    await _prepare(uri, duration);
    final hit = _cache[_bucket(t)];
    if (hit != null) return hit;
    final c = Completer<Uint8List?>();
    _waiters.add(c);
    _next = t;
    if (!_busy) unawaited(_pump());
    return c.future;
  }

  Future<void> _pump() async {
    _busy = true;
    try {
      while (_next != null) {
        final t = _next!;
        _next = null;
        final key = _bucket(t);
        var img = _cache[key];
        if (img == null) {
          await _seek(t);
          img = await _player
              .screenshot(format: 'image/jpeg')
              .timeout(const Duration(seconds: 2), onTimeout: () => null);
          if (img != null) _remember(key, img);
          lastFrameAt = await _timePos();
        }
        _last = img ?? _last;
        if (_next == null) {
          for (final w in _waiters) {
            w.complete(_last);
          }
          _waiters.clear();
        }
      }
    } finally {
      _busy = false;
    }
  }

  /// Must be in the widget tree so the hidden player renders frames.
  Widget surface() => Positioned(
    left: 0,
    top: 0,
    width: 2,
    height: 2,
    child: IgnorePointer(
      child: Opacity(
        opacity: 0.01,
        child: Video(
          controller: video,
          controls: NoVideoControls,
          subtitleViewConfiguration: const SubtitleViewConfiguration(
            visible: false,
          ),
        ),
      ),
    ),
  );

  Future<void> dispose() => _player.dispose();
}
