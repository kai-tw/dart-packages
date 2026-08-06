# ui_kit

This is a UI kit that shares Flutter components through my projects.

## Usage

Just use them like other Flutter components.

```dart
class SimpleWidget extends StatelessWidget {
  const SimpleWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return AppVersion();
  }
}
```

## Widget list

- **AppVersion**: automatically reads the app version and displays it with the
  OS icon (x.x.x).
- **DateTimePickerField**: a form field that picks a date and time when tapped.
- **DatePickerField**: a form field that picks a date when tapped.

## Status

Moved here from a standalone `pub.dev` package
([`flutter_ui_kit`](https://github.com/kai-tw/flutter_ui_kit), now
discontinued). No functional change from `1.0.5` — the widgets are
byte-for-byte what shipped there. Consumed as a git dependency, not published.
