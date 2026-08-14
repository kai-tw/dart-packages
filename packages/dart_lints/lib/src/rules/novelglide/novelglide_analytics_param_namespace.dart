import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/source/line_info.dart';

import '../../lint_rule_base.dart';

/// Flags an analytics event wire parameter whose name is not feature-qualified,
/// or one that two unrelated event families both claim.
///
/// GA4 registers a custom dimension against the **parameter name**, globally
/// across the property, and a registered dimension can be archived but never
/// renamed or repointed. So two features that both send `source` are stuck
/// sharing one dimension, with one display name that can only describe one of
/// them — and nothing about that is fixable after the fact. The property
/// already carries the scar: `source` was registered as "Acquisition path"
/// while three of the four events sending it had nothing to do with acquisition.
///
/// Bad — a bare noun any future feature will also want:
/// ```dart
/// const factory TrashNoticeShownEvent({
///   @JsonKey(name: 'kind') required String kind,
/// }) = _TrashNoticeShownEvent;
/// ```
///
/// Good — the wire key carries the namespace, so the dimension can only ever
/// mean one thing:
/// ```dart
/// const factory TrashNoticeShownEvent({
///   @JsonKey(name: 'trash_entry_kind') required String kind,
/// }) = _TrashNoticeShownEvent;
/// ```
///
/// A missing `@JsonKey` is the same violation: json_serializable then emits the
/// Dart field name verbatim, which is how an unqualified key gets onto the wire
/// without anyone choosing it.
///
/// This is a [ProjectLintRule] because the cross-family half is invisible
/// per file — each event alone looks fine, and only the whole set shows two of
/// them claiming one key. A scoped run over one changed file still catches the
/// unqualified-name half; the full-tree run
/// (`dart run novel_glide_lints lib`) is authoritative for both.
class NovelglideAnalyticsParamNamespace extends ProjectLintRule {
  /// Namespace prefixes a wire key may claim. Each names a feature or a
  /// sub-domain large enough to own dimensions of its own. Adding one is a
  /// deliberate act: it widens what every future event may be called.
  static const Set<String> _namespaces = <String>{
    'book',
    'cloud_sync',
    'explore',
    'preference',
    'read_aloud',
    'reader',
    'tip_jar',
    'toc',
    'translation',
    'trash',
  };

  /// Keys that mean the identical thing to every event that sends them, and so
  /// are deliberately one shared GA4 dimension rather than one per feature.
  /// Everything here has to survive the question "would a reader of this
  /// dimension, with no event filter applied, be misled?".
  static const Set<String> _sharedKeys = <String>{
    // The book a behavioural event is about — same UUID, same meaning, whether
    // the event came from the reader, the shelf, or a sync path.
    'book_id',
  };

  static const String _eventsDir = '/core/analytics/events/';

  @override
  String get name => 'novelglide_analytics_param_namespace';

  @override
  String get description =>
      'Analytics wire parameter names must carry their feature namespace; a '
      'GA4 custom dimension is registered per parameter name and can never be '
      'renamed.';

  @override
  bool shouldCollect(String relativePath, String source) =>
      relativePath.contains(_eventsDir);

