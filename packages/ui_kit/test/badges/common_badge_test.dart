import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';

/// Pumps what [build] returns and hands back the [ColorScheme] it rendered
/// with.
///
/// [build] receives that scheme so a test can pass a *role* into the widget
/// and then assert the same role came out the other side. Asserting against a
/// colour literal would pin the test to a value the theme is free to change,
/// and would say nothing about whether the parameter was forwarded.
Future<ColorScheme> _pump(
  WidgetTester tester,
  Widget Function(ColorScheme colors) build,
) async {
  late ColorScheme colors;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (BuildContext context) {
          colors = Theme.of(context).colorScheme;
          return Scaffold(body: Center(child: build(colors)));
        },
      ),
    ),
  );
  return colors;
}

Badge _badge(WidgetTester tester) => tester.widget<Badge>(find.byType(Badge));

IconThemeData _labelIconTheme(WidgetTester tester) =>
    IconTheme.of(tester.element(find.byIcon(Icons.priority_high)));

const Icon _host = Icon(Icons.person);

void main() {
  group('hidden', () {
    testWidgets('renders the child and no badge at all', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        (ColorScheme colors) =>
            const CommonBadge(type: CommonBadgeType.hidden, child: _host),
      );

      expect(find.byType(Badge), findsNothing);
      expect(find.byIcon(Icons.person), findsOneWidget);
    });
  });

  group('size', () {
    testWidgets('drives smallSize for a dot and leaves largeSize alone', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        (ColorScheme colors) => const CommonBadge(
          type: CommonBadgeType.minimal,
          size: 12.0,
          child: _host,
        ),
      );

      expect(_badge(tester).smallSize, 12.0);
      expect(_badge(tester).largeSize, isNull);
    });

    testWidgets(
      'drives largeSize for a labelled badge and leaves smallSize alone',
      (WidgetTester tester) async {
        await _pump(
          tester,
          (ColorScheme colors) => const CommonBadge(
            type: CommonBadgeType.normal,
            size: 18.0,
            label: Text('3'),
            child: _host,
          ),
        );

        expect(_badge(tester).largeSize, 18.0);
        expect(_badge(tester).smallSize, isNull);
      },
    );
  });

  group('colour', () {
    testWidgets('forwards background and foreground', (
      WidgetTester tester,
    ) async {
      final ColorScheme colors = await _pump(
        tester,
        (ColorScheme colors) => CommonBadge(
          type: CommonBadgeType.normal,
          backgroundColor: colors.tertiary,
          foregroundColor: colors.onTertiary,
          label: const Text('3'),
          child: _host,
        ),
      );

      expect(_badge(tester).backgroundColor, colors.tertiary);
      expect(_badge(tester).textColor, colors.onTertiary);
    });

    // The regression this widget exists to prevent: `Badge` puts its text
    // colour on a DefaultTextStyle only, so an icon label inherits the
    // surrounding tree's icon colour and is drawn near-invisibly on the
    // badge's saturated fill. Nothing errors; the glyph is simply wrong.
    testWidgets('reaches an Icon label, which Badge alone does not', (
      WidgetTester tester,
    ) async {
      final ColorScheme colors = await _pump(
        tester,
        (ColorScheme colors) => CommonBadge(
          type: CommonBadgeType.normal,
          foregroundColor: colors.onTertiary,
          label: const Icon(Icons.priority_high),
          child: _host,
        ),
      );

      expect(_labelIconTheme(tester).color, colors.onTertiary);
    });

    testWidgets('defaults an Icon label to onError', (
      WidgetTester tester,
    ) async {
      final ColorScheme colors = await _pump(
        tester,
        (ColorScheme colors) => const CommonBadge(
          type: CommonBadgeType.normal,
          label: Icon(Icons.priority_high),
          child: _host,
        ),
      );

      expect(_labelIconTheme(tester).color, colors.onError);
    });
  });

  group('standalone', () {
    testWidgets('renders the mark with nothing behind it', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        (ColorScheme colors) =>
            const CommonBadge.standalone(label: Icon(Icons.priority_high)),
      );

      expect(find.byType(Badge), findsOneWidget);
      expect(_badge(tester).child, isNull);
      expect(find.byIcon(Icons.priority_high), findsOneWidget);
    });

    testWidgets('takes the same size, colour and padding', (
      WidgetTester tester,
    ) async {
      final ColorScheme colors = await _pump(
        tester,
        (ColorScheme colors) => CommonBadge.standalone(
          label: const Icon(Icons.priority_high),
          backgroundColor: colors.tertiary,
          size: 18.0,
          padding: EdgeInsets.zero,
        ),
      );

      expect(_badge(tester).backgroundColor, colors.tertiary);
      expect(_badge(tester).largeSize, 18.0);
      expect(_badge(tester).padding, EdgeInsets.zero);
    });
  });

  group('CommonNavTile', () {
    testWidgets('forwards iconBadgeLabel to the leading badge', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        (ColorScheme colors) => CommonNavTile.internal(
          leading: const Icon(Icons.label),
          title: 'Tag',
          iconBadgeType: CommonBadgeType.normal,
          iconBadgeLabel: const Text('7'),
          onTap: () {},
        ),
      );

      expect(find.text('7'), findsOneWidget);
      expect(find.text('!'), findsNothing);
    });

    testWidgets('still falls back to ! when no label is given', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        (ColorScheme colors) => CommonNavTile.internal(
          leading: const Icon(Icons.label),
          title: 'Tag',
          iconBadgeType: CommonBadgeType.normal,
          onTap: () {},
        ),
      );

      expect(find.text('!'), findsOneWidget);
    });
  });
}
