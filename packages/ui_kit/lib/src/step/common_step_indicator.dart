import 'package:flutter/material.dart';

/// A step counter for a short, fixed-length wizard: [total] short pills,
/// filled solid through [current] and faint after it.
///
/// Built for a stepper whose length is known ahead of time — an onboarding
/// guide, a short setup flow — not a determinate download or upload, which
/// wants a continuous [LinearProgressIndicator] instead. A continuous bar
/// reads as progress toward an unstated number; discrete segments read as
/// "N steps, here is which one" at a glance.
///
/// **Segments only — no label.** An earlier revision paired the pills with a
/// text sentence ("Step 2 of 4") in the same widget, which forced every
/// caller into one fixed layout: label directly above the segments, both
/// centred as a single block. The one real caller so far needed the label
/// somewhere else entirely — an app bar's `title`, centred against the whole
/// toolbar, with the segments on their own in `bottom` below it — and
/// nothing about a caller wanting the words positioned differently is
/// unusual enough to special-case. Composing this with your own `Text` costs
/// two lines; a widget that forces one fixed relationship between the two
/// costs a rewrite the moment a caller's layout does not match it.
///
/// Sizes itself to its own compact width rather than stretching to fill the
/// parent. Placed under a wider container — an app bar's `bottom`, a
/// `Column` with no `crossAxisAlignment: stretch` — the container's own
/// default centring is what centres it; this widget does not claim the full
/// width for itself the way a determinate progress bar would.
class CommonStepIndicator extends StatelessWidget {
  const CommonStepIndicator({
    super.key,
    required this.current,
    required this.total,
  });

  /// Zero-based index of the step now on screen.
  final int current;

  /// How many steps the flow has in total.
  final int total;

  static const double _segmentWidth = 32.0;
  static const double _segmentHeight = 4.0;
  static const double _segmentGap = 8.0;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;

    return Row(
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
            child: const SizedBox(width: _segmentWidth, height: _segmentHeight),
          ),
        ],
      ],
    );
  }
}
