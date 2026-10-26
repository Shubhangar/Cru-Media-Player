import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:window_manager/window_manager.dart';

import '../library/library_store.dart';
import '../player/media_loader.dart';
import '../player/player_controller.dart';
import '../theme.dart';
import 'cone_volume.dart';
import 'flyouts.dart';
import 'osd.dart';
import 'home/home_view.dart';
import 'inspector/inspector_panel.dart';
import 'library/library_screen.dart';
import 'library/media_widgets.dart';
import 'music_view.dart';
import 'queue_panel.dart';
import 'resume_banner.dart';
import 'seek_bar.dart';

final bool _isMac = Platform.isMacOS;
final String _mod = _isMac ? '⌘' : 'Ctrl';

class PlayerScreen extends StatefulWidget {
  final List<String> initialFiles;
  final PlayerController? controller;
  final LibraryStore? library;
  const PlayerScreen({
    super.key,
    this.initialFiles = const [],
    this.controller,
    this.library,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late final c = widget.controller ?? PlayerController(library: widget.library);
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
  static const _topZone = 90.0, _bottomZone = 150.0;
  bool _nearTop = false, _nearBottom = false, _pointerIdle = false;
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
  bool _dragging = false;
  bool _subsLifted = false;

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
    c.init().then((_) {
      if (widget.initialFiles.isNotEmpty) c.openAll(widget.initialFiles);
    });
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _idleTimer?.cancel();
    c.dispose();
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

  void _onHover(PointerHoverEvent e, double height) {
    final y = e.localPosition.dy;
    final top = y < _topZone, bottom = y > height - _bottomZone;
    if (top != _nearTop || bottom != _nearBottom || _pointerIdle) {
      setState(() {
        _nearTop = top;
        _nearBottom = bottom;
        _pointerIdle = false;
      });
    }
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
    if (_libraryOpen && k == LogicalKeyboardKey.escape) {
      setState(() => _libraryOpen = false);
      return KeyEventResult.handled;
    }
    if (_libraryOpen) return KeyEventResult.ignored;

    if (k == LogicalKeyboardKey.space || k == LogicalKeyboardKey.keyK) {
      c.togglePlay(k == LogicalKeyboardKey.space ? 'Space' : 'K');
    } else if (k == LogicalKeyboardKey.arrowRight) {
      c.seekBy(Duration(seconds: shift ? 60 : 5), combo('→'));
    } else if (k == LogicalKeyboardKey.arrowLeft) {
      c.seekBy(Duration(seconds: shift ? -60 : -5), combo('←'));
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
    // Keep subtitles clear of the bottom bar while it is shown.
    final lift = _showBottom && _hasMedia;
    if (lift != _subsLifted) {
      _subsLifted = lift;
      c.liftSubtitles(lift);
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
                    Positioned(
                      top: 70,
                      left: 0,
                      right: 0,
                      child: Center(child: Osd(messages: c.osd)),
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
          if (e is PointerScrollEvent) {
            c.setVolume(p.state.volume - e.scrollDelta.dy.sign * 5, 'Scroll');
          }
        },
        // Trackpad: two-finger vertical swipe & pinch.
        onPointerPanZoomUpdate: (e) {
          if ((e.scale - 1).abs() > 0.02) {
            c.setZoom(c.adjust.zoom + (e.scale - 1) * 0.05);
          } else if (e.panDelta.dy.abs() > e.panDelta.dx.abs()) {
            _sideAdjust(e.localPosition.dx, box.maxWidth, e.panDelta.dy);
          }
        },
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
              ? MusicView(c: c)
              : Transform.scale(
                  scaleX: c.adjust.hflip ? -1 : 1,
                  scaleY: c.adjust.vflip ? -1 : 1,
                  child: Video(
                    controller: c.video,
                    controls: NoVideoControls,
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
    const Divider(height: 10, color: ConeColors.border),
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
    const Divider(height: 10, color: ConeColors.border),
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
              const Divider(height: 10, color: ConeColors.border),
              FlyoutItem(
                label: 'Load subtitle…',
                icon: Icons.subtitles_outlined,
                onTap: loader.openSubtitle,
              ),
              if (_lib != null)
                FlyoutItem(
                  label: 'Library',
                  detail: '$_mod+Shift+L',
                  icon: Icons.video_library_outlined,
                  onTap: _openLibrary,
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
              ControlIcon(
                icon: Icons.skip_previous_rounded,
                tooltip: 'Previous (P)',
                onPressed: c.previous,
              ),
              ControlIcon(
                icon: p.state.playing
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
                tooltip: p.state.playing ? 'Pause (Space)' : 'Play (Space)',
                size: 30,
                onPressed: c.togglePlay,
              ),
              ControlIcon(
                icon: Icons.skip_next_rounded,
                tooltip: 'Next (N)',
                onPressed: c.next,
              ),
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
                  style: const TextStyle(
                    color: ConeColors.accent,
                    fontSize: 12,
                  ),
                ),
              ],
              const Spacer(),
              ControlIcon(
                icon: _fullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                tooltip: 'Fullscreen (F)',
                onPressed: _toggleFullscreen,
              ),
              ControlIcon(
                icon: Icons.picture_in_picture_alt_outlined,
                tooltip: 'Picture-in-picture (I)',
                active: _pip,
                onPressed: _togglePip,
              ),
              ControlIcon(
                icon: Icons.queue_music,
                tooltip: 'Queue ($_mod+L)',
                active: _queueOpen,
                onPressed: () => _toggleQueue(),
              ),
              FlyoutButton(
                icon: Icons.subtitles_outlined,
                tooltip: 'Subtitles',
                active:
                    p.state.track.subtitle.id != 'no' &&
                    p.state.track.subtitle.id != 'auto',
                builder: () =>
                    subtitleFlyout(player: p, onLoadFile: loader.openSubtitle),
              ),
              FlyoutButton(
                icon: Icons.graphic_eq,
                tooltip: 'Audio tracks & output',
                builder: () => audioFlyout(player: p),
              ),
              const SizedBox(width: 6),
              ConeVolume(
                volume: p.state.volume,
                onChanged: (v) => c.setVolume(v),
                onToggleMute: () => c.toggleMute(),
              ),
              const SizedBox(width: 4),
            ],
          ),
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
            ),
          ),
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
        const Icon(
          Icons.change_history_rounded,
          size: 72,
          color: ConeColors.accent,
        ),
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
                side: const BorderSide(color: ConeColors.border),
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
        style: const TextStyle(
          color: ConeColors.accent,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
  );
}
