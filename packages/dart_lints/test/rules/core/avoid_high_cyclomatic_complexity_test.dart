import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:dart_lints/src/lint_rule_base.dart';
import 'package:dart_lints/src/rules/core/avoid_high_cyclomatic_complexity.dart';
import 'package:test/test.dart';

/// Parses [source] syntactically and runs the rule's visitor over it.
List<LintViolation> _lint(
  String source, {
  required int maxComplexity,
  bool exemptFlatDispatch = false,
}) {
  final ParseStringResult result = parseString(
    content: source,
    throwIfDiagnostics: false,
  );
  final AvoidHighCyclomaticComplexity rule = AvoidHighCyclomaticComplexity(
    maxComplexity: maxComplexity,
    exemptFlatDispatch: exemptFlatDispatch,
  );
  final LintVisitor visitor = rule.createVisitor(
    'lib/foo.dart',
    result.lineInfo,
    source,
  );
  result.unit.accept(visitor);
  return visitor.violations;
}

/// The lowest `maxComplexity` at which [source] stops reporting at all —
/// which, for a source with exactly one measurable unit, is that unit's
/// actual computed complexity. Probing the real behaviour this way tests the
/// computed number directly instead of parsing it back out of a message.
int _measuredComplexity(String source, {int upTo = 30}) {
  for (int max = 0; max <= upTo; max++) {
    if (_lint(source, maxComplexity: max).isEmpty) {
      return max;
    }
  }
  throw StateError('complexity exceeds $upTo');
}

