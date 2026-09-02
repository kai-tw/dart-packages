import 'package:flutter/material.dart';

enum CommonBadgeType { hidden, minimal, normal }

/// A Material [Badge] with three fixed states and a few things the raw widget
/// gets wrong for an icon label.
///
/// [CommonBadgeType.minimal] is a bare dot, [CommonBadgeType.normal] carries
/// a [label], and [CommonBadgeType.hidden] renders the child alone.
class CommonBadge extends StatelessWidget {
  const CommonBadge({
    super.key,
    this.type = CommonBadgeType.minimal,
    this.label,
    this.alignment,
    this.backgroundColor,
    this.foregroundColor,
    this.size,
    this.padding,
    required this.child,
  });

  /// A badge with nothing behind it.
  ///
  /// The overlay form covers a corner of whatever it hangs on, which is free
  /// on an avatar and destructive on an icon that is itself information — a
  /// status glyph, a type indicator. A caller in that position needs the mark
  /// as an ordinary widget it can place beside the thing instead of over it,
  /// and before this existed the only way to get one was to drop out of this
  /// widget and use Material's [Badge] directly, which loses everything below.
  ///
  /// [CommonBadgeType.hidden] is meaningless here — there is no child to fall
  /// back to — so this constructor takes no [type] and always renders the
  /// mark. Callers switching on presence should choose between this and
  /// rendering nothing at all.
  const CommonBadge.standalone({
    super.key,
    this.label,
    this.backgroundColor,
    this.foregroundColor,
    this.size,
    this.padding,
  }) : type = CommonBadgeType.normal,
       alignment = null,
       child = null;

  final CommonBadgeType type;

  /// What the badge shows. `null` with [CommonBadgeType.normal] falls back to
  /// `Text('!')`.
  ///
  /// An [Icon] is a legal label and is coloured correctly — see
  /// [foregroundColor].
  final Widget? label;

  final Alignment? alignment;

  /// The badge's fill. Defaults to Material's `colorScheme.error`.
  ///
  /// Not every "there is something here" is an error. A mark that asks the
  /// user a question, or that merely reports a fact about the row it sits on,
  /// reads wrong in the one colour this widget used to offer — and a caller
  /// cannot correct it from outside, because the colour is decided by
  /// [Badge]'s own defaults rather than by anything in the ambient theme the
  /// call site controls.
  final Color? backgroundColor;

  /// The ink on [backgroundColor]. Defaults to Material's
  /// `colorScheme.onError`.
  ///
  /// ⚠️ **Applies to an [Icon] label too, which Material's [Badge] does not
  /// do.** [Badge] puts its text colour on a `DefaultTextStyle` and installs
  /// no `IconTheme`, so an icon label is drawn in whatever icon colour the
  /// surrounding tree happens to carry — usually a dark `onSurface` on the
  /// badge's saturated fill. Nothing reports it; the glyph is simply close to
  /// invisible, and every caller that hits it has to re-discover the cause and
  /// pass a `color:` on the icon itself.
  final Color? foregroundColor;

  /// The badge's diameter, in logical pixels.
  ///
  /// Which Material dimension this sets follows from [type], so one parameter
  /// cannot be ambiguous: the dot's `smallSize` for [CommonBadgeType.minimal]
  /// (default 6.0), the labelled badge's `largeSize` for
  /// [CommonBadgeType.normal] (default 16.0).
  ///
  /// The defaults are small enough that a bare dot reads as a speck on a
  /// 40dp avatar and says nothing to anyone not looking straight at it.
  final double? size;

  /// Padding around a [label]. Defaults to Material's 4.0 horizontal.
  ///
  /// `EdgeInsets.zero` with a square label and an explicit [size] is what
  /// turns the badge's `StadiumBorder` into a true circle instead of an oval
  /// — the shape an icon label almost always wants.
  final EdgeInsetsGeometry? padding;

  /// What the badge hangs on, or `null` for the standalone form.
  ///
  /// Still `required` on the default constructor — every existing call passes
  /// one, and a badge with no host is a different enough thing to deserve its
  /// own constructor rather than a null nobody would think to try.
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final Widget? host = child;

    if (type == CommonBadgeType.hidden) {
      return host ?? const SizedBox.shrink();
    }

    final bool hasLabel = type == CommonBadgeType.normal;

    return Badge(
      label: hasLabel ? _colouredLabel(context) : null,
      alignment: alignment,
      backgroundColor: backgroundColor,
      textColor: foregroundColor,
      smallSize: hasLabel ? null : size,
      largeSize: hasLabel ? size : null,
      padding: padding,
      child: host,
    );
  }

  /// The label, with the foreground colour reaching an icon as well as text.
  Widget _colouredLabel(BuildContext context) {
    final Widget content = label ?? const Text('!');
    final Color ink = foregroundColor ?? Theme.of(context).colorScheme.onError;

    return IconTheme.merge(
      data: IconThemeData(color: ink),
      child: content,
    );
  }
}
