import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';

Future<void> _pump(WidgetTester tester, Widget tile) =>
    tester.pumpWidget(MaterialApp(home: Scaffold(body: tile)));

/// Every public constructor, each built with the same badge configuration.
///
/// ⚠️ **The three exist as separate redirecting constructors with
/// hand-written argument lists**, so a parameter added to the tile is added
/// three times and can be forgotten twice. That is not hypothetical: the tile
/// accepted an `iconBadgeType` for its whole life while forwarding no label at
/// all, and a test covering one constructor would not have noticed. This table
/// is what makes the next such omission fail rather than ship.
final Map<String, Widget Function({Widget? badgeLabel})> _constructors =
    <String, Widget Function({Widget? badgeLabel})>{
      'none': ({Widget? badgeLabel}) => CommonNavTile.none(
        leading: const Icon(Icons.label),
        title: 'Tag',
        iconBadgeType: CommonBadgeType.normal,
        iconBadgeLabel: badgeLabel,
        onTap: () {},
      ),
      'internal': ({Widget? badgeLabel}) => CommonNavTile.internal(
        leading: const Icon(Icons.label),
        title: 'Tag',
        iconBadgeType: CommonBadgeType.normal,
        iconBadgeLabel: badgeLabel,
        onTap: () {},
      ),
      'external': ({Widget? badgeLabel}) => CommonNavTile.external(
        leading: const Icon(Icons.label),
        title: 'Tag',
        iconBadgeType: CommonBadgeType.normal,
        iconBadgeLabel: badgeLabel,
        onTap: () {},
      ),
    };

void main() {
  for (final MapEntry<String, Widget Function({Widget? badgeLabel})> entry
      in _constructors.entries) {
    group('CommonNavTile.${entry.key}', () {
      testWidgets('forwards iconBadgeLabel to the leading badge', (
        WidgetTester tester,
      ) async {
        await _pump(tester, entry.value(badgeLabel: const Text('7')));

        expect(find.text('7'), findsOneWidget);
        expect(find.text('!'), findsNothing);
      });

      testWidgets('falls back to ! when no label is given', (
        WidgetTester tester,
      ) async {
        await _pump(tester, entry.value());

        expect(find.text('!'), findsOneWidget);
      });
    });
  }

  testWidgets('hides the badge entirely when the type says so', (
    WidgetTester tester,
  ) async {
    await _pump(
      tester,
      CommonNavTile.internal(
        leading: const Icon(Icons.label),
        title: 'Tag',
        iconBadgeLabel: const Text('7'),
        onTap: () {},
      ),
    );

    // The negative control for the cases above: a label that is present but
    // unused must not reach the screen, or 「forwards the label」 would be
    // indistinguishable from 「renders the label unconditionally」.
    expect(find.text('7'), findsNothing);
    expect(find.byType(Badge), findsNothing);
  });

  // The trailing icon is the tile's whole reason for having three
  // constructors, and until now nothing asserted that any of them produced a
  // different one. Mutation confirmed it: every arm of the trailing switch
  // could be swapped for any other and the suite stayed green.
  group('trailing', () {
    testWidgets('.none renders neither icon', (WidgetTester tester) async {
      await _pump(tester, _constructors['none']!());

      expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
      expect(find.byIcon(Icons.open_in_new_rounded), findsNothing);
    });

    testWidgets('.internal renders a chevron', (WidgetTester tester) async {
      await _pump(tester, _constructors['internal']!());

      expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
      expect(find.byIcon(Icons.open_in_new_rounded), findsNothing);
    });

    testWidgets('.external renders an external-link icon', (
      WidgetTester tester,
    ) async {
      await _pump(tester, _constructors['external']!());

      expect(find.byIcon(Icons.open_in_new_rounded), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
    });
  });

  group('externalSemanticLabel', () {
    testWidgets('announces the icon when given', (WidgetTester tester) async {
      await _pump(
        tester,
        CommonNavTile.external(
          leading: const Icon(Icons.label),
          title: 'Docs',
          externalSemanticLabel: 'opens in browser',
          onTap: () {},
        ),
      );

      // Read off the `Semantics` widget rather than `bySemanticsLabel`, which
      // needs the semantics tree switched on — and matching the negative
      // case below, which can only be expressed this way.
      expect(
        find.ancestor(
          of: find.byIcon(Icons.open_in_new_rounded),
          matching: find.byWidgetPredicate(
            (Widget w) =>
                w is Semantics && w.properties.label == 'opens in browser',
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets('leaves the icon decorative when omitted', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        CommonNavTile.external(
          leading: const Icon(Icons.label),
          title: 'Docs',
          onTap: () {},
        ),
      );

      expect(
        find.byWidgetPredicate(
          (Widget w) => w is Semantics && w.properties.label != null,
        ),
        findsNothing,
      );
      expect(
        find.ancestor(
          of: find.byIcon(Icons.open_in_new_rounded),
          matching: find.byType(ExcludeSemantics),
        ),
        findsOneWidget,
      );
    });
  });

  group('padding', () {
    ListTile tileOf(WidgetTester tester) =>
        tester.widget<ListTile>(find.byType(ListTile));

    testWidgets('defaults to the tile’s own inset', (
      WidgetTester tester,
    ) async {
      await _pump(tester, _constructors['internal']!());

      expect(
        tileOf(tester).contentPadding,
        const EdgeInsets.symmetric(horizontal: 8.0, vertical: 0.0),
      );
    });

    testWidgets('takes the caller’s when given', (WidgetTester tester) async {
      await _pump(
        tester,
        CommonNavTile.internal(
          padding: const EdgeInsets.all(24.0),
          leading: const Icon(Icons.label),
          title: 'Tag',
          onTap: () {},
        ),
      );

      expect(tileOf(tester).contentPadding, const EdgeInsets.all(24.0));
    });
  });
}
