import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:connectivity_status/connectivity_status.dart';
import 'package:connectivity_status/src/data/connectivity_repository_impl.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rxdart/rxdart.dart';

import 'helpers/connectivity_mocks.dart';

// ── Helpers ────────────────────────────────────────────────────────────────

/// Build a repository after stubbing both adapter methods.
///
/// The production constructor fires `_seedAndForward()` immediately, which
/// calls `_source.checkConnectivity()` once. Tests that care about call
/// counts must:
///   1. Call [buildRepository] to pre-stub before construction.
///   2. Call `clearInteractions(mockSource)` before the assertion.
///
/// [meteredSource] defaults to a fresh [FakeConnectivityMeteredDataSource]
/// returning `null` (no platform signal → allowlist fallback). Pass a
/// pre-configured fake to exercise the metered=true / metered=false / throw
/// paths.
ConnectivityRepositoryImpl buildRepository({
  required MockConnectivityDataSource mockSource,
  FakeConnectivityMeteredDataSource? meteredSource,
  List<ConnectivityResult> seedResults = const <ConnectivityResult>[],
  Stream<List<ConnectivityResult>>? adapterStream,
}) {
  when(
    () => mockSource.checkConnectivity(),
  ).thenAnswer((_) async => seedResults);
  when(() => mockSource.observeConnectivity()).thenAnswer(
    (_) => adapterStream ?? const Stream<List<ConnectivityResult>>.empty(),
  );
  return ConnectivityRepositoryImpl(
    mockSource,
    meteredSource ?? FakeConnectivityMeteredDataSource(),
  );
}

