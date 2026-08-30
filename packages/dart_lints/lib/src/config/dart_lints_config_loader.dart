import 'dart:io';

import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../rule_descriptor.dart';
import '../rule_registry.dart';
import 'analyzer_spec.dart';
import 'area.dart';
import 'area_coverage_check.dart';
import 'dart_lints_config.dart';
import 'dart_lints_config_exception.dart';
import 'file_system_probe.dart';

/// Reads and validates `dart_lints.yaml`.
///
/// Validation is total and fatal: every name is checked against the registry,
/// every option key against the rule that accepts it, every value against the
/// kind that key declares, and every Dart file against the areas. Anything
/// unrecognised stops the run. A configuration layer that warns instead would
/// leave the rule disabled and the run green, which is indistinguishable from
/// the rule passing.
class DartLintsConfigLoader {
  const DartLintsConfigLoader(this.registry, this.probe);

  static const String fileName = 'dart_lints.yaml';

  final RuleRegistry registry;
  final FileSystemProbe probe;

  /// The nearest [fileName] at or above [fromDirectory].
  String discover(String fromDirectory) {
    final String start = p.absolute(fromDirectory);

    // Bounded by the segment count: the walk can visit each ancestor once and
    // the root once, so it terminates without relying on the parent-of-root
    // fixed point alone.
    Directory current = Directory(start);
    for (int i = 0; i <= p.split(start).length; i++) {
      final String candidate = p.join(current.path, fileName);
      if (probe.exists(candidate)) {
        return candidate;
      }
      current = current.parent;
    }

    throw DartLintsConfigException('no $fileName found at or above $start');
  }

  DartLintsConfig load(String configPath) {
    final String root = p.dirname(p.absolute(configPath));
    final YamlMap document = _parse(configPath);

    final AnalyzerSpec analyzer = _analyzerSpec(
      document['analyzer'],
      configPath,
      'analyzer',
    );
    final List<Glob> exclude = _globs(
      document['exclude'],
      configPath,
      'exclude',
    );
    final List<Glob> coverageIgnore = _globs(
      document['coverageIgnore'],
      configPath,
      'coverageIgnore',
    );

    final Set<String> globalRules = _globalRuleSet(document, configPath);
    final Map<String, Map<String, Object?>> options = _withPackageNameDefault(
      _options(document['options'], configPath),
      _pubspecPackageName(root),
    );
    final List<Area> areas = _areas(
      document['areas'],
      globalRules,
      configPath,
      root,
    );

    final DartLintsConfig config = DartLintsConfig(
      rootDirectory: root,
      analyzer: analyzer,
      areas: areas,
      excludeGlobs: exclude,
      coverageIgnore: coverageIgnore,
      options: options,
    );

    _assertAreaPathsExist(config, configPath);
    _assertFullCoverage(config, configPath);
    return config;
  }

  YamlMap _parse(String configPath) {
    final String text;
    try {
      text = File(configPath).readAsStringSync();
    } on FileSystemException catch (e) {
      throw DartLintsConfigException(
        'cannot read config: ${e.message}',
        configPath: configPath,
      );
    }

    final Object? document;
    try {
      document = loadYaml(text);
    } on YamlException catch (e, stackTrace) {
      Error.throwWithStackTrace(
        DartLintsConfigException(
          'invalid YAML: ${e.message}',
          configPath: configPath,
        ),
        stackTrace,
      );
    }

    // An empty or comment-only document parses to null, not an empty map.
    if (document is! YamlMap) {
      throw DartLintsConfigException(
        'config is empty — expected a YAML map with at least an "areas:" key',
        configPath: configPath,
      );
    }
    return document;
  }

  Set<String> _globalRuleSet(YamlMap document, String configPath) {
    final Set<String> rules = <String>{};

    for (final String bundle in _stringList(
      document['bundles'],
      configPath,
      'bundles',
    )) {
      if (!registry.bundleNames.contains(bundle)) {
        throw DartLintsConfigException(
          'unknown bundle "$bundle"',
          configPath: configPath,
          suggestions: _nearest(bundle, registry.bundleNames),
        );
      }
      rules.addAll(registry.bundleRules(bundle));
    }

    for (final String rule in _stringList(
      document['enable'],
      configPath,
      'enable',
    )) {
      _assertKnownRule(rule, configPath, 'enable');
      rules.add(rule);
    }

    return rules;
  }

