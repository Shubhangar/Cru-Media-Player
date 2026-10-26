import 'package:flutter/material.dart';

import '../../player/models.dart';
import '../../player/player_controller.dart';
import '../../theme.dart';
import 'widgets.dart';

const subtitleFonts = [
  '', 'Helvetica Neue', 'Arial', 'Avenir Next', 'Verdana', 'Trebuchet MS',
  'Segoe UI', 'Roboto', 'Noto Sans', 'Georgia', 'Menlo', //
];

const _textColors = [
  Color(0xFFFFFFFF), Color(0xFFFFE14D), Color(0xFF7FE7FF), Color(0xFFB4F48C),
  Color(0xFFFF6600), //
];
const _outlineColors = [
  Color(0xFF000000),
  Color(0xFF333333),
  Color(0xFF1E3A5F),
  Color(0x00000000),
];

class SubtitleTab extends StatelessWidget {
  final PlayerController c;
  final VoidCallback onLoadFile;
  const SubtitleTab({super.key, required this.c, required this.onLoadFile});

  SubtitleStyle get s => c.subStyle;
  void _set(SubtitleStyle n) => c.setSubStyle(n);

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        SubtitlePreview(style: s),
        SectionHeader(
          'Timing',
          Icons.timer,
          Icons.timer_outlined,
          info:
              'Shift subtitles if they appear too early or too late. '
              'Positive values show them later.',
        ),
        SettingRow(
          label: 'Delay',
          child: DelayStepper(
            value: signed(c.subDelay, digits: 2, unit: ' s'),
            onMinus: () => c.setSubDelay(c.subDelay - 0.1),
            onPlus: () => c.setSubDelay(c.subDelay + 0.1),
          ),
        ),
        AdjustSlider(
          label: 'Fine delay',
          value: c.subDelay,
          min: -10,
          max: 10,
          defaultValue: 0,
          divisions: 400,
          format: (v) => signed(v, digits: 2, unit: ' s'),
          onChanged: c.setSubDelay,
        ),
        panelDivider,
        SectionHeader(
          'Style presets',
          Icons.bookmarks,
          Icons.bookmarks_outlined,
          info: 'One-click looks. Save your current style to reuse it later.',
          trailing: TextButton.icon(
            onPressed: () => _savePreset(context),
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Save current', style: TextStyle(fontSize: 12)),
          ),
        ),
        ChipRow([
          for (final p in [...builtInSubtitleStyles, ...c.userSubPresets])
            GestureDetector(
              onSecondaryTap: p.builtIn
                  ? null
                  : () => c.deleteSubPreset(p.name),
              child: ConeChip(
                label: p.name,
                selected: p.style.toMpv().toString() == s.toMpv().toString(),
                icon: p.builtIn
                    ? null
                    : InkWell(
                        onTap: () => c.deleteSubPreset(p.name),
                        child: const Icon(
                          Icons.close,
                          size: 13,
                          color: ConeColors.textMuted,
                        ),
                      ),
                onTap: () => _set(p.style),
              ),
            ),
        ]),
        panelDivider,
        SectionHeader('Font', Icons.text_fields, Icons.text_fields_outlined),
        SettingRow(
          label: 'Typeface',
          child: _FontPicker(
            value: s.font,
            onChanged: (f) => _set(s.copyWith(font: f)),
          ),
        ),
        SettingRow(
          label: 'Bold',
          child: ConeSwitch(
            value: s.bold,
            onChanged: (v) => _set(s.copyWith(bold: v)),
          ),
        ),
        SettingRow(
          label: 'Size mode',
          info:
              'Relative scales with the video. Exact uses a fixed font size '
              '(in 720-line units) regardless of the video.',
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ConeChip(
                label: 'Relative',
                selected: !s.exactSize,
                onTap: () => _set(s.copyWith(exactSize: false)),
              ),
              const SizedBox(width: 6),
              ConeChip(
                label: 'Exact',
                selected: s.exactSize,
                onTap: () => _set(s.copyWith(exactSize: true)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        if (s.exactSize)
          AdjustSlider(
            label: 'Font size',
            value: s.size.toDouble(),
            min: 20,
            max: 120,
            divisions: 100,
            defaultValue: 55,
            onChanged: (v) => _set(s.copyWith(size: v.round())),
          )
        else
          AdjustSlider(
            label: 'Scale',
            value: s.scale,
            min: 0.5,
            max: 3,
            divisions: 50,
            defaultValue: 1,
            format: (v) => '${(v * 100).round()}%',
            onChanged: (v) => _set(s.copyWith(scale: v)),
          ),
        panelDivider,
        SectionHeader(
          'Text & outline',
          Icons.format_color_text,
          Icons.format_color_text_outlined,
        ),
        SettingRow(
          label: 'Text colour',
          child: SwatchRow(
            colors: _textColors,
            selected: s.color,
            onPick: (col) => _set(s.copyWith(color: col)),
          ),
        ),
        SettingRow(
          label: 'Outline colour',
          child: SwatchRow(
            colors: _outlineColors,
            selected: s.borderColor,
            onPick: (col) => _set(s.copyWith(borderColor: col)),
          ),
        ),
        AdjustSlider(
          label: 'Outline width',
          value: s.borderSize,
          min: 0,
          max: 8,
          divisions: 32,
          defaultValue: 3,
          format: (v) => v.toStringAsFixed(1),
          onChanged: (v) => _set(s.copyWith(borderSize: v)),
        ),
        AdjustSlider(
          label: 'Shadow',
          value: s.shadow,
          min: 0,
          max: 5,
          divisions: 20,
          defaultValue: 0,
          format: (v) => v.toStringAsFixed(1),
          onChanged: (v) => _set(s.copyWith(shadow: v)),
        ),
        panelDivider,
        SectionHeader(
          'Position',
          Icons.vertical_align_bottom,
          Icons.vertical_align_bottom_outlined,
        ),
        AdjustSlider(
          label: 'Vertical position',
          info: '100 is the bottom edge, 0 the top.',
          value: s.position.toDouble(),
          min: 0,
          max: 100,
          divisions: 100,
          defaultValue: 100,
          onChanged: (v) => _set(s.copyWith(position: v.round())),
        ),
        SettingRow(
          label: 'Override embedded styles',
          info:
              'Styled subtitles (ASS/SSA, common in anime) normally keep their '
              'own look. Turn on to force your style onto them.',
          child: ConeSwitch(
            value: s.overrideEmbedded,
            onChanged: (v) => _set(s.copyWith(overrideEmbedded: v)),
          ),
        ),
        panelDivider,
        SectionHeader(
          'Auto-select',
          Icons.translate,
          Icons.translate_outlined,
          info:
              'Preferred subtitle languages, picked automatically when a '
              'file opens. Use codes like "en,eng" in priority order.',
        ),
        LangField(
          initial: c.subtitleLanguages,
          hint: 'e.g. en,eng',
          onSubmit: (v) => c.setLanguages(subtitle: v),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: OutlinedButton.icon(
            onPressed: onLoadFile,
            icon: const Icon(Icons.file_open_outlined, size: 16),
            label: const Text('Load subtitle file…'),
            style: OutlinedButton.styleFrom(
              foregroundColor: ConeColors.text,
              side: const BorderSide(color: ConeColors.border),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(ConeRadius.md),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _savePreset(BuildContext context) async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Save subtitle style'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Preset name'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
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
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (name != null && name.trim().isNotEmpty) c.saveSubPreset(name.trim());
  }
}

/// Approximate live preview of the subtitle style on a dark frame.
class SubtitlePreview extends StatelessWidget {
  final SubtitleStyle style;
  const SubtitlePreview({super.key, required this.style});

  @override
  Widget build(BuildContext context) {
    final s = style;
    // Preview frame is ~1/5 of a 720-line video.
    final px = (s.exactSize ? s.size : 55 * s.scale) * 0.24;
    final base = TextStyle(
      fontFamily: s.font.isEmpty ? null : s.font,
      fontSize: px,
      height: 1.15,
      fontWeight: s.bold ? FontWeight.w700 : FontWeight.w500,
    );
    const sample = 'The quick brown fox';
    return Container(
      height: 150,
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(ConeRadius.md),
        border: Border.all(color: ConeColors.border),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2B3A4A), Color(0xFF4A3B2B), Color(0xFF1A1A1A)],
        ),
      ),
      child: Stack(
        children: [
          const Positioned(
            left: 10,
            top: 8,
            child: Text(
              'PREVIEW',
              style: TextStyle(
                fontSize: 10,
                letterSpacing: 1,
                color: Color(0x88FFFFFF),
              ),
            ),
          ),
          Align(
            // sub-pos 0..100 -> top..bottom
            alignment: Alignment(0, -0.85 + 1.7 * s.position / 100),
            child: Stack(
              children: [
                if (s.borderSize > 0 && s.borderColor.a > 0)
                  Text(
                    sample,
                    style: base.copyWith(
                      foreground: Paint()
                        ..style = PaintingStyle.stroke
                        ..strokeWidth = s.borderSize * 0.9
                        ..strokeJoin = StrokeJoin.round
                        ..color = s.borderColor,
                    ),
                  ),
                Text(
                  sample,
                  style: base.copyWith(
                    color: s.color,
                    shadows: s.shadow > 0
                        ? [
                            Shadow(
                              offset: Offset(s.shadow * 0.8, s.shadow * 0.8),
                              color: const Color(0xAA000000),
                            ),
                          ]
                        : null,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FontPicker extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  const _FontPicker({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final fonts = [...subtitleFonts, if (!subtitleFonts.contains(value)) value];
    return DropdownButton<String>(
      value: value,
      isDense: true,
      underline: const SizedBox.shrink(),
      dropdownColor: ConeColors.surface,
      borderRadius: BorderRadius.circular(ConeRadius.md),
      style: const TextStyle(fontSize: 13, color: ConeColors.text),
      items: [
        for (final f in fonts)
          DropdownMenuItem(
            value: f,
            child: Text(
              f.isEmpty ? 'Default' : f,
              style: TextStyle(fontFamily: f.isEmpty ? null : f),
            ),
          ),
        const DropdownMenuItem(value: '\u0000custom', child: Text('Custom…')),
      ],
      onChanged: (f) async {
        if (f == null) return;
        if (f != '\u0000custom') return onChanged(f);
        final ctrl = TextEditingController(text: value);
        final name = await showDialog<String>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Custom font'),
            content: TextField(
              controller: ctrl,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Installed font name',
              ),
              onSubmitted: (v) => Navigator.pop(ctx, v),
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(ctx, ctrl.text),
                child: const Text('Use font'),
              ),
            ],
          ),
        );
        if (name != null) onChanged(name.trim());
      },
    );
  }
}

/// Text field that commits on Enter or when focus leaves.
class LangField extends StatefulWidget {
  final String initial;
  final String hint;
  final ValueChanged<String> onSubmit;
  const LangField({
    super.key,
    required this.initial,
    required this.hint,
    required this.onSubmit,
  });

  @override
  State<LangField> createState() => _LangFieldState();
}

class _LangFieldState extends State<LangField> {
  late final _ctrl = TextEditingController(text: widget.initial);
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) widget.onSubmit(_ctrl.text);
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: TextField(
      controller: _ctrl,
      focusNode: _focus,
      style: const TextStyle(fontSize: 13),
      decoration: InputDecoration(
        hintText: widget.hint,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 10,
        ),
      ),
      onSubmitted: widget.onSubmit,
    ),
  );
}
