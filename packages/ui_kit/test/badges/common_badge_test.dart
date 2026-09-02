import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';

/// Pumps [badge] and returns the [ColorScheme] it rendered with.
///
/// [badgeTheme] installs an ambient `BadgeTheme`, which is the configuration
/// callers were told to use before this widget grew its own parameters and is
/// therefore a live rung in the colour resolution, not a hypothetical.
Future<ColorScheme> _pump(
  WidgetTester tester,
  Widget badge, {
  BadgeThemeData? badgeTheme,
}) async {
  late ColorScheme colors;
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(badgeTheme: badgeTheme ?? const BadgeThemeData()),
      home: Builder(
        builder: (BuildContext context) {
          colors = Theme.of(context).colorScheme;
          return Scaffold(body: Center(child: badge));
        },
      ),
    ),
  );
  return colors;
}

/// The badge's rendered size.
///
/// ⚠️ **Measured, never read back off the `Badge` widget.** Two things go
/// wrong with reading arguments: `largeSize` is a *minimum*, so the number
/// asked for and the number drawn routinely differ; and Material's
/// `_IntrinsicHorizontalStadium` declares no `updateRenderObject`, so a
/// rebuilt labelled badge keeps its old size while the argument reports the
/// new one. Both make an argument assertion green on a badge that is visibly
/// the wrong size.
Size _markSize(WidgetTester tester) => tester.getSize(
  find.descendant(of: find.byType(Badge), matching: find.byType(Container)),
);

/// The badge's fill, off the rendered decoration rather than the argument.
Color? _markColor(WidgetTester tester) {
  final Container box = tester.widget<Container>(
    find.descendant(of: find.byType(Badge), matching: find.byType(Container)),
  );
  return (box.decoration! as ShapeDecoration).color;
}

Color? _labelInk(WidgetTester tester, IconData icon) =>
    IconTheme.of(tester.element(find.byIcon(icon))).color;

const Icon _host = Icon(Icons.person);

/// Sized to sit inside the badge rather than floor it — a default 24dp icon
/// would decide the badge's size itself and make every size assertion here
/// measure the icon.
const Icon _mark = Icon(Icons.priority_high, size: 10.0);

