import 'package:flutter/material.dart';

import 'common_error_dialog.dart';
import 'common_loading_dialog.dart';
import 'common_success_dialog.dart';

/// The three states [CommonProgressDialog] renders. Deliberately narrower
/// than a general-purpose loading vocabulary (no `initial`/
/// `backgroundLoading`) — a progress dialog is, by construction, only ever
/// shown while something is actively in flight.
enum CommonProgressStatus { loading, success, error }

/// A dialog that transitions between loading, success and error states.
///
/// Shows [CommonLoadingDialog] while [status] is `loading`,
/// [CommonSuccessDialog] when `success`, and [CommonErrorDialog] when
/// `error`.
class CommonProgressDialog extends StatelessWidget {
  const CommonProgressDialog({
    super.key,
    required this.status,
    required this.loadingTitle,
    this.successContent,
    required this.errorContent,
    required this.dismissLabel,
    this.onDismiss,
    this.onSuccessDismiss,
    this.onErrorDismiss,
  });

  final CommonProgressStatus status;
  final String loadingTitle;
  final String? successContent;
  final String errorContent;
  final String dismissLabel;

  /// Called when either the success or error dialog is dismissed.
  /// [onSuccessDismiss] and [onErrorDismiss] take precedence when provided.
  final VoidCallback? onDismiss;

  /// Called when the success dialog is dismissed. Falls back to [onDismiss].
  final VoidCallback? onSuccessDismiss;

  /// Called when the error dialog is dismissed. Falls back to [onDismiss].
  final VoidCallback? onErrorDismiss;

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case CommonProgressStatus.success:
        return CommonSuccessDialog(
          content: successContent,
          dismissLabel: dismissLabel,
          onDismiss: onSuccessDismiss ?? onDismiss,
        );

      case CommonProgressStatus.error:
        return CommonErrorDialog(
          content: errorContent,
          dismissLabel: dismissLabel,
          onDismiss: onErrorDismiss ?? onDismiss,
        );

      case CommonProgressStatus.loading:
        return PopScope(
          canPop: false,
          child: CommonLoadingDialog(title: loadingTitle),
        );
    }
  }
}
