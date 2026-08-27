import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/source/line_info.dart';

import '../../lint_rule_base.dart';

/// Warns when every member of a class is `static`.
///
/// The stock `avoid_classes_with_only_static_members` has a gap that lets
/// the most common shape of this antipattern straight through: **any
/// constructor exempts the class**, so `class X { X._(); static void a() {}
/// }` — a private constructor added specifically to block instantiation —
/// is read as "this class has a constructor" rather than "this class holds
/// no instance state at all." This rule closes that gap: it looks at every
/// member that is not itself a constructor and reports if there is at least
/// one such member and every one of them is `static`.
///
/// **A bare `abstract` class with no constructor at all is exempt**, not
/// caught. `abstract final class CustomerFields { static const id = 'id';
/// }` is Effective Dart's own idiom for a non-instantiable namespace — the
/// language already refuses `CustomerFields()`, so there is no workaround to
/// close. The gap this rule closes is specifically the *redundant*
/// workaround: a constructor written to block instantiation on a class that
/// either could have been `abstract` instead, or already is and gained a
/// constructor anyway. An `abstract` class that also declares one — even a
/// private `X._()` — is still reported: the constructor does nothing there
/// but confirm the class was never going to be a real unit of behavior.
///
/// **The fix for what remains is not a private constructor** — that only
/// stops instantiation, it does not give the members anywhere better to
/// live. Move each member onto the type it actually describes, or fold a
/// closed set of them into an `enum`. A class that exists solely to give
/// `static` members a namespace is not a unit of behavior or state; it is a
/// filing cabinet wearing a class declaration.
///
/// **Interacts with `avoid_top_level_identifiers`.** That rule's own
/// prescribed fix for a top-level function is "namespace it as a static
/// method on a class with a private constructor" — precisely the shape this
/// rule forbids. Enabling both in the same project is coherent (a pure
/// function's real home is an extension method, or the entity it operates
/// on, or an enum for a closed set of related constants) but only if every
/// top-level declaration the other rule catches actually has one of those
/// homes available. Audit both together before enabling them side by side.
///
/// **Bad — private constructor blocks instantiation, changes nothing else:**
/// ```dart
/// class LocaleUtils {
///   LocaleUtils._();
///   static String normalize(String tag) => tag.toLowerCase();
/// }
/// ```
///
/// **Bad — already `abstract`, so the constructor is pure redundancy:**
/// ```dart
/// abstract final class DebounceKeys {
///   DebounceKeys._();
///   static const search = 'search';
/// }
/// ```
///
/// **Fine as-is — bare `abstract`, nothing left to close:**
/// ```dart
/// abstract final class DebounceKeys {
///   static const search = 'search';
///   static const sync = 'sync';
/// }
/// ```
///
/// **Good — the behavior moves onto what it describes:**
/// ```dart
/// extension LocaleNormalization on String {
///   String get normalizedLocale => toLowerCase();
/// }
/// ```
class AvoidStaticOnlyClass extends LintRule {
  AvoidStaticOnlyClass({List<String>? exemptFiles})
    : exemptFiles = exemptFiles ?? const <String>[];

  /// Files a generator owns end to end, so there is nothing to restructure.
  ///
  /// `firebase_options.dart` is the worked example: `DefaultFirebaseOptions`
  /// is a static-only class the flutterfire CLI writes and rewrites, and the
  /// next `flutterfire configure` undoes any hand edit.
  final List<String> exemptFiles;

  @override
  String get name => 'avoid_static_only_class';

  @override
  String get description =>
      'Avoid a class whose members are all static. Move each member onto '
      'the type it describes, or fold a closed set into an enum — a private '
      'constructor does not turn a namespace into a unit.';

  @override
  LintVisitor createVisitor(
    String filePath,
    LineInfo lineInfo,
    String source,
  ) => _Visitor(filePath, lineInfo, source, exemptFiles);
}

class _Visitor extends LintVisitor {
  _Visitor(super.filePath, super.lineInfo, super.source, this.exemptFiles);

  final List<String> exemptFiles;

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    if (exemptFiles.any(filePath.endsWith)) {
      super.visitClassDeclaration(node);
      return;
    }

    bool hasMember = false;
    bool hasConstructor = false;
    bool allStatic = true;
    for (final ClassMember member in node.members) {
      if (member is ConstructorDeclaration) {
        hasConstructor = true;
        continue;
      }
      hasMember = true;
      final bool isStatic = switch (member) {
        FieldDeclaration(:final bool isStatic) => isStatic,
        MethodDeclaration(:final bool isStatic) => isStatic,
        _ => true,
      };
      if (!isStatic) {
        allStatic = false;
        break;
      }
    }

    // A bare `abstract` class with no constructor is already uninstantiable
    // by the language itself — Effective Dart's own recommended shape for a
    // namespace, and there is no redundant workaround left to flag. One that
    // ALSO declares a constructor still reports: the constructor is doing
    // nothing there, which is the tell that the class was never a unit.
    final bool isUnclosableWithoutWorkaround =
        node.abstractKeyword != null && !hasConstructor;

    if (hasMember && allStatic && !isUnclosableWithoutWorkaround) {
      report(
        ruleName: 'avoid_static_only_class',
        message:
            "'${node.name.lexeme}' has no member that is not static. Move "
            'each member onto the type it describes, or fold a closed set '
            'into an enum — a private constructor does not turn a '
            'namespace into a unit.',
        offset: node.name.offset,
      );
    }

    super.visitClassDeclaration(node);
  }
}
