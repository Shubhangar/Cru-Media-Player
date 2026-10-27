import '../player/settings_store.dart';

/// A typed preference with its default.
class Pref<T extends Object> {
  final String key;
  final T fallback;
  const Pref(this.key, this.fallback);

  T of(SettingsStore s) => s.value<T>(key, fallback);
  void set(SettingsStore s, T v) => s.setValue<T>(key, v);
}

/// Every generic preference, grouped by settings panel.
abstract final class Prefs {
  // General
  static const canvas = Pref('canvas', 'charcoal');
  static const accent = Pref('accent', 0xFFFF6600);
  static const onboarded = Pref('onboarded', false);

  // Interface
  static const density = Pref(
    'density',
    'comfortable',
  ); // compact|comfortable|large
  static const hideDelayMs = Pref('hideDelayMs', 600);
  static const osd = Pref('osd', true);
  static const osdMs = Pref('osdMs', 1300);
  static const seekPreviews = Pref('seekPreviews', true);
  static const stayOnTop = Pref('stayOnTop', false);

  // Privacy
  static const rememberHistory = Pref('rememberHistory', true);
  static const saveThumbnails = Pref('saveThumbnails', true);

  // Controls
  static const seekStep = Pref('seekStep', 5);
  static const bigSeekStep = Pref('bigSeekStep', 60);
  static const wheel = Pref('wheel', 'volume'); // volume|seek|none
  static const doubleClick = Pref(
    'doubleClick',
    'zones',
  ); // zones|fullscreen|play

  // Playback
  static const resume = Pref('resume', 'ask'); // ask|always|never
  static const autoplayNext = Pref('autoplayNext', true);
  static const repeat = Pref('repeat', 'off'); // off|one|all
  static const defaultSpeed = Pref('defaultSpeed', 1.0);

  // Video
  static const hwdec = Pref('hwdec', true);
  static const scaler = Pref('scaler', 'bilinear');
  static const deband = Pref('deband', false);
  static const toneMap = Pref('toneMap', true);

  // Audio
  static const startVolume = Pref('startVolume', 100.0);
  static const volumeBoost = Pref('volumeBoost', false);
  static const normalize = Pref('normalize', false);

  // Subtitle
  static const subMode = Pref('subMode', 'auto'); // auto|foreign|forced|off
  static const subAutoLoad = Pref('subAutoLoad', 'fuzzy'); // fuzzy|exact|no

  // Library
  static const refreshHours = Pref('refreshHours', 6);

  // Network / performance / recording / extensions
  static const netTimeout = Pref('netTimeout', 15);
  static const cacheMb = Pref('cacheMb', 150);
  static const prefetch = Pref('prefetch', true);
  static const userAgent = Pref('userAgent', '');
  static const shotFolder = Pref('shotFolder', '');
  static const shotFormat = Pref('shotFormat', 'png'); // png|jpeg
  static const shaderFolder = Pref('shaderFolder', '');
  static const activeShaders = Pref('activeShaders', ''); // ;-joined paths
  static const captureSources = Pref('captureSources', ''); // ;-joined URLs
  static const castDevices = Pref(
    'castDevices',
    '',
  ); // ;-joined description URLs
}
