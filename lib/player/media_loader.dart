import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';
import 'player_controller.dart';

const mediaExtensions = {
  'mp4',
  'mkv',
  'webm',
  'mov',
  'avi',
  'wmv',
  'flv',
  'm4v',
  'mpg',
  'mpeg',
  'ts',
  'm2ts',
  '3gp',
  'ogv',
  'mp3',
  'flac',
  'wav',
  'm4a',
  'aac',
  'ogg',
  'opus',
  'wma',
  'alac',
  'aiff',
  'm3u',
  'm3u8',
  'pls',
};

const subtitleExtensions = ['srt', 'ass', 'ssa', 'vtt', 'sub', 'idx', 'sup'];

bool isMediaPath(String p) =>
    mediaExtensions.contains(p.split('.').last.toLowerCase());

/// Loading actions behind the main dropdown and keyboard shortcuts.
class MediaLoader {
  final PlayerController c;
  MediaLoader(this.c);

  Future<void> openFiles({bool append = false}) async {
    final r = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: mediaExtensions.toList(),
    );
    final paths = r?.paths.whereType<String>().toList() ?? [];
    await c.openAll(paths, append: append);
  }

  Future<void> openFolder() async {
    final dir = await FilePicker.platform.getDirectoryPath();
    if (dir == null) return;
    final files =
        Directory(dir)
            .listSync(recursive: true, followLinks: false)
            .whereType<File>()
            .map((f) => f.path)
            .where(isMediaPath)
            .toList()
          ..sort();
    if (files.isEmpty) {
      c.notify('No media found in folder');
      return;
    }
    await c.openAll(files);
  }

  Future<void> openSubtitle() async {
    final r = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: subtitleExtensions,
    );
    final p = r?.files.single.path;
    if (p != null) await c.loadSubtitle(p);
  }

  Future<void> playClipboard([String? key]) async {
    final text = (await Clipboard.getData('text/plain'))?.text?.trim();
    if (text == null || text.isEmpty) {
      c.notify('Clipboard is empty', key);
      return;
    }
    final lines = text
        .split(RegExp(r'\s*\n\s*'))
        .where((l) => l.contains('://') || File(l).existsSync())
        .toList();
    if (lines.isEmpty) {
      c.notify('No link or file path in clipboard', key);
      return;
    }
    await c.openAll(lines);
    c.notify('Playing from clipboard', key);
  }

  Future<void> openStream(BuildContext context) async {
    final ctrl = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Open network stream'),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: ctrl,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'https://…/video.mp4  or  …/playlist.m3u',
                ),
                onSubmitted: (v) => Navigator.pop(ctx, v),
              ),
              const SizedBox(height: 10),
              const Text(
                'Direct video links, HLS/DASH streams and M3U/IPTV playlists are supported.',
                style: TextStyle(fontSize: 12, color: ConeColors.textMuted),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Cancel',
              style: TextStyle(color: ConeColors.textMuted),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: const Text('Play'),
          ),
        ],
      ),
    );
    if (url != null && url.trim().isNotEmpty) await c.openAll([url.trim()]);
  }
}
