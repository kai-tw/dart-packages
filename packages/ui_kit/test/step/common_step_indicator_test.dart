import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';

/// Pumps [CommonStepIndicator] and returns the [ColorScheme] it rendered
/// with, so a test can assert segment colours against the same roles the
/// widget itself reads rather than a colour literal that could drift from
/// the theme's actual values.
Future<ColorScheme> _pump(
  WidgetTester tester, {
  required int current,
  required int total,
}) async {
  late ColorScheme colors;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (BuildContext context) {
          colors = Theme.of(context).colorScheme;
          return CommonStepIndicator(current: current, total: total);
        },
      ),
    ),
  );
  return colors;
}

List<Color?> _segmentColors(WidgetTester tester) {
  return tester
      .widgetList<DecoratedBox>(find.byType(DecoratedBox))
      .map((DecoratedBox box) => (box.decoration as BoxDecoration).color)
      .toList();
}

void main() {
  testWidgets('renders one segment per total step', (
    WidgetTester tester,
  ) async {
    await _pump(tester, current: 1, total: 4);

    expect(find.byType(DecoratedBox), findsNWidgets(4));
  });

  testWidgets('fills segments through current and leaves the rest faint', (
    WidgetTester tester,
  ) async {
    final ColorScheme colors = await _pump(tester, current: 1, total: 4);

    expect(_segmentColors(tester), <Color?>[
      colors.primary,
      colors.primary,
      colors.surfaceContainerHighest,
      colors.surfaceContainerHighest,
    ]);
  });

  testWidgets('the first step fills exactly one segment', (
    WidgetTester tester,
  ) async {
    final ColorScheme colors = await _pump(tester, current: 0, total: 3);

    expect(_segmentColors(tester), <Color?>[
      colors.primary,
      colors.surfaceContainerHighest,
      colors.surfaceContainerHighest,
    ]);
  });

  testWidgets('the last step fills every segment', (WidgetTester tester) async {
    final ColorScheme colors = await _pump(tester, current: 2, total: 3);

    expect(_segmentColors(tester), <Color?>[
      colors.primary,
      colors.primary,
      colors.primary,
    ]);
  });
}
