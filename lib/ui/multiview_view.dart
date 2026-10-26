import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../player/multiview.dart';
import '../player/player_controller.dart';
import '../theme.dart';
import 'flyouts.dart';
import 'inspector/widgets.dart';
import 'seek_bar.dart';

Widget _video(VideoController v) => Video(
  controller: v,
  controls: NoVideoControls,
  fill: Colors.black,
  subtitleViewConfiguration: const SubtitleViewConfiguration(visible: false),
);

/// Picks a feed to add: files, a URL, or another item from the queue.
Future<void> addFeedFlow(
  BuildContext context,
  PlayerController c,
  MultiView mv,
) async {
  final queue = c.queueUris.where((u) => u != c.currentUri).toList();
  final choice = await showDialog<String>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: const Text('Add a feed'),
      children: [
        SimpleDialogOption(
          onPressed: () => Navigator.pop(ctx, 'file'),
          child: const Row(
            children: [
              Icon(Icons.insert_drive_file_outlined, size: 18),
              SizedBox(width: 10),
              Text('Video file…'),
            ],
          ),
        ),
        SimpleDialogOption(
          onPressed: () => Navigator.pop(ctx, 'url'),
          child: const Row(
            children: [
              Icon(Icons.language, size: 18),
              SizedBox(width: 10),
              Text('Stream URL…'),
            ],
          ),
        ),
        for (final q in queue)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, q),
            child: Row(
              children: [
                const Icon(Icons.queue_music, size: 18),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    q.split(RegExp(r'[/\\]')).last,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );
  if (choice == null) return;
  if (choice == 'file') {
    final r = await FilePicker.platform.pickFiles(allowMultiple: true);
    for (final p in r?.paths.whereType<String>() ?? const <String>[]) {
      await mv.addFeed(p);
    }
  } else if (choice == 'url') {
    if (!context.mounted) return;
    final ctrl = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Stream URL'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (url != null && url.trim().isNotEmpty) await mv.addFeed(url.trim());
  } else {
    await mv.addFeed(choice);
  }
}

/// Header strip on each tile: name, offset, audio focus, remove.
class _TileBar extends StatelessWidget {
  final String name;
  final bool audible;
  final VoidCallback onListen;
  final Feed? feed;
  final MultiView mv;
  const _TileBar({
    required this.name,
    required this.audible,
    required this.onListen,
    required this.mv,
    this.feed,
  });

  @override
  Widget build(BuildContext context) {
    final f = feed;
    return Container(
      color: const Color(0xB3000000),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: ConeColors.text),
            ),
          ),
          if (f != null) ...[
            Tooltip(
              message: 'Time offset from the main video',
              child: DelayStepper(
                value: signed(f.offset, digits: 2, unit: ' s'),
                onMinus: () => mv.setOffset(f, f.offset - 0.1),
                onPlus: () => mv.setOffset(f, f.offset + 0.1),
              ),
            ),
            const SizedBox(width: 4),
          ],
          IconButton(
            tooltip: audible ? 'Audible' : 'Listen to this',
            iconSize: 16,
            visualDensity: VisualDensity.compact,
            color: audible ? ConeColors.accent : ConeColors.textMuted,
            onPressed: onListen,
            icon: Icon(audible ? Icons.volume_up : Icons.volume_off),
          ),
          if (f != null)
            IconButton(
              tooltip: 'Remove feed',
              iconSize: 16,
              visualDensity: VisualDensity.compact,
              color: ConeColors.textMuted,
              onPressed: () => mv.removeFeed(f),
              icon: const Icon(Icons.close),
            ),
        ],
      ),
    );
  }
}

/// Full-window grid: the main video plus every feed, with shared controls.
class MultiViewGrid extends StatelessWidget {
  final PlayerController c;
  final MultiView mv;
  const MultiViewGrid({super.key, required this.c, required this.mv});

