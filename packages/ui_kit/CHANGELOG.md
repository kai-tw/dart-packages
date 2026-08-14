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
