import 'package:flutter_test/flutter_test.dart';
import 'package:log_system/log_system.dart';

/// Non-const on purpose, unlike `log_error_redactor_test.dart`'s
/// `_CloudSocketException`: a compile-time-constant instance is folded by
/// the compiler rather than constructed at runtime, so a suite that only
/// ever built one const instance could leave this class's own constructor
/// body looking untested despite every other test passing.
class _RuntimeConstructedException extends LoggableException {
  _RuntimeConstructedException(int? code) : super(diagnosticCode: code);
}

void main() {
  group('LoggableException — the template an app extends', () {
    test('diagnosticCode round-trips', () {
      expect(_RuntimeConstructedException(61).diagnosticCode, 61);
      expect(_RuntimeConstructedException(null).diagnosticCode, isNull);
    });

    test('toString carries the code when present', () {
      expect(
        _RuntimeConstructedException(61).toString(),
        '_RuntimeConstructedException(code=61)',
      );
    });

    test('toString omits the parenthesised code when absent', () {
      expect(
        _RuntimeConstructedException(null).toString(),
        '_RuntimeConstructedException',
      );
    });

    test('it is an Exception, per its own contract', () {
      expect(_RuntimeConstructedException(1), isA<Exception>());
    });
  });
}
