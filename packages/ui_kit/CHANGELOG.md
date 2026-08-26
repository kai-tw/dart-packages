## 3.0.0
- **BREAKING** — `CommonStepIndicator` drops the `label` parameter and the
  `Text` it rendered above the segments. The widget is the segments now,
  nothing else.

  2.2.0 shipped label-above-segments as one fixed composition on the
  reasoning that the two always travel together. The first real caller
  proved that wrong within the same week: CherishCRM's onboarding app bar
  wanted the label in the toolbar's own `title` (centred against the whole
  bar width) and the segments on their own in `bottom` below it — a layout
  the bundled widget could not produce without CherishCRM either
  duplicating the label outside it or living with the wrong composition.
  Nothing about that split is unusual enough to treat as a special case
  the widget should carry a flag for; a caller that wants a label composes
  one line of `Text` next to this, wherever its own layout puts it.

  **Adopters:** replace `CommonStepIndicator(label: ..., current: ...,
  total: ...)` with `CommonStepIndicator(current: ..., total: ...)` plus
  your own `Text(label)` positioned where the old rendering put it (directly
  above the segments, with an 8px gap, is what 2.2.0 did internally).

## 2.2.0
- New `CommonStepIndicator`: a text label above N short pills, filled solid
  through the current step and faint after it — a step counter for a wizard
  whose length is fixed and known ahead of time (an onboarding guide, a short
  setup flow), as distinct from `CommonLoadingWidget`'s determinate mode,
  which reads as progress toward an unstated number and belongs to an
  operation with a fraction rather than a step index.

  Extracted from CherishCRM's onboarding guide, where it started as a
  full-width continuous bar and changed shape twice before landing here: once
  to move it out of the app bar into the centred page content (a bold bar
  pinned to the top and a centred block below it read as two things
  competing for attention across empty space), and once back into the app
  bar after the bar itself became short segments — quiet enough that the
  competition the first move was solving no longer existed. Both app bar and
  in-page placement work: the widget sizes itself to its own compact width
  rather than stretching, so a caller centres it however its own layout
  already centres things.

  Takes `label` as a required `String`, like every other widget here that
  always shows text — see the README's Text ownership section.

## 2.1.0
- `CommonInfoWidget` caps its content column at a new optional
  `maxContentWidth` (default `CommonInfoWidget.defaultMaxContentWidth`, 480).
  Neither the title nor the caption was bounded before, so a caption on a
  1024px tablet spanned the whole window. The cap covers the icon, title,
  caption and the actions `Wrap` together, and `CommonErrorWidget` /
  `CommonErrorSliverWidget` inherit it through composition.

  Pass an explicit value where the surrounding page caps its own content
  differently — a placeholder that *replaces* that content should not render
  narrower than what it replaced.

- `CommonInfoWidget`'s **dense** variant gains 16px horizontal padding. It
  previously had none at all, so its text could sit flush against the host's
  edge.

  This does **not** make dense narrower than the default variant, and cannot:
  at a container width `W` the dense content is `min(cap, W - 32)` against the
  default's `min(cap, W - 48)`, so below `cap + 32` dense stays the wider of
  the two. The two variants never share a container in practice — the default
  is full-screen, dense sits inside a section that already carries its own
  inset — so the comparison is not the thing being fixed. Being flush is.

  **Adopters:** a dense call site that already compensated with its own
  horizontal inset now gets both. Check inline cards and dialogs with a tight
  measure; the padding is deliberately not a parameter, so compensate at the
  call site or give the host more room.

- ui_kit gains a `test/` directory and a `flutter_test` dev-dependency; CI runs
  `flutter test` for it. It was the only package in this workspace with no
  tests. (`flutter_test` cannot be added on any 1.x branch — `hlc_sync` pinned
  `test: ^1.31.2` there, which makes the whole workspace unresolvable once a
  Flutter package with tests joins it. That floor was widened on `main` only.)

## 2.0.0
- **BREAKING** — `CommonDeleteDialog` (and its `.show` helper) drops
  `errorMessageBuilder` and `onError`. A failure in `onDelete` now propagates to
  the caller instead of being caught and rendered inside the dialog.

  The dialog knows nothing about an arbitrary callback's exception types, so the
  only report it could produce was `toString()` in a text field — away from the
  handler that knows what failed. It still clears its loading state on failure,
  so the buttons come back live; what the user sees is the caller's decision.

  **Handle the failure INSIDE `onDelete`.** A `try` around `show` compiles,
  raises no lint, and catches nothing: the delete button invokes `onDelete`
  fire-and-forget, and `show` returns the dialog route's future, not the
  callback's. An unhandled exception reaches the zone handler instead — logged,
  with the user told nothing.

  Migration is not a one-line move. A caller that passed these may have no
  failure path of its own at all — the dialog *was* its error UI — so removing
  them leaves a delete that fails silently. Add the handling before bumping, and
  cover it with a test: telling a user a delete succeeded when it did not is the
  failure this shape invites.

## 1.2.0
- `CommonNavTile` (all three named constructors) gains an optional `subtitle`
  param, rendered as the tile's `ListTile.subtitle`.
- `CommonDeleteDialog` (and its `.show` helper) gains optional `confirmPhrase`
  + `confirmFieldHint` params — when set, the delete button stays disabled
  behind a text field that must match `confirmPhrase` exactly, for actions
  that need more friction than a second tap. `confirmFieldHint` is required
  whenever `confirmPhrase` is set (same text-ownership rule as everywhere
  else in this package).

## 1.1.0
- Added `CommonBadge`, `CommonNavTile` (`.none`/`.internal`/`.external`),
  `CommonInfoWidget`/`CommonErrorWidget`(+Sliver+Dialog)/`CommonLoadingWidget`
  (+Sliver+Dialog)/`CommonSuccessDialog`/`CommonProgressDialog`, and
  `CommonDeleteDialog` — merged from equivalent widgets independently built
  in CherishCRM-Flutter and NovelGlide-Flutter (see each class's doc comment
  for which app's shape won and why). New dependency:
  `loading_animation_widget`. No widget in this package ships built-in copy —
  see README §Text ownership.

## 1.0.6
- Moved into `dart-packages` as a workspace member. No longer published to
  pub.dev — consumed as a git dependency. No functional change.

## 1.0.5
- Fix that DateTimePickerField didn't update controller value after clearing the value.

## 1.0.4
- Fix that DateTimePickerField didn't get correct value in onSave if initial value was provided by controller in initState.

## 1.0.3
- Fix that DateTimePickerField didn't fill in if initial value was provided in initState.

## 1.0.2
- Fix missing components export.

## 1.0.1
- Added DateTimePickerField and DatePickerField.

## 1.0.0

- Initial version.