  @override
  List<LintViolation> run(List<ProjectUnit> units) {
    final List<LintViolation> violations = <LintViolation>[];
    final Map<String, Set<String>> familiesByKey = <String, Set<String>>{};
    final Map<String, _Site> firstSiteByKey = <String, _Site>{};

    for (final ProjectUnit pu in units) {
      if (!_isEventFile(pu.filePath)) {
        continue;
      }
      final String family = _familyOf(pu.filePath);

      final _ParamVisitor visitor = _ParamVisitor();
      pu.unit.accept(visitor);

      for (final _Param param in visitor.params) {
        // A parameter with no @JsonKey ships its Dart field name as the wire
        // key, so it is reported under the same rule rather than skipped.
        if (param.wireKey == null) {
          violations.add(
            _violation(
              pu,
              param.offset,
              'Analytics parameter `${param.fieldName}` has no '
              '@JsonKey(name: ...), so json_serializable will send the Dart '
              'field name as the wire key. Name it explicitly with a '
              'namespace prefix ($_namespaceHint).',
            ),
          );
          continue;
        }

        final String key = param.wireKey!;
        familiesByKey.putIfAbsent(key, () => <String>{}).add(family);
        firstSiteByKey.putIfAbsent(key, () => _Site(pu, param.offset));

        if (_namespaceOf(key) == null) {
          violations.add(
            _violation(
              pu,
              param.offset,
              'Analytics wire key `$key` is not feature-qualified. A GA4 '
              'custom dimension is registered against the parameter name '
              'globally and can never be renamed, so an unqualified name is '
              'permanently shared with whichever feature reaches for it next. '
              'Prefix it ($_namespaceHint).',
            ),
          );
        }
      }
    }

    // Cross-family reuse: one key claimed by events whose names belong to
    // different families is the `source` failure, and it is only visible here.
    for (final MapEntry<String, Set<String>> entry in familiesByKey.entries) {
      if (entry.value.length < 2 || _sharedKeys.contains(entry.key)) {
        continue;
      }
      final _Site site = firstSiteByKey[entry.key]!;
      final List<String> families = entry.value.toList()..sort();
      violations.add(
        _violation(
          site.unit,
          site.offset,
          'Analytics wire key `${entry.key}` is sent by unrelated event '
          'families (${families.join(', ')}). They share one GA4 dimension '
          'with one display name, which can only describe one of them. Give '
          'each family its own key, or — if the value means the identical '
          'thing everywhere — add it to '
          'AnalyticsParamNamespace._sharedKeys with the reason.',
        ),
      );
    }

    return violations;
  }

  static String get _namespaceHint {
    final List<String> sorted = _namespaces.toList()..sort();
    return 'one of: ${sorted.join(', ')}';
  }

  static bool _isEventFile(String path) =>
      path.contains(_eventsDir) && path.endsWith('_event.dart');

  /// The event family a file belongs to — the first token of the event's wire
  /// name, which is also the first segment of its filename. Two events share a
  /// family when they share that token (`trash_notice_shown` and
  /// `trash_entry_purged` are both `trash`).
  static String _familyOf(String path) {
    final String base = path.split('/').last;
    return base.split('_').first;
  }

  static String? _namespaceOf(String key) {
    for (final String ns in _namespaces) {
      if (key.startsWith('${ns}_')) {
        return ns;
      }
    }
    return null;
  }

  LintViolation _violation(ProjectUnit unit, int offset, String message) {
    final CharacterLocation location = unit.lineInfo.getLocation(offset);
    return LintViolation(
      ruleName: name,
      message: message,
      filePath: unit.filePath,
      line: location.lineNumber,
      column: location.columnNumber,
    );
  }
}

class _Site {
  const _Site(this.unit, this.offset);

  final ProjectUnit unit;
  final int offset;
}

class _Param {
  const _Param({
    required this.fieldName,
    required this.wireKey,
    required this.offset,
  });

  final String fieldName;

  /// The `@JsonKey(name: ...)` value, or `null` when the parameter carries no
  /// such annotation (or one whose name is not a plain string literal).
  final String? wireKey;

  final int offset;
}

/// Collects the parameters of a freezed canonical constructor — the unnamed
/// `const factory X({...}) = _X;` that owns the wire shape. Named factories
/// (`.from`, `.fromJson`) take domain types and never reach the wire.
class _ParamVisitor extends RecursiveAstVisitor<void> {
  final List<_Param> params = <_Param>[];

  @override
  void visitConstructorDeclaration(ConstructorDeclaration node) {
    final bool isCanonical =
        node.factoryKeyword != null &&
        node.redirectedConstructor != null &&
        node.name == null;
    if (!isCanonical) {
      return;
    }

    for (final FormalParameter parameter in node.parameters.parameters) {
      final String? fieldName = parameter.name?.lexeme;
      if (fieldName == null) {
        continue;
      }
      params.add(
        _Param(
          fieldName: fieldName,
          wireKey: _jsonKeyName(parameter.metadata),
          offset: parameter.offset,
        ),
      );
    }
  }

  static String? _jsonKeyName(NodeList<Annotation> metadata) {
    for (final Annotation annotation in metadata) {
      if (annotation.name.name != 'JsonKey') {
        continue;
      }
      for (final Expression argument
          in annotation.arguments?.arguments ?? const <Expression>[]) {
        if (argument is! NamedExpression ||
            argument.name.label.name != 'name') {
          continue;
        }
        final Expression value = argument.expression;
        if (value is SimpleStringLiteral) {
          return value.value;
        }
      }
    }
    return null;
  }
}
