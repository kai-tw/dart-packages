import 'package:flutter/material.dart';

enum CommonBadgeType { hidden, minimal, normal }

class CommonBadge extends StatelessWidget {
  const CommonBadge({
    super.key,
    this.type = CommonBadgeType.minimal,
    this.label,
    this.alignment,
    required this.child,
  });

  final CommonBadgeType type;
  final Widget? label;
  final Alignment? alignment;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    switch (type) {
      case CommonBadgeType.hidden:
        return child;

      case CommonBadgeType.minimal:
        return Badge(alignment: alignment, child: child);

      case CommonBadgeType.normal:
        return Badge(
          label: label ?? const Text('!'),
          alignment: alignment,
          child: child,
        );
    }
  }
}
