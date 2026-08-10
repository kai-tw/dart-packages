import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:log_system/log_system.dart';

class _CodedFailure implements Exception, LogDiagnosticCode {
  const _CodedFailure(this.diagnosticCode);

  @override
  final int? diagnosticCode;

  @override
  String toString() => 'the customer is 王小明, phone 0912345678';
}

class _Plain implements Exception {
  const _Plain();

  @override
  String toString() => 'plaintext-secret';
}

void main() {
  tearDown(LogErrorRedactor.resetRules);

  group('default-deny', () {
    test('an unrecognised type is reduced to its type name', () {
      expect(LogErrorRedactor.redact(const _Plain()).toString(), '_Plain');
    });

    test('the shape that actually leaks does not survive', () {
      // base64Decode's FormatException prints its entire source string. When
      // that source is key material, the exception *is* the key. Asserted
      // against the real exception rather than a stand-in, so a change to
      // Dart's formatting cannot quietly invalidate it.
      late final FormatException leaky;
      try {
        base64Decode('c2VjcmV0LWtleS1tYXRlcmlhbA==!!CORRUPT');
        fail('expected base64Decode to reject the input');
      } on FormatException catch (error) {
        leaky = error;
      }
      expect(leaky.toString(), contains('c2VjcmV0'));
      expect(
        LogErrorRedactor.redact(leaky).toString(),
        isNot(contains('c2VjcmV0')),
      );
    });

    test('null forwards nothing', () {
      expect(LogErrorRedactor.redact(null), isNull);
    });

    test('the surrogate leads with the type name, so grouping survives', () {
      // flutterfire #3310: the reporter groups non-fatals on the exception
      // type/message. A surrogate that dropped the type name would collapse
      // every redacted error into a single issue.
      expect(
        LogErrorRedactor.redact(const SocketException('x')).toString(),
        startsWith('SocketException'),
      );
      expect(
        LogErrorRedactor.redact(const _Plain()).toString(),
        startsWith('_Plain'),
      );
    });
  });

  group('allow-listed structural fields', () {
    test('SocketException keeps errno and drops the address', () {
      const SocketException error = SocketException(
        'Connection refused',
        osError: OSError('Connection refused', 61),
        address: null,
        port: 443,
      );
      expect(
        LogErrorRedactor.redact(error).toString(),
        'SocketException errno=61',
      );
    });

    test('a missing OSError renders a dash rather than throwing', () {
      expect(
        LogErrorRedactor.redact(const SocketException('x')).toString(),
        'SocketException errno=-',
      );
    });

    test('FileSystemException keeps errno and drops the path', () {
      const FileSystemException error = FileSystemException(
        'Cannot open',
        '/Users/someone/Documents/customers.db',
        OSError('No space left on device', 28),
      );
      final String redacted = LogErrorRedactor.redact(error).toString();
      expect(redacted, 'FileSystemException errno=28');
      expect(redacted, isNot(contains('customers')));
    });

    test('OSError keeps its code', () {
      expect(
        LogErrorRedactor.redact(const OSError('EACCES', 13)).toString(),
        'OSError errno=13',
      );
    });
  });

  group('PlatformException.code is admitted only when it is a token', () {
    test('an opaque code survives', () {
      expect(
        LogErrorRedactor.redact(PlatformException(code: 'channel-error'))
            .toString(),
        'PlatformException code=channel-error',
      );
    });

    test('a code containing a path degrades to type-name-only', () {
      expect(
        LogErrorRedactor.redact(
          PlatformException(code: '/Users/someone/file.txt'),
        ).toString(),
        'PlatformException',
      );
    });

    test('a code containing a sentence degrades', () {
      expect(
        LogErrorRedactor.redact(
          PlatformException(code: 'could not open the file'),
        ).toString(),
        'PlatformException',
      );
    });

    test('an over-long code degrades', () {
      expect(
        LogErrorRedactor.redact(PlatformException(code: 'a' * 49)).toString(),
        'PlatformException',
      );
    });
  });

  group('LogDiagnosticCode opt-in', () {
    test('a code in range is forwarded, and toString is never read', () {
      final String redacted = LogErrorRedactor.redact(
        const _CodedFailure(61),
      ).toString();
      expect(redacted, '_CodedFailure code=61');
      expect(redacted, isNot(contains('王小明')));
      expect(redacted, isNot(contains('0912345678')));
    });

    test('a null code renders a dash', () {
      expect(
        LogErrorRedactor.redact(const _CodedFailure(null)).toString(),
        '_CodedFailure code=-',
      );
    });

    test('an out-of-band code is treated as a smuggle and dropped', () {
      // The marker must never be able to widen the egress surface, however it
      // is misused downstream.
      expect(
        LogErrorRedactor.redact(const _CodedFailure(1700000000)).toString(),
        '_CodedFailure',
      );
      expect(
        LogErrorRedactor.redact(const _CodedFailure(-1)).toString(),
        '_CodedFailure',
      );
    });
  });

  group('host-registered rules', () {
    test('a rule runs before the built-in arms and can override one', () {
      LogErrorRedactor.addRule(
        LogErrorRule(
          matches: (Object error) => error is SocketException,
          describe: (Object error, String type) => '$type overridden',
        ),
      );
      expect(
        LogErrorRedactor.redact(const SocketException('x')).toString(),
        'SocketException overridden',
      );
    });

    test('rules are consulted in registration order', () {
      LogErrorRedactor.addRule(
        LogErrorRule(
          matches: (Object error) => error is _Plain,
          describe: (Object error, String type) => '$type first',
        ),
      );
      LogErrorRedactor.addRule(
        LogErrorRule(
          matches: (Object error) => error is _Plain,
          describe: (Object error, String type) => '$type second',
        ),
      );
      expect(
        LogErrorRedactor.redact(const _Plain()).toString(),
        '_Plain first',
      );
    });
  });

  group('redactDetails', () {
    test('drops context and information, keeps stack and library', () {
      final StackTrace stack = StackTrace.current;
      final FlutterErrorDetails details = FlutterErrorDetails(
        exception: const _Plain(),
        stack: stack,
        library: 'my_app',
        context: ErrorDescription('while building CustomerCard for 王小明'),
        informationCollector: () => <DiagnosticsNode>[
          ErrorDescription('phone 0912345678'),
        ],
      );

      final FlutterErrorDetails redacted =
          LogErrorRedactor.redactDetails(details);

      expect(redacted.exception.toString(), '_Plain');
      expect(redacted.stack, same(stack));
      expect(redacted.library, 'my_app');
      expect(redacted.context, isNull);
      expect(redacted.informationCollector, isNull);
    });
  });
}
