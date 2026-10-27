import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'blob_logo.dart';

import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:window_manager/window_manager.dart';

import '../library/library_store.dart';
import '../player/frame_previewer.dart';
import '../player/media_loader.dart';
import '../player/waveform.dart';
import '../player/player_controller.dart';
import '../theme.dart';
import 'volume_slider.dart';
import 'flyouts.dart';
import 'osd.dart';
import 'home/home_view.dart';
import 'inspector/inspector_panel.dart';
import 'library/library_screen.dart';
import 'library/media_widgets.dart';
import 'music_view.dart';
import 'queue_panel.dart';
import 'resume_banner.dart';
import 'subtitle_loader.dart';
import 'subtitle_timeline.dart';
import 'settings/settings_screen.dart';
import 'layout/control_layout.dart';
import 'layout/layout_editor.dart';
import 'onboarding.dart';
import 'multiview_view.dart';
import 'tools/tools_dialogs.dart';
import '../tools/cast_session.dart';
import '../player/multiview.dart';
import '../player/settings_store.dart';
import '../player/system_open.dart';
import '../settings/prefs.dart';
import 'seek_bar.dart';

final bool _isMac = Platform.isMacOS;
final String _mod = _isMac ? '⌘' : 'Ctrl';

class PlayerScreen extends StatefulWidget {
  final List<String> initialFiles;
  final PlayerController? controller;
  final LibraryStore? library;

