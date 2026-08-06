import 'package:flutter/material.dart';

import 'common_error_widget.dart';

/// The sliver version of [CommonErrorWidget], for use inside a
/// [CustomScrollView].
class CommonErrorSliverWidget extends CommonErrorWidget {
  const CommonErrorSliverWidget({
    super.key,
    super.icon,
    required super.content,
    super.caption,
    super.actions,
  });

  @override
  Widget build(BuildContext context) {
    return SliverFillRemaining(
      hasScrollBody: false,
      child: super.build(context),
    );
  }
}
