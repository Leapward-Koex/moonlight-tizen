abstract interface class DiagnosticLogger {
  void log(
    String level,
    String event, [
    Map<String, Object?> details = const <String, Object?>{},
  ]);
}

final class NoopDiagnosticLogger implements DiagnosticLogger {
  const NoopDiagnosticLogger();

  @override
  void log(
    String level,
    String event, [
    Map<String, Object?> details = const <String, Object?>{},
  ]) {}
}

extension DiagnosticLoggerErrors on DiagnosticLogger {
  void error(
    String event,
    Object error,
    StackTrace stackTrace, [
    Map<String, Object?> details = const <String, Object?>{},
  ]) {
    log('error', event, {
      ...details,
      'errorType': error.runtimeType.toString(),
      'error': error.toString(),
      'stack': stackTrace.toString(),
    });
  }
}