  List<Area> _areas(
    Object? node,
    Set<String> globalRules,
    String configPath,
    String root,
  ) {
    if (node is! YamlMap || node.isEmpty) {
      throw DartLintsConfigException(
        'config must declare at least one area under "areas:"',
        configPath: configPath,
      );
    }

    final List<Area> areas = <Area>[];
    for (final MapEntry<Object?, Object?> entry in node.entries) {
      final String name = entry.key.toString();
      final Object? body = entry.value;
      if (body is! YamlMap) {
        throw DartLintsConfigException(
          'area "$name" must be a map with a "paths:" key',
          configPath: configPath,
        );
      }

      final List<String> paths = _stringList(
        body['paths'],
        configPath,
        'areas.$name.paths',
      );
      if (paths.isEmpty) {
        throw DartLintsConfigException(
          'area "$name" declares no paths',
          configPath: configPath,
        );
      }

      final Set<String> rules = <String>{...globalRules};
      for (final String rule in _stringList(
        body['enable'],
        configPath,
        'areas.$name.enable',
      )) {
        _assertKnownRule(rule, configPath, 'areas.$name.enable');
        rules.add(rule);
      }
      for (final String rule in _stringList(
        body['disable'],
        configPath,
        'areas.$name.disable',
      )) {
        _assertKnownRule(rule, configPath, 'areas.$name.disable');
        rules.remove(rule);
      }

      areas.add(
        Area(
          name: name,
          pathGlobs: paths.map((String g) => Glob(g)).toList(),
          enabledRules: rules,
          optionOverrides: _options(body['options'], configPath),
          analyzer: body['analyzer'] == null
              ? null
              : _analyzerSpec(
                  body['analyzer'],
                  configPath,
                  'areas.$name.analyzer',
                ),
        ),
      );
    }
    return areas;
  }

  /// `avoid_layer_violation` needs the project's own package name to tell a
  /// self `package:` import (subject to the layer rules) from a dependency's
  /// (never subject to them) — without it, every `package:` import reads as
  /// external and the rule never fires. Reading it from the same
  /// `pubspec.yaml` `dart_lints.yaml` already sits beside means a consuming
  /// project gets a working rule for free; `options.avoid_layer_violation`
  /// still overrides this if a workspace member's own name differs from the
  /// config root's.
  Map<String, Map<String, Object?>> _withPackageNameDefault(
    Map<String, Map<String, Object?>> options,
    String? packageName,
  ) {
    if (packageName == null) {
      return options;
    }
    final Map<String, Object?> existing =
        options['avoid_layer_violation'] ?? const <String, Object?>{};
    if (existing.containsKey('packageName')) {
      return options;
    }
    return <String, Map<String, Object?>>{
      ...options,
      'avoid_layer_violation': <String, Object?>{
        ...existing,
        'packageName': packageName,
      },
    };
  }

  /// The `name:` field of `<root>/pubspec.yaml`, or null when the file is
  /// missing, unreadable, unparsable, or declares no name — every case is a
  /// silent pass-through here rather than a thrown [DartLintsConfigException],
  /// because a missing name only weakens one rule's default rather than
  /// invalidating the whole configuration.
  String? _pubspecPackageName(String root) {
    final String? text = probe.readFile(p.join(root, 'pubspec.yaml'));
    if (text == null) {
      return null;
    }
    final Object? document;
    try {
      document = loadYaml(text);
    } on YamlException {
      return null;
    }
    if (document is! YamlMap) {
      return null;
    }
    final Object? name = document['name'];
    return name is String ? name : null;
  }

  Map<String, Map<String, Object?>> _options(Object? node, String configPath) {
    if (node == null) {
      return const <String, Map<String, Object?>>{};
    }
    if (node is! YamlMap) {
      throw DartLintsConfigException(
        '"options:" must be a map of rule name to its options',
        configPath: configPath,
      );
    }

    final Map<String, Map<String, Object?>> result =
        <String, Map<String, Object?>>{};
    for (final MapEntry<Object?, Object?> entry in node.entries) {
      final String rule = entry.key.toString();
      final RuleDescriptor descriptor = _assertKnownRule(
        rule,
        configPath,
        'options',
      );

      final Object? body = entry.value;
      if (body is! YamlMap) {
        throw DartLintsConfigException(
          'options for "$rule" must be a map',
          configPath: configPath,
        );
      }

      final Map<String, Object?> ruleOptions = <String, Object?>{};
      for (final MapEntry<Object?, Object?> option in body.entries) {
        final String key = option.key.toString();
        final OptionKind? kind = descriptor.options[key];
        if (kind == null) {
          throw DartLintsConfigException(
            'rule "$rule" has no option "$key"',
            configPath: configPath,
            suggestions: _nearest(key, descriptor.options.keys.toSet()),
          );
        }
        ruleOptions[key] = _coerce(
          option.value,
          kind,
          configPath,
          '$rule.$key',
        );
      }
      result[rule] = ruleOptions;
    }
    return result;
  }

