import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../library/cover_art.dart';
import '../library/library_store.dart' show displayName;
import '../player/player_controller.dart';
import '../theme.dart';

/// Audio layout: large cover art, a blurred backdrop and track details.
/// Art is read from the file (or its folder) by [findCoverArt] since the
/// bundled ffmpeg cannot decode embedded PNG covers.
class MusicView extends StatelessWidget {
  final PlayerController c;
  final Widget? waveform;
  const MusicView({super.key, required this.c, this.waveform});

  @override
  Widget build(BuildContext context) {
    final uri = c.currentUri;
    return FutureBuilder<Uint8List?>(
      key: ValueKey(uri),
      future: uri == null || uri.contains('://')
          ? Future.value(null)
          : findCoverArt(uri),
      builder: (context, snap) => _layout(snap.data),
    );
  }

  Widget _layout(Uint8List? art) {
    final hasCover = art != null;
    Widget cover({BoxFit fit = BoxFit.cover}) => hasCover
        ? Image.memory(art, fit: fit, gaplessPlayback: true)
        : Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF3A2414), Color(0xFF1E1E1E)],
              ),
            ),
            child: Icon(Icons.music_note, size: 120, color: ConeColors.accent),
          );

    return Stack(
      fit: StackFit.expand,
      children: [
        Container(color: ConeColors.canvas),
        if (hasCover)
          Opacity(
            opacity: 0.35,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
              child: cover(fit: BoxFit.cover),
            ),
          ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x00121212), Color(0xEE121212)],
            ),
          ),
        ),
        LayoutBuilder(
          builder: (context, box) {
            final side = (box.maxHeight * 0.5).clamp(160.0, 380.0);
            return Padding(
              padding: EdgeInsets.fromLTRB(
                box.maxWidth * 0.08,
                72,
                box.maxWidth * 0.08,
                150,
              ),
              child: Column(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Container(
                          width: side,
                          height: side,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(ConeRadius.lg),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x99000000),
                                blurRadius: 40,
                                offset: Offset(0, 16),
                              ),
                            ],
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: cover(),
                        ),
                        const SizedBox(width: 40),
                        Expanded(child: _TrackInfo(c: c)),
                      ],
                    ),
                  ),
                  ?waveform,
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

class _TrackInfo extends StatelessWidget {
  final PlayerController c;
  const _TrackInfo({required this.c});

  @override
  Widget build(BuildContext context) {
    final pl = c.player.state.playlist;
    final fallback = c.currentUri == null ? '' : displayName(c.currentUri!);
    return FutureBuilder(
      // Re-read when the track changes and once it has finished loading
      // (tags are empty until the duration is known).
      key: ValueKey('${c.currentUri}|${c.player.state.duration}'),
      future: c.trackTags(),
      builder: (context, snap) {
        final t = snap.data ?? const {};
        final title = t['Title'] ?? fallback;
        final artist = t['Artist'] ?? t['Album artist'];
        final album = t['Album'];
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'NOW PLAYING',
              style: TextStyle(
                fontSize: 11,
                letterSpacing: 1.6,
                color: ConeColors.accent,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 34,
                height: 1.15,
                fontWeight: FontWeight.w700,
                color: ConeColors.text,
              ),
            ),
            if (artist != null) ...[
              const SizedBox(height: 8),
              Text(
                artist,
                style: const TextStyle(fontSize: 18, color: ConeColors.text),
              ),
            ],
            if (album != null) ...[
              const SizedBox(height: 4),
              Text(
                album,
                style: const TextStyle(
                  fontSize: 14,
                  color: ConeColors.textMuted,
                ),
              ),
            ],
            if (pl.medias.length > 1) ...[
              const SizedBox(height: 16),
              Text(
                'Track ${pl.index + 1} of ${pl.medias.length}',
                style: const TextStyle(
                  fontSize: 12,
                  color: ConeColors.textMuted,
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}
