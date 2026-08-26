import 'package:flutter/material.dart';

/// A step counter for a short, fixed-length wizard: a text [label] above
/// [total] short pills, filled solid through [current] and faint after it.
///
/// Built for a stepper whose length is known ahead of time — an onboarding
/// guide, a short setup flow — not a determinate download or upload, which
/// wants a continuous [LinearProgressIndicator] instead. A continuous bar
/// reads as progress toward an unstated number; discrete segments read as
/// "N steps, here is which one" at a glance, and [label] is the same fact in
/// words for whoever needs it that way.
///
/// **[label] carries the whole sentence** ("Step 2 of 4", 「第 2 步，共 4
/// 步」, …) — this package ships no built-in copy (see the README's Text
/// ownership section), so wording and pluralisation are the caller's.
///
/// Sizes itself to its own compact width rather than stretching to fill the
/// parent. Placed under a wider container — an app bar's `bottom`, a
/// `Column` with no `crossAxisAlignment: stretch` — the container's own
/// default centring is what centres it; this widget does not claim the full
/// width for itself the way a determinate progress bar would.
class CommonStepIndicator extends StatelessWidget {
  const CommonStepIndicator({
    super.key,
    required this.label,
    required this.current,
    required this.total,
  });

  /// The full sentence shown above the segments.
  final String label;

  /// Zero-based index of the step now on screen.
  final int current;

  /// How many steps the flow has in total.
  final int total;

  static const double _segmentWidth = 32.0;
  static const double _segmentHeight = 4.0;
  static const double _segmentGap = 8.0;
  static const double _labelGap = 8.0;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.labelLarge?.copyWith(color: colors.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: _labelGap),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (int i = 0; i < total; i++) ...<Widget>[
              if (i > 0) const SizedBox(width: _segmentGap),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: i <= current
                      ? colors.primary
                      : colors.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(_segmentHeight),
                ),
                child: const SizedBox(
                  width: _segmentWidth,
                  height: _segmentHeight,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}
