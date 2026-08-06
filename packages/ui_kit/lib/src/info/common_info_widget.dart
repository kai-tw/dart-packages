import 'package:flutter/material.dart';

/// A centred placeholder for a calm informational message — icon + title,
/// with optional [caption] body text and optional [actions] button row.
/// Defaults to `onSurfaceVariant` for the icon; pass an explicit [iconColor]
/// to tint per state (e.g. `colorScheme.error`).
///
/// Composition base for [CommonErrorWidget] and [CommonLoadingWidget] — use
/// this directly when the surface needs to show a neutral state (empty,
/// offline, info) that may carry an action.
///
/// Two density variants:
///
/// - **Default (`dense: false`)** — full-screen empty/error/offline
///   placeholder. 48px icon, `titleMedium` title, generous spacing,
///   `SafeArea` + 24px horizontal padding.
/// - **Dense (`dense: true`)** — inline-card placeholder for sections that
///   already live inside another scaffold (no `SafeArea`, no extra
///   padding). 20px icon, `bodyMedium` subdued title, tight spacing.
class CommonInfoWidget extends StatelessWidget {
  const CommonInfoWidget({
    super.key,
    this.icon,
    this.iconColor,
    required this.title,
    this.caption,
    this.actions,
    this.dense = false,
  });

  final IconData? icon;
  final Color? iconColor;
  final String title;
  final String? caption;
  final List<Widget>? actions;
  final bool dense;

  IconData get iconData => icon ?? Icons.info_outline_rounded;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final TextTheme textTheme = Theme.of(context).textTheme;
    final Color resolvedIconColor = iconColor ?? colorScheme.onSurfaceVariant;
    final List<Widget>? resolvedActions = actions;

    final double iconSize = dense ? 20.0 : 48.0;
    final double iconGap = dense ? 4.0 : 16.0;
    final double captionGap = dense ? 2.0 : 8.0;
    final double actionsGap = dense ? 12.0 : 24.0;
    final TextStyle? titleStyle = dense
        ? textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant)
        : textTheme.titleMedium;
    final TextStyle? captionStyle =
        (dense ? textTheme.bodySmall : textTheme.bodyMedium)?.copyWith(
          color: colorScheme.onSurfaceVariant,
        );

    final Widget centered = Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(iconData, size: iconSize, color: resolvedIconColor),
          SizedBox(height: iconGap),
          Text(title, style: titleStyle, textAlign: TextAlign.center),
          if (caption != null) ...<Widget>[
            SizedBox(height: captionGap),
            Text(caption!, style: captionStyle, textAlign: TextAlign.center),
          ],
          if (resolvedActions != null &&
              resolvedActions.isNotEmpty) ...<Widget>[
            SizedBox(height: actionsGap),
            Wrap(
              spacing: 8.0,
              runSpacing: 8.0,
              alignment: WrapAlignment.center,
              children: resolvedActions,
            ),
          ],
        ],
      ),
    );

    if (dense) {
      return centered;
    }
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0),
        child: centered,
      ),
    );
  }
}
