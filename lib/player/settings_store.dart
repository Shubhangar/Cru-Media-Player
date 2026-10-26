import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'eq.dart';
import 'models.dart';

/// Persists user preferences that should survive restarts.
class SettingsStore {
  final String prefix;
  SharedPreferences? _prefs;
  SettingsStore({this.prefix = 'cone.'});

  Future<void> load() async => _prefs = await SharedPreferences.getInstance();

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

  /// Comma-separated language priority lists, e.g. "en,eng".
  String get audioLanguages => _prefs?.getString('${prefix}alang') ?? '';
  set audioLanguages(String v) => _prefs?.setString('${prefix}alang', v);
  String get subtitleLanguages => _prefs?.getString('${prefix}slang') ?? '';
  set subtitleLanguages(String v) => _prefs?.setString('${prefix}slang', v);
}
