import 'package:flutter/material.dart';

import '../badges/common_badge.dart';

enum _CommonNavTileTrailing { none, internal, external }

/// A clickable navigation-style [ListTile]. The trailing icon is decided by
/// which named constructor is used, not by a caller-supplied flag —
/// [CommonNavTile.internal] renders a chevron, [CommonNavTile.external]
/// renders an external-link icon, [CommonNavTile.none] renders neither.
class CommonNavTile extends StatelessWidget {
  const CommonNavTile.none({
    Key? key,
    EdgeInsetsGeometry? padding,
    required Widget leading,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
    CommonBadgeType iconBadgeType = CommonBadgeType.hidden,
    Widget? iconBadgeLabel,
  }) : this._(
         key: key,
         padding: padding,
         leading: leading,
         title: title,
         subtitle: subtitle,
         onTap: onTap,
         iconBadgeType: iconBadgeType,
         iconBadgeLabel: iconBadgeLabel,
         trailing: _CommonNavTileTrailing.none,
         externalSemanticLabel: null,
       );

  const CommonNavTile.internal({
    Key? key,
    EdgeInsetsGeometry? padding,
    required Widget leading,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
    CommonBadgeType iconBadgeType = CommonBadgeType.hidden,
    Widget? iconBadgeLabel,
  }) : this._(
         key: key,
         padding: padding,
         leading: leading,
         title: title,
         subtitle: subtitle,
         onTap: onTap,
         iconBadgeType: iconBadgeType,
         iconBadgeLabel: iconBadgeLabel,
         trailing: _CommonNavTileTrailing.internal,
         externalSemanticLabel: null,
       );

  /// [externalSemanticLabel], if supplied, replaces the trailing icon's
  /// default (decorative, screen-reader-excluded) semantics with an
  /// explicit announcement — e.g. "opens in browser". Left `null`, the icon
  /// carries no semantic label of its own.
  const CommonNavTile.external({
    Key? key,
    EdgeInsetsGeometry? padding,
    required Widget leading,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
    CommonBadgeType iconBadgeType = CommonBadgeType.hidden,
    Widget? iconBadgeLabel,
    String? externalSemanticLabel,
  }) : this._(
         key: key,
         padding: padding,
         leading: leading,
         title: title,
         subtitle: subtitle,
         onTap: onTap,
         iconBadgeType: iconBadgeType,
         iconBadgeLabel: iconBadgeLabel,
         trailing: _CommonNavTileTrailing.external,
         externalSemanticLabel: externalSemanticLabel,
       );

  const CommonNavTile._({
    super.key,
    required this.padding,
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.onTap,
    required this.iconBadgeType,
    required this.iconBadgeLabel,
    required _CommonNavTileTrailing trailing,
    required String? externalSemanticLabel,
  }) : _trailing = trailing,
       _externalSemanticLabel = externalSemanticLabel;

  final EdgeInsetsGeometry? padding;
  final Widget leading;
  final CommonBadgeType iconBadgeType;

  /// What the leading badge shows when [iconBadgeType] is
  /// [CommonBadgeType.normal].
  ///
  /// Left null, the badge falls back to `CommonBadge`'s `Text('!')` — which
  /// used to be the only thing this tile could produce, because the label was
  /// never forwarded at all. A caller wanting a count or its own glyph had to
  /// abandon [iconBadgeType] entirely and wrap [leading] by hand.
  final Widget? iconBadgeLabel;

  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final _CommonNavTileTrailing _trailing;
  final String? _externalSemanticLabel;

  @override
  Widget build(BuildContext context) {
    final Widget? trailing = switch (_trailing) {
      _CommonNavTileTrailing.none => null,
      _CommonNavTileTrailing.internal => const ExcludeSemantics(
        child: Icon(Icons.chevron_right_rounded),
      ),
      _CommonNavTileTrailing.external =>
        _externalSemanticLabel != null
            ? Semantics(
                label: _externalSemanticLabel,
                child: const Icon(Icons.open_in_new_rounded),
              )
            : const ExcludeSemantics(child: Icon(Icons.open_in_new_rounded)),
    };

    return ListTile(
      onTap: onTap,
      contentPadding:
          padding ?? const EdgeInsets.symmetric(horizontal: 8.0, vertical: 0.0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24.0)),
      leading: CommonBadge(
        type: iconBadgeType,
        label: iconBadgeLabel,
        child: leading,
      ),
      title: Text(title),
      subtitle: subtitle != null ? Text(subtitle!) : null,
      trailing: trailing,
    );
  }
}
