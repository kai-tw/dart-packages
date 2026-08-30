import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/source/line_info.dart';

import '../../lint_rule_base.dart';

/// Flags circular dependencies in the GetIt (`sl`) registration graph.
///
/// Every `sl.registerXxx<T>(() => T(sl<A>(), sl<B>()))` declares that resolving
/// `T` first resolves `A` and `B`. If following those edges ever returns to `T`,
/// GetIt recurses forever and stack-overflows the first time the cycle is
/// resolved — a crash the per-file linter and `flutter analyze` cannot see
/// because the edges are spread across many `setup_dependencies.dart` files.
///
/// Only `sl<U>()` lookups evaluated **at construction time** count as edges —
/// the factory closure body itself. A lookup nested inside a *deeper* closure
/// (`onTap: () => sl<U>()`, a `.map((e) => sl<U>())` callback) is deferred, runs
/// after construction, and cannot stack-overflow resolution, so it is ignored.
///
/// Bad — `A` needs `B`, `B` needs `A`; resolving either crashes:
/// ```dart
/// sl.registerFactory<A>(() => A(sl<B>()));
/// sl.registerFactory<B>(() => B(sl<A>()));
/// ```
///
/// Good — break the cycle (invert one edge behind an interface, or have one
/// side resolve the other lazily through a callback rather than at construction).
///
/// This is a [ProjectLintRule]: the graph is only complete on a full-tree run
/// (`dart run dart_lints`). A scoped run over a single changed file
/// sees only that file's edges, so it may not surface a cross-feature cycle —
/// the full-tree run (CI / manual) is the authoritative gate.
class AvoidGetItDependencyCycle extends ProjectLintRule {
  AvoidGetItDependencyCycle({String? accessor}) : accessor = accessor ?? 'sl';

  /// The identifier a project resolves dependencies through. `sl` is one
  /// common alias; `getIt` and `GetIt.instance` are others, so the name is
  /// configuration rather than a constant.
  final String accessor;

  @override
  String get name => 'avoid_getit_dependency_cycle';

  @override
  String get description =>
      'Service-locator registrations must not form a dependency cycle; a cycle '
      'stack-overflows the first time it is resolved.';

  @override
  bool shouldCollect(String relativePath, String source) =>
      source.contains('$accessor.register');

  @override
  List<LintViolation> run(List<ProjectUnit> units) {
    // Build the construction-time dependency graph across every analyzed unit,
    // and remember where each type was registered so a cycle can be anchored.
    final Map<String, Set<String>> graph = <String, Set<String>>{};
    final Map<String, _Site> sites = <String, _Site>{};

    for (final ProjectUnit pu in units) {
      final _RegistrationVisitor visitor = _RegistrationVisitor(accessor);
      pu.unit.accept(visitor);

      for (final _Registration reg in visitor.registrations) {
        graph.putIfAbsent(reg.type, () => <String>{}).addAll(reg.deps);
        for (final String dep in reg.deps) {
          graph.putIfAbsent(dep, () => <String>{});
        }
        sites.putIfAbsent(
          reg.type,
          () => _Site(pu.filePath, pu.lineInfo.getLocation(reg.offset)),
        );
      }
    }

    // Each strongly-connected component with an internal edge is a cycle.
    final List<List<String>> cycles = _findCycles(graph);

    final List<LintViolation> violations = <LintViolation>[];
    for (final List<String> scc in cycles) {
      final String pathText = _cyclePath(scc, graph).join(' → ');

      // Anchor on every registration in the cycle that we actually parsed, so
      // a scoped run still flags the changed file's end of the cycle.
      for (final String type in scc) {
        final _Site? site = sites[type];
        if (site == null) {
          continue;
        }
        violations.add(
          LintViolation(
            ruleName: name,
            message:
                'GetIt dependency cycle: $pathText. Resolving any member '
                'recurses forever and stack-overflows. Break the cycle — invert '
                'one edge behind an interface, or resolve one side lazily after '
                'construction instead of injecting it in the factory.',
            filePath: site.filePath,
            line: site.location.lineNumber,
            column: site.location.columnNumber,
          ),
        );
      }
    }
    return violations;
  }
}

/// A single `sl.registerXxx<T>(...)` site: the registered type, the source
/// offset of the `register*` call, and the types resolved during construction.
class _Registration {
  _Registration(this.type, this.offset, this.deps);

  final String type;
  final int offset;
  final List<String> deps;
}

class _Site {
  _Site(this.filePath, this.location);

  final String filePath;
  final CharacterLocation location;
}

/// Collects every `sl.registerXxx<T>(...)` in a unit as a [_Registration].
class _RegistrationVisitor extends RecursiveAstVisitor<void> {
  _RegistrationVisitor(this.accessor);

  final String accessor;
  final List<_Registration> registrations = <_Registration>[];

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final String? type = _registeredType(node);
    if (type != null) {
      // Edges = construction-time sl<U>() lookups inside the factory closure.
      final _SlLookupVisitor lookups = _SlLookupVisitor(accessor);
      node.argumentList.accept(lookups);
      registrations.add(
        _Registration(type, node.methodName.offset, lookups.types.toList()),
      );
    }

    super.visitMethodInvocation(node);
  }

  /// Returns the registered type name for an `sl.register*<T>(...)` call, or
  /// null when [node] is not a GetIt registration.
  String? _registeredType(MethodInvocation node) {
    final Expression? target = node.target;
    if (target is! SimpleIdentifier || target.name != accessor) {
      return null;
    }
    if (!node.methodName.name.startsWith('register')) {
      return null;
    }
    final TypeArgumentList? typeArgs = node.typeArguments;
    if (typeArgs == null || typeArgs.arguments.isEmpty) {
      return null;
    }

    return typeArgs.arguments.first.toSource().trim();
  }
}

