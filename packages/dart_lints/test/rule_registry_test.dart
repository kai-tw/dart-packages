import 'package:dart_lints/src/built_rules.dart';
import 'package:dart_lints/src/config/dart_lints_config_exception.dart';
import 'package:dart_lints/src/rule_registry.dart';
import 'package:test/test.dart';

void main() {
  group('a rule with a required option', () {
    const RuleRegistry registry = RuleRegistry();

    test(
      '[boundary] enabling it without the option throws a config error '
      'naming the rule and the option, not a raw TypeError',
      () {
        expect(
          () => registry.build(
            <String>{'avoid_high_cyclomatic_complexity'},
            (String ruleName) => <String, Object?>{},
          ),
          throwsA(
            isA<DartLintsConfigException>().having(
              (DartLintsConfigException e) => e.message,
              'message',
              allOf(
                contains('avoid_high_cyclomatic_complexity'),
                contains('maxComplexity'),
              ),
            ),
          ),
        );
      },
    );

    test('[partition] supplying it builds the rule with no error', () {
      final BuiltRules built = registry.build(
        <String>{'avoid_high_cyclomatic_complexity'},
        (String ruleName) => <String, Object?>{'maxComplexity': 6},
      );
      expect(built.syntax, hasLength(1));
    });

    test(
      '[boundary] a rule with no required options is unaffected by an '
      'empty options map',
      () {
        final BuiltRules built = registry.build(
          <String>{'avoid_bare_catch'},
          (String ruleName) => <String, Object?>{},
        );
        expect(built.syntax, hasLength(1));
      },
    );
  });
}
