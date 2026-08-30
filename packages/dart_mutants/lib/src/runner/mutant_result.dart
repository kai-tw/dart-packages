import '../mutant.dart';
import 'mutant_verdict.dart';

/// One [Mutant] paired with what happened when it ran.
class MutantResult {
  const MutantResult({required this.mutant, required this.verdict});

  final Mutant mutant;
  final MutantVerdict verdict;

  Map<String, Object?> toJson() => <String, Object?>{
    'filePath': mutant.filePath,
    'line': mutant.line,
    'column': mutant.column,
    'operatorName': mutant.operatorName,
    'description': mutant.description,
    'verdict': verdict.name,
  };
}
