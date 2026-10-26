import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// A short on-screen notice: what happened and which shortcut caused it.
class OsdMessage {
  final String action;
  final String? shortcut;
  final DateTime at = DateTime.now();
  OsdMessage(this.action, [this.shortcut]);
}

class Bookmark {
  final Duration position;
  final String label;
  const Bookmark(this.position, this.label);
}

/// Owns the mpv-backed [Player] and the UI-level state around it.
class PlayerController extends ChangeNotifier {
  final Player player = Player(
    configuration: const PlayerConfiguration(title: 'Cone Player'),
  );
  late final VideoController video = VideoController(player);

  final _osd = StreamController<OsdMessage>.broadcast();
  Stream<OsdMessage> get osd => _osd.stream;

  final List<Bookmark> bookmarks = [];
  bool uiHidden = false;
  double zoom = 0; // mpv video-zoom (log2 scale)
  int rotation = 0;
  bool flipped = false;
  String aspect = 'auto';

  NativePlayer? get _mpv =>
      player.platform is NativePlayer ? player.platform as NativePlayer : null;

  void notify(String action, [String? shortcut]) =>
      _osd.add(OsdMessage(action, shortcut));

  // ---- Loading ----------------------------------------------------------

  Future<void> openAll(List<String> uris, {bool append = false}) async {
    if (uris.isEmpty) return;
    final medias = uris.map(Media.new).toList();
    if (append && player.state.playlist.medias.isNotEmpty) {
      for (final m in medias) {
        await player.add(m);
      }
      notify('Added ${medias.length} to queue');
    } else {
      await player.open(Playlist(medias), play: true);
      bookmarks.clear();
      notifyListeners();
    }
  }

  Future<void> loadSubtitle(String uri) async {
    await player.setSubtitleTrack(SubtitleTrack.uri(uri));
    notify('Subtitle loaded');
  }

  String get title {
    final pl = player.state.playlist;
    if (pl.medias.isEmpty) return 'Cone Player';
    final uri = pl.medias[pl.index.clamp(0, pl.medias.length - 1)].uri;
    final name = Uri.decodeComponent(uri.split(RegExp(r'[/\\]')).last);
    return name.isEmpty ? uri : name;
  }

  // ---- Transport --------------------------------------------------------

  Future<void> togglePlay([String? key]) async {
    final s = player.state;
    // mpv parks on the last frame at the end; Play should start over.
    if (!s.playing &&
        s.duration > Duration.zero &&
        s.position >= s.duration - const Duration(milliseconds: 300)) {
      await player.seek(Duration.zero);
      await player.play();
      notify('Replay', key);
      return;
    }
    // Label from the state before toggling: mpv reports the change later.
    notify(s.playing ? 'Pause' : 'Play', key);
    await player.playOrPause();
  }

  Future<void> seekBy(Duration d, [String? key]) async {
    final p = player.state.position + d;
    final dur = player.state.duration;
    await player.seek(p < Duration.zero ? Duration.zero : (p > dur ? dur : p));
    final s = d.inSeconds;
    notify('Seek ${s >= 0 ? '+' : ''}${s}s', key);
  }

  Future<void> frameStep(bool forward, [String? key]) async {
    await _mpv?.command([forward ? 'frame-step' : 'frame-back-step']);
    notify(forward ? 'Next frame' : 'Previous frame', key);
  }

  Future<void> next([String? key]) async {
    await player.next();
    notify('Next track', key);
  }

  Future<void> previous([String? key]) async {
    await player.previous();
    notify('Previous track', key);
  }

  Future<void> setVolume(double v, [String? key]) async {
    v = v.clamp(0, 100).toDouble();
    await player.setVolume(v);
    if (key != null) notify('Volume ${v.round()}%', key);
  }

  double _lastVolume = 100;
  Future<void> toggleMute([String? key]) async {
    final v = player.state.volume;
    if (v > 0) {
      _lastVolume = v;
      await player.setVolume(0);
      notify('Mute', key);
    } else {
      await player.setVolume(_lastVolume);
      notify('Unmute', key);
    }
  }

  Future<void> setRate(double r, [String? key]) async {
    r = double.parse(r.clamp(0.25, 4.0).toStringAsFixed(2));
    await player.setRate(r);
    notify('Speed ${r}x', key);
  }

  // ---- Bookmarks --------------------------------------------------------

  void addBookmark([String? key]) {
    final pos = player.state.position;
    bookmarks
      ..add(Bookmark(pos, 'Bookmark ${bookmarks.length + 1}'))
      ..sort((a, b) => a.position.compareTo(b.position));
    notify('Bookmark at ${formatDuration(pos)}', key);
    notifyListeners();
  }

  // ---- Video adjustments (mpv properties) -------------------------------

  Future<void> _prop(String name, String value) async =>
      _mpv?.setProperty(name, value);

  Future<void> setZoom(double z) async {
    zoom = z.clamp(-2.0, 3.0).toDouble();
    await _prop('video-zoom', zoom.toStringAsFixed(3));
    notifyListeners();
  }

  Future<void> rotate([String? key]) async {
    rotation = (rotation + 90) % 360;
    await _prop('video-rotate', '$rotation');
    notify('Rotate $rotation°', key);
    notifyListeners();
  }

  Future<void> toggleFlip() async {
    flipped = !flipped;
    await _prop('vf', flipped ? 'hflip' : '');
    notify(flipped ? 'Flip on' : 'Flip off');
    notifyListeners();
  }

  Future<void> setAspect(String a) async {
    aspect = a;
    await _prop('video-aspect-override', a == 'auto' ? 'no' : a);
    notify('Aspect $a');
    notifyListeners();
  }

  Future<void> setAdjust(String prop, int value) async =>
      _prop(prop, '$value'); // brightness / contrast / saturation: -100..100

  /// Raises subtitles above the bottom bar (mpv units: 720-line script res).
  Future<void> liftSubtitles(bool lift) =>
      _prop('sub-margin-y', lift ? '100' : '22');

  void toggleUi([String? key]) {
    uiHidden = !uiHidden;
    notify(uiHidden ? 'UI hidden' : 'UI shown', key);
    notifyListeners();
  }

  @override
  void dispose() {
    _osd.close();
    player.dispose();
    super.dispose();
  }
}

String formatDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}
