import 'package:flutter/material.dart';

import 'common_loading_widget.dart';

/// The sliver version of [CommonLoadingWidget], for use inside a
/// [CustomScrollView].
class CommonLoadingSliverWidget extends CommonLoadingWidget {
  const CommonLoadingSliverWidget({
    super.key,
    required super.title,
    super.progress,
  });

  @override
  Widget build(BuildContext context) {
    return SliverFillRemaining(
      hasScrollBody: false,
      child: super.build(context),
    );
  }
}
