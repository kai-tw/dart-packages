/// Structured logging with a redacted crash-reporting egress.
///
/// Call [LogSystem.install] once at startup with a [LogRepository]; everything
/// after that goes through the static [LogSystem] facade.
library;

export 'src/fan_out_log_repository.dart';
export 'src/firebase_crashlytics_adapter.dart';
export 'src/log_data_source.dart';
export 'src/log_diagnostic_code.dart';
export 'src/log_error_redactor.dart';
export 'src/log_repository.dart';
export 'src/log_system.dart';
export 'src/logger_adapter.dart';
