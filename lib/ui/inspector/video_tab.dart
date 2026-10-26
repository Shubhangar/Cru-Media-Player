import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../player/models.dart';
import '../../player/player_controller.dart';
import '../../theme.dart';
import 'widgets.dart';

class _Look {
  final String name;
  final IconData icon;
  final VideoAdjust Function(VideoAdjust) apply;
  const _Look(this.name, this.icon, this.apply);
}

final _looks = <_Look>[
  _Look(
    'Original',
    Icons.restart_alt,
    (a) => a.copyWith(brightness: 0, contrast: 0, saturation: 0, gamma: 0),
  ),
  _Look(
    'Vivid',
    Icons.palette_outlined,
    (a) => a.copyWith(brightness: 0, contrast: 10, saturation: 35, gamma: 0),
  ),
  _Look(
    'Cinema',
    Icons.movie_outlined,
    (a) => a.copyWith(brightness: -5, contrast: 15, saturation: -15, gamma: 0),
  ),
  _Look(
    'Bright',
    Icons.wb_sunny_outlined,
    (a) => a.copyWith(brightness: 15, contrast: 0, saturation: 0, gamma: 10),
  ),
  _Look(
    'Soft',
    Icons.blur_on,
    (a) => a.copyWith(brightness: 5, contrast: -15, saturation: -5, gamma: 0),
  ),
  _Look('Grayscale', Icons.filter_b_and_w, (a) => a.copyWith(saturation: -100)),
  _Look('Flip H', Icons.flip, (a) => a.copyWith(hflip: !a.hflip)),
  _Look('Flip V', Icons.flip, (a) => a.copyWith(vflip: !a.vflip)),
  _Look(
    'Rotate 90°',
    Icons.rotate_90_degrees_cw_outlined,
    (a) => a.copyWith(rotation: (a.rotation + 90) % 360),
  ),
];

class VideoTab extends StatefulWidget {
  final PlayerController c;
  const VideoTab({super.key, required this.c});

  @override
  State<VideoTab> createState() => _VideoTabState();
}

class _VideoTabState extends State<VideoTab> {
  Uint8List? _frame;
  VideoAdjust? _staged;
  String? _stagedName;

  PlayerController get c => widget.c;

  @override
  void initState() {
    super.initState();
    _grab();
  }

  Future<void> _grab() async {
    if (c.player.state.playlist.medias.isEmpty) return;
    final f = await c.player.screenshot();
    if (mounted && f != null) setState(() => _frame = f);
  }

  @override
  Widget build(BuildContext context) {
    final a = c.adjust;
    void set(VideoAdjust n) => c.setVideo(n);

    return ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        SectionHeader(
          'Looks',
          Icons.auto_awesome,
          Icons.auto_awesome_outlined,
          info: 'Pick a look to preview it on the current frame, then apply.',
          trailing: IconButton(
            tooltip: 'Refresh preview frame',
            iconSize: 16,
            color: ConeColors.textMuted,
            onPressed: _grab,
            icon: const Icon(Icons.refresh),
          ),
        ),
        _BeforeAfter(
          frame: _frame,
          current: a,
          staged: _staged,
          stagedName: _stagedName,
          onApply: () {
            set(_staged!);
            c.notify('Look: $_stagedName');
            setState(() => _staged = _stagedName = null);
          },
          onCancel: () => setState(() => _staged = _stagedName = null),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 6,
            crossAxisSpacing: 6,
            childAspectRatio: 1.25,
            children: [
              for (final l in _looks)
                _LookCard(
                  look: l,
                  frame: _frame,
                  current: a,
                  selected: _stagedName == l.name,
                  onTap: () => setState(() {
                    _staged = l.apply(a);
                    _stagedName = l.name;
                  }),
                ),
            ],
          ),
        ),
        panelDivider,
        SectionHeader(
          'Picture',
          Icons.tune,
          Icons.tune_outlined,
          info: 'Live adjustments, applied as you drag.',
          trailing: TextButton(
            onPressed: c.resetVideo,
            child: const Text('Reset all', style: TextStyle(fontSize: 12)),
          ),
        ),
        for (final (label, value, update) in [
          ('Brightness', a.brightness, (int v) => a.copyWith(brightness: v)),
          ('Contrast', a.contrast, (int v) => a.copyWith(contrast: v)),
          ('Saturation', a.saturation, (int v) => a.copyWith(saturation: v)),
          ('Gamma', a.gamma, (int v) => a.copyWith(gamma: v)),
        ])
          AdjustSlider(
            label: label,
            value: value.toDouble(),
            min: -100,
            max: 100,
            divisions: 200,
            defaultValue: 0,
            format: (v) => signed(v),
            onChanged: (v) => set(update(v.round())),
          ),
        panelDivider,
        SectionHeader(
          'Geometry',
          Icons.crop_rotate,
          Icons.crop_rotate_outlined,
        ),
        SettingRow(
          label: 'Rotate',
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final r in [0, 90, 180, 270]) ...[
                const SizedBox(width: 4),
                ConeChip(
                  label: '$r°',
                  selected: a.rotation == r,
                  onTap: () => set(a.copyWith(rotation: r)),
                ),
              ],
            ],
          ),
        ),
        SettingRow(
          label: 'Flip horizontally',
          child: ConeSwitch(
            value: a.hflip,
            onChanged: (v) => set(a.copyWith(hflip: v)),
          ),
        ),
        SettingRow(
          label: 'Flip vertically',
          child: ConeSwitch(
            value: a.vflip,
            onChanged: (v) => set(a.copyWith(vflip: v)),
          ),
        ),
        AdjustSlider(
          label: 'Zoom',
          value: a.zoom,
          min: -1,
          max: 2,
          divisions: 60,
          defaultValue: 0,
          format: (v) => '${(100 * _pow2(v)).round()}%',
          onChanged: (v) => set(a.copyWith(zoom: v)),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Text(
            'Aspect ratio',
            style: TextStyle(fontSize: 13, color: ConeColors.text),
          ),
        ),
        ChipRow([
          for (final r in [
            'auto',
            '16:9',
            '4:3',
            '21:9',
            '2.35:1',
            '1:1',
            '9:16',
          ])
            ConeChip(
              label: r == 'auto' ? 'Default' : r,
              selected: a.aspect == r,
              onTap: () => set(a.copyWith(aspect: r)),
            ),
        ]),
        panelDivider,
        SectionHeader(
          'Output',
          Icons.hd,
          Icons.hd_outlined,
          trailing: _SourceSize(c: c),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 0),
          child: Row(
            children: [
              Text(
                'Upscaling quality',
                style: TextStyle(fontSize: 13, color: ConeColors.text),
              ),
              InfoTip(
                'How the GPU resizes video to fit your screen. Sharp gives '
                'crisper low-resolution video but uses more power; Fast is '
                'lightest on battery.',
              ),
            ],
          ),
        ),
        ChipRow([
          for (final (id, label) in [
            ('bilinear', 'Fast'),
            ('lanczos', 'Default'),
            ('ewa_lanczossharp', 'Sharp'),
          ])
            ConeChip(
              label: label,
              selected: a.scaler == id,
              onTap: () => set(a.copyWith(scaler: id)),
            ),
        ]),
        SettingRow(
          label: 'HDR tone mapping',
          info:
              'Maps HDR video into the range your display can show, so '
              'highlights are not blown out. Turn off to clip instead.',
          child: ConeSwitch(
            value: a.toneMapHdr,
            onChanged: (v) => set(a.copyWith(toneMapHdr: v)),
          ),
        ),
      ],
    );
  }
}

