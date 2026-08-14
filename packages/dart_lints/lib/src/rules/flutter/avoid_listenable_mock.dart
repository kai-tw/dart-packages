import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';

import '../../lint_rule_base.dart';

/// Warns when a `class _MockX extends Mock implements Y` declaration has `Y`
/// either inheriting listenable machinery (Prong A) or exposing a `Stream` /
/// `StreamController` / `Sink` (Prong B). Excluded only from `Zone.production`
/// in `runner.dart` — mock classes have no reason to exist in shipped code,
/// but `tool/`'s design-mockup and screenshot harnesses use `mocktail` too, so
/// this rule does not scope itself to a single directory.
///
/// **Prong A** — `Mock implements <ChangeNotifier subclass>` leaks RSS
/// unboundedly because the proxy inherits notifier internals that are
/// never disposed when the test ends.
///
/// **Prong B** — `Mock implements <Stream-exposing seam>` doesn't leak
/// but stubs the getter without exercising real subscription behavior.
/// Use a hand-written fake backed by a real `StreamController` instead.
class AvoidListenableMock extends ResolvedLintRule {
  AvoidListenableMock({String? mockBase, List<String>? listenableTypes})
    : mockBase = mockBase ?? 'Mock',
      listenableTypes =
          listenableTypes ??
          const <String>[
            'ChangeNotifier',
            'Listenable',
            'ValueNotifier',
            'ValueListenable',
            'Animation',
            'AnimationController',
            'TickerProvider',
            'Stream',
          ];

  /// The mocking library's base class. Named because which library a project
  /// mocks with is the project's choice.
  final String mockBase;

  /// Supertypes whose machinery a mock cannot honestly stand in for.
  final List<String> listenableTypes;

  @override
  String get name => 'avoid_listenable_mock';

  @override
  String get description =>
      'In tests, do not Mock implements a listenable / stream-exposing '
      'type — see testing.md Rule 3 (Prong A & Prong B).';

  @override
  ResolvedLintVisitor createResolvedVisitor(
    String filePath,
    ResolvedUnitResult resolvedUnit,
  ) => _Visitor(filePath, resolvedUnit, mockBase, listenableTypes);
}

class _Visitor extends ResolvedLintVisitor {
  _Visitor(
    super.filePath,
    super.resolvedUnit,
    this.mockBase,
    this.listenableTypes,
  );

  final String mockBase;
  final List<String> listenableTypes;

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    if (!_extendsMock(node)) {
      return;
    }
    final ImplementsClause? implements_ = node.implementsClause;
    if (implements_ == null) {
      return;
    }
    for (final NamedType impl in implements_.interfaces) {
      final InterfaceType? type = _interfaceType(impl);
      if (type == null) {
        continue;
      }
      final String? prong = _classifyProng(type);
      if (prong != null) {
        report(
          ruleName: 'avoid_listenable_mock',
          message:
              '${node.name.lexeme} mocks ${impl.name.lexeme} which $prong. '
              'Rewrite the seam (callbacks / narrow interface) or use a '
              'hand-written fake backed by a real StreamController.',
          offset: impl.name.charOffset,
        );
      }
    }
  }

  bool _extendsMock(ClassDeclaration node) {
    final ExtendsClause? extends_ = node.extendsClause;
    return extends_ != null && extends_.superclass.name.lexeme == mockBase;
  }

  InterfaceType? _interfaceType(NamedType node) {
    final DartType? type = node.type;
    if (type is InterfaceType) {
      return type;
    }
    return null;
  }

  /// Returns a short prong description if [type] violates Prong A or B,
  /// else null.
  String? _classifyProng(InterfaceType type) {
    final List<InterfaceType> chain = <InterfaceType>[
      type,
      ...type.allSupertypes,
    ];

    for (final InterfaceType t in chain) {
      if (listenableTypes.contains(t.element.name)) {
        return 'inherits listenable / stream machinery (Prong A)';
      }
    }

    // Prong B: any public Stream/StreamController/Sink field/getter.
    for (final InterfaceType t in chain) {
      if (_hasStreamMember(t)) {
        return 'exposes a Stream / StreamController / Sink (Prong B)';
      }
    }
    return null;
  }

  bool _hasStreamMember(InterfaceType type) {
    final InterfaceElement element = type.element;
    for (final GetterElement g in element.getters) {
      if (_isPublic(g.name) && _isStreamLike(g.returnType)) {
        return true;
      }
    }
    for (final FieldElement f in element.fields) {
      if (_isPublic(f.name) && _isStreamLike(f.type)) {
        return true;
      }
    }
    return false;
  }

  bool _isPublic(String? name) =>
      name != null && name.isNotEmpty && !name.startsWith('_');

  bool _isStreamLike(DartType type) {
    if (type is! InterfaceType) {
      return false;
    }
    const Set<String> names = <String>{
      'Stream',
      'StreamController',
      'Sink',
      'StreamSink',
    };
    return names.contains(type.element.name);
  }
}
