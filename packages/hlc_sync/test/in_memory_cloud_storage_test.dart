import 'dart:typed_data';

import 'package:hlc_sync/hlc_sync.dart';
import 'package:test/test.dart';

void main() {
  late InMemoryCloudStorage storage;

  Uint8List bytes(String s) => Uint8List.fromList(s.codeUnits);

  setUp(() {
    storage = InMemoryCloudStorage();
  });

  group('read and write', () {
    test('round-trips', () async {
      await storage.write('/records/customer/c1.json', bytes('hello'));
      expect(await storage.read('/records/customer/c1.json'), bytes('hello'));
    });

    test('a missing path reads null rather than throwing', () async {
      // A record this device has never pushed is the normal state, not an
      // error — treating it as one would make the first sync look broken.
      expect(await storage.read('/nope.json'), isNull);
    });

    test('does not alias the caller buffer', () async {
      // Callers reuse buffers. Storing a reference that changes underneath is
      // the kind of bug that only shows up under load.
      final Uint8List buffer = bytes('one');
      await storage.write('/a.json', buffer);
      buffer[0] = 0;

      expect((await storage.read('/a.json'))![0], isNot(0));
    });

    test('overwrites in place', () async {
      await storage.write('/a.json', bytes('one'));
      await storage.write('/a.json', bytes('two'));
      expect(await storage.read('/a.json'), bytes('two'));
    });
  });

  group('list', () {
    test('returns direct children only', () async {
      await storage.write('/records/customer/c1.json', bytes('a'));
      await storage.write('/records/customer/c2.json', bytes('b'));
      await storage.write('/records/task/t1.json', bytes('c'));

      final List<CloudFile> files = await storage.list('/records/customer');
      expect(
        files.map((CloudFile f) => f.path).toSet(),
        <String>{'/records/customer/c1.json', '/records/customer/c2.json'},
      );
    });

    test('does not recurse into subdirectories', () async {
      await storage.write('/records/a.json', bytes('a'));
      await storage.write('/records/nested/b.json', bytes('b'));

      final List<CloudFile> files = await storage.list('/records');
      expect(files.map((CloudFile f) => f.path), <String>['/records/a.json']);
    });

    test('an empty directory lists empty', () async {
      expect(await storage.list('/records'), isEmpty);
    });

    test('a trailing slash makes no difference', () async {
      await storage.write('/records/a.json', bytes('a'));
      expect(
        (await storage.list('/records/')).length,
        (await storage.list('/records')).length,
      );
    });
  });

  group('delete', () {
    test('removes the file', () async {
      await storage.write('/a.json', bytes('a'));
      await storage.delete('/a.json');
      expect(await storage.read('/a.json'), isNull);
    });

    test('deleting something absent is not an error', () async {
      // Sync retries land here routinely; a throw would turn a no-op into a
      // failed round.
      await expectLater(storage.delete('/nope.json'), completes);
    });
  });

  group('offline', () {
    test('every operation reports offline distinctly', () async {
      // Offline has to stay separate from a storage failure: one means "try
      // later, nothing is wrong", the other means something needs attention.
      // Collapsing them makes every subway ride an error worth showing.
      storage.offline = true;

      await expectLater(
        storage.read('/a.json'),
        throwsA(isA<CloudOfflineException>()),
      );
      await expectLater(
        storage.write('/a.json', bytes('a')),
        throwsA(isA<CloudOfflineException>()),
      );
      await expectLater(
        storage.list('/'),
        throwsA(isA<CloudOfflineException>()),
      );
      await expectLater(
        storage.delete('/a.json'),
        throwsA(isA<CloudOfflineException>()),
      );
    });

    test('recovers when back online', () async {
      await storage.write('/a.json', bytes('a'));
      storage.offline = true;
      storage.offline = false;
      expect(await storage.read('/a.json'), bytes('a'));
    });
  });

  group('InMemoryCloudAuth', () {
    test('reports a cancelled sign-in as false, not an error', () async {
      // Cancelling is an ordinary outcome. Throwing would surface an error
      // toast for someone who simply changed their mind.
      final InMemoryCloudAuth auth = InMemoryCloudAuth(signedIn: false)
        ..cancelNextSignIn = true;

      expect(await auth.signIn(), isFalse);
      expect(await auth.currentlySignedIn(), isFalse);

      expect(await auth.signIn(), isTrue);
      expect(await auth.currentlySignedIn(), isTrue);

      auth.dispose();
    });
  });
}
