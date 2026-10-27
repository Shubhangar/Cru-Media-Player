import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../library/library_store.dart';
import 'eq.dart';
import 'format.dart';
import 'models.dart';
import '../settings/prefs.dart';
import 'settings_store.dart';
import 'shaders.dart';
import 'subtitles.dart';
import 'waveform.dart';

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
  PlayerController({SettingsStore? settings, this.library, this.waveforms})
    : settings = settings ?? SettingsStore();

  /// Builds audio waveforms; null disables waveform features.
  final WaveformService? waveforms;
  Waveform? waveform;
  String? _waveUri;

  /// Waveform is shown on the seek bar, the subtitle timeline or for music.
  bool get needsWaveform => showWaveform || showSubtitleTimeline || isAudioOnly;

  void _refreshWaveform() {
    final uri = currentUri;
    if (waveforms == null || uri == null) return;
    if (uri != _waveUri) {
      waveform = waveforms!.cached(uri);
      _waveUri = uri;
      notifyListeners();
    }
    if (waveform != null || !needsWaveform) return;
    waveforms!.load(uri).then((w) {
      if (w != null && currentUri == uri) {
        waveform = w;
        notifyListeners();
      }
    });
  }

  final SettingsStore settings;

  /// History, playlists and sources. Null in contexts without a library.
  final LibraryStore? library;
  final Player player = Player(
    // Warnings are needed to notice filters mpv silently drops.
    // libass: mpv draws subtitles into the video, so the Subtitles tab's
    // style (font, colours, outline, position, margin) is what you see.
    configuration: const PlayerConfiguration(
      title: 'Cru Media Player',
      logLevel: MPVLogLevel.warn,
      libass: true,
    ),
  );
  late final VideoController video = VideoController(player);

  final _osd = StreamController<OsdMessage>.broadcast();
  Stream<OsdMessage> get osd => _osd.stream;

  final List<Bookmark> bookmarks = [];
  bool uiHidden = false;

  // Inspector state.
  VideoAdjust adjust = const VideoAdjust();
  SubtitleStyle subStyle = const SubtitleStyle();
  List<NamedSubtitleStyle> userSubPresets = [];
  double subDelay = 0, audioDelay = 0;
  List<EqBand> eqBands = eqPresets.first.bands;
  bool eqEnabled = false;
  String eqPresetId = 'flat';
  String audioLanguages = '', subtitleLanguages = '';
  bool reverse = false;
  bool showWaveform = false, showSubtitleTimeline = false;
  DateTime? sleepAt;
  bool sleepAtEnd = false;
  Timer? _sleepTimer, _eqDebounce;
  StreamSubscription<bool>? _completedSub;

  NativePlayer? get _mpv =>
      player.platform is NativePlayer ? player.platform as NativePlayer : null;

  void notify(String action, [String? shortcut]) =>
      _osd.add(OsdMessage(action, shortcut));

  // ---- Loading ----------------------------------------------------------

  Future<void> openAll(
    List<String> uris, {
    bool append = false,
    int start = 0,
  }) async {
    if (uris.isEmpty) return;
    final medias = uris.map(Media.new).toList();
    if (append && player.state.playlist.medias.isNotEmpty) {
      for (final m in medias) {
        await player.add(m);
      }
      notify('Added ${medias.length} to queue');
    } else {
      await player.open(
        Playlist(medias, index: start.clamp(0, medias.length - 1)),
        play: true,
      );
      bookmarks.clear();
      notifyListeners();
    }
  }

  /// Saves progress, unloads everything and returns to the home hub.
  Future<void> closeMedia([String? key]) async {
    _recordProgress();
    _trackedUri = null;
    resumeOffer = null;
    await player.stop();
    bookmarks.clear();
    notify('Closed', key);
    notifyListeners();
  }

  /// Inserts [uris] right after the current item.
  Future<void> playNext(List<String> uris) async {
    if (player.state.playlist.medias.isEmpty) return openAll(uris);
    var at = player.state.playlist.index + 1;
    for (final u in uris) {
      await player.add(Media(u));
      await player.move(player.state.playlist.medias.length - 1, at++);
    }
    notify(uris.length == 1 ? 'Playing next' : '${uris.length} playing next');
  }

  List<String> get queueUris =>
      player.state.playlist.medias.map((m) => m.uri).toList();

  Future<void> loadSubtitle(String uri) async {
    await player.setSubtitleTrack(SubtitleTrack.uri(uri));
    notify('Subtitle loaded');
  }

  /// Subtitle files chosen for specific queue items (folder batch / online
  /// fetch); each is loaded when its item starts playing.
  final Map<String, String> assignedSubtitles = {};
  String? _assignedAppliedFor;

  Future<void> assignSubtitles(Map<String, String> map) async {
    assignedSubtitles.addAll(map);
    _assignedAppliedFor = null;
    await _applyAssignedSubtitle();
    notifyListeners();
  }

  Future<void> _applyAssignedSubtitle() async {
    final uri = currentUri;
    if (uri == null || player.state.duration <= Duration.zero) return;
    if (_assignedAppliedFor == uri) return;
    final sub = assignedSubtitles[uri];
    if (sub == null) return;
    _assignedAppliedFor = uri;
    await loadSubtitle(sub);
  }

  String get title {
    final pl = player.state.playlist;
    if (pl.medias.isEmpty) return 'Cru Media Player';
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

  // ---- mpv properties ----------------------------------------------------

  Future<void> _prop(String name, String value) async {
    try {
      await _mpv?.setProperty(name, value);
    } catch (e) {
      debugPrint('mpv: cannot set $name=$value: $e');
    }
  }

  Future<String> _get(String name) async {
    try {
      return await _mpv?.getProperty(name) ?? '';
    } catch (_) {
      return '';
    }
  }

  /// Sets only the properties whose values changed.
  Future<void> _applyDiff(
    Map<String, String> before,
    Map<String, String> after, {
    bool force = false,
  }) async {
    for (final e in after.entries) {
      if (force || before[e.key] != e.value) await _prop(e.key, e.value);
    }
  }

  /// Restores saved preferences and pushes them to mpv. Call once.
  /// Built-in + user GLSL shaders; null until [init] has run.
  ShaderLibrary? shaders;

  /// Last audio/video filter mpv refused (shown to the user), if any.
  String? filterError;
  StreamSubscription? _logSub;
  Map<String, String> _appliedPrefs = {};

  /// mpv properties derived from preferences.
  Map<String, String> prefsToMpv() {
    final s = settings;
    final shaders = Prefs.activeShaders
        .of(s)
        .split(';')
        .where((p) => p.isNotEmpty)
        .join(Platform.isWindows ? ';' : ':');
    final ua = Prefs.userAgent.of(s);
    return {
      'hwdec': Prefs.hwdec.of(s) ? 'auto-safe' : 'no',
      'deband': Prefs.deband.of(s) ? 'yes' : 'no',
      'volume-max': Prefs.volumeBoost.of(s) ? '150' : '100',
      'audio-normalize-downmix': Prefs.normalize.of(s) ? 'yes' : 'no',
      'sid': Prefs.subMode.of(s) == 'off' ? 'no' : 'auto',
      'subs-with-matching-audio': switch (Prefs.subMode.of(s)) {
        'foreign' => 'no',
        'forced' => 'forced',
        _ => 'yes',
      },
      'sub-auto': Prefs.subAutoLoad.of(s),
      'network-timeout': '${Prefs.netTimeout.of(s)}',
      'demuxer-max-bytes': '${Prefs.cacheMb.of(s)}MiB',
      'prefetch-playlist': Prefs.prefetch.of(s) ? 'yes' : 'no',
      'user-agent': ua.isEmpty ? 'CruMediaPlayer/1.0' : ua,
      'loop-file': Prefs.repeat.of(s) == 'one' ? 'inf' : 'no',
      'loop-playlist': Prefs.repeat.of(s) == 'all' ? 'inf' : 'no',
      if (!sleepAtEnd) 'keep-open': Prefs.autoplayNext.of(s) ? 'yes' : 'always',
      'glsl-shaders': shaders,
    };
  }

  Future<void> _applyPrefs() async {
    final next = prefsToMpv();
    await _applyDiff(_appliedPrefs, next);
    _appliedPrefs = next;
  }

  Future<void> init() async {
    await settings.load();
    _logSub = player.stream.log.listen((l) {
      final t = l.text;
      if (t.contains('filter') &&
          (t.contains('failed') || t.contains('No such filter'))) {
        filterError = t.trim();
        notify('An audio/video filter is not supported');
        notifyListeners();
      }
    });
    shaders = ShaderLibrary(
      Directory(
        '${library?.dir.path ?? '${Directory.systemTemp.path}/cone'}/shaders',
      ),
      settings,
    );
    try {
      await shaders!.prepare();
    } catch (e) {
      debugPrint('shaders: $e');
    }
    await _applyPrefs();
    settings.addListener(_applyPrefs);
    adjust = adjust.copyWith(
      scaler: Prefs.scaler.of(settings),
      toneMapHdr: Prefs.toneMap.of(settings),
    );
    await _applyDiff(const {}, adjust.toMpv(), force: true);
    await player.setVolume(Prefs.startVolume.of(settings));
    final speed = Prefs.defaultSpeed.of(settings);
    if (speed != 1.0) await player.setRate(speed);
    subStyle = settings.subtitleStyle ?? subStyle;
    userSubPresets = settings.subtitlePresets;
    eqBands = settings.eqBands ?? eqBands;
    eqEnabled = settings.eqEnabled;
    eqPresetId = settings.eqPresetId;
    audioLanguages = settings.audioLanguages;
    subtitleLanguages = settings.subtitleLanguages;
    showWaveform = settings.showWaveform;
    showSubtitleTimeline = settings.showSubtitleTimeline;
    await _applyDiff(const {}, subStyle.toMpv(), force: true);
    if (eqEnabled) await _prop('af', buildEqFilter(eqBands));
    if (audioLanguages.isNotEmpty) await _prop('alang', audioLanguages);
    if (subtitleLanguages.isNotEmpty) await _prop('slang', subtitleLanguages);
    _completedSub = player.stream.completed.listen((done) {
      if (done) _recordProgress(finished: true);
      if (done && sleepAtEnd) _finishSleep();
    });
    _waveSubs = [
      player.stream.duration.listen((_) => _refreshWaveform()),
      player.stream.tracks.listen((_) => _refreshWaveform()),
      player.stream.track.listen((_) => refreshCues()),
      player.stream.duration.listen((_) => refreshCues()),
      player.stream.duration.listen((_) => _applyAssignedSubtitle()),
    ];
    if (library != null) {
      _historySubs = [
        player.stream.duration.listen((_) => _checkFileChange()),
        player.stream.playlist.listen((_) => _checkFileChange()),
        player.stream.position.listen(_onPosition),
      ];
    }
    notifyListeners();
  }

  // ---- History & resume ---------------------------------------------------

  /// Set when the file that just opened was left unfinished last time.
  HistoryEntry? resumeOffer;
  String? _trackedUri;
  DateTime _lastSaved = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime? _lastThumb;
  List<StreamSubscription>? _historySubs, _waveSubs;

  String? get currentUri {
    final pl = player.state.playlist;
    if (pl.medias.isEmpty || pl.index < 0 || pl.index >= pl.medias.length) {
      return null;
    }
    return pl.medias[pl.index].uri;
  }

  /// Audio file, or a "video" that is only embedded cover art.
  bool get isAudioOnly {
    final v = player.state.tracks.video.where(
      (t) => t.id != 'auto' && t.id != 'no',
    );
    final hasAudio = player.state.tracks.audio.any(
      (t) => t.id != 'auto' && t.id != 'no',
    );
    if (!hasAudio) return false;
    return v.isEmpty || v.every((t) => t.albumart == true || t.image == true);
  }

  void _checkFileChange() {
    final uri = currentUri;
    if (uri == null || player.state.duration <= Duration.zero) return;
    if (uri == _trackedUri) return;
    _trackedUri = uri;
    _lastThumb = null;
    _lastSaved = DateTime.now();
    final h = library!.history[uri];
    final mode = Prefs.resume.of(settings);
    final offer = (h != null && h.resumable && mode != 'never') ? h : null;
    if (offer != null && mode == 'always') {
      resumeOffer = offer;
      acceptResume();
    } else {
      resumeOffer = offer;
    }
    notifyListeners();
  }

  void _onPosition(Duration pos) {
    final uri = currentUri;
    if (uri == null || uri != _trackedUri) return;
    if (DateTime.now().difference(_lastSaved) > const Duration(seconds: 5)) {
      _recordProgress();
    }
    // Card frame: refreshed at most once a minute so "Continue watching"
    // shows roughly where you stopped. Needs the history entry to exist.
    final due =
        _lastThumb == null ||
        DateTime.now().difference(_lastThumb!) > const Duration(minutes: 1);
    if (due &&
        Prefs.saveThumbnails.of(settings) &&
        library!.history[uri] != null &&
        !isAudioOnly) {
      _lastThumb = DateTime.now();
      player.screenshot().then((jpeg) {
        if (jpeg != null) library!.saveThumb(uri, jpeg);
      });
    }
  }

  void _recordProgress({bool finished = false}) {
    final uri = _trackedUri;
    final dur = player.state.duration;
    if (library == null || uri == null || dur <= Duration.zero) return;
    if (!Prefs.rememberHistory.of(settings)) return;
    _lastSaved = DateTime.now();
    library!.recordProgress(
      uri,
      title: displayName(uri),
      position: finished ? dur : player.state.position,
      duration: dur,
      isAudio: isAudioOnly,
    );
  }

  Future<void> acceptResume() async {
    final h = resumeOffer;
    resumeOffer = null;
    notifyListeners();
    if (h == null) return;
    await player.seek(Duration(milliseconds: h.positionMs));
    await player.play();
    notify(
      'Resumed at ${formatDuration(Duration(milliseconds: h.positionMs))}',
    );
  }

  void dismissResume() {
    if (resumeOffer == null) return;
    resumeOffer = null;
    notifyListeners();
  }

  // ---- Video --------------------------------------------------------------

  Future<void> setVideo(VideoAdjust a) async {
    final before = adjust.toMpv();
    adjust = a;
    notifyListeners();
    await _applyDiff(before, a.toMpv());
  }

  Future<void> resetVideo() async {
    await setVideo(const VideoAdjust());
    notify('Video reset');
  }

  Future<void> setZoom(double z) =>
      setVideo(adjust.copyWith(zoom: z.clamp(-2.0, 3.0).toDouble()));

  Future<void> rotate([String? key]) async {
    await setVideo(adjust.copyWith(rotation: (adjust.rotation + 90) % 360));
    notify('Rotate ${adjust.rotation}°', key);
  }

  Future<void> toggleFlip() async {
    await setVideo(adjust.copyWith(hflip: !adjust.hflip));
    notify(adjust.hflip ? 'Flip on' : 'Flip off');
  }

  Future<void> setAspect(String a) async {
    await setVideo(adjust.copyWith(aspect: a));
    notify('Aspect $a');
  }

  // ---- Subtitles ----------------------------------------------------------

  Future<void> setSubStyle(SubtitleStyle s) async {
    final before = subStyle.toMpv();
    subStyle = s;
    settings.subtitleStyle = s;
    notifyListeners();
    await _applyDiff(before, s.toMpv());
  }

  void saveSubPreset(String name) {
    userSubPresets = [
      ...userSubPresets.where((p) => p.name != name),
      NamedSubtitleStyle(name, subStyle),
    ];
    settings.subtitlePresets = userSubPresets;
    notify('Saved style "$name"');
    notifyListeners();
  }

  void deleteSubPreset(String name) {
    userSubPresets = userSubPresets.where((p) => p.name != name).toList();
    settings.subtitlePresets = userSubPresets;
    notifyListeners();
  }

  Future<void> setSubDelay(double seconds) async {
    subDelay = double.parse(seconds.clamp(-30.0, 30.0).toStringAsFixed(2));
    notifyListeners();
    await _prop('sub-delay', subDelay.toStringAsFixed(2));
  }

  // ---- Audio --------------------------------------------------------------

  Future<void> setAudioDelay(double seconds) async {
    audioDelay = double.parse(seconds.clamp(-10.0, 10.0).toStringAsFixed(2));
    notifyListeners();
    await _prop('audio-delay', audioDelay.toStringAsFixed(2));
  }

  /// Updates the equaliser. Filter rebuilds are debounced so dragging a
  /// band does not stutter the audio.
  void setEq({List<EqBand>? bands, bool? enabled, String? presetId}) {
    if (bands != null) eqBands = bands;
    if (enabled != null) eqEnabled = enabled;
    if (presetId != null) eqPresetId = presetId;
    settings
      ..eqBands = eqBands
      ..eqEnabled = eqEnabled
      ..eqPresetId = eqPresetId;
    notifyListeners();
    _eqDebounce?.cancel();
    _eqDebounce = Timer(
      const Duration(milliseconds: 120),
      () => _prop('af', eqEnabled ? buildEqFilter(eqBands) : ''),
    );
  }

  Future<void> setLanguages({String? audio, String? subtitle}) async {
    if (audio != null) {
      audioLanguages = audio.trim();
      settings.audioLanguages = audioLanguages;
      await _prop('alang', audioLanguages);
    }
    if (subtitle != null) {
      subtitleLanguages = subtitle.trim();
      settings.subtitleLanguages = subtitleLanguages;
      await _prop('slang', subtitleLanguages);
    }
    notifyListeners();
  }

  // ---- Playback -----------------------------------------------------------

  Future<void> setReverse(bool on) async {
    reverse = on;
    notifyListeners();
    await _prop('play-dir', on ? 'backward' : 'forward');
    notify(on ? 'Reverse playback' : 'Forward playback');
  }

  void setOverlay({bool? waveform, bool? subtitleTimeline}) {
    if (waveform != null) settings.showWaveform = showWaveform = waveform;
    if (subtitleTimeline != null) {
      settings.showSubtitleTimeline = showSubtitleTimeline = subtitleTimeline;
    }
    notifyListeners();
    _refreshWaveform();
    refreshCues();
  }

  String? _keepOpenBefore;

  /// [d] null cancels; [atEndOfFile] pauses when the current file ends.
  Future<void> setSleepTimer(Duration? d, {bool atEndOfFile = false}) async {
    _sleepTimer?.cancel();
    sleepAt = null;
    if (sleepAtEnd && !atEndOfFile) await _restoreKeepOpen();
    sleepAtEnd = atEndOfFile;
    if (atEndOfFile) {
      _keepOpenBefore ??= await _get('keep-open');
      await _prop('keep-open', 'always'); // stop instead of advancing
      notify('Sleep at end of file');
    } else if (d != null) {
      sleepAt = DateTime.now().add(d);
      _sleepTimer = Timer(d, _finishSleep);
      notify('Sleep in ${d.inMinutes} min');
    } else {
      notify('Sleep timer off');
    }
    notifyListeners();
  }

  Duration? get sleepRemaining => sleepAt?.difference(DateTime.now());

  Future<void> _restoreKeepOpen() async {
    if (_keepOpenBefore != null) {
      await _prop('keep-open', _keepOpenBefore!);
      _keepOpenBefore = null;
    }
  }

  Future<void> _finishSleep() async {
    _sleepTimer?.cancel();
    sleepAt = null;
    sleepAtEnd = false;
    await _restoreKeepOpen();
    await player.pause();
    notify('Sleep timer: paused');
    notifyListeners();
  }

  /// Technical details of the current file, grouped for display.
  Future<Map<String, Map<String, String>>> metadata() async {
    String same(String v) => v;
    Future<Map<String, String>> read(
      List<(String, String, String Function(String))> props,
    ) async {
      final out = <String, String>{};
      for (final (label, prop, fmt) in props) {
        final v = stripNull(await _get(prop));
        if (v.isNotEmpty) out[label] = fmt(v);
      }
      return out;
    }

    final file = await read([
      ('Name', 'filename', same),
      ('Path', 'path', same),
      ('Container', 'file-format', same),
      ('Size', 'file-size', formatBytes),
      ('Duration', 'duration', formatSeconds),
    ]);
    final video = await read([
      ('Codec', 'video-format', same),
      ('Decoder', 'video-codec', same),
      ('Resolution', 'video-params/w', same),
      ('Frame rate', 'container-fps', (v) => '${trimNumber(v)} fps'),
      ('Pixel format', 'video-params/hw-pixelformat', same),
      ('Colour matrix', 'video-params/colormatrix', same),
      ('Primaries', 'video-params/primaries', same),
      ('Transfer', 'video-params/gamma', same),
      ('Bitrate', 'video-bitrate', formatBitrate),
      ('Hardware decoding', 'hwdec-current', same),
    ]);
    if (video['Decoder'] == video['Codec']) video.remove('Decoder');
    // With hardware decoding pixelformat is just "videotoolbox"; the real
    // format is in hw-pixelformat, which is empty for software decoding.
    if (!video.containsKey('Pixel format')) {
      final pf = await _get('video-params/pixelformat');
      if (pf.isNotEmpty) video['Pixel format'] = pf;
    }
    if (video.containsKey('Resolution')) {
      video['Resolution'] =
          '${video['Resolution']}×${await _get('video-params/h')}';
    }
    final audio = await read([
      ('Codec', 'audio-codec-name', same),
      ('Sample rate', 'audio-params/samplerate', formatHz),
      ('Channels', 'audio-params/channel-count', same),
      ('Layout', 'audio-params/channels', same),
      ('Bitrate', 'audio-bitrate', formatBitrate),
      ('Output device', 'audio-device', same),
    ]);
    final tags = parseTags(await _get('metadata'));
    return {
      'File': file,
      'Video': video,
      'Audio': audio,
      if (tags.isNotEmpty) 'Tags': tags,
    };
  }

  /// Cues of the active external subtitle file, for the timeline.
  List<Cue>? cues;
  String? cuesPath;

  Future<void> refreshCues() async {
    if (!showSubtitleTimeline) return;
    final path = await _get('current-tracks/sub/external-filename');
    final next = path.isEmpty ? null : path;
    if (next == cuesPath && (cues != null || next == null)) return;
    cuesPath = next;
    cues = next == null ? null : await loadCues(next);
    notifyListeners();
  }

  /// Saves the current frame (with subtitles) to the screenshot folder.
  Future<String?> takeScreenshot([String? key]) async {
    if (currentUri == null) return null;
    final png = Prefs.shotFormat.of(settings) == 'png';
    final bytes = await player.screenshot(
      format: png ? 'image/png' : 'image/jpeg',
      includeLibassSubtitles: true,
    );
    if (bytes == null) {
      notify('Screenshot failed', key);
      return null;
    }
    var folder = Prefs.shotFolder.of(settings);
    if (folder.isEmpty) {
      final home =
          Platform.environment['HOME'] ??
          Platform.environment['USERPROFILE'] ??
          Directory.systemTemp.path;
      folder =
          '$home${Platform.pathSeparator}Pictures'
          '${Platform.pathSeparator}Cru Media Player';
    }
    await Directory(folder).create(recursive: true);
    final t = formatDuration(player.state.position).replaceAll(':', '-');
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final name = '${title.replaceAll(RegExp(r'[^\w\- .]'), '_')} $t $stamp';
    final path = '$folder${Platform.pathSeparator}$name.${png ? 'png' : 'jpg'}';
    await File(path).writeAsBytes(bytes);
    notify('Screenshot saved', key);
    return path;
  }

  /// Opens a live capture source with mpv's low-latency profile.
  Future<void> openCapture(String url, {bool lowLatency = true}) async {
    if (lowLatency) {
      try {
        await _mpv?.command(['apply-profile', 'low-latency']);
      } catch (_) {}
    }
    await openAll([url]);
    notify(lowLatency ? 'Live source · low latency' : 'Live source');
  }

  /// Title / artist / album tags of the current file.
  Future<Map<String, String>> trackTags() async =>
      parseTags(await _get('metadata'));

  /// Bottom subtitle margin in mpv's 720-line units (keeps text above bars).
  Future<void> setSubtitleMargin(int margin) =>
      _prop('sub-margin-y', '$margin');

  void toggleUi([String? key]) {
    uiHidden = !uiHidden;
    notify(uiHidden ? 'UI hidden' : 'UI shown', key);
    notifyListeners();
  }

  @override
  void dispose() {
    _recordProgress();
    library?.save();
    for (final sub in [...?_historySubs, ...?_waveSubs]) {
      sub.cancel();
    }
    settings.removeListener(_applyPrefs);
    _logSub?.cancel();
    _sleepTimer?.cancel();
    _eqDebounce?.cancel();
    _completedSub?.cancel();
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