void main() {
  group('hidden', () {
    testWidgets('renders the child and no badge at all', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        const CommonBadge(type: CommonBadgeType.hidden, child: _host),
      );

      expect(find.byType(Badge), findsNothing);
      expect(find.byIcon(Icons.person), findsOneWidget);
    });

    testWidgets('renders nothing at all when there is no child either', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        const CommonBadge(type: CommonBadgeType.hidden, child: null),
      );

      expect(find.byType(Badge), findsNothing);
      expect(find.byType(SizedBox), findsWidgets);
    });
  });

  group('size', () {
    testWidgets('sizes the dot', (WidgetTester tester) async {
      await _pump(
        tester,
        const CommonBadge(
          type: CommonBadgeType.minimal,
          size: 12.0,
          child: _host,
        ),
      );

      expect(_markSize(tester), const Size(12.0, 12.0));
    });

    testWidgets('sizes a labelled badge whose label fits inside it', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        const CommonBadge(
          type: CommonBadgeType.normal,
          size: 18.0,
          padding: EdgeInsets.zero,
          label: _mark,
          child: _host,
        ),
      );

      expect(_markSize(tester), const Size(18.0, 18.0));
    });

    // The documented caveat, pinned so the doc cannot quietly become false:
    // `largeSize` reaches Material as an intrinsic stadium's `minSize`, so a
    // label bigger than `size` wins. A default 24dp icon renders a 24dp badge
    // however small a `size` is asked for.
    testWidgets('is a minimum for a labelled badge, not a diameter', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        const CommonBadge(
          type: CommonBadgeType.normal,
          size: 10.0,
          padding: EdgeInsets.zero,
          label: Icon(Icons.priority_high),
          child: _host,
        ),
      );

      expect(_markSize(tester).height, 24.0);
    });
  });

  group('colour', () {
    testWidgets('fills with backgroundColor', (WidgetTester tester) async {
      final ColorScheme colors = await _pump(
        tester,
        Builder(
          builder: (BuildContext context) => CommonBadge(
            type: CommonBadgeType.normal,
            backgroundColor: Theme.of(context).colorScheme.primary,
            label: const Text('3'),
            child: _host,
          ),
        ),
      );

      expect(_markColor(tester), colors.primary);
      expect(
        colors.primary,
        isNot(colors.error),
        reason: 'a role equal to the default would make this assertion inert',
      );
    });

    // The regression this widget exists to prevent: `Badge` puts its ink on a
    // DefaultTextStyle only, so an icon label inherits the surrounding tree's
    // icon colour and is drawn near-invisibly on the badge's fill.
    testWidgets('foregroundColor reaches an Icon label', (
      WidgetTester tester,
    ) async {
      final ColorScheme colors = await _pump(
        tester,
        Builder(
          builder: (BuildContext context) => CommonBadge(
            type: CommonBadgeType.normal,
            foregroundColor: Theme.of(context).colorScheme.primary,
            label: const Icon(Icons.priority_high),
            child: _host,
          ),
        ),
      );

      expect(_labelInk(tester, Icons.priority_high), colors.primary);
      expect(
        colors.primary,
        isNot(colors.onError),
        reason:
            'onError is the fallback; an equal role would hide a mutation '
            'that deleted the parameter entirely',
      );
    });

    // The rung between the two above. Skipping it makes a Text label take the
    // ambient BadgeTheme's colour while an Icon label takes onError — the two
    // kinds of label diverging, which is the whole defect being fixed.
    testWidgets('an Icon label follows an ambient BadgeTheme', (
      WidgetTester tester,
    ) async {
      // Read off a default theme before pumping, so the ambient BadgeTheme
      // carries a role rather than a literal and the assertion still says
      // which role it expects.
      final Color themed = ThemeData().colorScheme.primary;

      final ColorScheme colors = await _pump(
        tester,
        const CommonBadge(
          type: CommonBadgeType.normal,
          label: Icon(Icons.priority_high),
          child: _host,
        ),
        badgeTheme: BadgeThemeData(textColor: themed),
      );

      expect(_labelInk(tester, Icons.priority_high), themed);
      expect(
        themed,
        isNot(colors.onError),
        reason: 'equal to the fallback would make the theme rung untested',
      );
    });

    testWidgets('defaults an Icon label to onError', (
      WidgetTester tester,
    ) async {
      final ColorScheme colors = await _pump(
        tester,
        const CommonBadge(
          type: CommonBadgeType.normal,
          label: Icon(Icons.priority_high),
          child: _host,
        ),
      );

      expect(_labelInk(tester, Icons.priority_high), colors.onError);
    });
  });

  group('standalone', () {
    testWidgets('renders the mark with nothing behind it', (
      WidgetTester tester,
    ) async {
      await _pump(tester, const CommonBadge.standalone(label: _mark));

      expect(find.byType(Badge), findsOneWidget);
      expect(find.byIcon(Icons.person), findsNothing);
      expect(find.byIcon(Icons.priority_high), findsOneWidget);
    });

    testWidgets('takes the same size, colour and padding', (
      WidgetTester tester,
    ) async {
      final ColorScheme colors = await _pump(
        tester,
        Builder(
          builder: (BuildContext context) => CommonBadge.standalone(
            label: _mark,
            backgroundColor: Theme.of(context).colorScheme.primary,
            size: 18.0,
            padding: EdgeInsets.zero,
          ),
        ),
      );

      expect(_markColor(tester), colors.primary);
      expect(_markSize(tester), const Size(18.0, 18.0));
    });

    testWidgets('falls back to ! with no label, like the hosted form', (
      WidgetTester tester,
    ) async {
      await _pump(tester, const CommonBadge.standalone());

      expect(find.text('!'), findsOneWidget);
    });

    // The only route to a standalone DOT — `.standalone` fixes type to
    // `normal`, so it always carries a label or the `!` fallback.
    testWidgets('a childless minimal badge is the standalone dot', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        const CommonBadge(
          type: CommonBadgeType.minimal,
          size: 12.0,
          child: null,
        ),
      );

      expect(_markSize(tester), const Size(12.0, 12.0));
      expect(find.text('!'), findsNothing);
    });
  });
}
