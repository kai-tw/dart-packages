import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:dart_lints/src/lint_rule_base.dart';
import 'package:dart_lints/src/rules/novelglide/novelglide_analytics_param_namespace.dart';
import 'package:test/test.dart';

/// Wraps [params] in the freezed canonical-constructor shape the rule reads.
String _event(String className, String params) =>
    '''
@Freezed(toJson: true, fromJson: true)
abstract class $className with _\$$className {
  const factory $className({
$params
  }) = _$className;

  factory $className.from({required Object kind}) =>
      $className(kind: kind.toString());

  factory $className.fromJson(Map<String, dynamic> json) =>
      _\$${className}FromJson(json);
}
''';

/// Runs the rule over a set of `path -> source` event files.
List<LintViolation> _lint(Map<String, String> files) {
  final List<ProjectUnit> units = <ProjectUnit>[];
  for (final MapEntry<String, String> entry in files.entries) {
    final ParseStringResult result = parseString(
      content: entry.value,
      throwIfDiagnostics: false,
    );
    units.add(ProjectUnit(entry.key, result.unit, result.lineInfo));
  }
  return NovelglideAnalyticsParamNamespace().run(units);
}

const String _dir = 'lib/core/analytics/events';

void main() {
  group('unqualified wire keys (technique: equivalence partitioning on the '
      'key-prefix classes)', () {
    test('TC-APN-1: a bare noun any feature could claim is flagged', () {
      final List<LintViolation> found = _lint(<String, String>{
        '$_dir/trash_notice_shown_event.dart': _event(
          'TrashNoticeShownEvent',
          "    @JsonKey(name: 'kind') required String kind,",
        ),
      });

      expect(found, hasLength(1));
      expect(found.single.message, contains('`kind` is not feature-qualified'));
      expect(
        found.single.ruleName,
        equals('novelglide_analytics_param_namespace'),
      );
    });

    test('TC-APN-2: the same key with its namespace passes', () {
      expect(
        _lint(<String, String>{
          '$_dir/trash_notice_shown_event.dart': _event(
            'TrashNoticeShownEvent',
            "    @JsonKey(name: 'trash_entry_kind') required String kind,",
          ),
        }),
        isEmpty,
      );
    });

    test('TC-APN-3 [boundary]: a key equal to the bare namespace, with no '
        'separator, does not count as prefixed', () {
      expect(
        _lint(<String, String>{
          '$_dir/trash_notice_shown_event.dart': _event(
            'TrashNoticeShownEvent',
            "    @JsonKey(name: 'trash') required String kind,",
          ),
        }),
        hasLength(1),
      );
    });

    test('TC-APN-4 [error guessing]: a namespace-shaped prefix that is not a '
        'declared namespace is still unqualified', () {
      expect(
        _lint(<String, String>{
          '$_dir/trash_notice_shown_event.dart': _event(
            'TrashNoticeShownEvent',
            "    @JsonKey(name: 'rubbish_entry_kind') required String kind,",
          ),
        }),
        hasLength(1),
      );
    });
  });

  group('missing @JsonKey (technique: FMEA-lite — the annotation is the only '
      'thing naming the wire key)', () {
    test('TC-APN-5: a parameter with no @JsonKey is flagged, because '
        'json_serializable then ships the Dart field name', () {
      final List<LintViolation> found = _lint(<String, String>{
        '$_dir/trash_retention_changed_event.dart': _event(
          'TrashRetentionChangedEvent',
          '    required String direction,',
        ),
      });

      expect(found, hasLength(1));
      expect(found.single.message, contains('has no @JsonKey'));
    });

    test('TC-APN-6: a @JsonKey without a `name:` argument is flagged the same '
        'way — the wire key is still the field name', () {
      expect(
        _lint(<String, String>{
          '$_dir/trash_retention_changed_event.dart': _event(
            'TrashRetentionChangedEvent',
            '    @JsonKey(includeIfNull: false) required String direction,',
          ),
        }),
        hasLength(1),
      );
    });
  });

  group('cross-family reuse (technique: state/graph — invisible per file, only '
      'the whole set shows it)', () {
    test('TC-APN-7: one key claimed by two unrelated families is flagged — the '
        'shipped `source` failure', () {
      final List<LintViolation> found = _lint(<String, String>{
        '$_dir/explore_catalog_opened_event.dart': _event(
          'ExploreCatalogOpenedEvent',
          "    @JsonKey(name: 'explore_source') required String source,",
        ),
        '$_dir/read_aloud_started_event.dart': _event(
          'ReadAloudStartedEvent',
          "    @JsonKey(name: 'explore_source') required String source,",
        ),
      });

      expect(found, hasLength(1));
      expect(found.single.message, contains('unrelated event families'));
      expect(found.single.message, contains('explore, read'));
    });

    test('TC-APN-8: one key shared across events of the SAME family is not '
        'flagged — that sharing is the point', () {
      expect(
        _lint(<String, String>{
          '$_dir/trash_notice_shown_event.dart': _event(
            'TrashNoticeShownEvent',
            "    @JsonKey(name: 'trash_entry_kind') required String kind,",
          ),
          '$_dir/trash_entry_purged_event.dart': _event(
            'TrashEntryPurgedEvent',
            "    @JsonKey(name: 'trash_entry_kind') required String kind,",
          ),
        }),
        isEmpty,
      );
    });

    test('TC-APN-9: an allowlisted shared key crosses families silently', () {
      expect(
        _lint(<String, String>{
          '$_dir/book_open_event.dart': _event(
            'BookOpenEvent',
            "    @JsonKey(name: 'book_id') required String bookId,",
          ),
          '$_dir/reading_session_event.dart': _event(
            'ReadingSessionEvent',
            "    @JsonKey(name: 'book_id') required String bookId,",
          ),
        }),
        isEmpty,
      );
    });
  });

  group('scope (technique: equivalence partitioning on file path / member '
      'kind)', () {
    test('TC-APN-10: a DTO outside the analytics events folder is not this '
        "rule's business", () {
      expect(
        _lint(<String, String>{
          'lib/features/trash/data/data_transfer_objects/trash_entry_dto.dart':
              _event(
                'TrashEntryDto',
                "    @JsonKey(name: 'kind') required String kind,",
              ),
        }),
        isEmpty,
      );
    });

    test('TC-APN-11 [mutation pin]: named factories are skipped — only the '
        'unnamed canonical constructor defines the wire shape', () {
      expect(
        _lint(<String, String>{
          '$_dir/trash_notice_shown_event.dart': '''
abstract class TrashNoticeShownEvent with _\$TrashNoticeShownEvent {
  factory TrashNoticeShownEvent.from({required String kind}) =>
      TrashNoticeShownEvent(kind: kind);
}
''',
        }),
        isEmpty,
      );
    });
  });
}
