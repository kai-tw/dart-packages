import 'dart:io';

import 'package:dart_mutants/src/runner/test_compilation_cache.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory workingDir;

  setUp(() {
    workingDir = Directory.systemTemp.createTempSync(
      'test_compilation_cache_test_',
    );
  });

  tearDown(() => workingDir.deleteSync(recursive: true));

  test(
    'deletes .dart_tool/test/ when present, contents and all',
    () {
      final Directory cacheDir = Directory(
        p.join(workingDir.path, '.dart_tool', 'test'),
      )..createSync(recursive: true);
      File(
        p.join(cacheDir.path, 'incremental_kernel.Ly9AZGFydD0zLjg='),
      ).writeAsBytesSync(<int>[1, 2, 3]);

      TestCompilationCache(workingDir.path).clear();

      expect(cacheDir.existsSync(), isFalse);
    },
  );

  test(
    'a missing cache directory is a no-op, not an error',
    () {
      expect(
        () => TestCompilationCache(workingDir.path).clear(),
        returnsNormally,
      );
    },
  );

  test(
    'leaves the rest of .dart_tool/ alone — only test/ is this cache\'s '
    'business',
    () {
      final Directory pubDir = Directory(
        p.join(workingDir.path, '.dart_tool', 'pub'),
      )..createSync(recursive: true);
      File(
        p.join(pubDir.path, 'package_config.json'),
      ).writeAsStringSync('{}');
      Directory(
        p.join(workingDir.path, '.dart_tool', 'test'),
      ).createSync(recursive: true);

      TestCompilationCache(workingDir.path).clear();

      expect(pubDir.existsSync(), isTrue);
      expect(
        File(p.join(pubDir.path, 'package_config.json')).existsSync(),
        isTrue,
      );
    },
  );

  test(
    'a null workingDirectory resolves against the current process directory',
    () {
      final String original = Directory.current.path;
      addTearDown(() => Directory.current = original);
      Directory.current = workingDir.path;

      Directory(
        p.join(workingDir.path, '.dart_tool', 'test'),
      ).createSync(recursive: true);

      const TestCompilationCache(null).clear();

      expect(
        Directory(p.join(workingDir.path, '.dart_tool', 'test')).existsSync(),
        isFalse,
      );
    },
  );
}