  Object _coerce(Object? value, OptionKind kind, String configPath, String at) {
    switch (kind) {
      case OptionKind.string:
        if (value is String) {
          return value;
        }
        throw DartLintsConfigException(
          '"$at" must be a string, got ${_typeName(value)}',
          configPath: configPath,
        );
      case OptionKind.stringList:
        if (value is YamlList &&
            value.every((Object? item) => item is String)) {
          return value.cast<String>().toList();
        }
        throw DartLintsConfigException(
          '"$at" must be a list of strings, got ${_typeName(value)}',
          configPath: configPath,
        );
      case OptionKind.mapList:
        if (value is YamlList &&
            value.every((Object? item) => item is YamlMap)) {
          return value
              .cast<YamlMap>()
              .map(
                (YamlMap m) => m.map(
                  (Object? k, Object? v) =>
                      MapEntry<String, Object?>(k.toString(), v),
                ),
              )
              .toList();
        }
        throw DartLintsConfigException(
          '"$at" must be a list of maps, got ${_typeName(value)}',
          configPath: configPath,
        );
      case OptionKind.integer:
        if (value is int) {
          return value;
        }
        throw DartLintsConfigException(
          '"$at" must be an integer, got ${_typeName(value)}',
          configPath: configPath,
        );
    }
  }

  AnalyzerSpec _analyzerSpec(Object? node, String configPath, String at) {
    if (node == null) {
      return AnalyzerSpec.none;
    }
    if (node is! YamlMap) {
      throw DartLintsConfigException(
        '"$at" must be a map with a "command:" key',
        configPath: configPath,
      );
    }

    final String command = (node['command'] ?? 'none').toString();
    final AnalyzerCommand? resolved = AnalyzerCommand.values
        .where((AnalyzerCommand c) => c.name == command)
        .firstOrNull;
    if (resolved == null) {
      throw DartLintsConfigException(
        'unknown analyzer command "$command"',
        configPath: configPath,
        suggestions: AnalyzerCommand.values
            .map((AnalyzerCommand c) => c.name)
            .toList(),
      );
    }

    return AnalyzerSpec(
      command: resolved,
      args: _stringList(node['args'], configPath, '$at.args'),
      paths: _stringList(node['paths'], configPath, '$at.paths'),
    );
  }

  void _assertAreaPathsExist(DartLintsConfig config, String configPath) {
    for (final Area area in config.areas) {
      final bool anyMatch = probe
          .dartFilesUnder(config.rootDirectory)
          .any(area.matches);
      if (!anyMatch) {
        throw DartLintsConfigException(
          'area "${area.name}" matches no Dart file — check its paths',
          configPath: configPath,
        );
      }
    }
  }

  void _assertFullCoverage(DartLintsConfig config, String configPath) {
    final List<String> uncovered = AreaCoverageCheck(probe).uncovered(config);
    if (uncovered.isEmpty) {
      return;
    }
    const int shown = 10;
    final String sample = uncovered.take(shown).join('\n    ');
    final String more = uncovered.length > shown
        ? '\n    …and ${uncovered.length - shown} more'
        : '';
    throw DartLintsConfigException(
      '${uncovered.length} Dart file(s) belong to no area and are not in '
      '"coverageIgnore:" — they would go unlinted while the run reported '
      'success:\n    $sample$more',
      configPath: configPath,
    );
  }

  RuleDescriptor _assertKnownRule(String rule, String configPath, String at) {
    final RuleDescriptor? descriptor = registry.byName(rule);
    if (descriptor == null) {
      throw DartLintsConfigException(
        'unknown rule "$rule" in "$at"',
        configPath: configPath,
        suggestions: _nearest(rule, registry.ruleNames),
      );
    }
    return descriptor;
  }

  List<String> _stringList(Object? node, String configPath, String at) {
    if (node == null) {
      return const <String>[];
    }
    if (node is! YamlList || node.any((Object? item) => item is! String)) {
      throw DartLintsConfigException(
        '"$at" must be a list of strings, got ${_typeName(node)}',
        configPath: configPath,
      );
    }
    return node.cast<String>().toList();
  }

  List<Glob> _globs(Object? node, String configPath, String at) =>
      _stringList(node, configPath, at).map((String g) => Glob(g)).toList();

  String _typeName(Object? value) =>
      value == null ? 'nothing' : value.runtimeType.toString();

  /// Candidate spellings for an unrecognised name — anything sharing a prefix
  /// or differing by a character or two reads as the likely intent.
  List<String> _nearest(String typo, Set<String> known) {
    final List<String> byPrefix =
        known
            .where(
              (String k) =>
                  k.startsWith(typo) ||
                  typo.startsWith(k) ||
                  (typo.length > 3 && k.contains(typo)),
            )
            .toList()
          ..sort();
    return byPrefix.take(5).toList();
  }
}
