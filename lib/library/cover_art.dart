import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

/// Finds album art for an audio file without relying on mpv's decoders:
/// embedded art (M4A `covr`, MP3 ID3v2 `APIC`, FLAC `PICTURE`) first, then
/// a `cover`/`folder`/`front` image next to the file.
Future<Uint8List?> findCoverArt(String path) => Isolate.run(() {
  try {
    final f = File(path);
    if (!f.existsSync()) return null;
    return embeddedArt(f) ?? _folderArt(f);
  } catch (_) {
    return null;
  }
});

Uint8List? embeddedArt(File f) {
  final raf = f.openSync();
  try {
    final head = raf.readSync(12);
    if (head.length < 12) return null;
    if (_ascii(head, 0, 3) == 'ID3') return _id3(raf);
    if (_ascii(head, 0, 4) == 'fLaC') return _flac(raf);
    if (_ascii(head, 4, 4) == 'ftyp') return _mp4(raf);
    return null;
  } finally {
    raf.closeSync();
  }
}

String _ascii(List<int> b, int off, int len) =>
    String.fromCharCodes(b.sublist(off, off + len));

int _u32(List<int> b, int o) =>
    (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];

// ---- MP4 / M4A: moov > udta > meta > ilst > covr > data -------------------

Uint8List? _mp4(RandomAccessFile raf) {
  Uint8List? find(int start, int end, List<String> path) {
    var off = start;
    while (off + 8 <= end) {
      raf.setPositionSync(off);
      final h = raf.readSync(16);
      if (h.length < 8) return null;
      var size = _u32(h, 0);
      final type = _ascii(h, 4, 4);
      var hdr = 8;
      if (size == 1 && h.length >= 16) {
        size = (_u32(h, 8) << 32) | _u32(h, 12);
        hdr = 16;
      } else if (size == 0) {
        size = end - off;
      }
      if (size < hdr) return null;
      if (type == path.first) {
        if (path.length == 1) {
          // 'data' atom: 4 bytes type indicator + 4 bytes locale.
          raf.setPositionSync(off + hdr + 8);
          return raf.readSync(size - hdr - 8);
        }
        // 'meta' is a full box: 4 bytes of version/flags first.
        final skip = type == 'meta' ? 4 : 0;
        final r = find(off + hdr + skip, off + size, path.sublist(1));
        if (r != null) return r;
      }
      off += size;
    }
    return null;
  }

  final len = raf.lengthSync();
  return find(0, len, ['moov', 'udta', 'meta', 'ilst', 'covr', 'data']) ??
      find(0, len, ['moov', 'meta', 'ilst', 'covr', 'data']);
}

// ---- MP3: ID3v2 APIC / PIC -------------------------------------------------

int _syncsafe(List<int> b, int o) =>
    (b[o] << 21) | (b[o + 1] << 14) | (b[o + 2] << 7) | b[o + 3];

Uint8List? _id3(RandomAccessFile raf) {
  raf.setPositionSync(0);
  final h = raf.readSync(10);
  final major = h[3];
  final size = _syncsafe(h, 6);
  final tag = raf.readSync(size);
  var off = 0;
  if (h[5] & 0x40 != 0 && major >= 3) {
    // Extended header.
    off += major == 4 ? _syncsafe(tag, 0) : _u32(tag, 0) + 4;
  }
  final idLen = major == 2 ? 3 : 4, hdrLen = major == 2 ? 6 : 10;
  while (off + hdrLen <= tag.length) {
    final id = _ascii(tag, off, idLen);
    if (id.codeUnits.every((c) => c == 0)) break;
    final fsize = major == 2
        ? (tag[off + 3] << 16) | (tag[off + 4] << 8) | tag[off + 5]
        : (major == 4 ? _syncsafe(tag, off + 4) : _u32(tag, off + 4));
    final body = off + hdrLen;
    if (fsize <= 0 || body + fsize > tag.length) break;
    if (id == 'APIC' || id == 'PIC') {
      final enc = tag[body];
      var p = body + 1;
      if (id == 'PIC') {
        p += 3; // image format, e.g. "JPG"
      } else {
        while (p < body + fsize && tag[p] != 0) {
          p++; // mime type
        }
        p++;
      }
      p++; // picture type
      // Description: null-terminated (two nulls for UTF-16).
      final wide = enc == 1 || enc == 2;
      while (p < body + fsize) {
        if (wide) {
          if (tag[p] == 0 && tag[p + 1] == 0) {
            p += 2;
            break;
          }
          p += 2;
        } else {
          if (tag[p] == 0) {
            p++;
            break;
          }
          p++;
        }
      }
      return Uint8List.sublistView(tag, p, body + fsize);
    }
    off = body + fsize;
  }
  return null;
}

// ---- FLAC: METADATA_BLOCK_PICTURE -----------------------------------------

Uint8List? _flac(RandomAccessFile raf) {
  var off = 4;
  while (true) {
    raf.setPositionSync(off);
    final h = raf.readSync(4);
    if (h.length < 4) return null;
    final last = h[0] & 0x80 != 0, type = h[0] & 0x7f;
    final len = (h[1] << 16) | (h[2] << 8) | h[3];
    if (type == 6) {
      final b = raf.readSync(len);
      var p = 4; // picture type
      p += 4 + _u32(b, p); // mime
      p += 4 + _u32(b, p); // description
      p += 16; // width, height, depth, colours
      final dataLen = _u32(b, p);
      return Uint8List.sublistView(b, p + 4, p + 4 + dataLen);
    }
    if (last) return null;
    off += 4 + len;
  }
}

// ---- Folder images -----------------------------------------------------------

Uint8List? _folderArt(File f) {
  const names = ['cover', 'folder', 'front', 'album', 'albumart'];
  for (final e in f.parent.listSync()) {
    if (e is! File) continue;
    final n = e.uri.pathSegments.last.toLowerCase();
    final dot = n.lastIndexOf('.');
    if (dot < 0) continue;
    final ext = n.substring(dot + 1), base = n.substring(0, dot);
    if ({'jpg', 'jpeg', 'png', 'webp'}.contains(ext) && names.contains(base)) {
      return e.readAsBytesSync();
    }
  }
  return null;
}