  @override
  Widget build(BuildContext context) {
    final p = c.player;
    return Material(
      color: ConeColors.canvas,
      child: ListenableBuilder(
        listenable: mv,
        builder: (context, _) {
          final tiles = <Widget>[
            _tile(
              _video(c.video),
              _TileBar(
                name: 'Main · ${c.title}',
                audible: mv.audioFocus == -1,
                onListen: () => mv.setAudioFocus(-1),
                mv: mv,
              ),
              highlight: mv.audioFocus == -1,
            ),
            for (var i = 0; i < mv.feeds.length; i++)
              _tile(
                _video(mv.feeds[i].video),
                _TileBar(
                  name: mv.feeds[i].name,
                  audible: mv.audioFocus == i,
                  onListen: () => mv.setAudioFocus(i),
                  feed: mv.feeds[i],
                  mv: mv,
                ),
                highlight: mv.audioFocus == i,
              ),
          ];
          final cols = tiles.length <= 1 ? 1 : 2;
          return Column(
            children: [
              _toolbar(context),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, box) {
                    final rows = (tiles.length / cols).ceil();
                    return GridView.count(
                      padding: const EdgeInsets.all(10),
                      crossAxisCount: cols,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      physics: const NeverScrollableScrollPhysics(),
                      childAspectRatio:
                          ((box.maxWidth - 20 - (cols - 1) * 8) / cols) /
                          ((box.maxHeight - 20 - (rows - 1) * 8) / rows),
                      children: tiles,
                    );
                  },
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(10, 0, 14, 10),
                child: Row(
                  children: [
                    StreamBuilder(
                      stream: p.stream.playing,
                      builder: (_, _) => ControlIcon(
                        icon: p.state.playing
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        tooltip: 'Play / pause all (Space)',
                        size: 28,
                        onPressed: c.togglePlay,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: StreamBuilder<Duration>(
                        stream: p.stream.position,
                        builder: (_, _) => SeekBar(
                          position: p.state.position,
                          duration: p.state.duration,
                          buffer: p.state.buffer,
                          bookmarks: c.bookmarks,
                          onSeek: p.seek,
                          onFrameStep: (fwd) => c.frameStep(fwd),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    StreamBuilder<Duration>(
                      stream: p.stream.position,
                      builder: (_, _) => Text(
                        '${formatDuration(p.state.position)} / '
                        '${formatDuration(p.state.duration)}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: ConeColors.textMuted,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _toolbar(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 10, 10, 4),
    child: Row(
      children: [
        const TwoToneIcon(Icons.grid_view, Icons.grid_view_outlined),
        const SizedBox(width: 10),
        const Text(
          'Multi-view',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        const InfoTip(
          'Watch several videos at once, kept in sync with the main one. '
          'Use the offset on a feed to line up different camera angles, and '
          'the speaker to choose which one you hear.',
        ),
        const SizedBox(width: 20),
        const Text('Sync', style: TextStyle(color: ConeColors.textMuted)),
        ConeSwitch(value: mv.sync, onChanged: mv.setSync),
        const Spacer(),
        if (mv.feeds.length < MultiView.maxFeeds)
          TextButton.icon(
            onPressed: () => addFeedFlow(context, c, mv),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add feed'),
          ),
        TextButton.icon(
          onPressed: () => mv.setMode(MultiMode.floating),
          icon: const Icon(Icons.picture_in_picture_alt_outlined, size: 18),
          label: const Text('Float over player'),
        ),
        IconButton(
          tooltip: 'Close multi-view',
          onPressed: mv.closeAll,
          icon: const Icon(Icons.close),
        ),
      ],
    ),
  );

  Widget _tile(Widget video, Widget bar, {required bool highlight}) =>
      Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(ConeRadius.md),
          border: Border.all(
            color: highlight ? ConeColors.accent : ConeColors.border,
            width: highlight ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Positioned.fill(child: video),
            Positioned(left: 0, right: 0, top: 0, child: bar),
          ],
        ),
      );
}

/// Feeds as draggable, resizable mini-windows over the main player.
class MultiViewFloating extends StatelessWidget {
  final MultiView mv;
  final VoidCallback onGrid;
  const MultiViewFloating({super.key, required this.mv, required this.onGrid});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: mv,
    builder: (context, _) => Stack(
      children: [for (var i = 0; i < mv.feeds.length; i++) _window(context, i)],
    ),
  );

  Widget _window(BuildContext context, int i) {
    final f = mv.feeds[i];
    return Positioned(
      left: f.floatPos.dx,
      top: f.floatPos.dy,
      width: f.floatSize.width,
      height: f.floatSize.height + 30,
      child: Material(
        elevation: 10,
        color: Colors.black,
        borderRadius: BorderRadius.circular(ConeRadius.md),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            GestureDetector(
              onPanUpdate: (d) => mv.moveFeed(f, d.delta),
              child: MouseRegion(
                cursor: SystemMouseCursors.move,
                child: SizedBox(
                  height: 30,
                  child: _TileBar(
                    name: f.name,
                    audible: mv.audioFocus == i,
                    onListen: () =>
                        mv.setAudioFocus(mv.audioFocus == i ? -1 : i),
                    feed: f,
                    mv: mv,
                  ),
                ),
              ),
            ),
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: GestureDetector(
                      onDoubleTap: onGrid,
                      child: _video(f.video),
                    ),
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: GestureDetector(
                      onPanUpdate: (d) => mv.resizeFeed(f, d.delta),
                      child: MouseRegion(
                        cursor: SystemMouseCursors.resizeDownRight,
                        child: Container(
                          width: 18,
                          height: 18,
                          color: const Color(0x66000000),
                          child: const Icon(
                            Icons.open_in_full,
                            size: 12,
                            color: ConeColors.textMuted,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
