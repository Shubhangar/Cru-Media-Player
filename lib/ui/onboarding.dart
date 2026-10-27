import 'package:flutter/material.dart';

import 'blob_logo.dart';

import '../player/settings_store.dart';
import '../settings/prefs.dart';
import '../theme.dart';
import 'layout/control_layout.dart';
import 'settings/shortcuts.dart';

/// First-run tour: look (theme + accent), layout density, essential keys.
class OnboardingWizard extends StatefulWidget {
  final SettingsStore settings;
  final VoidCallback onOpenFile;
  const OnboardingWizard({
    super.key,
    required this.settings,
    required this.onOpenFile,
  });

  @override
  State<OnboardingWizard> createState() => _OnboardingWizardState();
}

class _OnboardingWizardState extends State<OnboardingWizard> {
  int _step = 0;
  static const _steps = 5;

  SettingsStore get s => widget.settings;

  void _finish() => Prefs.onboarded.set(s, true);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xD9000000),
      child: Center(
        child: Container(
          width: 720,
          height: 500,
          decoration: BoxDecoration(
            color: ConeColors.surface,
            borderRadius: BorderRadius.circular(ConeRadius.lg),
            border: Border.all(color: ConeColors.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              LinearProgressIndicator(
                value: (_step + 1) / _steps,
                minHeight: 3,
                color: ConeColors.accent,
                backgroundColor: ConeColors.border,
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(36, 30, 36, 10),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: KeyedSubtree(
                      key: ValueKey(_step),
                      child: switch (_step) {
                        0 => _welcome(),
                        1 => _look(),
                        2 => _layout(),
                        3 => _keys(),
                        _ => _done(),
                      },
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
                child: Row(
                  children: [
                    if (_step < _steps - 1)
                      TextButton(
                        onPressed: _finish,
                        child: const Text(
                          'Skip',
                          style: TextStyle(color: ConeColors.textMuted),
                        ),
                      ),
                    const Spacer(),
                    if (_step > 0)
                      OutlinedButton(
                        onPressed: () => setState(() => _step--),
                        child: const Text('Back'),
                      ),
                    const SizedBox(width: 10),
                    if (_step < _steps - 1)
                      FilledButton(
                        onPressed: () => setState(() => _step++),
                        child: Text(_step == 0 ? 'Get started' : 'Next'),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _title(String t, String sub) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        t,
        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 6),
      Text(sub, style: const TextStyle(color: ConeColors.textMuted)),
      const SizedBox(height: 22),
    ],
  );

  Widget _welcome() => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      const BlobLogo(size: 110, animated: true),
      const SizedBox(height: 16),
      const Text(
        'Welcome to Cru Media Player',
        style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 8),
      const Text(
        'Three quick choices and you are ready to watch.',
        style: TextStyle(color: ConeColors.textMuted),
      ),
    ],
  );

  Widget _look() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _title(
        'Pick a look',
        'You can change this any time in Settings › General.',
      ),
      Row(
        children: [
          for (final p in canvasPalettes)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 12),
                child: _card(
                  selected: Prefs.canvas.of(s) == p.id,
                  onTap: () => Prefs.canvas.set(s, p.id),
                  label: p.name,
                  child: Container(
                    height: 90,
                    color: p.canvas,
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Container(height: 14, color: p.surface),
                        const SizedBox(height: 4),
                        Container(height: 4, color: ConeColors.accent),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      const SizedBox(height: 24),
      const Text('Accent', style: TextStyle(color: ConeColors.textMuted)),
      const SizedBox(height: 10),
      Wrap(
        spacing: 10,
        children: [
          for (final (name, col) in accentChoices)
            Tooltip(
              message: name,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => Prefs.accent.set(s, col.toARGB32()),
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: col,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Prefs.accent.of(s) == col.toARGB32()
                          ? ConeColors.text
                          : Colors.transparent,
                      width: 3,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    ],
  );

  Widget _layout() {
    final profiles = LayoutProfiles(s);
    Widget bar(double scale) => Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      color: ConeColors.canvas,
      child: Row(
        children: [
          for (final i in [
            Icons.skip_previous_rounded,
            Icons.play_arrow_rounded,
            Icons.skip_next_rounded,
          ])
            Icon(i, size: 18 * scale),
          const Spacer(),
          for (final i in [Icons.fullscreen, Icons.subtitles_outlined])
            Icon(i, size: 16 * scale),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title(
          'How big should the controls be?',
          'Compact shows more picture; Large is easier to hit.',
        ),
        Row(
          children: [
            for (final (id, label) in [
              ('compact', 'Compact'),
              ('comfortable', 'Comfortable'),
              ('large', 'Large'),
            ])
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: _card(
                    selected: Prefs.density.of(s) == id,
                    onTap: () => Prefs.density.set(s, id),
                    label: label,
                    child: bar(ConeDensity.forName(id)),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 22),
        const Text(
          'Starting buttons',
          style: TextStyle(color: ConeColors.textMuted),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          children: [
            for (final name in defaultLayouts.keys)
              ChoiceChip(
                label: Text(name),
                selected: profiles.activeName == name,
                onSelected: (_) => setState(() => profiles.select(name)),
                selectedColor: ConeColors.accentDim,
                showCheckmark: false,
                side: BorderSide(color: ConeColors.border),
              ),
          ],
        ),
      ],
    );
  }

  Widget _keys() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _title(
        'The essentials',
        'Every shortcut is listed in Settings › Controls.',
      ),
      const ShortcutTable(essentialOnly: true),
    ],
  );

  Widget _done() => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Icon(Icons.check_circle_outline, size: 72, color: ConeColors.accent),
      const SizedBox(height: 14),
      const Text(
        "You're all set",
        style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 8),
      const Text(
        'Drop a video anywhere, or open one now.',
        style: TextStyle(color: ConeColors.textMuted),
      ),
      const SizedBox(height: 24),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          FilledButton.icon(
            onPressed: () {
              _finish();
              widget.onOpenFile();
            },
            icon: const Icon(Icons.insert_drive_file_outlined, size: 18),
            label: const Text('Open a file'),
          ),
          const SizedBox(width: 10),
          OutlinedButton(onPressed: _finish, child: const Text('Explore')),
        ],
      ),
    ],
  );

  Widget _card({
    required bool selected,
    required VoidCallback onTap,
    required String label,
    required Widget child,
  }) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(ConeRadius.md),
    child: Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(ConeRadius.md),
        border: Border.all(
          color: selected ? ConeColors.accent : ConeColors.border,
          width: selected ? 2 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          child,
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              label,
              style: TextStyle(
                color: selected ? ConeColors.accent : ConeColors.text,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
