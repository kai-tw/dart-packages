import 'dart:io';

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter_test/flutter_test.dart';
// Not exported: the crash-reporter egress is package-internal, and this is
// the single highest-value file to test directly — everything that leaves
// the device does so from here.
import 'package:log_system/src/data/adapters/firebase_crashlytics_adapter.dart';
import 'package:mocktail/mocktail.dart';

/// `FirebaseCrashlytics` has a private constructor
/// (`FirebaseCrashlytics._({required this.app})`), so a hand-written fake
/// cannot `extends` it — there is no accessible super-constructor to call.
/// `Mock`'s `implements` sidesteps that: it satisfies the interface via
/// `noSuchMethod` and never calls the real constructor at all.
class _MockFirebaseCrashlytics extends Mock implements FirebaseCrashlytics {}

void main() {
  late _MockFirebaseCrashlytics instance;

  setUpAll(() {
    // mocktail needs a fallback for any type used with `any()` on a method
    // whose parameter is not a primitive — `stackTrace` in `recordError`.
    registerFallbackValue(StackTrace.empty);
  });

  setUp(() {
    instance = _MockFirebaseCrashlytics();
    when(
      () => instance.setCrashlyticsCollectionEnabled(any()),
    ).thenAnswer((_) async {});
    when(
      () => instance.setCustomKey(any(), any()),
    ).thenAnswer((_) async {});
    when(
      () => instance.recordError(
        any(),
        any(),
        reason: any(named: 'reason'),
        printDetails: any(named: 'printDetails'),
        fatal: any(named: 'fatal'),
      ),
    ).thenAnswer((_) async {});
    when(() => instance.log(any())).thenAnswer((_) async {});
  });

  group('the collection switch is thrown on every construction', () {
    test('enabled: true switches collection on', () {
      FirebaseCrashlyticsAdapter(instance, enabled: true);
      verify(() => instance.setCrashlyticsCollectionEnabled(true)).called(1);
    });

    test('enabled: false switches collection off', () {
      FirebaseCrashlyticsAdapter(instance, enabled: false);
      verify(() => instance.setCrashlyticsCollectionEnabled(false)).called(1);
    });

    test(
      'omitting enabled falls back to kReleaseMode — false under flutter '
      'test',
      () {
        // The adapter's own default, not this test's: `enabled: enabled ??
        // kReleaseMode`. Asserted because a caller relying on the default
        // getting flipped silently by a refactor would ship every debug
        // build reporting to production Crashlytics.
        FirebaseCrashlyticsAdapter(instance);
        verify(
          () => instance.setCrashlyticsCollectionEnabled(false),
        ).called(1);
      },
    );

    test('always switched, whatever the value — never left at the SDK '
        'default', () {
      // The SDK default is on. Skipping the call on a disabled build would
      // leave debug-run crashes reporting to the same project as real ones.
      FirebaseCrashlyticsAdapter(instance, enabled: false);
      verify(() => instance.setCrashlyticsCollectionEnabled(false)).called(1);
    });
  });

  group('custom keys are gated by enabled, not sent unconditionally', () {
    test(
      'disabled: no custom key reaches the reporter, deferred or not',
      () async {
        FirebaseCrashlyticsAdapter(
          instance,
          enabled: false,
          customKeys: const <String, String>{'channel': 'beta'},
          deferredCustomKeys: () async => <String, String>{'late': 'value'},
        );
        await Future<void>.delayed(Duration.zero);
        verifyNever(() => instance.setCustomKey(any(), any()));
      },
    );

    test('enabled: every entry in customKeys is stamped', () {
      FirebaseCrashlyticsAdapter(
        instance,
        enabled: true,
        customKeys: const <String, String>{
          'channel': 'beta',
          'sha': 'abc123',
        },
      );
      verify(() => instance.setCustomKey('channel', 'beta')).called(1);
      verify(() => instance.setCustomKey('sha', 'abc123')).called(1);
    });

    test('enabled with no customKeys: nothing is stamped', () {
      FirebaseCrashlyticsAdapter(instance, enabled: true);
      verifyNever(() => instance.setCustomKey(any(), any()));
    });

    test(
      'deferredCustomKeys lands once its future resolves, after construction '
      'returns',
      () async {
        FirebaseCrashlyticsAdapter(
          instance,
          enabled: true,
          deferredCustomKeys: () async => <String, String>{
            'install_id': 'xyz',
          },
        );
        // Not yet — the constructor does not await it, on purpose: it needs a
        // platform round-trip and must not stall startup on it.
        verifyNever(() => instance.setCustomKey('install_id', any()));

        await Future<void>.delayed(Duration.zero);
        verify(() => instance.setCustomKey('install_id', 'xyz')).called(1);
      },
    );

    test('no deferredCustomKeys: nothing pending, nothing stamped', () async {
      FirebaseCrashlyticsAdapter(instance, enabled: true);
      await Future<void>.delayed(Duration.zero);
      verifyNever(() => instance.setCustomKey(any(), any()));
    });
  });

  group('debug and event never reach the reporter, whatever enabled is', () {
    for (final bool enabled in <bool>[true, false]) {
      test('debug — enabled: $enabled', () async {
        final FirebaseCrashlyticsAdapter adapter = FirebaseCrashlyticsAdapter(
          instance,
          enabled: enabled,
        );
        // The construction itself is the only interaction so far — verified
        // here so `verifyNoMoreInteractions` below is judging what `debug`
        // added, not flagging the constructor's own collection-switch call.
        verify(
          () => instance.setCrashlyticsCollectionEnabled(enabled),
        ).called(1);

        await adapter.debug('local only', error: StateError('x'));
        verifyNoMoreInteractions(instance);
      });

      test('event — enabled: $enabled', () async {
        final FirebaseCrashlyticsAdapter adapter = FirebaseCrashlyticsAdapter(
          instance,
          enabled: enabled,
        );
        verify(
          () => instance.setCrashlyticsCollectionEnabled(enabled),
        ).called(1);

        await adapter.event(
          'opened',
          parameters: <String, Object>{
            'count': 3,
          },
        );
        verifyNoMoreInteractions(instance);
      });
    }
  });

  group('info, warning, error, fatal are no-ops while disabled', () {
    late FirebaseCrashlyticsAdapter adapter;

    setUp(() {
      adapter = FirebaseCrashlyticsAdapter(instance, enabled: false);
    });

    test('info', () async {
      await adapter.info('i');
      verifyNever(() => instance.log(any()));
    });

    test('warning', () async {
      await adapter.warning('w', error: StateError('x'));
      verifyNever(() => instance.log(any()));
    });

    test('error does not record a fault entry', () async {
      await adapter.error('e', error: StateError('x'));
      verifyNever(
        () => instance.recordError(
          any(),
          any(),
          reason: any(named: 'reason'),
          printDetails: any(named: 'printDetails'),
          fatal: any(named: 'fatal'),
        ),
      );
    });

    test('fatal does not record a fault entry', () async {
      await adapter.fatal('f', error: StateError('x'));
      verifyNever(
        () => instance.recordError(
          any(),
          any(),
          reason: any(named: 'reason'),
          printDetails: any(named: 'printDetails'),
          fatal: any(named: 'fatal'),
        ),
      );
    });
  });

  group('while enabled', () {
    late FirebaseCrashlyticsAdapter adapter;

    setUp(() {
      adapter = FirebaseCrashlyticsAdapter(instance, enabled: true);
    });

    test('info is logged as a plain breadcrumb, message verbatim', () async {
      await adapter.info('sync finished');
      verify(() => instance.log('Info: sync finished')).called(1);
    });

    test(
      'warning is a breadcrumb, never recordError — a warning is not a '
      'fault',
      () async {
        await adapter.warning('retrying', error: StateError('x'));
        verifyNever(
          () => instance.recordError(
            any(),
            any(),
            reason: any(named: 'reason'),
            printDetails: any(named: 'printDetails'),
            fatal: any(named: 'fatal'),
          ),
        );
      },
    );

    test('a warning with no error is just the message', () async {
      await adapter.warning('nothing went wrong yet');
      verify(() => instance.log('Warning: nothing went wrong yet')).called(1);
    });

    test('a warning\'s error arrives REDACTED, not raw', () async {
      const FileSystemException error = FileSystemException(
        'could not read',
        '/Users/someone/Library/private-book.epub',
      );
      await adapter.warning('load failed', error: error);

      final String logged =
          verify(() => instance.log(captureAny())).captured.single as String;
      expect(logged, 'Warning: load failed — FileSystemException errno=-');
      expect(logged, isNot(contains('private-book')));
      expect(logged, isNot(contains('/Users')));
    });

    test(
      'a warning\'s stack trace is appended after the redacted error',
      () async {
        final StackTrace stack = StackTrace.current;
        await adapter.warning('w', error: StateError('x'), stackTrace: stack);

        final String logged =
            verify(() => instance.log(captureAny())).captured.single as String;
        expect(logged, 'Warning: w — StateError\n$stack');
      },
    );

    test(
      'error records a non-fatal fault entry with the redacted error',
      () async {
        // Each named argument gets its OWN exact-value matcher rather than a
        // second `captureAny()`: mocktail's `VerificationResult.captured`
        // documents only that captures come back in a flat list, not which
        // position a given named capture lands at, and that order was checked
        // empirically here to differ from every plausible guess (call-site
        // order, declaration order, alphabetical). One capture per
        // verification is unambiguous regardless.
        const FileSystemException error = FileSystemException(
          'could not read',
          '/Users/someone/Library/private-book.epub',
        );
        final StackTrace stack = StackTrace.current;

        await adapter.error('load failed', error: error, stackTrace: stack);

        final Object redacted = verify(
          () => instance.recordError(
            captureAny(),
            stack,
            reason: 'load failed',
            // The console sink already printed at full fidelity; the plugin
            // printing the redacted surrogate underneath would read like the
            // error lost its detail.
            printDetails: false,
            fatal: false,
          ),
        ).captured.single;
        expect(redacted.toString(), 'FileSystemException errno=-');
        expect(redacted.toString(), isNot(contains('private-book')));
      },
    );

    test('fatal records the SAME shape, with fatal: true', () async {
      await adapter.fatal('f', error: StateError('x'));

      verify(
        () => instance.recordError(
          any(),
          any(),
          reason: 'f',
          printDetails: false,
          fatal: true,
        ),
      ).called(1);
    });

    test('no error object on error() still records — reason carries the '
        'message', () async {
      await adapter.error('message only');

      final Object redacted = verify(
        () => instance.recordError(
          captureAny(),
          null,
          reason: 'message only',
          printDetails: false,
          fatal: false,
        ),
      ).captured.single;
      expect(redacted.toString(), '<no error object>');
    });
  });
}
