import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:log_system/log_system.dart';
// Not exported. The routing table is what these assert against, and a
// `LogSink` deliberately cannot see which destination a level reached.
import 'package:log_system/src/data/log_data_source.dart';
import 'package:log_system/src/data/log_repository_impl.dart';

/// The four-line implementation the `LogSink` doc tells a host app to copy.
/// It lives here for the same reason it is not shipped: a test double belongs
/// to the suite that asserts on it.
final class _RecordingLogSink implements LogSink {
  final List<LogEntry> entries = <LogEntry>[];

  @override
  void emit(LogEntry entry) => entries.add(entry);
}

final class _ThrowingLogSink implements LogSink {
  @override
  void emit(LogEntry entry) => throw StateError('the host sink is broken');
}

/// Records what each level was asked to do, without touching a real sink.
class _RecordingDataSource extends LogDataSource {
  final List<String> calls = <String>[];

  @override
  Future<void> debug(
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) async => calls.add('debug:$message');

  @override
  Future<void> info(String message) async => calls.add('info:$message');

  @override
  Future<void> warning(
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) async => calls.add('warning:$message');

  @override
  Future<void> error(
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) async => calls.add('error:$message');

  @override
  Future<void> fatal(
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) async => calls.add('fatal:$message');

  @override
  Future<void> event(String name, {Map<String, Object>? parameters}) async =>
      calls.add('event:$name');
}

