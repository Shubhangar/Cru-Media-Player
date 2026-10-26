import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import '../theme.dart';

/// Small header shown inside flyouts and menus.
class FlyoutHeader extends StatelessWidget {
  final String text;
  const FlyoutHeader(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
    child: Text(
      text.toUpperCase(),
      style: const TextStyle(
        fontSize: 11,
        letterSpacing: 0.8,
        fontWeight: FontWeight.w600,
        color: ConeColors.textMuted,
      ),
    ),
  );
}

/// A selectable row with an orange check when active.
class FlyoutItem extends StatelessWidget {
  final String label;
  final String? detail;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  const FlyoutItem({
    super.key,
    required this.label,
    required this.onTap,
    this.detail,
    this.selected = false,
    this.icon,
  });

  @override
  Widget build(BuildContext context) => MenuItemButton(
    onPressed: onTap,
    leadingIcon: SizedBox(
      width: 20,
      child: selected
          ? const Icon(Icons.check, size: 18, color: ConeColors.accent)
          : (icon != null
                ? Icon(icon, size: 18, color: ConeColors.textMuted)
                : null),
    ),
    trailingIcon: detail == null
        ? null
        : Text(
            detail!,
            style: const TextStyle(fontSize: 11, color: ConeColors.textMuted),
          ),
    child: ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 200, maxWidth: 320),
      child: Text(
        label,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: selected ? ConeColors.accent : ConeColors.text,
          fontSize: 13,
        ),
      ),
    ),
  );
}

final menuStyle = MenuStyle(
  backgroundColor: const WidgetStatePropertyAll(ConeColors.surface),
  side: const WidgetStatePropertyAll(BorderSide(color: ConeColors.border)),
  shape: WidgetStatePropertyAll(
    RoundedRectangleBorder(borderRadius: BorderRadius.circular(ConeRadius.lg)),
  ),
  padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: 6)),
);

/// Tracks open menus so Escape can close them even though keyboard focus
/// stays on the player.
class OpenMenus {
  static final Set<MenuController> _open = {};
  static void opened(MenuController c) => _open.add(c);
  static void closed(MenuController c) => _open.remove(c);

  /// Closes every open menu; returns whether any was open.
  static bool closeAll() {
    if (_open.isEmpty) return false;
    for (final c in _open.toList()) {
      c.close();
    }
    _open.clear();
    return true;
  }
}

/// [MenuAnchor] that registers itself with [OpenMenus].
class TrackedMenuAnchor extends StatefulWidget {
  final List<Widget> menuChildren;
  final MenuAnchorChildBuilder? builder;
  final Widget? child;
  final MenuController? controller;
  final Offset? alignmentOffset;
  const TrackedMenuAnchor({
    super.key,
    required this.menuChildren,
    this.builder,
    this.child,
    this.controller,
    this.alignmentOffset,
  });

  @override
  State<TrackedMenuAnchor> createState() => _TrackedMenuAnchorState();
}

class _TrackedMenuAnchorState extends State<TrackedMenuAnchor> {
  late final MenuController _ctrl = widget.controller ?? MenuController();

  @override
  void dispose() {
    OpenMenus.closed(_ctrl);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MenuAnchor(
    controller: _ctrl,
    style: menuStyle,
    alignmentOffset: widget.alignmentOffset,
    onOpen: () => OpenMenus.opened(_ctrl),
    onClose: () => OpenMenus.closed(_ctrl),
    menuChildren: widget.menuChildren,
    builder: widget.builder,
    child: widget.child,
  );
}

/// Icon button that opens an anchored flyout on a single click.
class FlyoutButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final List<Widget> Function() builder;
  final bool active;
  const FlyoutButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.builder,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) => TrackedMenuAnchor(
    alignmentOffset: const Offset(0, 8),
    menuChildren: builder(),
    builder: (context, ctrl, _) => ControlIcon(
      icon: icon,
      tooltip: tooltip,
      active: active || ctrl.isOpen,
      onPressed: () => ctrl.isOpen ? ctrl.close() : ctrl.open(),
    ),
  );
}

/// Monochrome control icon used across the bars.
class ControlIcon extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool active;
  final double size;
  const ControlIcon({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.active = false,
    this.size = 22,
  });

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: IconButton(
      onPressed: onPressed,
      iconSize: size,
      color: active ? ConeColors.accent : ConeColors.text,
      hoverColor: ConeColors.surfaceHigh,
      style: IconButton.styleFrom(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ConeRadius.md),
        ),
      ),
      icon: Icon(icon),
    ),
  );
}

String trackLabel({String? title, String? language, required String id}) {
  final parts = [
    if (title != null && title.isNotEmpty) title,
    if (language != null && language.isNotEmpty) language.toUpperCase(),
  ];
  return parts.isEmpty ? 'Track $id' : parts.join(' · ');
}

List<Widget> subtitleFlyout({
  required Player player,
  required VoidCallback onLoadFile,
}) {
  final tracks = player.state.tracks.subtitle
      .where((t) => t.id != 'auto')
      .toList();
  final current = player.state.track.subtitle;
  return [
    const FlyoutHeader('Subtitles'),
    for (final t in tracks)
      FlyoutItem(
        label: t.id == 'no'
            ? 'Off'
            : trackLabel(title: t.title, language: t.language, id: t.id),
        detail: t.codec,
        selected: t.id == current.id,
        onTap: () => player.setSubtitleTrack(t),
      ),
    const Divider(height: 10, color: ConeColors.border),
    FlyoutItem(
      label: 'Load subtitle file…',
      icon: Icons.file_open_outlined,
      onTap: onLoadFile,
    ),
  ];
}

List<Widget> audioFlyout({required Player player}) {
  final tracks = player.state.tracks.audio
      .where((t) => t.id != 'auto')
      .toList();
  final current = player.state.track.audio;
  final devices = player.state.audioDevices;
  final device = player.state.audioDevice;
  return [
    const FlyoutHeader('Audio track'),
    for (final t in tracks)
      FlyoutItem(
        label: t.id == 'no'
            ? 'Disabled'
            : trackLabel(title: t.title, language: t.language, id: t.id),
        detail: [
          if (t.codec != null) t.codec!,
          if (t.channels != null) t.channels!,
        ].join(' '),
        selected: t.id == current.id,
        onTap: () => player.setAudioTrack(t),
      ),
    const Divider(height: 10, color: ConeColors.border),
    const FlyoutHeader('Output device'),
    for (final d in devices)
      FlyoutItem(
        label: d.name == 'auto'
            ? 'System default'
            : (d.description.isEmpty ? d.name : d.description),
        selected: d.name == device.name,
        icon: Icons.speaker_outlined,
        onTap: () => player.setAudioDevice(d),
      ),
  ];
}
