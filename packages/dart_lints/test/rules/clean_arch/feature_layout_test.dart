import 'package:dart_lints/src/rules/clean_arch/feature_layout.dart';
import 'package:test/test.dart';

void main() {
  group('FeatureLayout defaults', () {
    final FeatureLayout layout = FeatureLayout();

    test('resolves the three standard layers under lib/features', () {
      expect(layout.layerOf('lib/features/reader/domain/book.dart'), 'domain');
      expect(layout.layerOf('lib/features/reader/data/book_dto.dart'), 'data');
      expect(
        layout.layerOf('lib/features/reader/presentation/reader_page.dart'),
        'presentation',
      );
    });

    test('resolves a layer anywhere in the path, not only at the start', () {
      expect(
        layout.layerOf('/abs/path/lib/features/reader/domain/book.dart'),
        'domain',
      );
    });
  });

  group('paths the layout deliberately declines to classify', () {
    final FeatureLayout layout = FeatureLayout();

    // Pass-through is the load-bearing behaviour: real projects keep unlayered
    // folders beside layered ones, and a layout rule has nothing to say about a
    // file whose layer it cannot identify. Without this, a project mixing the
    // two styles could not adopt the clean_arch bundle at all.
    test('a feature directory that is not a layer resolves to null', () {
      expect(layout.layerOf('lib/features/note/models/note.dart'), isNull);
      expect(layout.layerOf('lib/features/tag/widgets/tag_chip.dart'), isNull);
      expect(
        layout.layerOf('lib/features/tag/notifiers/tag_notifier.dart'),
        isNull,
      );
    });

    test('directories outside any configured root resolve to null', () {
      expect(layout.layerOf('lib/core/http/client.dart'), isNull);
      expect(layout.layerOf('lib/shared/widgets/spacer.dart'), isNull);
    });

    test('a second layered root is NOT covered by the default config', () {
      expect(layout.layerOf('lib/modules/tag/domain/tag.dart'), isNull);
    });
  });

  group('multiple feature roots', () {
    final FeatureLayout layout = FeatureLayout(
      roots: <String>['lib/features', 'lib/modules'],
    );

    test('classifies both roots', () {
      expect(layout.layerOf('lib/features/task/domain/task.dart'), 'domain');
      expect(layout.layerOf('lib/modules/tag/domain/tag.dart'), 'domain');
    });

    test('a root with no presentation layer needs no separate config', () {
      // The layer list is a vocabulary, not a requirement: a root that simply
      // has no presentation directory produces no presentation files, so one
      // shared list serves roots of differing depth.
      expect(layout.layerOf('lib/modules/tag/data/tag_dao.dart'), 'data');
      expect(layout.layerOf('lib/modules/tag/models/tag_row.dart'), isNull);
    });
  });

  group('custom layer names', () {
    final FeatureLayout layout = FeatureLayout(
      roots: <String>['src/modules'],
      layers: <String>['core', 'ui'],
    );

    test('replaces the standard vocabulary rather than extending it', () {
      expect(layout.layerOf('src/modules/billing/ui/checkout.dart'), 'ui');
      expect(layout.layerOf('src/modules/billing/domain/plan.dart'), isNull);
    });
  });

  group('isIn', () {
    final FeatureLayout layout = FeatureLayout(
      roots: <String>['lib/features', 'lib/modules'],
    );

    test('matches a layer across every root', () {
      expect(
        layout.isIn('lib/features/task/domain/task.dart', 'domain'),
        isTrue,
      );
      expect(layout.isIn('lib/modules/tag/domain/tag.dart', 'domain'), isTrue);
      expect(
        layout.isIn('lib/features/task/data/task_dto.dart', 'domain'),
        isFalse,
      );
    });

    test('narrows to a subdirectory when asked', () {
      expect(
        layout.isIn(
          'lib/features/task/domain/exceptions/task_exception.dart',
          'domain',
          subdirectory: 'exceptions',
        ),
        isTrue,
      );
      expect(
        layout.isIn(
          'lib/features/task/domain/entities/task.dart',
          'domain',
          subdirectory: 'exceptions',
        ),
        isFalse,
      );
    });
  });

  group('regex-significant characters in configuration', () {
    test('a root containing them is matched literally, not as a pattern', () {
      final FeatureLayout layout = FeatureLayout(
        roots: <String>['lib/f+eatures'],
      );
      expect(layout.layerOf('lib/f+eatures/x/domain/y.dart'), 'domain');
      expect(layout.layerOf('lib/ffffeatures/x/domain/y.dart'), isNull);
    });
  });
}