void main() {
  group('a straight-line unit has complexity 1', () {
    test('[partition] a function with no branches', () {
      expect(_measuredComplexity('void f() { print(1); }'), 1);
    });

    test('[boundary] exactly at the max does not report', () {
      expect(_lint('void f() { print(1); }', maxComplexity: 1), isEmpty);
    });

    test('[boundary] one under the max reports', () {
      final List<LintViolation> found = _lint(
        'void f() { print(1); }',
        maxComplexity: 0,
      );
      expect(found, hasLength(1));
      expect(found.single.message, contains('complexity 1'));
      expect(found.single.message, contains('max of 0'));
    });
  });

  group('each branch point adds exactly 1', () {
    test('[partition] if', () {
      expect(
        _measuredComplexity('void f(bool a) { if (a) { print(1); } }'),
        2,
      );
    });

    test('[partition] for (C-style)', () {
      expect(
        _measuredComplexity('''
void f(List<int> xs) {
  for (int i = 0; i < xs.length; i++) {
    print(i);
  }
}
'''),
        2,
      );
    });

    test('[partition] for-in', () {
      expect(
        _measuredComplexity('''
void f(List<int> xs) {
  for (final int x in xs) {
    print(x);
  }
}
'''),
        2,
      );
    });

    test('[partition] while', () {
      expect(
        _measuredComplexity('''
void f(bool Function() cond) {
  while (cond()) {
    print(1);
  }
}
'''),
        2,
      );
    });

    test('[partition] do-while', () {
      expect(
        _measuredComplexity('''
void f(bool Function() cond) {
  do {
    print(1);
  } while (cond());
}
'''),
        2,
      );
    });

    test('[partition] each catch clause on a try', () {
      expect(
        _measuredComplexity('''
void f() {
  try {
    doThing();
  } on FormatException catch (e) {
    print(e);
  } on StateError {
    print('state');
  } catch (e) {
    print(e);
  }
}
'''),
        4,
      );
    });

    test('[partition] &&, ||, and ?? each count, chained ones add up', () {
      expect(
        _measuredComplexity('bool f(bool a, bool b, bool c) => a && b || c;'),
        3,
      );
      // Calls on both sides of each ??, not simple access — see the
      // dedicated group below for the field-defaulting exemption itself.
      expect(
        _measuredComplexity(
          "String f() => a() ?? b() ?? 'd';",
        ),
        3,
      );
    });

    test('[partition] the ?: ternary', () {
      expect(_measuredComplexity('int f(bool a) => a ? 1 : 0;'), 2);
    });

    test('[partition] null-aware member access', () {
      expect(_measuredComplexity('int? f(A? a) => a?.value;'), 2);
    });

    test('[partition] null-aware method call', () {
      expect(_measuredComplexity('void f(A? a) => a?.doThing();'), 2);
    });

    test('[partition] null-aware index access', () {
      expect(_measuredComplexity('int? f(List<int>? a) => a?[0];'), 2);
    });

    test('[boundary] an if-else is one IfStatement, not two', () {
      expect(
        _measuredComplexity('int f(bool a) { if (a) return 1; return 0; }'),
        2,
      );
    });
  });

  group(
    '?? does not count when both sides are simple access — the '
    'field-defaulting exemption',
    () {
      test('[partition] field ?? this.field does not count', () {
        expect(
          _measuredComplexity(
            'class C { int x = 0; C f(int? x) => C()..x = x ?? this.x; }',
          ),
          1,
        );
      });

      test('[partition] two bare identifiers do not count', () {
        expect(_measuredComplexity('int f(int? a, int b) => a ?? b;'), 1);
      });

      test(
        '[partition] a field on any simple base counts as field access too '
        '— not only this',
        () {
          expect(
            _measuredComplexity(
              'int f(int? a, C other) => a ?? other.x;',
            ),
            1,
          );
        },
      );

      test(
        '[boundary] a call on either side still counts — this is no longer '
        '"keep the field unchanged"',
        () {
          expect(_measuredComplexity('int f(int? a) => a ?? compute();'), 2);
          expect(_measuredComplexity('int f(int? a) => compute() ?? a;'), 2);
        },
      );

      test(
        '[boundary] two levels of property access still counts — one level '
        'is the line, not "no chaining at all"',
        () {
          expect(
            _measuredComplexity(
              'class C { int x = 0; int f(int? a) => a ?? this.x.hashCode; }',
            ),
            2,
          );
        },
      );

      test(
        '[boundary] a realistic copyWith stays low regardless of field '
        'count — this is the whole point',
        () {
          expect(
            _measuredComplexity('''
class C {
  C copyWith({int? a, int? b, int? c, int? d, int? e}) => C()
    ..a = a ?? this.a
    ..b = b ?? this.b
    ..c = c ?? this.c
    ..d = d ?? this.d
    ..e = e ?? this.e;
}
'''),
            1,
          );
        },
      );

      test(
        '[partition] the clear-to-null thunk ternary is untouched — it is '
        'not a ??, this exemption never reaches it',
        () {
          expect(
            _measuredComplexity(
              'class C { int x = 0; C f(int? Function()? x) => '
              'C()..x = x != null ? x() : this.x; }',
            ),
            2,
          );
        },
      );
    },
  );

  group('switch cases are decision points, default and wildcard are not', () {
    test('[partition] each value case adds 1, default does not', () {
      expect(
        _measuredComplexity('''
void f(int x) {
  switch (x) {
    case 1:
      print('one');
      break;
    case 2:
      print('two');
      break;
    default:
      print('other');
  }
}
'''),
        3,
      );
    });

    test('[partition] a pattern case adds 1, its guard adds 1 more', () {
      expect(
        _measuredComplexity('''
void f(Object x) {
  switch (x) {
    case int n when n > 0:
      print(n);
    default:
      print('other');
  }
}
'''),
        3,
      );
    });

    test(
      '[boundary] a switch expression counts each case, skips the wildcard',
      () {
        expect(
          _measuredComplexity('''
String f(Object x) {
  return switch (x) {
    int n when n > 0 => 'pos',
    int() => 'nonpos',
    _ => 'other',
  };
}
'''),
          4,
        );
      },
    );
  });

  group('an if-case guard is a second condition on the same branch', () {
    test('[boundary] if-case with a guard adds 2: the if and the guard', () {
      expect(
        _measuredComplexity('''
void f(Object x) {
  if (x case int n when n > 0) {
    print(n);
  }
}
'''),
        3,
      );
    });
  });

  group('collection if/for elements are branch points too', () {
    test('[partition] an if element', () {
      expect(_measuredComplexity('List<int> f(bool a) => [1, if (a) 2];'), 2);
    });

    test('[boundary] an if element with a guard adds 2', () {
      expect(
        _measuredComplexity(
          'List<int> f(Object x) => [1, if (x case int n when n > 0) n];',
        ),
        3,
      );
    });

    test('[partition] a for element', () {
      expect(
        _measuredComplexity(
          'List<int> f(List<int> xs) => [for (final int x in xs) x * 2];',
        ),
        2,
      );
    });
  });

  group('every function-shaped node is its own unit', () {
    test('[partition] a method is measured under its own name', () {
      final List<LintViolation> found = _lint('''
class C {
  void f(bool a) {
    if (a) {
      print(1);
    }
  }
}
''', maxComplexity: 1);
      expect(found, hasLength(1));
      expect(found.single.message, contains("'f'"));
    });

    test('[partition] a named constructor is labelled Type.name', () {
      final List<LintViolation> found = _lint('''
class C {
  C.named(bool a) {
    if (a) {
      print(1);
    }
  }
}
''', maxComplexity: 1);
      expect(found, hasLength(1));
      expect(found.single.message, contains("'C.named'"));
    });

    test('[partition] an unnamed constructor is labelled by its type', () {
      final List<LintViolation> found = _lint('''
class C {
  C(bool a) {
    if (a) {
      print(1);
    }
  }
}
''', maxComplexity: 1);
      expect(found, hasLength(1));
      expect(found.single.message, contains("'C'"));
    });

    test(
      '[boundary] a local function is its own unit, not folded into the '
      'function that declares it',
      () {
        final List<LintViolation> found = _lint('''
void outer() {
  void local() {
    if (true) {
      print(1);
    }
  }
  local();
}
''', maxComplexity: 1);
        expect(found, hasLength(1));
        expect(found.single.message, contains("'local'"));
      },
    );

    test(
      '[boundary] a closure is its own unit, not folded into the method '
      'that passes it along',
      () {
        final List<LintViolation> found = _lint('''
class C {
  void build(List<int> xs) {
    xs.forEach((int x) {
      if (x > 0) {
        print(x);
      }
    });
  }
}
''', maxComplexity: 1);
        expect(found, hasLength(1));
        expect(found.single.message, contains("closure in 'build'"));
      },
    );

    test(
      '[boundary] a closure with no enclosing named unit is labelled '
      'generically',
      () {
        final List<LintViolation> found = _lint('''
final Function f = (int x) {
  if (x > 0) {
    print(x);
  }
};
''', maxComplexity: 1);
        expect(found, hasLength(1));
        expect(found.single.message, contains('this closure'));
      },
    );
  });

  group('a body-less declaration is not measured', () {
    test('[boundary] an abstract method does not report at any threshold', () {
      expect(
        _lint('abstract class C { void f(); }', maxComplexity: 0),
        isEmpty,
      );
    });
  });

  group('exemptFlatDispatch — off by default, opt-in', () {
    const String cleanSwitchExpression = '''
enum E { a, b }
int f(E x) {
  return switch (x) {
    E.a => 1,
    E.b => 2,
  };
}
''';

    test('[boundary] reports when the option is off (the default)', () {
      expect(_lint(cleanSwitchExpression, maxComplexity: 1), hasLength(1));
    });

    test(
      '[boundary] the rule constructor\'s own default — exemptFlatDispatch '
      'omitted entirely, not just explicitly passed false — still reports',
      () {
        // _lint always forwards a value (its own `= false` default masks
        // AvoidHighCyclomaticComplexity's), so this constructs the rule
        // directly to exercise the constructor's default value itself.
        final ParseStringResult result = parseString(
          content: cleanSwitchExpression,
          throwIfDiagnostics: false,
        );
        final AvoidHighCyclomaticComplexity rule =
            AvoidHighCyclomaticComplexity(maxComplexity: 1);
        final LintVisitor visitor = rule.createVisitor(
          'lib/foo.dart',
          result.lineInfo,
          cleanSwitchExpression,
        );
        result.unit.accept(visitor);
        expect(visitor.violations, hasLength(1));
      },
    );

    test(
      '[partition] a clean top-level switch expression is exempt when the '
      'option is on',
      () {
        expect(
          _lint(
            cleanSwitchExpression,
            maxComplexity: 1,
            exemptFlatDispatch: true,
          ),
          isEmpty,
        );
      },
    );

    test(
      '[partition] a clean arrow-body (=>) switch expression is exempt',
      () {
        const String source = '''
enum E { a, b }
int f(E x) => switch (x) {
  E.a => 1,
  E.b => 2,
};
''';
        expect(
          _lint(source, maxComplexity: 1, exemptFlatDispatch: true),
          isEmpty,
        );
      },
    );

    test(
      '[boundary] an arrow body that is not a switch at all is never '
      'exempt',
      () {
        const String source = '''
int f(bool a, bool b, bool c, bool d) => a && b && c && d;
''';
        expect(
          _lint(source, maxComplexity: 1, exemptFlatDispatch: true),
          hasLength(1),
        );
      },
    );

    test('[partition] a clean top-level switch STATEMENT is exempt', () {
      const String source = '''
enum E { a, b }
void f(E x) {
  switch (x) {
    case E.a:
      print(1);
      break;
    case E.b:
      print(2);
      break;
  }
}
''';
      expect(
        _lint(source, maxComplexity: 1, exemptFlatDispatch: true),
        isEmpty,
      );
    });

    test('[partition] a clean top-level try/catch is exempt', () {
      const String source = '''
void f() {
  try {
    doThing();
  } on FormatException catch (e) {
    handle(e);
  } on StateError catch (e) {
    handle(e);
  }
}
''';
      expect(
        _lint(source, maxComplexity: 1, exemptFlatDispatch: true),
        isEmpty,
      );
    });

    test(
      '[boundary] a branch-free hoisted local before the switch is still '
      'exempt',
      () {
        const String source = '''
enum E { a, b }
int f(E e) {
  final int y = 1;
  return switch (e) {
    E.a => 1,
    E.b => 2,
  };
}
''';
        expect(
          _lint(source, maxComplexity: 1, exemptFlatDispatch: true),
          isEmpty,
        );
      },
    );

    test(
      '[boundary] a hoisted local whose own initializer has a branch '
      'disqualifies it',
      () {
        const String source = '''
enum E { a, b }
int f(E e, int? a) {
  final int y = a ?? compute();
  return switch (e) {
    E.a => 1,
    E.b => 2,
  };
}
''';
        expect(
          _lint(source, maxComplexity: 1, exemptFlatDispatch: true),
          hasLength(1),
        );
      },
    );

    test('[boundary] wrapped in a loop is not exempt', () {
      const String source = '''
enum E { a, b }
void f(List<E> xs) {
  for (final E x in xs) {
    switch (x) {
      case E.a:
        print(1);
        break;
      case E.b:
        print(2);
        break;
    }
  }
}
''';
      expect(
        _lint(source, maxComplexity: 1, exemptFlatDispatch: true),
        hasLength(1),
      );
    });

    test(
      '[boundary] preceded by a leading guard is not exempt — split the '
      'guard into its own method instead',
      () {
        const String source = '''
enum E { a, b }
int f(bool ready, E x) {
  if (!ready) {
    return 0;
  }
  return switch (x) {
    E.a => 1,
    E.b => 2,
  };
}
''';
        expect(
          _lint(source, maxComplexity: 1, exemptFlatDispatch: true),
          hasLength(1),
        );
      },
    );

    test('[boundary] followed by more logic is not exempt', () {
      const String source = '''
enum E { a, b }
int f(E x) {
  final int y = switch (x) {
    E.a => 1,
    E.b => 2,
  };
  return y + 1;
}
''';
      expect(
        _lint(source, maxComplexity: 1, exemptFlatDispatch: true),
        hasLength(1),
      );
    });

    test(
      '[boundary] the switch scrutinee itself having a branch disqualifies '
      'it',
      () {
        // x ?? E.a would itself be exempted by the ?? field-defaulting rule
        // (E.a is a PrefixedIdentifier with a bare-identifier prefix, same
        // shape as `other.field`) — compute() is a call, so this ?? counts
        // regardless.
        const String source = '''
enum E { a, b }
int f(E? x) {
  return switch (x ?? compute()) {
    E.a => 1,
    E.b => 2,
  };
}
''';
        expect(
          _lint(source, maxComplexity: 1, exemptFlatDispatch: true),
          hasLength(1),
        );
      },
    );

    test('[boundary] an arm with its own branch disqualifies it', () {
      const String source = '''
enum E { a, b }
int f(E x, bool cond) {
  return switch (x) {
    E.a => cond ? 1 : 2,
    E.b => 3,
  };
}
''';
      expect(
        _lint(source, maxComplexity: 1, exemptFlatDispatch: true),
        hasLength(1),
      );
    });

    test('[boundary] a guarded case (a when clause) disqualifies it', () {
      const String source = '''
int f(Object x) {
  return switch (x) {
    int n when n > 0 => 1,
    int() => 2,
    _ => 3,
  };
}
''';
      expect(
        _lint(source, maxComplexity: 1, exemptFlatDispatch: true),
        hasLength(1),
      );
    });

    test(
      '[boundary] the try body itself having a branch disqualifies it',
      () {
        const String source = '''
void f(bool cond) {
  try {
    if (cond) {
      doThing();
    }
  } on FormatException catch (e) {
    handle(e);
  } on StateError catch (e) {
    handle(e);
  }
}
''';
        expect(
          _lint(source, maxComplexity: 1, exemptFlatDispatch: true),
          hasLength(1),
        );
      },
    );

    test('[boundary] a catch arm with its own branch disqualifies it', () {
      const String source = '''
void f(bool cond) {
  try {
    doThing();
  } on FormatException catch (e) {
    if (cond) {
      handle(e);
    }
  } on StateError catch (e) {
    handle(e);
  }
}
''';
      expect(
        _lint(source, maxComplexity: 1, exemptFlatDispatch: true),
        hasLength(1),
      );
    });

    test('[boundary] a finally block with its own branch disqualifies it', () {
      const String source = '''
void f(bool cond) {
  try {
    doThing();
  } on FormatException catch (e) {
    handle(e);
  } on StateError catch (e) {
    handle(e);
  } finally {
    if (cond) {
      cleanup();
    }
  }
}
''';
      expect(
        _lint(source, maxComplexity: 1, exemptFlatDispatch: true),
        hasLength(1),
      );
    });

    test('[boundary] an empty function body is not exempt', () {
      const String source = '''
void f() {}
''';
      expect(
        _lint(source, maxComplexity: 0, exemptFlatDispatch: true),
        hasLength(1),
      );
    });

    test(
      '[boundary] a clean switch statement that is not the last statement '
      'is not exempt',
      () {
        // Distinguishes the `i != statements.length - 1` guard from a
        // no-op: without it, `last` resolves to the switch (which passes
        // _isCleanSwitchStatement in isolation) and the trailing
        // print('done') is never accounted for.
        const String source = '''
enum E { a, b }
void f(E x) {
  switch (x) {
    case E.a:
      print(1);
      break;
    case E.b:
      print(2);
      break;
  }
  print('done');
}
''';
        expect(
          _lint(source, maxComplexity: 1, exemptFlatDispatch: true),
          hasLength(1),
        );
      },
    );

    test(
      '[boundary] a switch STATEMENT scrutinee having a branch '
      'disqualifies it',
      () {
        const String source = '''
enum E { a, b }
void f(E? x) {
  switch (x ?? compute()) {
    case E.a:
      print(1);
      break;
    case E.b:
      print(2);
      break;
  }
}
''';
        expect(
          _lint(source, maxComplexity: 1, exemptFlatDispatch: true),
          hasLength(1),
        );
      },
    );

    test(
      '[boundary] a switch STATEMENT case with a when guard disqualifies '
      'it',
      () {
        const String source = '''
void f(Object x) {
  switch (x) {
    case int n when n > 0:
      print(n);
      break;
    case int():
      print(0);
      break;
    default:
      print(-1);
  }
}
''';
        expect(
          _lint(source, maxComplexity: 1, exemptFlatDispatch: true),
          hasLength(1),
        );
      },
    );

    test(
      '[boundary] a switch STATEMENT case with its own branch disqualifies '
      'it',
      () {
        const String source = '''
enum E { a, b }
void f(E x, bool cond) {
  switch (x) {
    case E.a:
      if (cond) {
        print(1);
      }
      break;
    case E.b:
      print(2);
      break;
  }
}
''';
        expect(
          _lint(source, maxComplexity: 1, exemptFlatDispatch: true),
          hasLength(1),
        );
      },
    );

    test(
      '[boundary] a try with no catch clauses (finally only) is not '
      'exempt',
      () {
        const String source = '''
void f() {
  try {
    doThing();
  } finally {
    cleanup();
  }
}
''';
        expect(
          _lint(source, maxComplexity: 0, exemptFlatDispatch: true),
          hasLength(1),
        );
      },
    );

    test(
      '[boundary] a body of only branch-free local declarations, with no '
      'switch or try at all, is not exempt — and does not walk the '
      'leading-locals scan past the end of the statement list',
      () {
        // Every statement here passes the "leading local, no branches" test,
        // so the scan that looks for a trailing dispatch has nothing to stop
        // on before running off the end. Pins the loop bound at
        // `statements.length - 1`, not `- 1` weakened to `+ 1`: that specific
        // slip lets `i` advance one past the last valid index and index the
        // list out of bounds instead of cleanly falling through to "not a
        // flat dispatch".
        const String source = '''
void f() {
  final int a = 1;
}
''';
        expect(
          _lint(source, maxComplexity: 0, exemptFlatDispatch: true),
          hasLength(1),
        );
      },
    );
  });
}
