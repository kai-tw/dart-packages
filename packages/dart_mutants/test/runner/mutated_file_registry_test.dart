import 'dart:io';

import 'package:dart_mutants/src/runner/mutated_file_registry.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tempDir;
  late File file;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('mutated_file_registry_test_');
    file = File(p.join(tempDir.path, 'target.dart'))
      ..writeAsStringSync('original content');
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  test('[partition] restore puts the tracked content back', () {
    final MutatedFileRegistry registry = MutatedFileRegistry();
    registry.track(file.path, 'original content');
    file.writeAsStringSync('mutated content');

    registry.restore(file.path);

    expect(file.readAsStringSync(), 'original content');
  });

  test('[boundary] restoring an untracked path is a no-op, not an error', () {
    final MutatedFileRegistry registry = MutatedFileRegistry();
    expect(() => registry.restore(file.path), returnsNormally);
  });

  test(
    '[boundary] the second track for the same path does not overwrite the '
    'first — only the true original is ever restored',
    () {
      final MutatedFileRegistry registry = MutatedFileRegistry();
      registry.track(file.path, 'true original');
      registry.track(file.path, 'a later mutant\'s "before" snapshot');
      file.writeAsStringSync('current mutated state');

      registry.restore(file.path);

      expect(file.readAsStringSync(), 'true original');
    },
  );

  test('[partition] restoreAll restores every tracked file', () {
    final File second = File(p.join(tempDir.path, 'second.dart'))
      ..writeAsStringSync('second original');
    final MutatedFileRegistry registry = MutatedFileRegistry();
    registry.track(file.path, 'original content');
    registry.track(second.path, 'second original');
    file.writeAsStringSync('mutated');
    second.writeAsStringSync('mutated');

    registry.restoreAll();

    expect(file.readAsStringSync(), 'original content');
    expect(second.readAsStringSync(), 'second original');
  });

  test('[boundary] restore after restoreAll is a no-op', () {
    final MutatedFileRegistry registry = MutatedFileRegistry();
    registry.track(file.path, 'original content');
    registry.restoreAll();
    file.writeAsStringSync('mutated again, unrelated to this registry now');

    registry.restore(file.path);

    // restoreAll already forgot this path, so a later restore() must not
    // resurrect a stale snapshot over whatever is there now.
    expect(
      file.readAsStringSync(),
      'mutated again, unrelated to this registry now',
    );
  });

  test(
    '[partition] armSignalRestore is idempotent and disarm leaves it '
    'callable again',
    () async {
      final MutatedFileRegistry registry = MutatedFileRegistry();
      expect(registry.isArmed, isFalse);
      registry.armSignalRestore();
      expect(registry.isArmed, isTrue);
      registry.armSignalRestore(); // must not double-subscribe
      await registry.disarm();
      expect(registry.isArmed, isFalse);
    },
  );
}
