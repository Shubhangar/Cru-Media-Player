import 'dart:io';

import 'package:flutter/material.dart';

import '../../library/library_store.dart';
import '../../theme.dart';

/// Callbacks the library UI uses to act on the player.
class LibraryActions {
  final void Function(List<String> uris, {int start}) play;
  final void Function(List<String> uris) enqueue;
  final void Function(List<String> uris) playNext;
  const LibraryActions({
    required this.play,
    required this.enqueue,
    required this.playNext,
  });
}

String timeLeft(HistoryEntry h) {
  final left = Duration(milliseconds: h.durationMs - h.positionMs);
  if (left.inHours > 0) {
    return '${left.inHours} h ${left.inMinutes % 60} min left';
  }
  if (left.inMinutes > 0) return '${left.inMinutes} min left';
  return '${left.inSeconds} s left';
}

/// Thumbnail from history, or a tinted icon placeholder.
class MediaThumb extends StatelessWidget {
  final String? thumb;
  final bool audio;
  final double progress; // 0..1, 0 hides the strip
  final bool watched;
  const MediaThumb({
    super.key,
    this.thumb,
    this.audio = false,
    this.progress = 0,
    this.watched = false,
  });

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2A2A2A), Color(0xFF1A1A1A)],
        ),
      ),
      alignment: Alignment.center,
      child: Icon(
        audio ? Icons.music_note : Icons.movie_outlined,
        size: 30,
        color: ConeColors.textMuted,
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(ConeRadius.md),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (thumb != null)
            Image.file(
              File(thumb!),
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => placeholder,
            )
          else
            placeholder,
          if (watched)
            Positioned(
              top: 6,
              right: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xCC000000),
                  borderRadius: BorderRadius.circular(ConeRadius.sm),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check, size: 12, color: ConeColors.accent),
                    SizedBox(width: 3),
                    Text(
                      'Watched',
                      style: TextStyle(fontSize: 10, color: ConeColors.text),
                    ),
                  ],
                ),
              ),
            ),
          if (progress > 0 && !watched)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 3,
                backgroundColor: const Color(0x66000000),
                color: ConeColors.accent,
              ),
            ),
        ],
      ),
    );
  }
}

/// 16:9 card with title and caption, used in grids and shelves.
class MediaCard extends StatefulWidget {
  final String title;
  final String? caption;
  final Widget thumb;
  final VoidCallback onTap;
  final VoidCallback? onRemove;
  final List<PopupMenuEntry<VoidCallback>> menu;
  const MediaCard({
    super.key,
    required this.title,
    required this.thumb,
    required this.onTap,
    this.caption,
    this.onRemove,
    this.menu = const [],
  });

  @override
  State<MediaCard> createState() => _MediaCardState();
}

class _MediaCardState extends State<MediaCard> {
  bool _hover = false;

  Future<void> _showMenu(Offset pos) async {
    if (widget.menu.isEmpty) return;
    final f = await showMenu<VoidCallback>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx, pos.dy),
      items: widget.menu,
    );
    f?.call();
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    onEnter: (_) => setState(() => _hover = true),
    onExit: (_) => setState(() => _hover = false),
    child: GestureDetector(
      onTap: widget.onTap,
      onSecondaryTapDown: (d) => _showMenu(d.globalPosition),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(ConeRadius.md + 1),
                border: Border.all(
                  color: _hover ? ConeColors.accent : ConeColors.border,
                ),
              ),
              padding: const EdgeInsets.all(1),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  widget.thumb,
                  if (_hover)
                    Center(
                      child: CircleAvatar(
                        radius: 20,
                        backgroundColor: Color(0xCC000000),
                        child: Icon(
                          Icons.play_arrow_rounded,
                          color: ConeColors.accent,
                          size: 28,
                        ),
                      ),
                    ),
                  if (_hover && widget.onRemove != null)
                    Positioned(
                      top: 4,
                      left: 4,
                      child: IconButton(
                        tooltip: 'Remove',
                        iconSize: 14,
                        visualDensity: VisualDensity.compact,
                        style: IconButton.styleFrom(
                          backgroundColor: const Color(0xCC000000),
                        ),
                        color: ConeColors.text,
                        onPressed: widget.onRemove,
                        icon: const Icon(Icons.close),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            widget.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, color: ConeColors.text),
          ),
          if (widget.caption != null)
            Text(
              widget.caption!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: ConeColors.textMuted),
            ),
        ],
      ),
    ),
  );
}

PopupMenuItem<VoidCallback> menuItem(
  String label,
  IconData icon,
  VoidCallback f,
) => PopupMenuItem(
  value: f,
  height: 36,
  child: Row(
    children: [
      Icon(icon, size: 16, color: ConeColors.textMuted),
      const SizedBox(width: 10),
      Text(label, style: const TextStyle(fontSize: 13)),
    ],
  ),
);

class ShelfHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;
  const ShelfHeader(this.title, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(0, 22, 0, 10),
    child: Row(
      children: [
        Container(width: 3, height: 16, color: ConeColors.accent),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: ConeColors.text,
          ),
        ),
        const Spacer(),
        ?trailing,
      ],
    ),
  );
}
