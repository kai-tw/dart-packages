import 'package:flutter/material.dart';

import 'common_error_widget.dart';

/// [dismissLabel] is required — see the package README §Text ownership.
class CommonErrorDialog extends CommonErrorWidget {
  const CommonErrorDialog({
    super.key,
    super.icon,
    this.title,
    required super.content,
    required this.dismissLabel,
    this.onDismiss,
  });

  final String? title;
  final String dismissLabel;

  /// Called when the dismiss button is tapped. Defaults to popping the
  /// nearest [Navigator].
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: Icon(iconData),
      iconColor: Theme.of(context).colorScheme.error,
      title: title != null ? Text(title!) : null,
      content: Text(content),
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