/// Collects the type names of `sl<U>()` lookups, ignoring those nested inside a
/// closure deeper than the factory body (those are deferred, not construction
/// dependencies).
///
/// A typed `sl<U>()` resolves to a [FunctionExpressionInvocation] (the analyzer
/// rewrites `sl<U>()` into a call on `sl`'s `call` method); the
/// [MethodInvocation] form only appears when `sl` is untyped/dynamic. Both are
/// handled so the rule does not silently see zero edges.
class _SlLookupVisitor extends RecursiveAstVisitor<void> {
  _SlLookupVisitor(this.accessor);

  final String accessor;
  final Set<String> types = <String>{};
  int _closureDepth = 0;

  bool get _isConstructionTime => _closureDepth <= 1;

  @override
  void visitFunctionExpression(FunctionExpression node) {
    _closureDepth++;
    super.visitFunctionExpression(node);
    _closureDepth--;
  }

  @override
  void visitFunctionExpressionInvocation(FunctionExpressionInvocation node) {
    final Expression function = node.function;
    final TypeArgumentList? typeArgs = node.typeArguments;
    if (_isConstructionTime &&
        function is SimpleIdentifier &&
        function.name == accessor &&
        typeArgs != null &&
        typeArgs.arguments.isNotEmpty) {
      types.add(typeArgs.arguments.first.toSource().trim());
    }

    super.visitFunctionExpressionInvocation(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final TypeArgumentList? typeArgs = node.typeArguments;
    if (_isConstructionTime &&
        node.target == null &&
        node.methodName.name == accessor &&
        typeArgs != null &&
        typeArgs.arguments.isNotEmpty) {
      types.add(typeArgs.arguments.first.toSource().trim());
    }

    super.visitMethodInvocation(node);
  }
}

/// Tarjan's strongly-connected-components. An SCC with more than one node — or a
/// single node with a self-edge — is a dependency cycle.
List<List<String>> _findCycles(Map<String, Set<String>> graph) {
  final Map<String, int> index = <String, int>{};
  final Map<String, int> lowLink = <String, int>{};
  final Set<String> onStack = <String>{};
  final List<String> stack = <String>[];
  final List<List<String>> sccs = <List<String>>[];
  int counter = 0;

  void initializeNode(_Frame frame) {
    final String v = frame.node;
    index[v] = counter;
    lowLink[v] = counter;
    counter++;
    stack.add(v);
    onStack.add(v);
    frame.neighbors = (graph[v] ?? const <String>{}).toList();
  }

  // Folds each already-indexed neighbor into v's lowlink; returns the first
  // unvisited one to recurse into, or null once none remain.
  _Frame? nextChildFrame(_Frame frame) {
    final String v = frame.node;
    while (frame.cursor < frame.neighbors!.length) {
      final String w = frame.neighbors![frame.cursor++];
      if (!index.containsKey(w)) {
        return _Frame(w);
      } else if (onStack.contains(w)) {
        lowLink[v] = lowLink[v]! < index[w]! ? lowLink[v]! : index[w]!;
      }
    }
    return null;
  }

  void popComponent(String v) {
    final List<String> component = <String>[];
    String w;
    do {
      w = stack.removeLast();
      onStack.remove(w);
      component.add(w);
    } while (w != v);
    final bool selfLoop =
        component.length == 1 && (graph[v]?.contains(v) ?? false);
    if (component.length > 1 || selfLoop) {
      sccs.add(component);
    }
  }

  // Iterative Tarjan — the DI graph is shallow, but recursion-free keeps it
  // safe regardless of dependency-chain depth.
  void strongConnect(String root) {
    final List<_Frame> frames = <_Frame>[_Frame(root)];
    while (frames.isNotEmpty) {
      final _Frame frame = frames.last;
      final String v = frame.node;

      if (frame.neighbors == null) {
        initializeNode(frame);
      }

      final _Frame? child = nextChildFrame(frame);
      if (child != null) {
        frames.add(child);
        continue;
      }

      if (lowLink[v] == index[v]) {
        popComponent(v);
      }

      frames.removeLast();
      if (frames.isNotEmpty) {
        final String parent = frames.last.node;
        lowLink[parent] = lowLink[parent]! < lowLink[v]!
            ? lowLink[parent]!
            : lowLink[v]!;
      }
    }
  }

  for (final String node in graph.keys) {
    if (!index.containsKey(node)) {
      strongConnect(node);
    }
  }
  return sccs;
}

/// Returns one concrete loop through [scc] (e.g. `A → B → A`) for the message.
List<String> _cyclePath(List<String> scc, Map<String, Set<String>> graph) {
  final Set<String> inScc = scc.toSet();
  final String start = scc.first;

  // A self-edge is its own shortest loop.
  if (graph[start]?.contains(start) ?? false) {
    return <String>[start, start];
  }

  final List<String> path = <String>[];
  final Set<String> visited = <String>{};

  bool dfs(String node) {
    path.add(node);
    visited.add(node);
    for (final String next in graph[node] ?? const <String>{}) {
      if (!inScc.contains(next)) {
        continue;
      }
      if (next == start) {
        return true;
      }
      if (!visited.contains(next) && dfs(next)) {
        return true;
      }
    }
    path.removeLast();
    return false;
  }

  dfs(start);
  return <String>[...path, start];
}

class _Frame {
  _Frame(this.node);

  final String node;
  List<String>? neighbors;
  int cursor = 0;
}
