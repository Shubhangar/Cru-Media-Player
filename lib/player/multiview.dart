import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// One extra feed shown next to (grid) or over (floating) the main video.
class Feed {
  final String uri;
  final Player player = Player();

  /// Created with the player, before media opens: a controller attached
  /// afterwards never receives frames.
  late final VideoController video;
  double offset = 0; // seconds relative to the master
  Offset floatPos;
  Size floatSize = const Size(320, 180);
  Feed(this.uri, this.floatPos) {
    video = VideoController(player);
  }

  String get name {
    final last = uri.split(RegExp(r'[/\\]')).last;
    return Uri.decodeComponent(last);
  }
}

enum MultiMode { off, grid, floating }

/// Keeps extra feeds in lock-step with a master [Player]: play/pause, speed,
/// seeks and position (with a per-feed offset). Only one source is audible.
class MultiView extends ChangeNotifier {
  final Player master;
  MultiView(this.master);

  static const maxFeeds = 3;
  final List<Feed> feeds = [];
  MultiMode mode = MultiMode.off;

  /// -1 = the master is audible, otherwise the index of the audible feed.
  int audioFocus = -1;
  bool sync = true;
  double _masterVolume = 100;
  Timer? _timer;
  final List<StreamSubscription> _subs = [];
  Duration _lastMasterPos = Duration.zero;

  bool get active => mode != MultiMode.off;

  void setMode(MultiMode m) {
    if (m == mode) return;
    mode = m;
    if (m == MultiMode.off) {
      _stop();
    } else {
      _start();
    }
    notifyListeners();
  }

  void _start() {
    _timer ??= Timer.periodic(
      const Duration(milliseconds: 400),
      (_) => _syncAll(),
    );
    if (_subs.isNotEmpty) return;
    _subs.addAll([
      master.stream.playing.listen((_) => _syncAll(force: true)),
      master.stream.rate.listen((_) => _syncAll(force: true)),
      // A jump (seek) in the master is applied to every feed at once.
      master.stream.position.listen((p) {
        final jump = (p - _lastMasterPos).abs() > const Duration(seconds: 1);
        _lastMasterPos = p;
        if (jump) _syncAll(force: true);
      }),
    ]);
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
  }

  Future<void> addFeed(String uri) async {
    if (feeds.length >= maxFeeds) return;
    final f = Feed(
      uri,
      Offset(24.0 + feeds.length * 30, 80.0 + feeds.length * 30),
    );
    feeds.add(f);
    await f.player.setVolume(0);
    await f.player.open(Media(uri), play: false);
    if (mode == MultiMode.off) setMode(MultiMode.grid);
    notifyListeners();
    await _syncFeed(f, force: true);
  }

  Future<void> removeFeed(Feed f) async {
    final i = feeds.indexOf(f);
    if (i == audioFocus) await setAudioFocus(-1);
    if (i < audioFocus) audioFocus--;
    feeds.remove(f);
    notifyListeners();
    await f.player.dispose();
    if (feeds.isEmpty) setMode(MultiMode.off);
  }

  /// Floating mode: drag the window.
  void moveFeed(Feed f, Offset delta) {
    f.floatPos += delta;
    notifyListeners();
  }

  /// Floating mode: resize from the corner handle (kept 16:9-ish bounds).
  void resizeFeed(Feed f, Offset delta) {
    final s = f.floatSize + delta;
    f.floatSize = Size(s.width.clamp(200, 900), s.height.clamp(112, 520));
    notifyListeners();
  }

  void setOffset(Feed f, double seconds) {
    f.offset = double.parse(seconds.toStringAsFixed(2));
    notifyListeners();
    _syncFeed(f, force: true);
  }

  /// Makes one source audible and mutes the others.
  Future<void> setAudioFocus(int index) async {
    if (audioFocus == -1) _masterVolume = master.state.volume;
    final vol = audioFocus == -1 ? master.state.volume : _masterVolume;
    audioFocus = index;
    await master.setVolume(index == -1 ? vol : 0);
    for (var i = 0; i < feeds.length; i++) {
      await feeds[i].player.setVolume(i == index ? vol : 0);
    }
    notifyListeners();
  }

  void setSync(bool on) {
    sync = on;
    notifyListeners();
    if (on) _syncAll(force: true);
  }

  Future<void> _syncAll({bool force = false}) async {
    if (!sync) return;
    for (final f in List.of(feeds)) {
      await _syncFeed(f, force: force);
    }
  }

  /// Matches state and corrects drift beyond 200 ms.
  Future<void> _syncFeed(Feed f, {bool force = false}) async {
    if (!sync) return;
    final m = master.state, s = f.player.state;
    if (s.duration <= Duration.zero) return;
    if (s.rate != m.rate) await f.player.setRate(m.rate);
    final target =
        m.position + Duration(milliseconds: (f.offset * 1000).round());
    final clamped = target < Duration.zero
        ? Duration.zero
        : (target > s.duration ? s.duration : target);
    final drift = (s.position - clamped).abs();
    if (force || drift > const Duration(milliseconds: 200)) {
      await f.player.seek(clamped);
    }
    if (s.playing != m.playing) {
      m.playing ? await f.player.play() : await f.player.pause();
    }
  }

  /// Drift of a feed from where it should be (for display/tests).
  Duration drift(Feed f) {
    final target =
        master.state.position +
        Duration(milliseconds: (f.offset * 1000).round());
    return (f.player.state.position - target).abs();
  }

  Future<void> closeAll() async {
    if (audioFocus != -1) await setAudioFocus(-1);
    for (final f in List.of(feeds)) {
      await removeFeed(f);
    }
    setMode(MultiMode.off);
  }

  @override
  void dispose() {
    _stop();
    for (final f in feeds) {
      f.player.dispose();
    }
    super.dispose();
  }
}
