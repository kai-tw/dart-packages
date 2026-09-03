import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter_test/flutter_test.dart';
// Not exported: package-internal, and the one place in this package still
// worth mocking the real SDK type — see the class doc on
// `FirebaseCrashlyticsClient` for why everything else moved off it.
import 'package:log_system/src/data/adapters/firebase_crashlytics_client.dart';
import 'package:mocktail/mocktail.dart';

/// `FirebaseCrashlytics` has a private constructor
/// (`FirebaseCrashlytics._({required this.app})`), so a hand-written fake
/// cannot `extends` it — there is no accessible super-constructor to call.
/// `Mock`'s `implements` sidesteps that: it satisfies the interface via
/// `noSuchMethod` and never calls the real constructor at all.
class _MockFirebaseCrashlytics extends Mock implements FirebaseCrashlytics {}

void main() {
  late _MockFirebaseCrashlytics instance;
  late FirebaseCrashlyticsClient client;

  setUpAll(() {
    registerFallbackValue(StackTrace.empty);
  });

  setUp(() {
    instance = _MockFirebaseCrashlytics();
    client = FirebaseCrashlyticsClient.wrapping(instance);
    when(
      () => instance.setCrashlyticsCollectionEnabled(any()),
    ).thenAnswer((_) async {});
    when(
      () => instance.setCustomKey(any(), any()),
    ).thenAnswer((_) async {});
    when(() => instance.log(any())).thenAnswer((_) async {});
    when(
      () => instance.recordError(
        any(),
        any(),
        reason: any(named: 'reason'),
        printDetails: any(named: 'printDetails'),
        fatal: any(named: 'fatal'),
      ),
    ).thenAnswer((_) async {});
  });

  // Every test here is pure delegation: one call in, the identical call out.
  // No captures, so the multi-argument capture-order ambiguity
  // `firebase_crashlytics_adapter_test.dart` used to work around does not
  // arise — a plain `verify()` against literal expected values only needs
  // the invocation to match, never to report back which value was which.

  test('setCrashlyticsCollectionEnabled delegates with the same value', () {
    client.setCrashlyticsCollectionEnabled(true);
    verify(() => instance.setCrashlyticsCollectionEnabled(true)).called(1);
  });

  test('setCustomKey delegates with the same key and value', () {
    client.setCustomKey('channel', 'beta');
    verify(() => instance.setCustomKey('channel', 'beta')).called(1);
  });

  test('log delegates with the same message', () {
    client.log('hello');
    verify(() => instance.log('hello')).called(1);
  });

  test('recordError delegates with every argument, unchanged', () {
    final Object exception = StateError('x');
    final StackTrace stack = StackTrace.current;

    client.recordError(
      exception,
      stack,
      reason: 'load failed',
      printDetails: false,
      fatal: true,
    );

    verify(
      () => instance.recordError(
        exception,
        stack,
        reason: 'load failed',
        printDetails: false,
        fatal: true,
      ),
    ).called(1);
  });

  test('recordError delegates a null reason and stack trace as-is', () {
    client.recordError(
      'exception text',
      null,
      reason: null,
      printDetails: true,
      fatal: false,
    );

    verify(
      () => instance.recordError(
        'exception text',
        null,
        reason: null,
        printDetails: true,
        fatal: false,
      ),
    ).called(1);
  });
}
