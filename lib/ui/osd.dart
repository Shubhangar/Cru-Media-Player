import 'dart:async';

import 'package:flutter/material.dart';

import '../player/player_controller.dart';
import '../theme.dart';

/// On-screen display: shows the executed action and the key that did it.
class Osd extends StatefulWidget {
  final Stream<OsdMessage> messages;
  final bool enabled;
  final int durationMs;
  const Osd({
    super.key,
    required this.messages,
    this.enabled = true,
    this.durationMs = 1300,
  });

  @override
  State<Osd> createState() => _OsdState();
}

class _OsdState extends State<Osd> {
  OsdMessage? _msg;
  bool _visible = false;
  Timer? _timer;
  late final StreamSubscription<OsdMessage> _sub;

  @override
  void initState() {
    super.initState();
    _sub = widget.messages.listen((m) {
      if (!widget.enabled) return;
      _timer?.cancel();
      setState(() {
        _msg = m;
        _visible = true;
      });
      _timer = Timer(
        Duration(milliseconds: widget.durationMs),
        () => mounted ? setState(() => _visible = false) : null,
      );
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _sub.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = _msg;
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: _visible ? 1 : 0,
        duration: const Duration(milliseconds: 160),
        child: m == null
            ? const SizedBox.shrink()
            : Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: ConeColors.surface.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(ConeRadius.md),
                  border: Border.all(color: ConeColors.border),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 3,
                      height: 18,
                      margin: const EdgeInsets.only(right: 10),
                      color: ConeColors.accent,
                    ),
                    Text(
                      m.action,
                      style: const TextStyle(
                        color: ConeColors.text,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (m.shortcut != null) ...[
                      const SizedBox(width: 12),
                      KeyChip(m.shortcut!),
                    ],
                  ],
                ),
              ),
      ),
    );
  }
}

class KeyChip extends StatelessWidget {
  final String label;
  const KeyChip(this.label, {super.key});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: ConeColors.canvas,
      borderRadius: BorderRadius.circular(ConeRadius.sm),
      border: Border.all(color: ConeColors.border),
    ),
    child: Text(
      label,
      style: TextStyle(
        color: ConeColors.accent,
        fontSize: 12,
        fontFamily: 'monospace',
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}