double _pow2(double x) => math.pow(2, x).toDouble();

/// Renders [frame] the way [target] would look. The grabbed frame has none
/// of the adjustments (they are applied at display time), so apply them all.
Widget _render(
  Uint8List frame,
  VideoAdjust current,
  VideoAdjust target, {
  BoxFit fit = BoxFit.cover,
}) {
  Widget img = Image.memory(frame, fit: fit, gaplessPlayback: true);
  img = ColorFiltered(
    colorFilter: ColorFilter.matrix(target.previewMatrix),
    child: img,
  );
  final fx = target.hflip ? -1.0 : 1.0;
  final fy = target.vflip ? -1.0 : 1.0;
  if (fx != 1 || fy != 1) {
    img = Transform.scale(scaleX: fx, scaleY: fy, child: img);
  }
  if (target.rotation != 0) {
    img = RotatedBox(quarterTurns: target.rotation ~/ 90, child: img);
  }
  return img;
}

class _LookCard extends StatelessWidget {
  final _Look look;
  final Uint8List? frame;
  final VideoAdjust current;
  final bool selected;
  final VoidCallback onTap;
  const _LookCard({
    required this.look,
    required this.frame,
    required this.current,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Material(
    color: ConeColors.canvas,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(ConeRadius.md),
      side: BorderSide(
        color: selected ? ConeColors.accent : ConeColors.border,
        width: selected ? 2 : 1,
      ),
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (frame != null)
            _render(frame!, current, look.apply(current))
          else
            Icon(look.icon, color: ConeColors.textMuted),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 3),
              color: const Color(0xB3000000),
              child: Text(
                look.name,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 10.5,
                  color: selected ? ConeColors.accent : ConeColors.text,
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _BeforeAfter extends StatelessWidget {
  final Uint8List? frame;
  final VideoAdjust current;
  final VideoAdjust? staged;
  final String? stagedName;
  final VoidCallback onApply, onCancel;
  const _BeforeAfter({
    required this.frame,
    required this.current,
    required this.staged,
    required this.stagedName,
    required this.onApply,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    if (frame == null) {
      return Container(
        height: 90,
        margin: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: ConeColors.canvas,
          borderRadius: BorderRadius.circular(ConeRadius.md),
          border: Border.all(color: ConeColors.border),
        ),
        child: const Text(
          'Play something to preview looks',
          style: TextStyle(color: ConeColors.textMuted, fontSize: 12),
        ),
      );
    }
    Widget pane(String label, VideoAdjust a) => Expanded(
      child: Column(
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(ConeRadius.sm),
              child: Container(
                color: Colors.black,
                child: _render(frame!, current, a, fit: BoxFit.contain),
              ),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: ConeColors.textMuted),
          ),
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        children: [
          Row(
            children: [
              pane('Now', current),
              const SizedBox(width: 8),
              pane(
                staged == null ? 'Pick a look' : stagedName!,
                staged ?? current,
              ),
            ],
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 150),
            child: staged == null
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: onCancel,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: ConeColors.text,
                              side: const BorderSide(color: ConeColors.border),
                            ),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton(
                            onPressed: onApply,
                            child: const Text('Apply'),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// Source resolution of the current video, e.g. "1280×720".
class _SourceSize extends StatelessWidget {
  final PlayerController c;
  const _SourceSize({required this.c});

  @override
  Widget build(BuildContext context) => StreamBuilder(
    stream: c.player.stream.width,
    builder: (context, _) {
      final w = c.player.state.width, h = c.player.state.height;
      if (w == null || h == null || w == 0) return const SizedBox.shrink();
      return Text(
        'Source $w×$h',
        style: const TextStyle(fontSize: 12, color: ConeColors.textMuted),
      );
    },
  );
}
