import 'package:flutter/material.dart';

import '../../theme.dart';

/// Two-tone (orange fill under a gray outline) icon for non-interactive
/// section headers.
class TwoToneIcon extends StatelessWidget {
  final IconData filled;
  final IconData outlined;
  final double size;
  const TwoToneIcon(this.filled, this.outlined, {super.key, this.size = 20});

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: Stack(
      children: [
        Icon(
          filled,
          size: size,
          color: ConeColors.accent.withValues(alpha: 0.45),
        ),
        Icon(outlined, size: size, color: ConeColors.textMuted),
      ],
    ),
  );
}

/// Small "i" icon that explains a setting in plain language on hover.
class InfoTip extends StatelessWidget {
  final String text;
  const InfoTip(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Tooltip(
    message: text,
    waitDuration: const Duration(milliseconds: 150),
    constraints: const BoxConstraints(maxWidth: 280),
    padding: const EdgeInsets.all(10),
    child: const Padding(
      padding: EdgeInsets.symmetric(horizontal: 4),
      child: Icon(Icons.info_outline, size: 14, color: ConeColors.textMuted),
    ),
  );
}

class SectionHeader extends StatelessWidget {
  final String title;
  final IconData filled, outlined;
  final String? info;
  final Widget? trailing;
  const SectionHeader(
    this.title,
    this.filled,
    this.outlined, {
    super.key,
    this.info,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 18, 12, 6),
    child: Row(
      children: [
        TwoToneIcon(filled, outlined),
        const SizedBox(width: 10),
        Text(
          title.toUpperCase(),
          style: const TextStyle(
            fontSize: 12,
            letterSpacing: 0.8,
            fontWeight: FontWeight.w700,
            color: ConeColors.text,
          ),
        ),
        if (info != null) InfoTip(info!),
        const Spacer(),
        ?trailing,
      ],
    ),
  );
}

/// Label + value + optional reset, with a slider underneath.
class AdjustSlider extends StatelessWidget {
  final String label;
  final double value, min, max;
  final double? defaultValue;
  final int? divisions;
  final String Function(double) format;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;
  final String? info;
  const AdjustSlider({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.onChangeEnd,
    this.defaultValue,
    this.divisions,
    this.info,
    String Function(double)? format,
  }) : format = format ?? _round;

  static String _round(double v) => v.round().toString();

  @override
  Widget build(BuildContext context) {
    final changed =
        defaultValue != null && (value - defaultValue!).abs() > 1e-6;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                label,
                style: const TextStyle(fontSize: 13, color: ConeColors.text),
              ),
              if (info != null) InfoTip(info!),
              const Spacer(),
              Text(
                format(value),
                style: TextStyle(
                  fontSize: 12,
                  color: changed ? ConeColors.accent : ConeColors.textMuted,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              SizedBox(
                width: 28,
                height: 24,
                child: changed
                    ? IconButton(
                        padding: EdgeInsets.zero,
                        iconSize: 14,
                        tooltip: 'Reset',
                        color: ConeColors.textMuted,
                        onPressed: () {
                          onChanged(defaultValue!);
                          onChangeEnd?.call(defaultValue!);
                        },
                        icon: const Icon(Icons.restart_alt),
                      )
                    : null,
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
              onChangeEnd: onChangeEnd,
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact selectable chip.
class ConeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Widget? icon;
  const ConeChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  @override
  Widget build(BuildContext context) => Material(
    color: selected ? ConeColors.accentDim : ConeColors.canvas,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(ConeRadius.sm),
      side: BorderSide(color: selected ? ConeColors.accent : ConeColors.border),
    ),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(ConeRadius.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[icon!, const SizedBox(width: 6)],
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: selected ? ConeColors.accent : ConeColors.text,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class ChipRow extends StatelessWidget {
  final List<Widget> children;
  const ChipRow(this.children, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
    child: Wrap(spacing: 6, runSpacing: 6, children: children),
  );
}

/// Labelled row with a widget on the right (switches, dropdowns, ...).
class SettingRow extends StatelessWidget {
  final String label;
  final String? info;
  final Widget child;
  const SettingRow({
    super.key,
    required this.label,
    required this.child,
    this.info,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 2, 10, 2),
    child: Row(
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 13, color: ConeColors.text),
        ),
        if (info != null) InfoTip(info!),
        const Spacer(),
        child,
      ],
    ),
  );
}

class ConeSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  const ConeSwitch({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) => Transform.scale(
    scale: 0.75,
    child: Switch(
      value: value,
      onChanged: onChanged,
      activeThumbColor: ConeColors.canvas,
      activeTrackColor: ConeColors.accent,
      inactiveThumbColor: ConeColors.textMuted,
      inactiveTrackColor: ConeColors.surfaceHigh,
      trackOutlineColor: WidgetStatePropertyAll(ConeColors.border),
    ),
  );
}

/// Row of colour dots.
class SwatchRow extends StatelessWidget {
  final List<Color> colors;
  final Color selected;
  final ValueChanged<Color> onPick;
  const SwatchRow({
    super.key,
    required this.colors,
    required this.selected,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final c in colors)
        Padding(
          padding: const EdgeInsets.only(left: 6),
          child: InkWell(
            onTap: () => onPick(c),
            customBorder: const CircleBorder(),
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: c,
                shape: BoxShape.circle,
                border: Border.all(
                  color: c.toARGB32() == selected.toARGB32()
                      ? ConeColors.accent
                      : ConeColors.border,
                  width: c.toARGB32() == selected.toARGB32() ? 2.5 : 1,
                ),
              ),
            ),
          ),
        ),
    ],
  );
}

/// "−  value  +" stepper used for delays.
class DelayStepper extends StatelessWidget {
  final String value;
  final VoidCallback onMinus, onPlus;
  const DelayStepper({
    super.key,
    required this.value,
    required this.onMinus,
    required this.onPlus,
  });

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      _btn(Icons.remove, onMinus, 'Earlier'),
      SizedBox(
        width: 64,
        child: Text(
          value,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 13,
            color: ConeColors.text,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      ),
      _btn(Icons.add, onPlus, 'Later'),
    ],
  );

  Widget _btn(IconData i, VoidCallback f, String tip) => SizedBox(
    width: 28,
    height: 28,
    child: IconButton(
      tooltip: tip,
      padding: EdgeInsets.zero,
      iconSize: 16,
      color: ConeColors.text,
      style: IconButton.styleFrom(
        backgroundColor: ConeColors.canvas,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ConeRadius.sm),
          side: BorderSide(color: ConeColors.border),
        ),
      ),
      onPressed: f,
      icon: Icon(i),
    ),
  );
}

/// Getter, not a const: the border colour follows the active theme.
Widget get panelDivider => Divider(
  height: 20,
  thickness: 1,
  indent: 16,
  endIndent: 16,
  color: ConeColors.border,
);

String signed(double v, {int digits = 0, String unit = ''}) =>
    '${v > 0 ? '+' : ''}${v.toStringAsFixed(digits)}$unit';
