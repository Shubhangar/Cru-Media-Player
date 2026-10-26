import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'eq.dart';
import 'models.dart';

/// Persists user preferences that should survive restarts. Generic values
/// (see `lib/settings/prefs.dart`) notify listeners when they change.
class SettingsStore extends ChangeNotifier {
  final String prefix;
  SharedPreferences? _prefs;
  final Map<String, Object> _memory = {}; // used before/without load()
  SettingsStore({this.prefix = 'cone.'});

  Future<void> load() async => _prefs = await SharedPreferences.getInstance();

  /// Generic typed value with a default; see [Pref].
  T value<T extends Object>(String key, T fallback) {
    final v = _prefs?.get('$prefix$key') ?? _memory[key];
    if (v is T) return v;
    if (fallback is double && v is int) return v.toDouble() as T;
    return fallback;
  }

  void setValue<T extends Object>(String key, T v) {
    _memory[key] = v;
    final k = '$prefix$key';
    switch (v) {
      case bool b:
        _prefs?.setBool(k, b);
      case int i:
        _prefs?.setInt(k, i);
      case double d:
        _prefs?.setDouble(k, d);
      case String s:
        _prefs?.setString(k, s);
      default:
        throw ArgumentError('Unsupported preference type ${v.runtimeType}');
    }
    notifyListeners();
  }

  /// Removes generic values so defaults apply again.
  void reset(Iterable<String> keys) {
    for (final k in keys) {
      _memory.remove(k);
      _prefs?.remove('$prefix$k');
    }
    notifyListeners();
  }

  T? _json<T>(String key, T Function(dynamic) parse) {
    final raw = _prefs?.getString('$prefix$key');
    if (raw == null) return null;
    try {
      return parse(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  Future<void> _put(String key, Object value) async =>
      _prefs?.setString('$prefix$key', jsonEncode(value));

  SubtitleStyle? get subtitleStyle => _json(
    'subStyle',
    (j) => SubtitleStyle.fromJson(Map<String, dynamic>.from(j as Map)),
  );
  set subtitleStyle(SubtitleStyle? s) => _put('subStyle', s!.toJson());

  List<NamedSubtitleStyle> get subtitlePresets =>
      _json(
        'subPresets',
        (j) => [
          for (final e in j as List)
            NamedSubtitleStyle(
              e['name'] as String,
              SubtitleStyle.fromJson(
                Map<String, dynamic>.from(e['style'] as Map),
              ),
            ),
        ],
      ) ??
      [];
  set subtitlePresets(List<NamedSubtitleStyle> v) => _put('subPresets', [
    for (final p in v) {'name': p.name, 'style': p.style.toJson()},
  ]);

  List<EqBand>? get eqBands => _json(
    'eqBands',
    (j) => [
      for (final b in j as List)
        EqBand.fromJson(Map<String, dynamic>.from(b as Map)),
    ],
  );
  set eqBands(List<EqBand>? v) =>
      _put('eqBands', [for (final b in v!) b.toJson()]);

  bool get eqEnabled => _prefs?.getBool('${prefix}eqEnabled') ?? false;
  set eqEnabled(bool v) => _prefs?.setBool('${prefix}eqEnabled', v);

  String get eqPresetId => _prefs?.getString('${prefix}eqPreset') ?? 'flat';
  set eqPresetId(String v) => _prefs?.setString('${prefix}eqPreset', v);

  bool get showWaveform => _prefs?.getBool('${prefix}showWaveform') ?? false;
  set showWaveform(bool v) => _prefs?.setBool('${prefix}showWaveform', v);
  bool get showSubtitleTimeline =>
      _prefs?.getBool('${prefix}showSubTimeline') ?? false;
  set showSubtitleTimeline(bool v) =>
      _prefs?.setBool('${prefix}showSubTimeline', v);

  /// OpenSubtitles.com consumer API key (user-provided).
  String get openSubtitlesKey => _prefs?.getString('${prefix}osKey') ?? '';
  set openSubtitlesKey(String v) => _prefs?.setString('${prefix}osKey', v);

  /// Comma-separated language priority lists, e.g. "en,eng".
  String get audioLanguages => _prefs?.getString('${prefix}alang') ?? '';
  set audioLanguages(String v) => _prefs?.setString('${prefix}alang', v);
  String get subtitleLanguages => _prefs?.getString('${prefix}slang') ?? '';
  set subtitleLanguages(String v) => _prefs?.setString('${prefix}slang', v);
}
