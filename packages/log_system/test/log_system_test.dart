import 'package:flutter_test/flutter_test.dart';
import 'package:log_system/log_system.dart';
// Not exported. A host app configures via flags on `LogSystem.init`; these are
// the internals those flags assemble, reachable from inside the package only.
import 'package:log_system/src/fan_out_log_repository.dart';
import 'package:log_system/src/log_data_source.dart';

/// Records what each level was asked to do, without touching a real sink.
class _RecordingSink extends LogDataSource {
  final List<String> calls = <String>[];
  final List<Object?> errors = <Object?>[];

  @override
  Future<void> debug(
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) async {
    calls.add('debug:$message');
    errors.add(error);
  }

  @override
  Future<void> info(String message) async => calls.add('info:$message');

  @override
  Future<void> warning(
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) async {
    calls.add('warning:$message');
    errors.add(error);
  }

  @override
  Future<void> error(
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) async {
    calls.add('error:$message');
    errors.add(error);
  }

  @override
  Future<void> fatal(
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) async {
    calls.add('fatal:$message');
    errors.add(error);
  }
}

void main() {
  late _RecordingSink console;
  late _RecordingSink report;

  setUp(() {
    console = _RecordingSink();
    report = _RecordingSink();
    LogSystem.initWithRepository(
      FanOutLogRepository(console: console, report: report),
    );
  });

  tearDown(LogSystem.reset);

  group('severity routing — the reason the repository layer exists', () {
    test('debug reaches the console and never the reporter', () {
      LogSystem.debug('local only');
      expect(console.calls, <String>['debug:local only']);
      expect(report.calls, isEmpty);
    });

    test('info, warning, error and fatal reach both', () {
      LogSystem.info('i');
      LogSystem.warning('w');
      LogSystem.error('e');
      LogSystem.fatal('f');
      const List<String> expected = <String>[
        'info:i',
        'warning:w',
        'error:e',
        'fatal:f',
      ];
      expect(console.calls, expected);
      expect(report.calls, expected);
    });
  });

  group('initialisation', () {
    test('logging before init is a silent no-op, not a throw', () {
      // A unit test that constructs production types directly never stands up
      // the app's wiring, and a log line must not be why it fails.
      LogSystem.reset();
      expect(() => LogSystem.error('nothing is listening'), returnsNormally);
    });

    test('init again replaces the existing repository', () {
      // What an integration harness does to keep a test build off the real
      // crash reporter.
      final _RecordingSink replacement = _RecordingSink();
      LogSystem.initWithRepository(
        FanOutLogRepository(console: replacement),
      );
      LogSystem.error('e');
      expect(replacement.calls, <String>['error:e']);
      expect(console.calls, isEmpty);
    });

    test('a repository with no reporter keeps every level device-local', () {
      LogSystem.initWithRepository(FanOutLogRepository(console: console));
      LogSystem.info('i');
      LogSystem.fatal('f');
      expect(console.calls, <String>['info:i', 'fatal:f']);
      expect(report.calls, isEmpty);
    });
  });

  test('the error object is passed through, not stringified by the facade', () {
    // Reduction happens at the egress sink, not here — the console sink is
    // entitled to the real object.
    const FormatException error = FormatException('raw');
    LogSystem.error('e', error: error);
    expect(console.errors.last, same(error));
  });
}
