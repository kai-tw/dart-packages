## 2.0.0
- **BREAKING** — `CommonDeleteDialog` asks for confirmation and nothing else.
  `onDelete`, `onError` and `errorMessageBuilder` are gone; `show` now resolves
  to `bool` — `true` when confirmed, `false` for every other way out, including
  a back gesture.

  ```dart
  final bool confirmed = await CommonDeleteDialog.show(context, …);
  if (!confirmed) {
    return;
  }
  await repository.delete(id);
  ```

  Running the caller's work put it somewhere with no vocabulary to report it:
  the dialog knows nothing about an arbitrary callback's exception types, so its
  only possible report was `toString()` in a text field. The error-message
  builder, the logging hook, the loading flag and the spinner were all
  consequences of that one decision, as was a class of bugs where the dialog
  closed on a delete that had not happened. Returning a decision removes the
  cause rather than each symptom.

  Migration is not a rename. Move the `onDelete` body to after the `show` call
  and give it a failure path there — a caller that passed the old callbacks may
  have had none of its own, because the dialog *was* its error UI. Telling a
  user a delete succeeded when it did not is the failure this shape invites, so
  cover the new path with a test.

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
