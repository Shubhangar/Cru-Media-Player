import 'package:flutter/material.dart';

import '../../theme.dart';
import '../inspector/widgets.dart';
import 'control_layout.dart';

/// Drag-and-drop wireframe of the control bar. Changes apply live to the
/// active profile; profiles can be switched, saved as new, or deleted.
class LayoutEditor extends StatefulWidget {
  final LayoutProfiles profiles;
  final VoidCallback onClose;
  const LayoutEditor({
    super.key,
    required this.profiles,
    required this.onClose,
  });

  @override
  State<LayoutEditor> createState() => _LayoutEditorState();
}

/// What is being dragged: a control and where it came from.
class _Drag {
  final ControlId id;
  final String from; // 'left' | 'right' | 'palette'
  const _Drag(this.id, this.from);
}

class _LayoutEditorState extends State<LayoutEditor> {
  LayoutProfiles get p => widget.profiles;

  void _edit(void Function(BarLayout l) change) {
    final l = p.active.copy();
    change(l);
    p.update(p.activeName, l);
    setState(() {});
  }

  void _drop(_Drag d, String zone, [int? index]) => _edit((l) {
    l.left.remove(d.id);
    l.right.remove(d.id);
    if (zone == 'palette') return;
    final list = zone == 'left' ? l.left : l.right;
    list.insert((index ?? list.length).clamp(0, list.length), d.id);
  });

  @override
  Widget build(BuildContext context) {
    final layout = p.active;
    final names = p.all.keys.toList();
    final unused = ControlId.values.where((c) => !layout.used.contains(c));
    return Material(
      color: Colors.black54,
      child: Center(
        child: Container(
          width: 900,
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: ConeColors.surface,
            borderRadius: BorderRadius.circular(ConeRadius.lg),
            border: Border.all(color: ConeColors.border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const TwoToneIcon(
                    Icons.dashboard_customize,
                    Icons.dashboard_customize_outlined,
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'Control bar layout',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  const InfoTip(
                    'Drag buttons between the left and right groups, reorder '
                    'them, or drag them back to the tray to remove them. '
                    'Changes apply immediately.',
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Done',
                    onPressed: widget.onClose,
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  const Text(
                    'Profile',
                    style: TextStyle(color: ConeColors.textMuted),
                  ),
                  const SizedBox(width: 10),
                  for (final n in names)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ConeChip(
                        label: n,
                        selected: n == p.activeName,
                        onTap: () => setState(() => p.select(n)),
                      ),
                    ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () async {
                      final name = await _askName(context);
                      if (name != null) {
                        setState(() => p.saveAs(name, layout.copy()));
                      }
                    },
                    icon: const Icon(Icons.save_outlined, size: 16),
                    label: const Text('Save as new'),
                  ),
                  if (defaultLayouts.containsKey(p.activeName))
                    TextButton(
                      onPressed: () =>
                          setState(() => p.resetBuiltIn(p.activeName)),
                      child: const Text('Reset'),
                    )
                  else
                    TextButton(
                      onPressed: () => setState(() => p.delete(p.activeName)),
                      child: const Text('Delete'),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              // Wireframe of the bar.
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: ConeColors.canvas,
                  borderRadius: BorderRadius.circular(ConeRadius.md),
                  border: Border.all(color: ConeColors.border),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _zone('left', layout.left, 'Left group'),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _zone(
                            'right',
                            layout.right,
                            'Right group',
                            alignEnd: true,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      height: 6,
                      decoration: BoxDecoration(
                        color: ConeColors.border,
                        borderRadius: BorderRadius.circular(3),
                      ),
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: 0.35,
                        child: Container(
                          decoration: BoxDecoration(
                            color: ConeColors.accent,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Available buttons',
                style: TextStyle(color: ConeColors.textMuted, fontSize: 12),
              ),
              const SizedBox(height: 8),
              DragTarget<_Drag>(
                onAcceptWithDetails: (d) => _drop(d.data, 'palette'),
                builder: (context, cand, _) => Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(minHeight: 60),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(ConeRadius.md),
                    border: Border.all(
                      color: cand.isNotEmpty
                          ? ConeColors.accent
                          : ConeColors.border,
                    ),
                  ),
                  child: unused.isEmpty
                      ? const Text(
                          'Every button is on the bar. Drag one here to remove it.',
                          style: TextStyle(
                            color: ConeColors.textMuted,
                            fontSize: 12,
                          ),
                        )
                      : Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final id in unused) _chip(id, 'palette'),
                          ],
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _zone(
    String zone,
    List<ControlId> items,
    String label, {
    bool alignEnd = false,
  }) => DragTarget<_Drag>(
    onAcceptWithDetails: (d) => _drop(d.data, zone),
    builder: (context, cand, _) => Container(
      key: ValueKey('zone-$zone'),
      constraints: const BoxConstraints(minHeight: 66),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: cand.isNotEmpty ? ConeColors.accentDim : Colors.transparent,
        borderRadius: BorderRadius.circular(ConeRadius.md),
        border: Border.all(color: ConeColors.border),
      ),
      child: Column(
        crossAxisAlignment: alignEnd
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 10, color: ConeColors.textMuted),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            alignment: alignEnd ? WrapAlignment.end : WrapAlignment.start,
            children: [
              for (var i = 0; i < items.length; i++)
                // Dropping onto a button inserts before it.
                DragTarget<_Drag>(
                  onAcceptWithDetails: (d) => _drop(d.data, zone, i),
                  builder: (context, c, _) => Container(
                    padding: EdgeInsets.only(left: c.isNotEmpty ? 14 : 0),
                    child: _chip(items[i], zone),
                  ),
                ),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _chip(ControlId id, String from) {
    final chip = Material(
      color: from == 'palette' ? ConeColors.surfaceHigh : ConeColors.surface,
      borderRadius: BorderRadius.circular(ConeRadius.sm),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(ConeRadius.sm),
          border: Border.all(color: ConeColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(id.icon, size: 16, color: ConeColors.text),
            const SizedBox(width: 6),
            Text(id.label, style: const TextStyle(fontSize: 12)),
            if (from != 'palette') ...[
              const SizedBox(width: 4),
              InkWell(
                onTap: () => _drop(_Drag(id, from), 'palette'),
                child: const Icon(
                  Icons.close,
                  size: 12,
                  color: ConeColors.textMuted,
                ),
              ),
            ],
          ],
        ),
      ),
    );
    return Draggable<_Drag>(
      key: ValueKey('chip-${id.name}'),
      data: _Drag(id, from),
      feedback: Opacity(opacity: 0.9, child: chip),
      childWhenDragging: Opacity(opacity: 0.3, child: chip),
      child: MouseRegion(cursor: SystemMouseCursors.grab, child: chip),
    );
  }

  Future<String?> _askName(BuildContext context) {
    final ctrl = TextEditingController(text: 'My layout');
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Save layout as'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
