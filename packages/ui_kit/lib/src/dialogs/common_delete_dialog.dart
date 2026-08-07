import 'package:flutter/material.dart';

/// The standard confirm-then-delete dialog: a destructive action gated by a
/// confirmation, with the delete button itself managing [onDelete]'s async
/// lifecycle — a spinner while it runs, and on failure the dialog stays
/// open with the error shown inline rather than closing silently.
///
/// All copy (`title`, `content`, `cancelLabel`, `deleteLabel`) is required —
/// see the package README §Text ownership. [onError] is an optional hook
/// for logging/telemetry only; [errorMessageBuilder] controls what the user
/// sees (defaults to `error.toString()`).
///
/// [confirmPhrase], if set, gates the delete button behind a text field that
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
    required this.onDelete,
    this.errorMessageBuilder,
    this.onError,
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
  final Future<void> Function() onDelete;
  final String Function(Object error)? errorMessageBuilder;
  final void Function(Object error, StackTrace stackTrace)? onError;
  final String? confirmPhrase;
  final String? confirmFieldHint;

  @override
  State<CommonDeleteDialog> createState() => _CommonDeleteDialogState();

  static Future<void> show(
    BuildContext context, {
    required String title,
    required String content,
    required String cancelLabel,
    required String deleteLabel,
    IconData deleteIcon = Icons.delete_rounded,
    required Future<void> Function() onDelete,
    String Function(Object error)? errorMessageBuilder,
    void Function(Object error, StackTrace stackTrace)? onError,
    String? confirmPhrase,
    String? confirmFieldHint,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) => CommonDeleteDialog(
        title: title,
        content: content,
        cancelLabel: cancelLabel,
        deleteLabel: deleteLabel,
        deleteIcon: deleteIcon,
        onDelete: onDelete,
        errorMessageBuilder: errorMessageBuilder,
        onError: onError,
        confirmPhrase: confirmPhrase,
        confirmFieldHint: confirmFieldHint,
      ),
    );
  }
}

class _CommonDeleteDialogState extends State<CommonDeleteDialog> {
  bool _isLoading = false;
  String? _errorMessage;
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
    return PopScope(
      canPop: !_isLoading,
      child: AlertDialog(
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
                  enabled: !_isLoading,
                  decoration: InputDecoration(
                    hintText: widget.confirmFieldHint,
                  ),
                ),
              ),
            ],
            if (_errorMessage != null) ...<Widget>[
              const SizedBox(height: 12.0),
              Text(
                _errorMessage!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
        actions: <Widget>[
          TextButton.icon(
            onPressed: _isLoading ? null : _onCancel,
            icon: const Icon(Icons.close_rounded),
            label: Text(widget.cancelLabel),
          ),
          FilledButton.icon(
            onPressed: _isLoading || !_confirmSatisfied ? null : _onDelete,
            icon: _isLoading
                ? const SizedBox(
                    width: 16.0,
                    height: 16.0,
                    child: CircularProgressIndicator(strokeWidth: 2.0),
                  )
                : Icon(widget.deleteIcon),
            label: Text(widget.deleteLabel),
            style: FilledButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.onError,
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _onDelete() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await widget.onDelete();

      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e, s) {
      widget.onError?.call(e, s);

      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = widget.errorMessageBuilder?.call(e) ?? e.toString();
        });
      }
    }
  }

  void _onCancel() {
    Navigator.of(context).pop();
  }
}