  /// Injectable for tests; one is created otherwise.
  final FramePreviewer? previewer;
  final SettingsStore? settings;
  const PlayerScreen({
    super.key,
    this.initialFiles = const [],
    this.controller,
    this.library,
    this.previewer,
    this.settings,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late final c =
      widget.controller ??
      PlayerController(
        library: widget.library,
        settings: widget.settings,
        waveforms: WaveformService(
          Directory(
            '${widget.library?.dir.path ?? Directory.systemTemp.path}/waveforms',
          ),
        ),
      );
  late final _previewer = widget.previewer ?? FramePreviewer();
  late final _multi = MultiView(p);
  final _cast = CastSession();

  @visibleForTesting
  CastSession get debugCast => _cast;

  @visibleForTesting
  MultiView get debugMultiView => _multi;

  Future<void> _openMultiView() async {
    if (_multi.feeds.isEmpty) {
      await addFeedFlow(context, c, _multi);
    } else {
      _multi.setMode(MultiMode.grid);
    }
  }

  SettingsStore get _s => c.settings;
  bool _settingsOpen = false;
  bool _layoutEditorOpen = false;
  String _settingsPanel = 'General';
  bool _onTop = false;

  void _openSettings([String panel = 'General']) => setState(() {
    _settingsOpen = true;
    _settingsPanel = panel;
    _libraryOpen = _queueOpen = _inspectorOpen = false;
  });

  /// Window-level preferences that are not mpv properties.
  void _onPrefs() {
    final top = Prefs.stayOnTop.of(_s);
    if (top != _onTop && !_pip) {
      _onTop = top;
      windowManager.setAlwaysOnTop(top);
    }
    if (mounted) setState(() {});
  }

  Future<Uint8List?> _previewAt(Duration t) async {
    final uri = c.currentUri;
    if (uri == null || c.isAudioOnly) return null;
    if (!Prefs.seekPreviews.of(_s)) return null;
    return _previewer.frameAt(uri, p.state.duration, t);
  }

  LibraryStore? get _lib => c.library;

  // Full-window library over the player.
  bool _libraryOpen = false;
  LibrarySection _librarySection = LibrarySection.videos;
  String? _libraryFolder, _librarySource;

  void _openLibrary({
    String? folder,
    String? sourceUrl,
    LibrarySection? section,
  }) => setState(() {
    _libraryOpen = true;
    _librarySection = section ?? _librarySection;
    _libraryFolder = folder;
    _librarySource = sourceUrl;
    _queueOpen = _inspectorOpen = false;
  });

  late final _actions = LibraryActions(
    play: (uris, {int start = 0}) {
      setState(() => _libraryOpen = false);
      c.openAll(uris, start: start);
    },
    enqueue: (uris) => c.openAll(uris, append: true),
    playNext: c.playNext,
  );
  late final loader = MediaLoader(c);
  final _focus = FocusNode();
  final _contextMenu = MenuController();
  final List<StreamSubscription> _subs = [];

  // Edge-proximity auto-hide.
  static const _topZone = 90.0;
  double get _bottomZone => c.showSubtitleTimeline ? 240 : 150;
  bool _nearTop = false, _nearBottom = false, _pointerIdle = false;
  bool _lastTop = false, _lastBottom = false;
  Timer? _idleTimer;

  bool _queueOpen = false;
  bool _inspectorOpen = false;
  InspectorTab _inspectorTab = InspectorTab.subtitles;

  // The queue and the inspector share the right edge; one at a time.
  void _toggleQueue() => setState(() {
    _queueOpen = !_queueOpen;
    if (_queueOpen) _inspectorOpen = false;
  });

  void _toggleInspector([InspectorTab? tab]) => setState(() {
    if (tab != null && _inspectorOpen && tab != _inspectorTab) {
      _inspectorTab = tab;
      return;
    }
    if (tab != null) _inspectorTab = tab;
    _inspectorOpen = !_inspectorOpen;
    if (_inspectorOpen) _queueOpen = false;
  });
  bool _fullscreen = false;
  bool _pip = false;
  Rect? _boundsBeforePip;
  double _brightness = 0; // accumulates small gesture deltas

  // Two-finger trackpad swipes lock to one axis once they have moved a few
  // pixels: horizontal scrubs, vertical adjusts brightness / volume.
  Offset _panTotal = Offset.zero;
  Axis? _panAxis;
  Duration? _scrubBase, _scrubTarget;
  DateTime _lastScrubSeek = DateTime(0);

  void _panStart() {
    _panTotal = Offset.zero;
    _panAxis = null;
    _scrubBase = _scrubTarget = null;
  }

  /// A full-width swipe covers a quarter of the file (30 s to 5 min);
  /// fingers moving right go forward.
  void _scrub(double dx, double width) {
    final dur = p.state.duration;
    if (!_hasMedia || dur <= Duration.zero || width <= 0) return;
    final base = _scrubBase ??= p.state.position;
    final spanMs = (dur.inMilliseconds / 4).clamp(30000, 300000);
    final ms = (base.inMilliseconds + spanMs * dx / width).clamp(
      0,
      dur.inMilliseconds,
    );
    final target = Duration(milliseconds: ms.round());
    _scrubTarget = target;
    final delta = target - base;
    c.notify(
      '${formatDuration(target)}  '
          '(${delta.isNegative ? '−' : '+'}${formatDuration(delta.abs())})',
      'Swipe',
    );
    final now = DateTime.now();
    if (now.difference(_lastScrubSeek) > const Duration(milliseconds: 60)) {
      _lastScrubSeek = now;
      p.seek(target);
    }
  }

  void _panEnd() {
    final t = _scrubTarget;
    if (t != null) p.seek(t);
    _panStart();
  }

  bool _dragging = false;
  int _subMargin = -1;

  Player get p => c.player;

  @override
  void initState() {
    super.initState();
    for (final s in <Stream>[
      p.stream.playing,
      p.stream.duration,
      p.stream.volume,
      p.stream.rate,
      p.stream.tracks,
      p.stream.track,
      p.stream.playlist,
      p.stream.audioDevices,
      p.stream.audioDevice,
    ]) {
      _subs.add(s.listen((_) => mounted ? setState(() {}) : null));
    }
    _subs.add(p.stream.playlist.listen((_) => windowManager.setTitle(c.title)));
    c.addListener(() => mounted ? setState(() {}) : null);
    _s.addListener(_onPrefs);
    _onPrefs();
    _multi.addListener(() => mounted ? setState(() {}) : null);
    _cast.addListener(() => mounted ? setState(() {}) : null);
    c.init().then((_) async {
      final launched = await SystemOpen.listen(_openFromSystem);
      final files = [...widget.initialFiles, ...launched];
      if (files.isNotEmpty) await _openFromSystem(files);
    });
  }

  /// Files from the command line or the OS (Finder "Open With", Dock icon):
  /// media replaces what is playing; a subtitle file loads onto it.
  Future<void> _openFromSystem(List<String> files) async {
    final subs = files.where(
      (f) => subtitleExtensions.contains(f.split('.').last.toLowerCase()),
    );
    final media = files.where((f) => !subs.contains(f)).toList();
    if (media.isNotEmpty) {
      await c.openAll(media);
    } else if (subs.isNotEmpty && _hasMedia) {
      await c.loadSubtitle(subs.first);
    }
    if (files.isNotEmpty) await windowManager.focus();
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _idleTimer?.cancel();
    _hideTimer?.cancel();
    _s.removeListener(_onPrefs);
    c.dispose();
    _previewer.dispose();
    _multi.dispose();
    _cast.dispose();
    _focus.dispose();
    super.dispose();
  }

  bool get _hasMedia => p.state.playlist.medias.isNotEmpty;

  // Music has nothing to cover up, so its controls stay put.
  bool get _showTop =>
      !c.uiHidden &&
      (!_hasMedia || !p.state.playing || _nearTop || c.isAudioOnly);
  // Nothing to control on the home hub, so the bottom bar stays away.
  bool get _showBottom =>
      !c.uiHidden &&
      _hasMedia &&
      (!p.state.playing || _nearBottom || c.isAudioOnly);

  Timer? _hideTimer;

  void _onHover(PointerHoverEvent e, double height) {
    final y = e.localPosition.dy;
    final top = y < _topZone, bottom = y > height - _bottomZone;
    final leaving = (_nearTop && !top) || (_nearBottom && !bottom);
    final delay = Prefs.hideDelayMs.of(_s);
    if (leaving && delay > 0) {
      // Keep the bars a moment after the pointer leaves an edge.
      _hideTimer ??= Timer(Duration(milliseconds: delay), () {
        _hideTimer = null;
        if (mounted) {
          setState(() {
            _nearTop = _lastTop;
            _nearBottom = _lastBottom;
          });
        }
      });
      _lastTop = top;
      _lastBottom = bottom;
    } else if (top != _nearTop || bottom != _nearBottom || _pointerIdle) {
      _hideTimer?.cancel();
      _hideTimer = null;
      setState(() {
        _nearTop = top;
        _nearBottom = bottom;
        _pointerIdle = false;
      });
    }
    _lastTop = top;
    _lastBottom = bottom;
    _idleTimer?.cancel();
    _idleTimer = Timer(const Duration(seconds: 2), () {
      if (mounted && p.state.playing && !top && !bottom) {
        setState(() => _pointerIdle = true);
      }
    });
  }

  // ---- Window modes -----------------------------------------------------

  Future<void> _toggleFullscreen([String? key]) async {
    if (_pip) await _togglePip();
    _fullscreen = !_fullscreen;
    await windowManager.setFullScreen(_fullscreen);
    c.notify(_fullscreen ? 'Fullscreen' : 'Exit fullscreen', key);
    setState(() {});
  }

  /// Desktop picture-in-picture: a small, always-on-top, chrome-less window.
  Future<void> _togglePip([String? key]) async {
    if (_fullscreen) {
      _fullscreen = false;
      await windowManager.setFullScreen(false);
    }
    _pip = !_pip;
    if (_pip) {
      _boundsBeforePip = await windowManager.getBounds();
      await windowManager.setTitleBarStyle(
        TitleBarStyle.hidden,
        windowButtonVisibility: false,
      );
      await windowManager.setAlwaysOnTop(true);
      await windowManager.setSize(const Size(480, 270));
      await windowManager.setAlignment(Alignment.bottomRight);
    } else {
      await windowManager.setAlwaysOnTop(false);
      await windowManager.setTitleBarStyle(TitleBarStyle.normal);
      if (_boundsBeforePip != null) {
        await windowManager.setBounds(_boundsBeforePip!);
      }
    }
    c.notify(_pip ? 'Picture-in-picture' : 'Exit picture-in-picture', key);
    setState(() {});
  }

  /// After overlays close (settings, library, editor, tour) give keyboard
  /// focus back to the player so shortcuts work again. Never steals focus
  /// from a dialog on top or from a text field being typed in.
  void _reclaimFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _focus.hasFocus) return;
      if (_settingsOpen || _layoutEditorOpen || _libraryOpen) return;
      if (ModalRoute.of(context)?.isCurrent == false) return;
      final f = FocusManager.instance.primaryFocus?.context;
      if (f != null &&
          (f.widget is EditableText ||
              f.findAncestorWidgetOfExactType<EditableText>() != null)) {
        return;
      }
      _focus.requestFocus();
    });
  }

  // ---- Keyboard ---------------------------------------------------------

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    // Typing in a text field must not trigger player shortcuts.
    final focused = FocusManager.instance.primaryFocus?.context;
    if (focused != null &&
        (focused.widget is EditableText ||
            focused.findAncestorWidgetOfExactType<EditableText>() != null)) {
      return KeyEventResult.ignored;
    }
    final hk = HardwareKeyboard.instance;
    final mod = _isMac ? hk.isMetaPressed : hk.isControlPressed;
    final shift = hk.isShiftPressed;
    final k = e.logicalKey;
    String combo(String key) =>
        [if (mod) _mod, if (shift) 'Shift', key].join(' + ');

    if (mod) {
      if (k == LogicalKeyboardKey.keyB) {
        c.addBookmark(combo('B'));
      } else if (k == LogicalKeyboardKey.keyO) {
        shift ? loader.openFolder() : loader.openFiles();
      } else if (k == LogicalKeyboardKey.keyU) {
        loader.openStream(context);
      } else if (k == LogicalKeyboardKey.keyV) {
        loader.playClipboard(combo('V'));
      } else if (k == LogicalKeyboardKey.keyL) {
        if (shift && _lib != null) {
          _libraryOpen ? setState(() => _libraryOpen = false) : _openLibrary();
        } else {
          _toggleQueue();
        }
      } else if (k == LogicalKeyboardKey.keyI) {
        _toggleInspector();
      } else if (k == LogicalKeyboardKey.keyT) {
        showMediaHub(context, c, loader, _cast);
      } else if (k == LogicalKeyboardKey.keyG && _hasMedia) {
        _multi.mode == MultiMode.grid
            ? _multi.setMode(MultiMode.floating)
            : _openMultiView();
      } else if (k == LogicalKeyboardKey.comma) {
        _settingsOpen ? setState(() => _settingsOpen = false) : _openSettings();
      } else if (k == LogicalKeyboardKey.keyW && _hasMedia) {
        c.closeMedia(combo('W'));
      } else {
        return KeyEventResult.ignored;
      }
      return KeyEventResult.handled;
    }

    if (c.resumeOffer != null &&
        (k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.escape)) {
      k == LogicalKeyboardKey.enter ? c.acceptResume() : c.dismissResume();
      return KeyEventResult.handled;
    }
    if (!Prefs.onboarded.of(_s)) {
      if (k == LogicalKeyboardKey.escape) Prefs.onboarded.set(_s, true);
      return KeyEventResult.ignored;
    }
    if (_multi.mode == MultiMode.grid && k == LogicalKeyboardKey.escape) {
      _multi.setMode(MultiMode.floating);
      return KeyEventResult.handled;
    }
    if (_settingsOpen && k == LogicalKeyboardKey.escape) {
      setState(() => _settingsOpen = false);
      return KeyEventResult.handled;
    }
    if (_settingsOpen) return KeyEventResult.ignored;
    if (_libraryOpen && k == LogicalKeyboardKey.escape) {
      setState(() => _libraryOpen = false);
      return KeyEventResult.handled;
    }
    if (_libraryOpen) return KeyEventResult.ignored;

    if (k == LogicalKeyboardKey.space || k == LogicalKeyboardKey.keyK) {
      c.togglePlay(k == LogicalKeyboardKey.space ? 'Space' : 'K');
    } else if (k == LogicalKeyboardKey.arrowRight) {
      c.seekBy(
        Duration(
          seconds: shift ? Prefs.bigSeekStep.of(_s) : Prefs.seekStep.of(_s),
        ),
        combo('→'),
      );
    } else if (k == LogicalKeyboardKey.arrowLeft) {
      c.seekBy(
        Duration(
          seconds: -(shift ? Prefs.bigSeekStep.of(_s) : Prefs.seekStep.of(_s)),
        ),
        combo('←'),
      );
    } else if (k == LogicalKeyboardKey.period) {
      c.frameStep(true, '.');
    } else if (k == LogicalKeyboardKey.comma) {
      c.frameStep(false, ',');
    } else if (k == LogicalKeyboardKey.arrowUp) {
      c.setVolume(p.state.volume + 5, '↑');
    } else if (k == LogicalKeyboardKey.arrowDown) {
      c.setVolume(p.state.volume - 5, '↓');
    } else if (k == LogicalKeyboardKey.keyM) {
      c.toggleMute('M');
    } else if (k == LogicalKeyboardKey.keyF) {
      _toggleFullscreen('F');
    } else if (k == LogicalKeyboardKey.escape) {
      if (OpenMenus.closeAll()) {
        // A popup was open; Escape only dismisses it.
      } else if (_fullscreen) {
        _toggleFullscreen('Esc');
      } else if (_pip) {
        _togglePip('Esc');
      }
    } else if (k == LogicalKeyboardKey.keyI) {
      _togglePip('I');
    } else if (k == LogicalKeyboardKey.keyN) {
      c.next('N');
    } else if (k == LogicalKeyboardKey.keyP) {
      c.previous('P');
    } else if (k == LogicalKeyboardKey.bracketRight) {
      c.setRate(p.state.rate + 0.1, ']');
    } else if (k == LogicalKeyboardKey.bracketLeft) {
      c.setRate(p.state.rate - 0.1, '[');
    } else if (k == LogicalKeyboardKey.backspace) {
      c.setRate(1.0, 'Backspace');
    } else if (k == LogicalKeyboardKey.keyH) {
      c.toggleUi('H');
    } else if (k == LogicalKeyboardKey.keyS && _hasMedia) {
      c.takeScreenshot('S');
    } else if (k == LogicalKeyboardKey.keyR) {
      c.rotate('R');
    } else if (k == LogicalKeyboardKey.keyZ) {
      c.setZoom(c.adjust.zoom + 0.1);
      c.notify('Zoom ${(100 * _zoomFactor).round()}%', 'Z');
    } else if (k == LogicalKeyboardKey.keyX) {
      c.setZoom(c.adjust.zoom - 0.1);
      c.notify('Zoom ${(100 * _zoomFactor).round()}%', 'X');
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  // mpv's video-zoom is log2-scaled.
  double get _zoomFactor => math.pow(2, c.adjust.zoom).toDouble();

  // ---- Gestures (trackpad / touch / mouse) -----------------------------

  void _sideAdjust(double localX, double width, double dy) {
    // Swipe up = increase. Left half = brightness, right half = volume.
    final delta = -dy * 0.25;
    if (localX < width / 2) {
      if (_brightness.round() != c.adjust.brightness) {
        _brightness = c.adjust.brightness.toDouble();
      }
      _brightness = (_brightness + delta).clamp(-100.0, 100.0);
      c.setVideo(c.adjust.copyWith(brightness: _brightness.round()));
      c.notify('Brightness ${_brightness.round()}');
    } else {
      c.setVolume(p.state.volume + delta, 'Swipe');
    }
  }

  void _doubleTap(TapDownDetails d, double width) {
    final x = d.localPosition.dx;
    switch (Prefs.doubleClick.of(_s)) {
      case 'fullscreen':
        _toggleFullscreen('Double-click');
        return;
      case 'play':
        c.togglePlay('Double-click');
        return;
    }
    if (x < width / 3) {
      c.seekBy(const Duration(seconds: -10), 'Double-tap');
    } else if (x > width * 2 / 3) {
      c.seekBy(const Duration(seconds: 10), 'Double-tap');
    } else {
      _toggleFullscreen('Double-click');
    }
  }

  // ---- Build ------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    _reclaimFocus();
    // Keep subtitles clear of the bottom bar while it is shown. mpv's
    // margin is in 720-line units, so convert from this window's pixels.
    final barPx = !(_showBottom && _hasMedia)
        ? 0.0
        : 112.0 + (c.showSubtitleTimeline ? 90.0 : 0.0);
    final winH = MediaQuery.sizeOf(context).height;
    final margin = 22 + (winH <= 0 ? 0 : (barPx / winH * 720).round());
    if (margin != _subMargin) {
      _subMargin = margin;
      c.setSubtitleMargin(margin);
    }
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: DropTarget(
          onEnter: (_) => setState(() => _dragging = true),
          onLeave: () => setState(() => _dragging = false),
          onDrop: (d) async {
            setState(() => _dragging = false);
            final dropped = <String>[];
            for (final item in d.items) {
              switch (item) {
                case DropFileItem(:final localPath?):
                  dropped.add(localPath);
                case DropDirectoryItem(:final localPath?):
                  dropped.addAll(
                    Directory(localPath)
                        .listSync(recursive: true)
                        .whereType<File>()
                        .map((f) => f.path)
                        .where(isMediaPath)
                        .toList()
                      ..sort(),
                  );
                case DropStringItem(:final value) when value.contains('://'):
                  dropped.addAll(
                    value.split(RegExp(r'\s+')).where((s) => s.contains('://')),
                  );
                default:
                  break;
              }
            }
            final subs = dropped.where(
              (f) =>
                  subtitleExtensions.contains(f.split('.').last.toLowerCase()),
            );
            if (subs.isNotEmpty && _hasMedia) await c.loadSubtitle(subs.first);
            final media = dropped
                .where((f) => f.contains('://') || isMediaPath(f))
                .toSet()
                .toList();
            // Dropping while something plays appends to the queue without
            // interrupting playback.
            await c.openAll(media, append: _hasMedia);
          },
          child: LayoutBuilder(
            builder: (context, box) {
              return MouseRegion(
                cursor: _pointerIdle && p.state.playing
                    ? SystemMouseCursors.none
                    : MouseCursor.defer,
                onHover: (e) => _onHover(e, box.maxHeight),
                onExit: (_) => setState(() {
                  _nearTop = false;
                  _nearBottom = false;
                }),
                child: Stack(
                  children: [
                    _previewer.surface(),
                    Positioned.fill(child: _videoLayer(box)),
                    if (!_hasMedia)
                      Positioned.fill(
                        child: _lib == null
                            ? _emptyState()
                            : HomeView(
                                library: _lib!,
                                actions: _actions,
                                onOpenFile: loader.openFiles,
                                onOpenFolder: loader.openFolder,
                                onOpenStream: () => loader.openStream(context),
                                onOpenLibrary: _openLibrary,
                              ),
                      ),
                    if (_dragging) Positioned.fill(child: _dropHint()),
                    if (_multi.mode == MultiMode.floating)
                      Positioned.fill(
                        child: MultiViewFloating(
                          mv: _multi,
                          onGrid: () => _multi.setMode(MultiMode.grid),
                        ),
                      ),
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: _fade(_showTop && !_pip, _topBar()),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: _fade(_showBottom, _bottomBar(box.maxWidth)),
                    ),
                    Positioned(
                      top: 70,
                      right: 0,
                      bottom: 0,
                      child: QueuePanel(
                        open: _queueOpen,
                        controller: c,
                        onClose: () => setState(() => _queueOpen = false),
                        onAddFiles: () => loader.openFiles(append: true),
                      ),
                    ),
                    Positioned(
                      top: 70,
                      right: 0,
                      bottom: 0,
                      child: InspectorPanel(
                        open: _inspectorOpen,
                        controller: c,
                        tab: _inspectorTab,
                        onTab: (t) => setState(() => _inspectorTab = t),
                        onClose: () => setState(() => _inspectorOpen = false),
                        onLoadSubtitle: loader.openSubtitle,
                      ),
                    ),
                    if (_multi.mode == MultiMode.grid)
                      Positioned.fill(
                        child: MultiViewGrid(c: c, mv: _multi),
                      ),
                    if (c.resumeOffer != null && !_libraryOpen)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 128,
                        child: Center(
                          child: ResumeBanner(
                            key: ValueKey(c.resumeOffer!.uri),
                            entry: c.resumeOffer!,
                            onResume: c.acceptResume,
                            onDismiss: c.dismissResume,
                          ),
                        ),
                      ),
                    if (_lib != null)
                      Positioned.fill(
                        child: IgnorePointer(
                          ignoring: !_libraryOpen,
                          child: AnimatedOpacity(
                            opacity: _libraryOpen ? 1 : 0,
                            duration: const Duration(milliseconds: 160),
                            child: _libraryOpen
                                ? LibraryScreen(
                                    library: _lib!,
                                    actions: _actions,
                                    currentQueue: () => c.queueUris,
                                    initialSection: _librarySection,
                                    initialFolder: _libraryFolder,
                                    initialSourceUrl: _librarySource,
                                    onClose: () =>
                                        setState(() => _libraryOpen = false),
                                  )
                                : const SizedBox.shrink(),
                          ),
                        ),
                      ),
                    if (!Prefs.onboarded.of(_s))
                      Positioned.fill(
                        child: OnboardingWizard(
                          settings: _s,
                          onOpenFile: loader.openFiles,
                        ),
                      ),
                    if (_layoutEditorOpen)
                      Positioned.fill(
                        child: LayoutEditor(
                          profiles: _layouts,
                          onClose: () =>
                              setState(() => _layoutEditorOpen = false),
                        ),
                      ),
                    if (_settingsOpen)
                      Positioned.fill(
                        child: SettingsScreen(
                          controller: c,
                          initialPanel: _settingsPanel,
                          onClose: () => setState(() => _settingsOpen = false),
                          onShowOnboarding: () => setState(() {
                            _settingsOpen = false;
                            Prefs.onboarded.set(_s, false);
                          }),
                          onEditLayout: () => setState(() {
                            _settingsOpen = false;
                            _layoutEditorOpen = true;
                          }),
                          onEditSubtitleStyle: () => setState(() {
                            _settingsOpen = false;
                            _inspectorOpen = true;
                            _inspectorTab = InspectorTab.subtitles;
                          }),
                        ),
                      ),
                    Positioned(
                      top: 70,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: Osd(
                          messages: c.osd,
                          enabled: Prefs.osd.of(_s),
                          durationMs: Prefs.osdMs.of(_s),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _fade(bool visible, Widget child) => IgnorePointer(
    ignoring: !visible,
    child: AnimatedOpacity(
      opacity: visible ? 1 : 0,
      duration: Duration(milliseconds: visible ? 120 : 220),
      child: child,
    ),
  );

  Widget _videoLayer(BoxConstraints box) {
    return TrackedMenuAnchor(
      controller: _contextMenu,
      menuChildren: _contextMenuItems(),
      child: Listener(
        onPointerSignal: (e) {
          if (e is PointerScrollEvent &&
              e.scrollDelta.dx.abs() > e.scrollDelta.dy.abs()) {
            // Horizontal wheel (tilt wheels, Magic Mouse): seek.
            c.seekBy(
              Duration(seconds: e.scrollDelta.dx > 0 ? 5 : -5),
              'Scroll',
            );
          } else if (e is PointerScrollEvent) {
            switch (Prefs.wheel.of(_s)) {
              case 'volume':
                c.setVolume(
                  p.state.volume - e.scrollDelta.dy.sign * 5,
                  'Scroll',
                );
              case 'seek':
                c.seekBy(
                  Duration(seconds: e.scrollDelta.dy > 0 ? -5 : 5),
                  'Scroll',
                );
            }
          }
        },
        // Trackpad: pinch zooms; two-finger swipes scrub (horizontal) or
        // adjust brightness / volume (vertical, left / right half).
        onPointerPanZoomStart: (_) => _panStart(),
        onPointerPanZoomUpdate: (e) {
          if ((e.scale - 1).abs() > 0.02) {
            c.setZoom(c.adjust.zoom + (e.scale - 1) * 0.05);
            return;
          }
          _panTotal += e.panDelta;
          _panAxis ??= _panTotal.distance < 6
              ? null
              : _panTotal.dx.abs() > _panTotal.dy.abs()
              ? Axis.horizontal
              : Axis.vertical;
          switch (_panAxis) {
            case Axis.horizontal:
              _scrub(_panTotal.dx, box.maxWidth);
            case Axis.vertical:
              _sideAdjust(e.localPosition.dx, box.maxWidth, e.panDelta.dy);
            case null:
              break;
          }
        },
        onPointerPanZoomEnd: (_) => _panEnd(),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            _focus.requestFocus();
            if (_contextMenu.isOpen) {
              _contextMenu.close();
            } else if (_hasMedia) {
              c.togglePlay();
            }
          },
          onDoubleTapDown: (d) => _doubleTap(d, box.maxWidth),
          onDoubleTap: () {},
          onSecondaryTapDown: (d) =>
              _contextMenu.open(position: d.localPosition),
          // Touchscreens: vertical swipe on left/right halves.
          onVerticalDragUpdate: (d) =>
              _sideAdjust(d.localPosition.dx, box.maxWidth, d.delta.dy),
          supportedDevices: const {
            PointerDeviceKind.touch,
            PointerDeviceKind.mouse,
            PointerDeviceKind.trackpad,
          },
          // Flips are a GPU transform here (cheap, works with hwdec).
          child: c.isAudioOnly
              ? MusicView(
                  c: c,
                  waveform: StreamBuilder<Duration>(
                    stream: p.stream.position,
                    builder: (_, _) => SeekBar(
                      position: p.state.position,
                      duration: p.state.duration,
                      buffer: p.state.buffer,
                      bookmarks: c.bookmarks,
                      onSeek: p.seek,
                      onFrameStep: (fwd) => c.frameStep(fwd, 'Scroll'),
                      waveform: c.waveform,
                      waveformHeight: 72,
                    ),
                  ),
                )
              : Transform.scale(
                  scaleX: c.adjust.hflip ? -1 : 1,
                  scaleY: c.adjust.vflip ? -1 : 1,
                  child: Video(
                    controller: c.video,
                    controls: NoVideoControls,
                    // Subtitles are rendered by mpv (libass), not this overlay.
                    subtitleViewConfiguration: const SubtitleViewConfiguration(
                      visible: false,
                    ),
                    fill: Colors.black,
                  ),
                ),
        ),
      ),
    );
  }

  List<Widget> _contextMenuItems() => [
    FlyoutItem(
      label: p.state.playing ? 'Pause' : 'Play',
      detail: 'Space',
      onTap: () => c.togglePlay(),
    ),
    FlyoutItem(
      label: 'Hide UI',
      detail: 'H',
      selected: c.uiHidden,
      onTap: () => c.toggleUi(),
    ),
    Divider(height: 10, color: ConeColors.border),
    const FlyoutHeader('Video'),
    FlyoutItem(label: 'Rotate 90°', detail: 'R', onTap: () => c.rotate()),
    FlyoutItem(
      label: 'Flip horizontally',
      selected: c.adjust.hflip,
      onTap: c.toggleFlip,
    ),
    SubmenuButton(
      menuStyle: menuStyle,
      menuChildren: [
        for (final a in ['auto', '16:9', '4:3', '21:9', '1:1', '2.35:1'])
          FlyoutItem(
            label: a == 'auto' ? 'Default' : a,
            selected: c.adjust.aspect == a,
            onTap: () => c.setAspect(a),
          ),
      ],
      leadingIcon: const SizedBox(width: 20),
      child: const Text('Aspect ratio'),
    ),
    FlyoutItem(
      label: 'Reset zoom',
      onTap: () {
        c.setZoom(0);
        c.notify('Zoom 100%');
      },
    ),
    Divider(height: 10, color: ConeColors.border),
    FlyoutItem(
      label: 'Add bookmark',
      detail: '$_mod+B',
      onTap: () => c.addBookmark(),
    ),
    FlyoutItem(
      label: 'Picture-in-picture',
      detail: 'I',
      selected: _pip,
      onTap: () => _togglePip(),
    ),
  ];

  Widget _topBar() {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xCC000000), Color(0x00000000)],
        ),
      ),
      child: Row(
        children: [
          TrackedMenuAnchor(
            alignmentOffset: const Offset(0, 6),
            menuChildren: [
              FlyoutItem(
                label: 'Open & tools…',
                detail: '$_mod+T',
                icon: Icons.apps,
                onTap: () => showMediaHub(context, c, loader, _cast),
              ),
              const Divider(height: 10),
              FlyoutItem(
                label: 'Open file…',
                detail: '$_mod+O',
                icon: Icons.insert_drive_file_outlined,
                onTap: () => loader.openFiles(),
              ),
              FlyoutItem(
                label: 'Open folder…',
                detail: '$_mod+Shift+O',
                icon: Icons.folder_open_outlined,
                onTap: loader.openFolder,
              ),
              FlyoutItem(
                label: 'Open network stream…',
                detail: '$_mod+U',
                icon: Icons.language,
                onTap: () => loader.openStream(context),
              ),
              FlyoutItem(
                label: 'Play from clipboard',
                detail: '$_mod+V',
                icon: Icons.content_paste,
                onTap: () => loader.playClipboard(),
              ),
              if (_hasMedia)
                FlyoutItem(
                  label: 'Close media',
                  detail: '$_mod+W',
                  icon: Icons.close,
                  onTap: () => c.closeMedia(),
                ),
              Divider(height: 10, color: ConeColors.border),
              FlyoutItem(
                label: 'Subtitles…',
                detail: 'File · Folder · Online',
                icon: Icons.subtitles_outlined,
                onTap: () => showSubtitleLoader(context, c),
              ),
              if (_lib != null)
                FlyoutItem(
                  label: 'Library',
                  detail: '$_mod+Shift+L',
                  icon: Icons.video_library_outlined,
                  onTap: _openLibrary,
                ),
              FlyoutItem(
                label: 'Capture device…',
                icon: Icons.videocam_outlined,
                onTap: () => showCaptureDialog(context, c),
              ),
              if (_hasMedia) ...[
                FlyoutItem(
                  label: 'Convert…',
                  icon: Icons.transform,
                  onTap: () => showConvertDialog(context, c),
                ),
                FlyoutItem(
                  label: 'Cast…',
                  icon: Icons.cast,
                  onTap: () => showCastDialog(context, c, _cast),
                ),
              ],
              if (_hasMedia)
                FlyoutItem(
                  label: 'Multi-view',
                  detail: '$_mod+G',
                  icon: Icons.grid_view,
                  onTap: _openMultiView,
                ),
              FlyoutItem(
                label: 'Settings',
                detail: '$_mod+,',
                icon: Icons.settings_outlined,
                onTap: () => _openSettings(),
              ),
              FlyoutItem(
                label: 'Inspector',
                detail: '$_mod+I',
                icon: Icons.tune,
                onTap: _toggleInspector,
              ),
              FlyoutItem(
                label: 'Queue & bookmarks',
                detail: '$_mod+L',
                icon: Icons.queue_music,
                onTap: () => _toggleQueue(),
              ),
            ],
            builder: (context, ctrl, _) => ControlIcon(
              icon: Icons.menu,
              tooltip: 'Menu',
              active: ctrl.isOpen,
              onPressed: () => ctrl.isOpen ? ctrl.close() : ctrl.open(),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              _hasMedia ? c.title : '',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: ConeColors.text,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          CastPill(cast: _cast),
          const SizedBox(width: 8),
          if (_lib != null)
            ControlIcon(
              icon: Icons.video_library_outlined,
              tooltip: 'Library ($_mod+Shift+L)',
              active: _libraryOpen,
              onPressed: () => _libraryOpen
                  ? setState(() => _libraryOpen = false)
                  : _openLibrary(),
            ),
          ControlIcon(
            icon: Icons.tune,
            tooltip: 'Inspector ($_mod+I)',
            active: _inspectorOpen,
            onPressed: _toggleInspector,
          ),
        ],
      ),
    );
  }

  late final _layouts = LayoutProfiles(_s);

  void _cycleRepeat() {
    const order = ['off', 'all', 'one'];
    final next = order[(order.indexOf(Prefs.repeat.of(_s)) + 1) % order.length];
    Prefs.repeat.set(_s, next);
    c.notify(switch (next) {
      'one' => 'Repeat this file',
      'all' => 'Repeat queue',
      _ => 'Repeat off',
    });
  }

  /// Widgets for one control-bar button (see the layout customizer).
  List<Widget> _control(ControlId id) => switch (id) {
    ControlId.prev => [
      ControlIcon(
        icon: Icons.skip_previous_rounded,
        tooltip: 'Previous (P)',
        onPressed: c.previous,
      ),
    ],
    ControlId.play => [
      ControlIcon(
        icon: p.state.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
        tooltip: p.state.playing ? 'Pause (Space)' : 'Play (Space)',
        size: 30,
        onPressed: c.togglePlay,
      ),
    ],
    ControlId.next => [
      ControlIcon(
        icon: Icons.skip_next_rounded,
        tooltip: 'Next (N)',
        onPressed: c.next,
      ),
    ],
    ControlId.frameBack => [
      ControlIcon(
        icon: Icons.chevron_left,
        tooltip: 'Previous frame (,)',
        onPressed: () => c.frameStep(false),
      ),
    ],
    ControlId.frameForward => [
      ControlIcon(
        icon: Icons.chevron_right,
        tooltip: 'Next frame (.)',
        onPressed: () => c.frameStep(true),
      ),
    ],
    ControlId.time => [
      const SizedBox(width: 10),
      StreamBuilder<Duration>(
        stream: p.stream.position,
        builder: (_, _) => Text(
          '${formatDuration(p.state.position)} / ${formatDuration(p.state.duration)}',
          style: const TextStyle(
            color: ConeColors.textMuted,
            fontSize: 12,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      ),
      if (p.state.rate != 1.0) ...[
        const SizedBox(width: 10),
        Text(
          '${p.state.rate}x',
          style: TextStyle(color: ConeColors.accent, fontSize: 12),
        ),
      ],
      const SizedBox(width: 6),
    ],
    ControlId.speed => [
      TrackedMenuAnchor(
        menuChildren: [
          for (final r in [0.5, 0.75, 1.0, 1.25, 1.5, 2.0])
            FlyoutItem(
              label: '$r×',
              selected: (p.state.rate - r).abs() < 0.01,
              onTap: () => c.setRate(r),
            ),
        ],
        builder: (context, ctrl, _) => ControlIcon(
          icon: Icons.speed,
          tooltip: 'Speed',
          active: p.state.rate != 1.0,
          onPressed: () => ctrl.isOpen ? ctrl.close() : ctrl.open(),
        ),
      ),
    ],
    ControlId.bookmark => [
      ControlIcon(
        icon: Icons.bookmark_add_outlined,
        tooltip: 'Bookmark ($_mod+B)',
        onPressed: () => c.addBookmark(),
      ),
    ],
    ControlId.screenshot => [
      ControlIcon(
        icon: Icons.photo_camera_outlined,
        tooltip: 'Screenshot (S)',
        onPressed: () => c.takeScreenshot(),
      ),
    ],
    ControlId.rotate => [
      ControlIcon(
        icon: Icons.rotate_90_degrees_cw_outlined,
        tooltip: 'Rotate (R)',
        onPressed: () => c.rotate(),
      ),
    ],
    ControlId.repeat => [
      ControlIcon(
        icon: switch (Prefs.repeat.of(_s)) {
          'one' => Icons.repeat_one,
          _ => Icons.repeat,
        },
        tooltip: 'Repeat',
        active: Prefs.repeat.of(_s) != 'off',
        onPressed: _cycleRepeat,
      ),
    ],
    ControlId.fullscreen => [
      ControlIcon(
        icon: _fullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
        tooltip: 'Fullscreen (F)',
        onPressed: _toggleFullscreen,
      ),
    ],
    ControlId.pip => [
      ControlIcon(
        icon: Icons.picture_in_picture_alt_outlined,
        tooltip: 'Picture-in-picture (I)',
        active: _pip,
        onPressed: _togglePip,
      ),
    ],
    ControlId.queue => [
      ControlIcon(
        icon: Icons.queue_music,
        tooltip: 'Queue ($_mod+L)',
        active: _queueOpen,
        onPressed: () => _toggleQueue(),
      ),
    ],
    ControlId.subtitles => [
      FlyoutButton(
        icon: Icons.subtitles_outlined,
        tooltip: 'Subtitles',
        active:
            p.state.track.subtitle.id != 'no' &&
            p.state.track.subtitle.id != 'auto',
        builder: () => subtitleFlyout(
          playingId: c.playingSubId,
          player: p,
          onLoadFile: loader.openSubtitle,
          onFind: () => showSubtitleLoader(context, c),
        ),
      ),
    ],
    ControlId.audio => [
      FlyoutButton(
        icon: Icons.graphic_eq,
        tooltip: 'Audio tracks & output',
        builder: () => audioFlyout(player: p, playingId: c.playingAudioId),
      ),
    ],
    ControlId.inspector => [
      ControlIcon(
        icon: Icons.tune,
        tooltip: 'Inspector ($_mod+I)',
        active: _inspectorOpen,
        onPressed: _toggleInspector,
      ),
    ],
    ControlId.library => [
      if (_lib != null)
        ControlIcon(
          icon: Icons.video_library_outlined,
          tooltip: 'Library ($_mod+Shift+L)',
          onPressed: _openLibrary,
        ),
    ],
    ControlId.cast => [
      ControlIcon(
        icon: _cast.active ? Icons.cast_connected : Icons.cast,
        tooltip: 'Cast to TV',
        active: _cast.active,
        onPressed: () => showCastDialog(context, c, _cast),
      ),
    ],
    ControlId.volume => [
      const SizedBox(width: 4),
      VolumeSlider(
        volume: p.state.volume,
        onChanged: (v) => c.setVolume(v),
        onToggleMute: () => c.toggleMute(),
      ),
    ],
  };

  Widget _bottomBar(double width) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 28, 12, 6),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Color(0xE6000000), Color(0x00000000)],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              for (final id in _layouts.active.left) ..._control(id),
              const Spacer(),
              for (final id in _layouts.active.right) ..._control(id),
              const SizedBox(width: 4),
            ],
          ),
          // Music shows a large waveform scrubber in its own layout.
          if (!c.isAudioOnly && c.showSubtitleTimeline) ...[
            const SizedBox(height: 6),
            if (c.cues == null)
              SubtitleTimelineHint(onLoad: loader.openSubtitle)
            else
              StreamBuilder<Duration>(
                stream: p.stream.position,
                builder: (_, _) => SubtitleTimeline(
                  cues: c.cues!,
                  position: p.state.position,
                  duration: p.state.duration,
                  delay: c.subDelay,
                  waveform: c.waveform,
                  onDelay: c.setSubDelay,
                  onSeek: p.seek,
                ),
              ),
          ],
          if (!c.isAudioOnly) ...[
            const SizedBox(height: 2),
            StreamBuilder<Duration>(
              stream: p.stream.position,
              builder: (_, _) => SeekBar(
                position: p.state.position,
                duration: p.state.duration,
                buffer: p.state.buffer,
                bookmarks: c.bookmarks,
                onSeek: p.seek,
                onFrameStep: (fwd) => c.frameStep(fwd, 'Scroll'),
                waveform: c.showWaveform ? c.waveform : null,
                preview: _previewAt,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _emptyState() => Container(
    color: ConeColors.canvas,
    alignment: Alignment.center,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const BlobLogo(size: 96, animated: true),
        const SizedBox(height: 14),
        const Text(
          'Drop media here',
          style: TextStyle(
            fontSize: 20,
            color: ConeColors.text,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Video, audio, playlists or subtitles',
          style: TextStyle(color: ConeColors.textMuted),
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            FilledButton.icon(
              onPressed: () => loader.openFiles(),
              icon: const Icon(Icons.insert_drive_file_outlined, size: 18),
              label: const Text('Open file'),
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(ConeRadius.md),
                ),
              ),
            ),
            const SizedBox(width: 10),
            OutlinedButton.icon(
              onPressed: () => loader.openStream(context),
              icon: const Icon(Icons.language, size: 18),
              label: const Text('Network stream'),
              style: OutlinedButton.styleFrom(
                foregroundColor: ConeColors.text,
                side: BorderSide(color: ConeColors.border),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(ConeRadius.md),
                ),
              ),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _dropHint() => IgnorePointer(
    child: Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ConeColors.accent.withValues(alpha: 0.08),
        border: Border.all(color: ConeColors.accent, width: 2),
        borderRadius: BorderRadius.circular(ConeRadius.lg),
      ),
      alignment: Alignment.center,
      child: Text(
        _hasMedia ? 'Drop to add to queue' : 'Drop to play',
        style: TextStyle(
          color: ConeColors.accent,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
  );
}