/// Covers:
///   • ConnectivityResult → ConnectivityStatus mapping decision table
///   • Three-tier metered-source gate (OS signal / allowlist / exception handling)
///   • Stream seeding contract (BehaviorSubject eager-offline seed)
///   • Adapter forwarding via asyncMap
void main() {
  late MockConnectivityDataSource mockSource;

  setUp(() {
    mockSource = MockConnectivityDataSource();
  });

  // ── getStatus mapping decision table ──────────────────────────────────────
  //
  // All tests in this group use the default FakeConnectivityMeteredDataSource
  // (response = null → no platform signal). The metered probe returns null so
  // the allowlist fallback applies:
  //   any(wifi | ethernet) → unmetered; everything else → cellular.
  //
  // rule | input list                          | isOnline | status (null-metered)
  // -----|-------------------------------------|----------|-----------------------
  // R-1  | [none]                              | false    | offline
  // R-2  | [wifi]                              | true     | unmetered
  // R-3  | [mobile]                            | true     | cellular
  // R-4  | [ethernet]                          | true     | unmetered
  // R-5  | [wifi, ethernet]                    | true     | unmetered
  // R-6  | [vpn, wifi]                         | true     | unmetered (wifi in allowlist)
  // R-7  | [none, wifi]  (platform quirk)      | true     | unmetered
  // R-8  | []   (empty — defensive)            | false    | offline
  // R-9  | [bluetooth]                         | true     | cellular  (not in allowlist)
  // R-10 | [vpn]                               | true     | cellular  (not in allowlist)
  // R-11 | [wifi, mobile]  (multi-homed)       | true     | unmetered (wifi in allowlist)
  // R-12 | [mobile, wifi]  (order-stable)      | true     | unmetered (wifi in allowlist)

  group('ConnectivityRepositoryImpl.getStatus — mapping decision table', () {
    test(
      'R-1: [none] maps to offline (isOnline=false, isCellular=false)',
      () async {
        final ConnectivityRepositoryImpl repository = buildRepository(
          mockSource: mockSource,
          seedResults: <ConnectivityResult>[ConnectivityResult.none],
        );

        // Let the construction seed settle, then re-stub for the test call.
        await Future<void>.delayed(Duration.zero);
        when(() => mockSource.checkConnectivity()).thenAnswer(
          (_) async => <ConnectivityResult>[ConnectivityResult.none],
        );

        final ConnectivityStatus status = await repository.getStatus();

        expect(status, equals(ConnectivityStatus.offline));
        expect(status.isOnline, isFalse);
      },
    );

    test('R-2: [wifi] maps to online, non-cellular', () async {
      final ConnectivityRepositoryImpl repository = buildRepository(
        mockSource: mockSource,
        seedResults: <ConnectivityResult>[ConnectivityResult.none],
      );
      await Future<void>.delayed(Duration.zero);
      when(
        () => mockSource.checkConnectivity(),
      ).thenAnswer((_) async => <ConnectivityResult>[ConnectivityResult.wifi]);

      final ConnectivityStatus status = await repository.getStatus();

      expect(status, equals(ConnectivityStatus.unmetered));
    });

    test('R-3: [mobile] maps to online + cellular', () async {
      final ConnectivityRepositoryImpl repository = buildRepository(
        mockSource: mockSource,
        seedResults: <ConnectivityResult>[ConnectivityResult.none],
      );
      await Future<void>.delayed(Duration.zero);
      when(() => mockSource.checkConnectivity()).thenAnswer(
        (_) async => <ConnectivityResult>[ConnectivityResult.mobile],
      );

      final ConnectivityStatus status = await repository.getStatus();

      expect(status, equals(ConnectivityStatus.cellular));
    });

    test('R-4: [ethernet] maps to online, non-cellular', () async {
      final ConnectivityRepositoryImpl repository = buildRepository(
        mockSource: mockSource,
        seedResults: <ConnectivityResult>[ConnectivityResult.none],
      );
      await Future<void>.delayed(Duration.zero);
      when(() => mockSource.checkConnectivity()).thenAnswer(
        (_) async => <ConnectivityResult>[ConnectivityResult.ethernet],
      );

      final ConnectivityStatus status = await repository.getStatus();

      expect(status, equals(ConnectivityStatus.unmetered));
    });

    test(
      'R-5: [wifi, ethernet] maps to online, non-cellular (no mobile)',
      () async {
        final ConnectivityRepositoryImpl repository = buildRepository(
          mockSource: mockSource,
          seedResults: <ConnectivityResult>[ConnectivityResult.none],
        );
        await Future<void>.delayed(Duration.zero);
        when(() => mockSource.checkConnectivity()).thenAnswer(
          (_) async => <ConnectivityResult>[
            ConnectivityResult.wifi,
            ConnectivityResult.ethernet,
          ],
        );

        final ConnectivityStatus status = await repository.getStatus();

        expect(status, equals(ConnectivityStatus.unmetered));
      },
    );

    test('R-6: [vpn, wifi] maps to online, non-cellular '
        '(VPN does not mask the wifi allowlist entry)', () async {
      final ConnectivityRepositoryImpl repository = buildRepository(
        mockSource: mockSource,
        seedResults: <ConnectivityResult>[ConnectivityResult.none],
      );
      await Future<void>.delayed(Duration.zero);
      when(() => mockSource.checkConnectivity()).thenAnswer(
        (_) async => <ConnectivityResult>[
          ConnectivityResult.vpn,
          ConnectivityResult.wifi,
        ],
      );

      final ConnectivityStatus status = await repository.getStatus();

      expect(status, equals(ConnectivityStatus.unmetered));
    });

    test('R-7: [none, wifi] — platform quirk. any-non-none is online; '
        'wifi in allowlist so non-cellular', () async {
      final ConnectivityRepositoryImpl repository = buildRepository(
        mockSource: mockSource,
        seedResults: <ConnectivityResult>[ConnectivityResult.none],
      );
      await Future<void>.delayed(Duration.zero);
      when(() => mockSource.checkConnectivity()).thenAnswer(
        (_) async => <ConnectivityResult>[
          ConnectivityResult.none,
          ConnectivityResult.wifi,
        ],
      );

      final ConnectivityStatus status = await repository.getStatus();

      expect(
        status,
        equals(ConnectivityStatus.unmetered),
        reason:
            'Mapping rule is `any(r != none)`; a wifi entry alongside '
            'a stray none should still register as online + non-cellular.',
      );
    });

    test('R-8: [] (empty defensive input) maps to offline', () async {
      final ConnectivityRepositoryImpl repository = buildRepository(
        mockSource: mockSource,
        seedResults: <ConnectivityResult>[ConnectivityResult.none],
      );
      await Future<void>.delayed(Duration.zero);
      when(
        () => mockSource.checkConnectivity(),
      ).thenAnswer((_) async => const <ConnectivityResult>[]);

      final ConnectivityStatus status = await repository.getStatus();

      expect(status, equals(ConnectivityStatus.offline));
    });

    test('R-9: [bluetooth] maps to online, cellular '
        '(bluetooth is not in the wifi/ethernet allowlist)', () async {
      final ConnectivityRepositoryImpl repository = buildRepository(
        mockSource: mockSource,
        seedResults: <ConnectivityResult>[ConnectivityResult.none],
      );
      await Future<void>.delayed(Duration.zero);
      when(() => mockSource.checkConnectivity()).thenAnswer(
        (_) async => <ConnectivityResult>[ConnectivityResult.bluetooth],
      );

      final ConnectivityStatus status = await repository.getStatus();

      expect(
        status,
        equals(ConnectivityStatus.cellular),
        reason:
            'bluetooth is not in the {wifi, ethernet} allowlist; with no '
            'OS metered signal the heuristic fallback treats it as metered.',
      );
    });

    test('R-10: [vpn] alone maps to online, cellular '
        '(vpn is not in the wifi/ethernet allowlist)', () async {
      final ConnectivityRepositoryImpl repository = buildRepository(
        mockSource: mockSource,
        seedResults: <ConnectivityResult>[ConnectivityResult.none],
      );
      await Future<void>.delayed(Duration.zero);
      when(
        () => mockSource.checkConnectivity(),
      ).thenAnswer((_) async => <ConnectivityResult>[ConnectivityResult.vpn]);

      final ConnectivityStatus status = await repository.getStatus();

      expect(
        status,
        equals(ConnectivityStatus.cellular),
        reason:
            'vpn is not in the {wifi, ethernet} allowlist; with no OS '
            'metered signal, a VPN-only report is treated as metered '
            '(the VPN could be tunnelling over cellular).',
      );
    });

    test(
      'R-11: [wifi, mobile] multi-homed → online, non-cellular '
      '(wifi entry is in the allowlist; allowlist check is any(), not every())',
      () async {
        final ConnectivityRepositoryImpl repository = buildRepository(
          mockSource: mockSource,
          seedResults: <ConnectivityResult>[ConnectivityResult.none],
        );
        await Future<void>.delayed(Duration.zero);
        when(() => mockSource.checkConnectivity()).thenAnswer(
          (_) async => <ConnectivityResult>[
            ConnectivityResult.wifi,
            ConnectivityResult.mobile,
          ],
        );

        final ConnectivityStatus status = await repository.getStatus();

        expect(
          status,
          equals(ConnectivityStatus.unmetered),
          reason:
              '[wifi, mobile] must NOT be cellular: the wifi entry is in the '
              'allowlist. The allowlist uses any() so one unmetered link is '
              'sufficient.',
        );
      },
    );

    test('R-12: [mobile, wifi] reversed order → same non-cellular result '
        '(order-stable; any() is commutative over list order)', () async {
      final ConnectivityRepositoryImpl repository = buildRepository(
        mockSource: mockSource,
        seedResults: <ConnectivityResult>[ConnectivityResult.none],
      );
      await Future<void>.delayed(Duration.zero);
      when(() => mockSource.checkConnectivity()).thenAnswer(
        (_) async => <ConnectivityResult>[
          ConnectivityResult.mobile,
          ConnectivityResult.wifi,
        ],
      );

      final ConnectivityStatus status = await repository.getStatus();

      expect(
        status,
        equals(ConnectivityStatus.unmetered),
        reason:
            'Platform list ordering must not affect the allowlist gate. '
            '[mobile, wifi] and [wifi, mobile] are equivalent multi-homed '
            'states and must both resolve to unmetered.',
      );
    });

    test(
      'forwards exactly one call to the adapter per getStatus() invocation',
      () async {
        // The constructor fires _seedAndForward() → checkConnectivity() once.
        // clearInteractions() resets the call count after the seed settles,
        // so the subsequent explicit getStatus() call shows exactly 1.
        final ConnectivityRepositoryImpl repository = buildRepository(
          mockSource: mockSource,
          seedResults: <ConnectivityResult>[ConnectivityResult.wifi],
        );
        await Future<void>.delayed(Duration.zero);
        clearInteractions(mockSource);

        await repository.getStatus();

        verify(() => mockSource.checkConnectivity()).called(1);
      },
    );
  });

  // ── getStatus: metered-source gate ────────────────────────────────────────
  //
  // Three-tier logic in _statusFrom:
  //   1. offline gate: !isOnline → offline; metered NOT probed.
  //   2. metered=true  → cellular  (regardless of type list)
  //   3. metered=false → unmetered (regardless of type list)
  //   4. metered=null (or probe throws) → heuristic allowlist:
  //         any(wifi | ethernet) → unmetered; else → cellular.
  //
  // Null-metered + type-list cases are additionally covered by R-2 through
  // R-12 in the mapping decision table group above; this group isolates the
  // non-null axes, the offline short-circuit, and the exception paths.

  group('ConnectivityRepositoryImpl.getStatus — metered-source gate', () {
    test(
      'D-offline: metered source is NOT consulted when all results are none',
      () async {
        // The short-circuit `if (!isOnline) return offline;` must not be
        // removed — if it were, the status assertion would still pass but
        // the callCount assertion would catch the regression.
        final FakeConnectivityMeteredDataSource fake =
            FakeConnectivityMeteredDataSource();

        final ConnectivityRepositoryImpl repository = buildRepository(
          mockSource: mockSource,
          meteredSource: fake,
          seedResults: const <ConnectivityResult>[ConnectivityResult.none],
        );
        await Future<void>.delayed(Duration.zero); // seed (offline) settles
        when(() => mockSource.checkConnectivity()).thenAnswer(
          (_) async => const <ConnectivityResult>[ConnectivityResult.none],
        );

        final ConnectivityStatus status = await repository.getStatus();

        expect(status, equals(ConnectivityStatus.offline));
        expect(
          fake.callCount,
          isZero,
          reason:
              '_statusFrom must return offline immediately on no active link '
              'without probing the metered channel. Both the seed call (using '
              '[none]) and the explicit getStatus() call take this path, so '
              'callCount stays 0.',
        );
      },
    );

    test('D-1: online + metered=true + [wifi] → cellular '
        '(OS metered signal overrides the wifi allowlist)', () async {
      // The key VPN-over-cellular case: connectivity_plus may report [wifi]
      // because the VPN exposes a virtual adapter, but the OS flags the
      // underlying transport as metered. The OS flag must win.
      final FakeConnectivityMeteredDataSource fake =
          FakeConnectivityMeteredDataSource();
      fake.response = true;

      final ConnectivityRepositoryImpl repository = buildRepository(
        mockSource: mockSource,
        meteredSource: fake,
        seedResults: const <ConnectivityResult>[ConnectivityResult.none],
      );
      await Future<void>.delayed(Duration.zero);
      when(() => mockSource.checkConnectivity()).thenAnswer(
        (_) async => const <ConnectivityResult>[ConnectivityResult.wifi],
      );

      final ConnectivityStatus status = await repository.getStatus();

      expect(
        status,
        equals(ConnectivityStatus.cellular),
        reason:
            'metered=true is authoritative — the OS flag identifies a '
            'metered-Wi-Fi hotspot or VPN-over-cellular that connectivity_plus '
            'cannot distinguish from a real unmetered Wi-Fi link.',
      );
    });

    test('D-2: online + metered=true + [vpn] → cellular '
        '(metered=true short-circuits before the allowlist)', () async {
      final FakeConnectivityMeteredDataSource fake =
          FakeConnectivityMeteredDataSource();
      fake.response = true;

      final ConnectivityRepositoryImpl repository = buildRepository(
        mockSource: mockSource,
        meteredSource: fake,
        seedResults: const <ConnectivityResult>[ConnectivityResult.none],
      );
      await Future<void>.delayed(Duration.zero);
      when(() => mockSource.checkConnectivity()).thenAnswer(
        (_) async => const <ConnectivityResult>[ConnectivityResult.vpn],
      );

      final ConnectivityStatus status = await repository.getStatus();

      expect(status, equals(ConnectivityStatus.cellular));
    });

    test('D-3: online + metered=true + [other] → cellular '
        '(metered=true handles unknown adapter types unambiguously)', () async {
      final FakeConnectivityMeteredDataSource fake =
          FakeConnectivityMeteredDataSource();
      fake.response = true;

      final ConnectivityRepositoryImpl repository = buildRepository(
        mockSource: mockSource,
        meteredSource: fake,
        seedResults: const <ConnectivityResult>[ConnectivityResult.none],
      );
      await Future<void>.delayed(Duration.zero);
      when(() => mockSource.checkConnectivity()).thenAnswer(
        (_) async => const <ConnectivityResult>[ConnectivityResult.other],
      );

      final ConnectivityStatus status = await repository.getStatus();

      expect(status, equals(ConnectivityStatus.cellular));
    });

    test('D-4: online + metered=false + [mobile] → unmetered '
        '(OS unmetered signal overrides cellular type)', () async {
      final FakeConnectivityMeteredDataSource fake =
          FakeConnectivityMeteredDataSource();
      fake.response = false;

      final ConnectivityRepositoryImpl repository = buildRepository(
        mockSource: mockSource,
        meteredSource: fake,
        seedResults: const <ConnectivityResult>[ConnectivityResult.none],
      );
      await Future<void>.delayed(Duration.zero);
      when(() => mockSource.checkConnectivity()).thenAnswer(
        (_) async => const <ConnectivityResult>[ConnectivityResult.mobile],
      );

      final ConnectivityStatus status = await repository.getStatus();

      expect(
        status,
        equals(ConnectivityStatus.unmetered),
        reason:
            'metered=false from the OS overrides the type-list: mobile would '
            'normally be cellular but an unmetered mobile plan must not gate '
            'downloads.',
      );
    });

    test(
      'D-5: online + metered=false + [vpn, mobile] → unmetered '
      '(OS unmetered signal overrides multi-link non-allowlist list)',
      () async {
        final FakeConnectivityMeteredDataSource fake =
            FakeConnectivityMeteredDataSource();
        fake.response = false;

        final ConnectivityRepositoryImpl repository = buildRepository(
          mockSource: mockSource,
          meteredSource: fake,
          seedResults: const <ConnectivityResult>[ConnectivityResult.none],
        );
        await Future<void>.delayed(Duration.zero);
        when(() => mockSource.checkConnectivity()).thenAnswer(
          (_) async => const <ConnectivityResult>[
            ConnectivityResult.vpn,
            ConnectivityResult.mobile,
          ],
        );

        final ConnectivityStatus status = await repository.getStatus();

        expect(status, equals(ConnectivityStatus.unmetered));
      },
    );

    test('D-6: online + metered=null + [other] → cellular '
        '(other is not in the wifi/ethernet allowlist)', () async {
      final FakeConnectivityMeteredDataSource fake =
          FakeConnectivityMeteredDataSource();

      final ConnectivityRepositoryImpl repository = buildRepository(
        mockSource: mockSource,
        meteredSource: fake,
        seedResults: const <ConnectivityResult>[ConnectivityResult.none],
      );
      await Future<void>.delayed(Duration.zero);
      when(() => mockSource.checkConnectivity()).thenAnswer(
        (_) async => const <ConnectivityResult>[ConnectivityResult.other],
      );

      final ConnectivityStatus status = await repository.getStatus();

      expect(
        status,
        equals(ConnectivityStatus.cellular),
        reason:
            'ConnectivityResult.other is not in the {wifi, ethernet} '
            'allowlist; with no OS metered signal it defaults to cellular.',
      );
    });

    test('D-7: online + metered=null + [vpn, mobile] → cellular '
        '(neither vpn nor mobile is in the allowlist)', () async {
      final FakeConnectivityMeteredDataSource fake =
          FakeConnectivityMeteredDataSource();

      final ConnectivityRepositoryImpl repository = buildRepository(
        mockSource: mockSource,
        meteredSource: fake,
        seedResults: const <ConnectivityResult>[ConnectivityResult.none],
      );
      await Future<void>.delayed(Duration.zero);
      when(() => mockSource.checkConnectivity()).thenAnswer(
        (_) async => const <ConnectivityResult>[
          ConnectivityResult.vpn,
          ConnectivityResult.mobile,
        ],
      );

      final ConnectivityStatus status = await repository.getStatus();

      expect(
        status,
        equals(ConnectivityStatus.cellular),
        reason:
            'Neither vpn nor mobile is in the {wifi, ethernet} allowlist; '
            'the null-metered heuristic must treat the combination as metered.',
      );
    });

    test(
      'D-8: metered source throws PlatformException → _readMetered catches → '
      'null → heuristic fallback → [mobile] → cellular; no throw escapes getStatus',
      () async {
        // Collaborator failure mode: platform channel throws
        // PlatformException (e.g. missing ACCESS_NETWORK_STATE on Android).
        // _readMetered() must catch it and return null so the allowlist
        // fallback applies. getStatus() must not propagate the throw.
        final FakeConnectivityMeteredDataSource fake =
            FakeConnectivityMeteredDataSource();
        fake.throwWith = PlatformException(
          code: 'PERMISSION_DENIED',
          message: 'ACCESS_NETWORK_STATE denied',
        );

        final ConnectivityRepositoryImpl repository = buildRepository(
          mockSource: mockSource,
          meteredSource: fake,
          seedResults: const <ConnectivityResult>[ConnectivityResult.none],
        );
        await Future<void>.delayed(Duration.zero);
        when(() => mockSource.checkConnectivity()).thenAnswer(
          (_) async => const <ConnectivityResult>[ConnectivityResult.mobile],
        );

        // If getStatus() throws here the test fails — that is the "no throw
        // escapes" assertion.
        final ConnectivityStatus status = await repository.getStatus();

        expect(status, equals(ConnectivityStatus.cellular));
        expect(
          fake.callCount,
          isPositive,
          reason:
              'The metered source must be invoked (and then caught) — '
              'the catch must not prevent the call from happening at all.',
        );
      },
    );

    test(
      'D-9: metered source throws TimeoutException → _readMetered catches → '
      'null → heuristic fallback → [mobile] → cellular; no throw escapes getStatus',
      () async {
        // Same absorb-and-fallback contract as D-8, for a probe that outran
        // its timeout.
        final FakeConnectivityMeteredDataSource fake =
            FakeConnectivityMeteredDataSource();
        fake.throwWith = TimeoutException(
          'Metered probe timed out',
          const Duration(seconds: 5),
        );

        final ConnectivityRepositoryImpl repository = buildRepository(
          mockSource: mockSource,
          meteredSource: fake,
          seedResults: const <ConnectivityResult>[ConnectivityResult.none],
        );
        await Future<void>.delayed(Duration.zero);
        when(() => mockSource.checkConnectivity()).thenAnswer(
          (_) async => const <ConnectivityResult>[ConnectivityResult.mobile],
        );

        final ConnectivityStatus status = await repository.getStatus();

        expect(status, equals(ConnectivityStatus.cellular));
        expect(fake.callCount, isPositive);
      },
    );
  });

  // ── observeStatus: seed + forward ─────────────────────────────────────────
  //
  // `observeStatus()` returns the BehaviorSubject's ValueStream, so late
  // subscribers receive the latest value synchronously on subscription.
  // Tests exercise this by subscribing AFTER allowing the seed to settle.
  //
  // The stream's inner transform is `.asyncMap`, so each emission goes
  // through the async metered probe. One `await Future.delayed(Duration.zero)`
  // per event is sufficient because the async hops within `_statusFrom` are
  // all microtasks, and `Future.delayed(Duration.zero)` fires only after the
  // microtask queue drains — so all async processing completes before the
  // assertion runs.

  group('ConnectivityRepositoryImpl.observeStatus — seed + forward', () {
    test(
      'BehaviorSubject seed value is available via stream.value after async seed settles',
      () async {
        // BehaviorSubject.value reflects the most recent addition
        // synchronously, letting late subscribers (including the
        // ValueStream.value accessor) read it without an additional adapter
        // event. Plain StreamController.broadcast() has no such guarantee.
        final ConnectivityRepositoryImpl repository = buildRepository(
          mockSource: mockSource,
          seedResults: <ConnectivityResult>[ConnectivityResult.wifi],
        );

        await Future<void>.delayed(Duration.zero);

        final ValueStream<ConnectivityStatus> stream = repository
            .observeStatus();

        expect(
          stream.value,
          equals(ConnectivityStatus.unmetered),
          reason:
              'BehaviorSubject.value reflects the seeded status. A late '
              'subscriber calling stream.value reads it without any additional '
              'adapter event.',
        );
      },
    );

    test('forwards every adapter event mapped through _statusFrom', () async {
      final StreamController<List<ConnectivityResult>> controller =
          StreamController<List<ConnectivityResult>>();
      final ConnectivityRepositoryImpl repository = buildRepository(
        mockSource: mockSource,
        seedResults: <ConnectivityResult>[ConnectivityResult.none],
        adapterStream: controller.stream,
      );

      // Allow the seed (offline) to settle.
      await Future<void>.delayed(Duration.zero);

      final List<ConnectivityStatus> received = <ConnectivityStatus>[];
      final StreamSubscription<ConnectivityStatus> sub = repository
          .observeStatus()
          .listen(received.add);

      controller.add(<ConnectivityResult>[ConnectivityResult.wifi]);
      await Future<void>.delayed(Duration.zero);
      controller.add(<ConnectivityResult>[ConnectivityResult.mobile]);
      await Future<void>.delayed(Duration.zero);
      controller.add(<ConnectivityResult>[ConnectivityResult.none]);
      await Future<void>.delayed(Duration.zero);

      expect(received, <ConnectivityStatus>[
        ConnectivityStatus.offline, // seed (BehaviorSubject replay)
        ConnectivityStatus.unmetered, // wifi (null metered → allowlist)
        ConnectivityStatus.cellular, // mobile (null metered → not in allowlist)
        ConnectivityStatus.offline, // none
      ]);

      await sub.cancel();
      await controller.close();
    });

    test(
      'seed is offline when adapter returns [none] at construction',
      () async {
        final ConnectivityRepositoryImpl repository = buildRepository(
          mockSource: mockSource,
          seedResults: <ConnectivityResult>[ConnectivityResult.none],
        );
        await Future<void>.delayed(Duration.zero);

        final ValueStream<ConnectivityStatus> stream = repository
            .observeStatus();

        expect(
          stream.value,
          equals(ConnectivityStatus.offline),
          reason: 'BehaviorSubject.value reflects the most recent seed.',
        );
      },
    );

    test('PlatformException during seed → fallback to offline status', () async {
      // PlatformException from the connectivity data source
      // (checkConnectivity) maps to offline fallback in _seedAndForward, not
      // an uncaught error. The metered source is never reached because the
      // exception fires before _statusFrom is called.
      when(() => mockSource.checkConnectivity()).thenThrow(
        PlatformException(code: 'PERMISSION_DENIED', message: 'denied'),
      );
      when(
        () => mockSource.observeConnectivity(),
      ).thenAnswer((_) => const Stream<List<ConnectivityResult>>.empty());

      final ConnectivityRepositoryImpl repository = ConnectivityRepositoryImpl(
        mockSource,
        FakeConnectivityMeteredDataSource(),
      );

      // Allow the async seed to settle (catches PlatformException, adds offline).
      await Future<void>.delayed(Duration.zero);

      final ValueStream<ConnectivityStatus> stream = repository.observeStatus();

      expect(
        stream.value,
        equals(ConnectivityStatus.offline),
        reason:
            'When _seedAndForward catches a PlatformException it must '
            'add ConnectivityStatus.offline to the subject rather than '
            'leaving the subject empty.',
      );
    });
  });
}
