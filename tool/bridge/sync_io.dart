import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

/// Synchronous line IO over stdin/stdout using libc read/write via FFI.
///
/// The bridge protocol requires strict request/response interleaving with
/// mid-op callback round trips (JS `sortFn`/`getFn`/`tokenize` closures are
/// synchronous on the Dart side), so async stdin/stdout cannot be used:
/// Dart's async stdout buffers writes until the event loop runs, which
/// deadlocks a synchronous callback. Raw libc syscalls land the bytes in
/// the pipe immediately.
///
/// A single native buffer is allocated once and reused for every read and
/// write; no per-call allocation happens on the hot path.

final DynamicLibrary _libc = DynamicLibrary.process();

final int Function(int, Pointer<Uint8>, int) _read = _libc.lookupFunction<
    IntPtr Function(Int32, Pointer<Uint8>, UintPtr),
    int Function(int, Pointer<Uint8>, int)>('read');

final int Function(int, Pointer<Uint8>, int) _write = _libc.lookupFunction<
    IntPtr Function(Int32, Pointer<Uint8>, UintPtr),
    int Function(int, Pointer<Uint8>, int)>('write');

const int _stdinFd = 0;
const int _stdoutFd = 1;
const int _bufferSize = 1 << 16;

class SyncLineIO {
  final Pointer<Uint8> _native = malloc<Uint8>(_bufferSize);
  late final Uint8List _view = _native.asTypedList(_bufferSize);
  final BytesBuilder _pending = BytesBuilder();

  /// Reads one newline-terminated line, blocking. Returns `null` on EOF.
  String? readLine() {
    while (true) {
      final data = _pending.takeBytes();
      final newline = data.indexOf(10); // \n
      if (newline != -1) {
        // Keep the remainder.
        if (newline + 1 < data.length) {
          _pending.add(data.sublist(newline + 1));
        }
        final lineBytes = data.sublist(0, newline);
        // Trim a trailing \r just in case.
        var end = lineBytes.length;
        if (end > 0 && lineBytes[end - 1] == 13) end -= 1;
        return utf8.decode(lineBytes.sublist(0, end));
      }
      _pending.add(data);

      final n = _read(_stdinFd, _native, _bufferSize);
      if (n <= 0) {
        if (_pending.isEmpty) return null;
        // EOF with a trailing line without newline.
        final rest = _pending.takeBytes();
        return rest.isEmpty ? null : utf8.decode(rest);
      }
      _pending.add(Uint8List.sublistView(_view, 0, n));
    }
  }

  /// Writes a line followed by a newline, blocking until all bytes have
  /// been handed to the OS.
  void writeLine(String line) {
    final bytes = utf8.encode('$line\n');
    var offset = 0;
    while (offset < bytes.length) {
      final chunk = (bytes.length - offset).clamp(0, _bufferSize);
      _view.setRange(0, chunk, bytes, offset);
      final written = _write(_stdoutFd, _native, chunk);
      if (written <= 0) {
        throw StateError('stdout write failed');
      }
      offset += written;
    }
  }
}
