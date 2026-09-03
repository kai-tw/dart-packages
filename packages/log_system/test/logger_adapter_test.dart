import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
// Not exported: the console adapter is package-internal.
import 'package:log_system/src/data/adapters/logger_adapter.dart';
import 'package:logger/logger.dart';

void main() {
  late MemoryOutput output;
  late LoggerAdapter adapter;

  setUp(() {
    // The real `Logger`, real `PrettyPrinter`, with only the destination
    // swapped — everything upstream of `output` is exactly what production
    // runs, so a passing test here is evidence about production formatting,
    // not about a stand-in for it.
    output = MemoryOutput(bufferSize: 20);
    adapter = LoggerAdapter(output: output);
  });

  String printed() =>
      output.buffer.expand((OutputEvent e) => e.lines).join('\n');

  group('every level completes without throwing', () {
    test('debug, with and without an error', () async {
      await expectLater(adapter.debug('d'), completes);
      await expectLater(
        adapter.debug(
          'd',
          error: StateError('x'),
          stackTrace: StackTrace.current,
        ),
        completes,
      );
    });

    test('info', () async {
      await expectLater(adapter.info('i'), completes);
    });

    test('warning, with and without an error', () async {
      await expectLater(adapter.warning('w'), completes);
      await expectLater(
        adapter.warning('w', error: StateError('x')),
        completes,
      );
    });

    test('error, with and without an error object', () async {
      await expectLater(adapter.error('e'), completes);
      await expectLater(
        adapter.error(
          'e',
          error: StateError('x'),
          stackTrace: StackTrace.current,
        ),
        completes,
      );
    });

    test('fatal', () async {
      await expectLater(
        adapter.fatal('f', error: StateError('x')),
        completes,
      );
    });

    test('event, with and without parameters', () async {
      await expectLater(adapter.event('opened'), completes);
      await expectLater(
        adapter.event('opened', parameters: <String, Object>{'count': 3}),
        completes,
      );
    });
  });

  group('the console forwards the RAW error — no redaction here', () {
    // The documented claim this file exists to check, not assume:
    // "Deliberately forwards the raw error at full fidelity — redaction is
    // for the crash reporter only." `FirebaseCrashlyticsAdapter`'s own tests
    // assert the opposite for the same object, at the other egress.
    //
    // All four levels that take an error object are covered here, not just
    // one — each is its own call to the underlying `logger`, so a broken
    // delegation in any one of them (or, for `debug`, `kReleaseMode` read
    // backwards and short-circuiting every call) would otherwise print
    // nothing and go unnoticed by a `completes`-only assertion.
    const FileSystemException error = FileSystemException(
      'could not read',
      '/Users/someone/Library/private-book.epub',
    );

    test('debug prints the real exception text, unredacted', () async {
      await adapter.debug('load failed', error: error);
      expect(printed(), contains('private-book.epub'));
    });

    test('warning prints the real exception text, unredacted', () async {
      await adapter.warning('load failed', error: error);
      expect(printed(), contains('private-book.epub'));
    });

    test('error prints the real exception text, unredacted', () async {
      await adapter.error('load failed', error: error);
      expect(printed(), contains('private-book.epub'));
    });

    test('fatal prints the real exception text, unredacted', () async {
      await adapter.fatal('load failed', error: error);
      expect(printed(), contains('private-book.epub'));
    });
  });

  test('info uses a separate, quieter logger — no stack frames printed', () async {
    // `_infoLogger`'s `PrettyPrinter` is built with `methodCount: 0`; `_logger`
    // (every other level) uses `methodCount: 50`. Constructing `LoggerAdapter`
    // with a single shared `output` and checking which configuration a given
    // call went through is the only way to tell the two loggers apart from
    // outside — there is no other observable difference.
    await adapter.info('i');
    // A method-count-0 printer's box art is a single line; asserting the
    // event produced exactly the message line (plus the printer's box
    // border) rather than a multi-line stack dump is the signal.
    expect(output.buffer.single.lines.length, lessThanOrEqualTo(3));
  });

  test('event includes the parameters map in the printed line', () async {
    await adapter.event('opened', parameters: <String, Object>{'count': 3});
    expect(printed(), contains('opened'));
    expect(printed(), contains('count'));
    expect(printed(), contains('3'));
  });
}