void main() {
  late _RecordingLogSink sink;

  setUp(() {
    sink = _RecordingLogSink();
    LogSystem.register(LogSystem.withSink(sink));
  });

  tearDown(LogSystem.reset);

  group('what a registered sink sees', () {
    test(
      'every level, in call order, including the two the reporter never '
      'receives',
      () {
        // `debug` and `event` are exactly the levels an app cannot otherwise
        // observe anywhere: the crash reporter drops both by routing. A sink
        // that inherited the reporter's column would let an app see only the
        // half of its logging that was never in question.
        LogSystem.debug('d');
        LogSystem.info('i');
        LogSystem.warning('w');
        LogSystem.error('e');
        LogSystem.fatal('f');
        LogSystem.event('opened');

        expect(sink.entries.map((LogEntry e) => e.level), <LogLevel>[
          LogLevel.debug,
          LogLevel.info,
          LogLevel.warning,
          LogLevel.error,
          LogLevel.fatal,
          LogLevel.event,
        ]);
        expect(sink.entries.map((LogEntry e) => e.message), <String>[
          'd',
          'i',
          'w',
          'e',
          'f',
          'opened',
        ]);
      },
    );

    test(
      'the error arrives REDACTED — the sink is not a way around the boundary',
      () {
        // The whole reason this seam could be opened at all. A raw object
        // here would let a host sink forward an exception whose `toString()`
        // carries a file path to a backend of its own: the failure this
        // package was extracted to prevent, reintroduced by the feature meant
        // to make logging observable.
        const FileSystemException error = FileSystemException(
          'could not read',
          '/Users/someone/Library/private-book.epub',
        );

        LogSystem.error('load failed', error: error);

        final LogEntry entry = sink.entries.single;
        expect(entry.redactedError, 'FileSystemException errno=-');
        expect(entry.redactedError, isNot(contains('private-book')));
        expect(entry.redactedError, isNot(contains('/Users')));
      },
    );

    test(
      'the redactor runs exactly once — a chained reduction would lose the '
      'type name that keeps crash-report grouping apart',
      () {
        // Reduction happens at each egress, never in sequence: redacting a
        // surrogate would yield the private surrogate type's own name, and
        // every distinct error in the app would group under it. Asserting the
        // ORIGINAL type name survives is how that stays true, because a
        // second pass is precisely what would erase it.
        LogSystem.error('e', error: const FormatException('raw'));
        expect(sink.entries.single.redactedError, 'FormatException');
      },
    );

    test('no error object gives null, not the reporter\'s placeholder', () {
      // The reporter is handed `<no error object>` because its plugin ends at
      // `toString()` on a dynamic, so a null would title an issue `"null"`
      // and collect every message-only call site under it. A sink has no such
      // constraint, and `null` is the honest answer to "was an error passed?"
      LogSystem.warning('nothing went wrong yet');
      expect(sink.entries.single.redactedError, isNull);
    });

    test('an event carries its parameters and no error', () {
      LogSystem.event('opened', parameters: <String, Object>{'count': 3});
      final LogEntry entry = sink.entries.single;
      expect(entry.parameters, <String, Object>{'count': 3});
      expect(entry.redactedError, isNull);
    });

    test('the stack trace passes through unreduced', () {
      // It names the app's own frames, not its user's data, and the crash
      // reporter already receives it as-is.
      final StackTrace stack = StackTrace.current;
      LogSystem.error(
        'e',
        error: const FormatException('x'),
        stackTrace: stack,
      );
      expect(sink.entries.single.stackTrace, same(stack));
    });
  });

  group('registration', () {
    test('reset returns every level to a silent no-op', () {
      // The half of the contract a host `tearDown` has to hold up. Without it
      // one test's sink goes on recording into every later test in the same
      // process.
      LogSystem.reset();
      expect(() => LogSystem.error('nobody is listening'), returnsNormally);
      expect(sink.entries, isEmpty);
    });

    test('withSink forwards to the sink ALONE — no console, no reporter', () {
      // What makes it the shape a test wants: `init` would stand up the
      // console, read the Firebase registry and reassign a process-wide error
      // handler from a `setUp`.
      LogSystem.info('i');
      expect(sink.entries.single.message, 'i');
    });

    test('a sink registered through init is ADDITIVE, not a replacement', () {
      // An app routing logging into its own backend does not thereby give up
      // the crash reporter. Asserted against the repository rather than
      // `init`, which is the same wiring plus the global side effects.
      final _RecordingDataSource console = _RecordingDataSource();
      final _RecordingDataSource report = _RecordingDataSource();
      LogSystem.initWithRepositoryForTest(
        LogRepositoryImpl(console: console, report: report, sink: sink),
      );

      LogSystem.error('e');

      expect(console.calls, <String>['error:e']);
      expect(report.calls, <String>['error:e']);
      expect(sink.entries.single.message, 'e');
    });
  });

  test(
    'a sink that throws rejects the future instead of propagating to the call '
    'site',
    () async {
      // A sink is app code this package does not control, and a log line must
      // never be why the line after it does not run. `expectLater` receiving a
      // future at all is half the assertion: a synchronous throw would come
      // out of the call below before any matcher saw it.
      final LogRepositoryImpl repository = LogRepositoryImpl(
        sink: _ThrowingLogSink(),
      );
      await expectLater(
        repository.error('e'),
        throwsA(isA<StateError>()),
        reason:
            'the throw belongs in the discarded future, where a zone handler '
            'sees it, not at the log call site',
      );
    },
  );

  group('LogEntry.toString — what a failed expectation prints', () {
    // Not decoration. It is the only thing a host sees when `expect(entries,
    // ...)` fails, and an entry that prints as `Instance of 'LogEntry'` turns
    // every failure into a debugging session.
    test('level and message, with neither optional half', () {
      const LogEntry entry = LogEntry(
        level: LogLevel.info,
        message: 'sync finished',
      );
      expect(entry.toString(), 'info: sync finished');
    });

    test('the redacted error is appended when there is one', () {
      const LogEntry entry = LogEntry(
        level: LogLevel.error,
        message: 'load failed',
        redactedError: 'FileSystemException errno=2',
      );
      expect(
        entry.toString(),
        'error: load failed — FileSystemException errno=2',
      );
    });

    test('an event appends its parameters', () {
      const LogEntry entry = LogEntry(
        level: LogLevel.event,
        message: 'opened',
        parameters: <String, Object>{'count': 3},
      );
      expect(entry.toString(), 'event: opened {count: 3}');
    });
  });
}
