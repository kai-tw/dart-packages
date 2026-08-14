import 'dart:io';

import 'package:path/path.dart' as p;

/// The filesystem reads the configuration layer needs, behind an interface so
/// validation can be tested against a described tree instead of a real one.
abstract class FileSystemProbe {
  bool exists(String path);

  /// Every `.dart` file under [rootDirectory], as POSIX paths relative to it.
  List<String> dartFilesUnder(String rootDirectory);
}

class SystemFileSystemProbe implements FileSystemProbe {
  const SystemFileSystemProbe();

  /// Directories never worth walking: build output and VCS metadata hold no
  /// source anyone lints, and `.dart_tool` alone can dwarf a repository.
  static const Set<String> _skipDirectories = <String>{
    '.dart_tool',
    '.git',
    'build',
    '.symlinks',
  };

  @override
  bool exists(String path) =>
      FileSystemEntity.isDirectorySync(path) ||
      FileSystemEntity.isFileSync(path);

  @override
  List<String> dartFilesUnder(String rootDirectory) {
    final List<String>? tracked = _gitFilesUnder(rootDirectory);
    if (tracked != null) {
      return tracked;
    }

    final List<String> found = <String>[];
    _walk(Directory(rootDirectory), rootDirectory, found);
    found.sort();
    return found;
  }

  /// The Dart files git considers part of the repository, or null when this is
  /// not a work tree.
  ///
  /// Asking git beats walking the tree and beats parsing `.gitignore` by hand:
  /// it applies the full ignore ruleset (repo, global, `.git/info/exclude`) the
  /// way the project already means it. Without this, an in-repo worktree
  /// directory — a layout both consuming projects use — contributes thousands
  /// of checked-out copies that no area could sensibly claim, and coverage
  /// validation fails on files that are not really part of the tree.
  ///
  /// `--cached --others --exclude-standard` is tracked files plus untracked
  /// ones that are not ignored: a file added but not yet committed still has to
  /// be linted.
  List<String>? _gitFilesUnder(String rootDirectory) {
    final ProcessResult result;
    try {
      result = Process.runSync('git', <String>[
        '-C',
        rootDirectory,
        'ls-files',
        '--cached',
        '--others',
        '--exclude-standard',
        '--',
        '*.dart',
      ]);
    } on ProcessException {
      return null;
    }
    if (result.exitCode != 0) {
      return null;
    }

    return (result.stdout as String)
        .split('\n')
        .where((String line) => line.isNotEmpty)
        .toList()
      ..sort();
  }

  void _walk(Directory directory, String rootDirectory, List<String> found) {
    // listSync throws on a directory that vanished or denies access mid-walk;
    // coverage reporting is advisory about such a directory, not entitled to
    // abort the run over it.
    late final List<FileSystemEntity> entries;
    try {
      entries = directory.listSync(followLinks: false);
    } on FileSystemException {
      return;
    }

    for (final FileSystemEntity entity in entries) {
      final String name = p.basename(entity.path);
      if (entity is Directory) {
        if (_skipDirectories.contains(name) || name.startsWith('.')) {
          continue;
        }
        _walk(entity, rootDirectory, found);
        continue;
      }
      if (entity is File && name.endsWith('.dart')) {
        found.add(
          p.posix.joinAll(
            p.split(p.relative(entity.path, from: rootDirectory)),
          ),
        );
      }
    }
  }
}
