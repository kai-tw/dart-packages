import 'package:flutter/material.dart';

/// Asks for confirmation of a destructive action. It does not perform one.
///
/// `show` completes with `true` when the user confirmed and `false` otherwise —
/// cancelled, dismissed, or popped. The caller does the deleting.
///
/// ```dart
/// final bool confirmed = await CommonDeleteDialog.show(context, …);
/// if (!confirmed) {
///   return;
/// }
/// await repository.delete(id);
/// ```
///
/// It used to take an `onDelete` callback and run it itself, which put the work
/// somewhere with no access to the vocabulary for reporting it: the dialog knows
/// nothing about an arbitrary callback's exception types, so its only possible
/// report was `toString()` in a text field. Everything downstream of that was a
/// consequence — an error-message builder, a logging hook, a loading flag, and a
/// class of bugs where the dialog closed on a delete that had not happened.
/// Returning a decision instead of running the work removes all of it: failure
/// is handled where the call is written, which is the only place that knows what
/// failed.
///
/// All copy (`title`, `content`, `cancelLabel`, `deleteLabel`) is required —
/// see the package README §Text ownership.
///
/// [confirmPhrase], if set, gates the confirm button behind a text field that
/// must match it exactly — for actions destructive enough that a second tap
/// isn't enough friction. [confirmFieldHint] is then required too (the same
/// text-ownership rule extends to it — the package cannot phrase "type X to
/// confirm" itself without picking a language).
class CommonDeleteDialog extends StatefulWidget {
  const CommonDeleteDialog({
    super.key,
    required this.title,
    required this.content,
    required this.cancelLabel,
    required this.deleteLabel,
    this.deleteIcon = Icons.delete_rounded,
    this.confirmPhrase,
    this.confirmFieldHint,
  }) : assert(
         confirmPhrase == null || confirmFieldHint != null,
         'confirmFieldHint is required when confirmPhrase is set',
       );

  final String title;
  final String content;
  final String cancelLabel;
  final String deleteLabel;
  final IconData deleteIcon;
  final String? confirmPhrase;
  final String? confirmFieldHint;

  @override
  State<CommonDeleteDialog> createState() => _CommonDeleteDialogState();

  /// Shows the dialog and resolves to the user's decision.
  ///
  /// `false` covers every way of not confirming, including a system back
  /// gesture, so a caller only has to check one thing.
  static Future<bool> show(
    BuildContext context, {
    required String title,
    required String content,
    required String cancelLabel,
    required String deleteLabel,
    IconData deleteIcon = Icons.delete_rounded,
    String? confirmPhrase,
    String? confirmFieldHint,
  }) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => CommonDeleteDialog(
        title: title,
        content: content,
        cancelLabel: cancelLabel,
        deleteLabel: deleteLabel,
        deleteIcon: deleteIcon,
        confirmPhrase: confirmPhrase,
        confirmFieldHint: confirmFieldHint,
      ),
    );
    return confirmed ?? false;
  }
}

class _CommonDeleteDialogState extends State<CommonDeleteDialog> {
  final TextEditingController _confirmController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _confirmController.addListener(_onConfirmTextChanged);
  }

  @override
  void dispose() {
    _confirmController.removeListener(_onConfirmTextChanged);
    _confirmController.dispose();
    super.dispose();
  }

  void _onConfirmTextChanged() {
    setState(() {});
  }

  bool get _confirmSatisfied =>
      widget.confirmPhrase == null ||
      _confirmController.text == widget.confirmPhrase;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(widget.content),
          if (widget.confirmPhrase != null) ...<Widget>[
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: TextField(
                controller: _confirmController,
                decoration: InputDecoration(hintText: widget.confirmFieldHint),
              ),
            ),
          ],
        ],
      ),
      actions: <Widget>[
        TextButton.icon(
          onPressed: () => Navigator.of(context).pop(false),
          icon: const Icon(Icons.close_rounded),
          label: Text(widget.cancelLabel),
        ),
        FilledButton.icon(
          onPressed: _confirmSatisfied
              ? () => Navigator.of(context).pop(true)
              : null,
          icon: Icon(widget.deleteIcon),
          label: Text(widget.deleteLabel),
          style: FilledButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.onError,
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        ),
      ],
    );
  }
}
