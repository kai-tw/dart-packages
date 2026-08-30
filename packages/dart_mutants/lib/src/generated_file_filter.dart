/// Whether [filePath] is generated output this package should never mutate.
///
/// Not configurable in v1 — these four are universal across every project in
/// this workspace and every project this tool is likely to run against next;
/// a generator's own output is never hand-edited, and mutating it tests
/// nothing about anyone's actual code. Revisit if a real project turns up a
/// generated-output convention outside this list.
bool isGeneratedFile(String filePath) {
  const List<String> suffixes = <String>[
    '.g.dart',
    '.freezed.dart',
    '.mocks.dart',
  ];
  if (suffixes.any(filePath.endsWith)) {
    return true;
  }
  return filePath.contains('/generated/');
}
