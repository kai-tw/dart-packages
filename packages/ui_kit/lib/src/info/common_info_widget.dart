import 'package:flutter/material.dart';

/// A centred placeholder for a calm informational message — icon + title,
/// with optional [caption] body text and optional [actions] button row.
/// Defaults to `onSurfaceVariant` for the icon; pass an explicit [iconColor]
/// to tint per state (e.g. `colorScheme.error`).
///
/// Composition base for [CommonErrorWidget] — use this directly when the
/// surface needs to show a neutral state (empty, offline, info) that may
/// carry an action. `CommonLoadingWidget` builds its own column and does
/// **not** compose this widget.
///
/// Two density variants:
///
/// - **Default (`dense: false`)** — full-screen empty/error/offline
///   placeholder. 48px icon, `titleMedium` title, generous spacing,
///   `SafeArea` + 24px horizontal padding.
/// - **Dense (`dense: true`)** — inline-card placeholder for sections that
///   already live inside another scaffold (no `SafeArea`). 20px icon,
///   `bodyMedium` subdued title, tight spacing, 16px horizontal padding.
///
/// **Both variants cap their content at [maxContentWidth]** (default
/// [defaultMaxContentWidth]). Centred text needs a shorter measure than
/// left-aligned body copy, and without a cap a caption on a 1024px tablet
/// spans the whole window. Pass an explicit value where the surrounding
/// page caps its own content differently, so a placeholder that *replaces*
/// that content does not render narrower than what it replaced.
///
/// The two variants are **not** interchangeable in width: at a container
/// width `W` the dense content is `min(cap, W - 32)` and the default is
/// `min(cap, W - 48)`, so below `cap + 32` the dense variant is the wider
/// of the two. The 16px is there so dense never renders flush against its
/// host's edge — not to make it narrower than the full-screen variant,
/// which no inline inset can achieve.
class CommonInfoWidget extends StatelessWidget {
  const CommonInfoWidget({
    super.key,
    this.icon,
    this.iconColor,
    required this.title,
    this.caption,
    this.actions,
    this.dense = false,
    this.maxContentWidth,
  });

  /// The content measure applied when [maxContentWidth] is null.
  static const double defaultMaxContentWidth = 480.0;

  static const double _denseHorizontalPadding = 16.0;
  static const double _defaultHorizontalPadding = 24.0;

  final IconData? icon;
  final Color? iconColor;
  final String title;
  final String? caption;
  final List<Widget>? actions;
  final bool dense;

  /// Caps the width of the whole icon + title + caption + actions column.
  ///
  /// Null means [defaultMaxContentWidth]. The nullable sentinel is
  /// deliberate: it keeps "unspecified" distinguishable from a caller that
  /// deliberately asked for the default.
  final double? maxContentWidth;

  IconData get iconData => icon ?? Icons.info_outline_rounded;

  @override
  Widget build(BuildContext context) {
    // The cap sits INSIDE the Center, not around it. A Scaffold body is laid
    // out under tight constraints and `BoxConstraints.enforce` clamps an
    // additional maximum back up to the incoming minimum, so a bare
    // ConstrainedBox there is silently ignored — the Center is what loosens
    // the constraints that make the cap take effect at all. Capping the whole
    // column (rather than each Text) also keeps the actions Wrap from
    // spreading across a wide window.
    final Widget centered = Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxContentWidth ?? defaultMaxContentWidth,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _buildIcon(context),
            SizedBox(height: dense ? 4.0 : 16.0),
            _buildTitle(context),
            ..._buildCaption(context),
            ..._buildActions(context),
          ],
        ),
      ),
    );

    if (dense) {
      return Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: _denseHorizontalPadding,
        ),
        child: centered,
      );
    }
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: _defaultHorizontalPadding,
        ),
        child: centered,
      ),
    );
  }

  Widget _buildIcon(BuildContext context) {
    final Color resolvedIconColor =
        iconColor ?? Theme.of(context).colorScheme.onSurfaceVariant;
    return Icon(iconData, size: dense ? 20.0 : 48.0, color: resolvedIconColor);
  }

  Widget _buildTitle(BuildContext context) {
    final TextTheme textTheme = Theme.of(context).textTheme;
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final TextStyle? titleStyle = dense
        ? textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant)
        : textTheme.titleMedium;
    return Text(title, style: titleStyle, textAlign: TextAlign.center);
  }

  List<Widget> _buildCaption(BuildContext context) {
    if (caption != null) {
      final TextTheme textTheme = Theme.of(context).textTheme;
      final ColorScheme colorScheme = Theme.of(context).colorScheme;
      final TextStyle? captionStyle =
          (dense ? textTheme.bodySmall : textTheme.bodyMedium)?.copyWith(
            color: colorScheme.onSurfaceVariant,
          );
      return <Widget>[
        SizedBox(height: dense ? 2.0 : 8.0),
        Text(caption!, style: captionStyle, textAlign: TextAlign.center),
      ];
    }
    return const <Widget>[];
  }

  List<Widget> _buildActions(BuildContext context) {
    final List<Widget>? resolvedActions = actions;
    if (resolvedActions != null && resolvedActions.isNotEmpty) {
      return <Widget>[
        SizedBox(height: dense ? 12.0 : 24.0),
        Wrap(
          spacing: 8.0,
          runSpacing: 8.0,
          alignment: WrapAlignment.center,
          children: resolvedActions,
        ),
      ];
    }
    return const <Widget>[];
  }
}
