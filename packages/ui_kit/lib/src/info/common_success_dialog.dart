import 'package:flutter/material.dart';

/// A success-confirmation dialog. [title] and [content] may both be left
/// `null` for a pure checkmark (rendered larger in that case) — that is a
/// deliberate no-text state, not a missing-copy gap.
///
/// [dismissLabel] is required — see the package README §Text ownership.
class CommonSuccessDialog extends StatelessWidget {
  const CommonSuccessDialog({
    super.key,
    this.title,
    this.content,
    required this.dismissLabel,
    this.onDismiss,
  });

  final String? title;
  final String? content;
  final String dismissLabel;

  /// Called when the dismiss button is tapped. Defaults to popping the
  /// nearest [Navigator].
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: Icon(
        Icons.check_rounded,
        color: Theme.of(context).colorScheme.primary,
        size: title == null && content == null ? 50.0 : null,
      ),
      title: title != null ? Text(title!) : null,
      content: content != null ? Text(content!) : null,
      actions: <Widget>[
        TextButton.icon(
          onPressed: onDismiss ?? () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close_rounded),
          label: Text(dismissLabel),
        ),
      ],
    );
  }
}
