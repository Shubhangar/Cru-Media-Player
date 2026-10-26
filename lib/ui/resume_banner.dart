import 'package:flutter/material.dart';

import '../library/library_store.dart';
import '../player/player_controller.dart';
import '../theme.dart';

/// "Resume from 12:34?" prompt shown near the controls when an unfinished
/// file opens. Dismisses itself after [timeout].
class ResumeBanner extends StatefulWidget {
  final HistoryEntry entry;
  final VoidCallback onResume, onDismiss;
  final Duration timeout;
  const ResumeBanner({
    super.key,
    required this.entry,
    required this.onResume,
    required this.onDismiss,
    this.timeout = const Duration(seconds: 10),
  });

  @override
  State<ResumeBanner> createState() => _ResumeBannerState();
}

class _ResumeBannerState extends State<ResumeBanner>
    with SingleTickerProviderStateMixin {
  late final _countdown =
      AnimationController(vsync: this, duration: widget.timeout)
        ..forward().whenComplete(() {
          if (mounted) widget.onDismiss();
        });

  @override
  void dispose() {
    _countdown.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final at = formatDuration(Duration(milliseconds: widget.entry.positionMs));
    return Material(
      color: ConeColors.surface.withValues(alpha: 0.97),
      elevation: 8,
      shadowColor: Colors.black,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ConeRadius.lg),
        side: BorderSide(color: ConeColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
              child: Row(
                children: [
                  Icon(Icons.history, color: ConeColors.accent),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Resume from $at?',
                          style: const TextStyle(
                            color: ConeColors.text,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          '${(widget.entry.progress * 100).round()}% watched'
                          '  ·  Enter to resume, Esc to dismiss',
                          style: const TextStyle(
                            color: ConeColors.textMuted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: widget.onDismiss,
                    child: const Text(
                      'Start over',
                      style: TextStyle(color: ConeColors.textMuted),
                    ),
                  ),
                  const SizedBox(width: 4),
                  FilledButton(
                    onPressed: widget.onResume,
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(ConeRadius.md),
                      ),
                    ),
                    child: const Text('Resume'),
                  ),
                ],
              ),
            ),
            AnimatedBuilder(
              animation: _countdown,
              builder: (_, _) => LinearProgressIndicator(
                value: 1 - _countdown.value,
                minHeight: 2,
                backgroundColor: Colors.transparent,
                color: ConeColors.accent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
