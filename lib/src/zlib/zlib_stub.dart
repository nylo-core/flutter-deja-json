import '../exceptions.dart';

/// Whether zlib is available on this platform.
const bool zlibSupported = false;

Never _unsupported() => throw const DejaJsonUnsupportedException(
      'DejaJson requires dart:io zlib, which is unavailable on this '
      'platform. The interceptor advertises nothing here, so servers send '
      'plain JSON.',
    );

List<int> zlibDeflate(List<int> bytes, int level, List<int>? dictionary) =>
    _unsupported();

List<int> zlibInflate(List<int> bytes, List<int>? dictionary) => _unsupported();
