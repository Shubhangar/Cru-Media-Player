import 'dart:io';

import 'package:flutter/services.dart';

import '../settings/prefs.dart';
import 'settings_store.dart';

class BuiltInShader {
  final String id, name, description;
  const BuiltInShader(this.id, this.name, this.description);
  String get asset => 'assets/shaders/$id.glsl';
}

const builtInShaders = [
  BuiltInShader(
    'cone_sharpen',
    'Adaptive sharpen',
    'Crisper detail without halos. Light on the GPU.',
  ),
  BuiltInShader(
    'cone_lines',
    'Darken line art',
    'Bolder outlines for animation.',
  ),
  BuiltInShader(
    'cone_denoise',
    'Soften noise',
    'Smooths grain and compression noise while keeping edges.',
  ),
];

/// A ready-made chain from a known shader pack found in the shader folder.
class ShaderPreset {
  final String name, description;
  final List<String> files; // file names, in order
  const ShaderPreset(this.name, this.description, this.files);
}

/// Standard Anime4K (v4) and FSR chains, offered when the files are present.
const knownPresets = [
  ShaderPreset(
    'Anime4K: Mode A (HQ)',
    '1080p anime with blur or compression artefacts.',
    [
      'Anime4K_Clamp_Highlights.glsl',
      'Anime4K_Restore_CNN_VL.glsl',
      'Anime4K_Upscale_CNN_x2_VL.glsl',
      'Anime4K_AutoDownscalePre_x2.glsl',
      'Anime4K_AutoDownscalePre_x4.glsl',
      'Anime4K_Upscale_CNN_x2_M.glsl',
    ],
  ),
  ShaderPreset(
    'Anime4K: Mode B (HQ)',
    'Lower-resolution anime with aliasing (jagged lines).',
    [
      'Anime4K_Clamp_Highlights.glsl',
      'Anime4K_Restore_CNN_Soft_VL.glsl',
      'Anime4K_Upscale_CNN_x2_VL.glsl',
      'Anime4K_AutoDownscalePre_x2.glsl',
      'Anime4K_AutoDownscalePre_x4.glsl',
      'Anime4K_Upscale_CNN_x2_M.glsl',
    ],
  ),
  ShaderPreset(
    'Anime4K: Mode C (HQ)',
    'Already sharp anime that just needs upscaling.',
    [
      'Anime4K_Clamp_Highlights.glsl',
      'Anime4K_Upscale_Denoise_CNN_x2_VL.glsl',
      'Anime4K_AutoDownscalePre_x2.glsl',
      'Anime4K_AutoDownscalePre_x4.glsl',
      'Anime4K_Upscale_CNN_x2_M.glsl',
    ],
  ),
  ShaderPreset(
    'AMD FSR upscale',
    'Sharp, fast upscaling for any low-resolution video.',
    ['FSR.glsl'],
  ),
];

/// Built-in shaders (extracted to [dir]) plus the user's shader folder.
class ShaderLibrary {
  final Directory dir;
  final SettingsStore settings;
  final AssetBundle bundle;
  ShaderLibrary(this.dir, this.settings, {AssetBundle? bundle})
    : bundle = bundle ?? rootBundle;

  final Map<String, String> _builtInPaths = {};

  /// Writes the bundled shaders to disk (mpv needs file paths).
  Future<void> prepare() async {
    await dir.create(recursive: true);
    for (final s in builtInShaders) {
      final text = await bundle.loadString(s.asset);
      final f = File('${dir.path}/${s.id}.glsl');
      if (!f.existsSync() || f.readAsStringSync() != text) {
        await f.writeAsString(text);
      }
      _builtInPaths[s.id] = f.path;
    }
  }

  String? builtInPath(String id) => _builtInPaths[id];

  /// `.glsl` / `.hook` files in the user's shader folder.
  List<String> folderShaders() {
    final folder = Prefs.shaderFolder.of(settings);
    if (folder.isEmpty) return const [];
    final d = Directory(folder);
    if (!d.existsSync()) return const [];
    return d
        .listSync(recursive: true)
        .whereType<File>()
        .map((f) => f.path)
        .where((p) => p.endsWith('.glsl') || p.endsWith('.hook'))
        .toList()
      ..sort();
  }

  /// Presets whose files all exist in the shader folder, with full paths.
  List<(ShaderPreset, List<String>)> availablePresets() {
    final byName = {
      for (final p in folderShaders()) p.split(RegExp(r'[/\\]')).last: p,
    };
    return [
      for (final preset in knownPresets)
        if (preset.files.every(byName.containsKey))
          (preset, [for (final f in preset.files) byName[f]!]),
    ];
  }

  List<String> get active => Prefs.activeShaders
      .of(settings)
      .split(';')
      .where((p) => p.isNotEmpty)
      .toList();

  void setActive(List<String> paths) =>
      Prefs.activeShaders.set(settings, paths.join(';'));

  void toggle(String path, bool on) {
    final a = active..remove(path);
    if (on) a.add(path);
    setActive(a);
  }
}
