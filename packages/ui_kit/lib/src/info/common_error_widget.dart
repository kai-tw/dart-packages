import 'package:flutter/material.dart';

import 'common_info_widget.dart';

/// [content] is required and carries no built-in fallback text — this
/// package ships no copy of its own, so every caller supplies its own
/// error message (see the package README §Text ownership).
class CommonErrorWidget extends StatelessWidget {
  const CommonErrorWidget({
    super.key,
    this.icon,
    required this.content,
    this.caption,
    this.actions,
  });

  final IconData? icon;
  final String content;
  final String? caption;
  final List<Widget>? actions;

  IconData get iconData => icon ?? Icons.error_outline_rounded;

  @override
  Widget build(BuildContext context) {
    return CommonInfoWidget(
      icon: iconData,
      iconColor: Theme.of(context).colorScheme.error,
      title: content,
      caption: caption,
      actions: actions,
    );
  }
}
