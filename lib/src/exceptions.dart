/// Base type for every error thrown by `package:dejajson`.
class DejaJsonException implements Exception {
  const DejaJsonException(this.message);

  final String message;

  @override
  String toString() => 'DejaJsonException: $message';
}

/// The payload is not a valid DejaJson envelope, or does not match the
/// dictionary it claims to need.
class DejaJsonFormatException extends DejaJsonException {
  const DejaJsonFormatException(super.message);

  @override
  String toString() => 'DejaJsonFormatException: $message';
}

/// The value cannot be represented in the DejaJson wire format.
class DejaJsonEncodeException extends DejaJsonException {
  const DejaJsonEncodeException(super.message);

  @override
  String toString() => 'DejaJsonEncodeException: $message';
}

/// The current platform cannot handle DejaJson (zlib needs `dart:io`, which
/// is unavailable in web builds — web clients simply receive plain JSON).
class DejaJsonUnsupportedException extends DejaJsonException {
  const DejaJsonUnsupportedException(super.message);

  @override
  String toString() => 'DejaJsonUnsupportedException: $message';
}
