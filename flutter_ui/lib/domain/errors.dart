class MoonlightException implements Exception {
  const MoonlightException(this.message, {this.cause});
  final String message;
  final Object? cause;

  @override
  String toString() => message;
}

final class TransportException extends MoonlightException {
  const TransportException(super.message, {this.code, super.cause});
  final int? code;

  bool get isCertificateMismatch => code == -100;
}

final class ProtocolException extends MoonlightException {
  const ProtocolException(
    super.message, {
    this.statusCode,
    this.statusMessage,
    super.cause,
  });
  final int? statusCode;
  final String? statusMessage;
}

final class UnexpectedHostException extends ProtocolException {
  const UnexpectedHostException({required this.expected, required this.actual})
    : super('The responding host identity changed from $expected to $actual.');
  final String expected;
  final String actual;
}

final class StaleOperationException extends MoonlightException {
  const StaleOperationException() : super('The operation was superseded.');
}

final class PairingBusyException extends MoonlightException {
  const PairingBusyException()
    : super('Another host pairing operation is active.');
}
