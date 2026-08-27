import 'package:flutter/foundation.dart';

/// DateTime picker controller
class DateTimePickerController extends ValueNotifier<DateTime?> {
  DateTimePickerController({DateTime? initialValue}) : super(initialValue);

  /// Set the value of the controller
  set dateTime(DateTime? value) {
    this.value = value;
  }

  /// Get the value of the controller
  DateTime? get dateTime => value;

  /// Clear the value of the controller
  void clear() {
    value = null;
  }
}
