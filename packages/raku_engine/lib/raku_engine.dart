/// The Raku++ interpreter, running inside the app.
///
/// The native side (engine/rakupp_mobile.cpp) runs one program at a time on a
/// thread of its own and buffers what it prints; this class starts runs,
/// polls that buffer on a short timer, and turns it into a stream. Nothing
/// here blocks the UI isolate.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

/// One piece of a program's output — or, with [isInput], a line the user
/// typed in reply, kept in the transcript the way a terminal echoes it.
class RakuOutput {
  final String text;
  final bool isError;
  final bool isInput;
  const RakuOutput(this.text, {this.isError = false, this.isInput = false});
}

/// How a run ended.
class RakuResult {
  /// 0 fine, 1 a compile or runtime error, 130 stopped, 3 internal.
  final int exitCode;
  final Duration elapsed;
  const RakuResult(this.exitCode, this.elapsed);

  bool get ok => exitCode == 0;
  bool get stopped => exitCode == 130;
}

/// A program started with [RakuEngine.run].
class RakuRun {
  final RakuEngine _engine;
  final String _source;
  final String _input;
  final String _fileName;
  final bool _interactive;
  Duration? _timeout;
  final _output = StreamController<RakuOutput>.broadcast();
  final _done = Completer<RakuResult>();
  final _clock = Stopwatch();
  final _carry = <bool, List<int>>{false: [], true: []};
  Timer? _deadline;

  RakuRun._(
    this._engine,
    this._source,
    this._input,
    this._fileName,
    this._interactive,
  );

  /// True while the program is waiting for input that has not been sent
  /// (interactive runs only).
  final waiting = ValueNotifier<bool>(false);

  /// Send a line of input; a newline is added.
  void sendInput(String line) => _engine._send(this, '$line\n');

  /// End the input, as ^D does in a terminal.
  void endInput() => _engine._endInput(this);

  // A time limit counts only the time the program runs, not the time it
  // spends waiting for someone to type.
  void _setWaiting(bool w) {
    if (w == waiting.value) return;
    waiting.value = w;
    final limit = _timeout;
    if (limit == null) return;
    _deadline?.cancel();
    _deadline = w ? null : Timer(limit, stop);
  }

  /// Output as it is produced, stdout and stderr interleaved.
  Stream<RakuOutput> get output => _output.stream;

  /// Completes when the program ends, however it ends.
  Future<RakuResult> get done => _done.future;

  bool get isFinished => _done.isCompleted;

  /// Ask the program to stop. It ends at its next statement or loop
  /// iteration, with exit code 130.
  void stop() => _engine._stop(this);

  void _emit(bool isError, List<int> bytes) {
    final carry = _carry[isError]!;
    final all = carry.isEmpty ? bytes : [...carry, ...bytes];
    // Hold back a UTF-8 sequence that a poll cut in half.
    var end = all.length;
    var i = all.length - 1;
    var back = 0;
    while (i >= 0 && back < 4 && (all[i] & 0xC0) == 0x80) {
      i--;
      back++;
    }
    if (i >= 0) {
      final lead = all[i];
      final need = lead >= 0xF0
          ? 4
          : lead >= 0xE0
          ? 3
          : lead >= 0xC0
          ? 2
          : 1;
      if (all.length - i < need) end = i;
    }
    carry
      ..clear()
      ..addAll(all.sublist(end));
    if (end == 0) return;
    final text = const Utf8Decoder(allowMalformed: true).convert(all, 0, end);
    if (!_output.isClosed) _output.add(RakuOutput(text, isError: isError));
  }

  void _finish(int exitCode) {
    _deadline?.cancel();
    waiting.value = false;
    _clock.stop();
    for (final isError in [false, true]) {
      final rest = _carry[isError]!;
      if (rest.isNotEmpty && !_output.isClosed) {
        _output.add(
          RakuOutput(
            const Utf8Decoder(allowMalformed: true).convert(rest),
            isError: isError,
          ),
        );
      }
      rest.clear();
    }
    _output.close();
    if (!_done.isCompleted) {
      _done.complete(RakuResult(exitCode, _clock.elapsed));
    }
  }

  void _fail(String message) {
    if (!_output.isClosed) _output.add(RakuOutput('$message\n', isError: true));
    _finish(3);
  }
}

/// Syntax classes from the engine's own tokenizer.
enum RakuTokenKind {
  plain,
  keyword,
  builtin,
  name,
  variable,
  string,
  regex,
  comment,
  number,
  type,
}

class RakuToken {
  final RakuTokenKind kind;
  final String text;
  const RakuToken(this.kind, this.text);
}

class RakuEngine {
  RakuEngine._();

  /// The one engine: the interpreter allows one live instance per process.
  static final RakuEngine instance = RakuEngine._();

  _Bindings? _bindingsCache;
  bool _loadTried = false;
  String? _loadError;

  RakuRun? _current;
  RakuRun? _pending;
  Timer? _poller;
  String? _workdir;

  _Bindings? get _b {
    if (!_loadTried) {
      _loadTried = true;
      try {
        _bindingsCache = _Bindings(_open());
      } catch (e) {
        _loadError = '$e';
      }
    }
    return _bindingsCache;
  }

  static DynamicLibrary _open() {
    if (Platform.isIOS || Platform.isMacOS) {
      try {
        return DynamicLibrary.open('RakuEngine.framework/RakuEngine');
      } catch (_) {
        final app = File(Platform.resolvedExecutable).parent.path;
        return DynamicLibrary.open(
          '$app/Frameworks/RakuEngine.framework/RakuEngine',
        );
      }
    }
    if (Platform.isAndroid) return DynamicLibrary.open('librakuengine.so');
    throw UnsupportedError('No Raku engine for ${Platform.operatingSystem}');
  }

  /// Whether the engine is present on this device.
  bool get isAvailable => _b != null;

  /// Why the engine could not be loaded, if it could not.
  String? get loadError => isAvailable ? null : _loadError;

  /// The engine's version, e.g. "5.4.1".
  String get version {
    final b = _b;
    return b == null ? '' : b.version().toDartString();
  }

  /// Whether a program is running (or waiting to).
  bool get isBusy => _current != null || _pending != null;

  /// Run [source] as a whole program. [input] is what `get`, `lines` and
  /// `prompt` read before end of input. A run started while another is going
  /// stops that one first. With [timeout], the program is stopped when it
  /// runs longer.
  RakuRun run(
    String source, {
    String input = '',
    String fileName = 'main.raku',
    Duration? timeout,
    bool interactive = false,
  }) {
    final r = RakuRun._(this, source, input, fileName, interactive);
    r._timeout = timeout;
    if (timeout != null) r._deadline = Timer(timeout, r.stop);
    final b = _b;
    if (b == null) {
      scheduleMicrotask(
        () => r._fail('The Raku engine is not available on this device.'),
      );
      return r;
    }
    if (_current != null) {
      _pending?._finish(130);
      _pending = r;
      b.stop();
    } else {
      _launch(r);
    }
    return r;
  }

  void _launch(RakuRun r) {
    final b = _b!;
    final dir = _workdir ??= _makeWorkdir();
    final rc = using((arena) {
      return b.start(
        r._source.toNativeUtf8(allocator: arena),
        r._input.toNativeUtf8(allocator: arena),
        r._fileName.toNativeUtf8(allocator: arena),
        dir.toNativeUtf8(allocator: arena),
        r._interactive ? 1 : 0,
      );
    });
    if (rc != 0) {
      scheduleMicrotask(
        () => r._fail(
          rc == -1
              ? 'Another program is still running.'
              : 'The program could not be started.',
        ),
      );
      return;
    }
    _current = r;
    r._clock.start();
    _poller ??= Timer.periodic(const Duration(milliseconds: 40), (_) => _poll());
  }

  static String _makeWorkdir() {
    // Relative file IO in a program lands here: a scratch directory the app
    // owns, rather than the read-only bundle.
    final dir = Directory('${Directory.systemTemp.path}/raku');
    try {
      dir.createSync(recursive: true);
    } catch (_) {}
    return dir.path;
  }

  void _poll() {
    final r = _current;
    final b = _b;
    if (r == null || b == null) {
      _poller?.cancel();
      _poller = null;
      return;
    }
    final finished = b.state() == _finished;
    _drain(b, r);
    if (!finished) {
      if (r._interactive) r._setWaiting(b.waitingInput() == 1);
      return;
    }
    _current = null;
    r._finish(b.exitCode());
    final next = _pending;
    _pending = null;
    if (next != null) {
      _launch(next);
    } else {
      _poller?.cancel();
      _poller = null;
    }
  }

  void _drain(_Bindings b, RakuRun r) {
    final len = calloc<Int32>();
    try {
      final p = b.takeOutput(len);
      if (p == nullptr) return;
      final bytes = Uint8List.fromList(p.asTypedList(len.value));
      b.free(p.cast());
      var i = 0;
      while (i + 5 <= bytes.length) {
        final isError = bytes[i] == 0x65; // 'e'
        final n =
            bytes[i + 1] |
            bytes[i + 2] << 8 |
            bytes[i + 3] << 16 |
            bytes[i + 4] << 24;
        i += 5;
        final end = (i + n).clamp(0, bytes.length);
        r._emit(isError, bytes.sublist(i, end));
        i = end;
      }
    } finally {
      calloc.free(len);
    }
  }

  void _send(RakuRun r, String text) {
    if (!identical(r, _current)) return;
    using((arena) => _b?.sendInput(text.toNativeUtf8(allocator: arena)));
    r._setWaiting(false);
  }

  void _endInput(RakuRun r) {
    if (!identical(r, _current)) return;
    _b?.endInput();
    r._setWaiting(false);
  }

  void _stop(RakuRun r) {
    if (identical(r, _pending)) {
      _pending = null;
      r._finish(130);
    } else if (identical(r, _current)) {
      _b?.stop();
    }
  }

  final _hlCache = <String, List<RakuToken>>{};

  /// [source] split into classified tokens, or null when the engine is not
  /// available. Concatenating the tokens' text gives back [source].
  List<RakuToken>? highlight(String source) {
    final b = _b;
    if (b == null) return null;
    final cached = _hlCache[source];
    if (cached != null) return cached;
    final tokens = <RakuToken>[];
    using((arena) {
      final len = arena<Int32>();
      final p = b.highlight(source.toNativeUtf8(allocator: arena), len);
      if (p == nullptr) return;
      final bytes = Uint8List.fromList(p.asTypedList(len.value));
      b.free(p.cast());
      var i = 0;
      while (i + 5 <= bytes.length) {
        final kind = bytes[i];
        final n =
            bytes[i + 1] |
            bytes[i + 2] << 8 |
            bytes[i + 3] << 16 |
            bytes[i + 4] << 24;
        i += 5;
        final end = (i + n).clamp(0, bytes.length);
        tokens.add(
          RakuToken(
            kind < RakuTokenKind.values.length
                ? RakuTokenKind.values[kind]
                : RakuTokenKind.plain,
            const Utf8Decoder(allowMalformed: true).convert(bytes, i, end),
          ),
        );
        i = end;
      }
    });
    // The tokenizer is byte-exact; if decoding ever disagrees, use nothing
    // rather than a mangled program.
    if (tokens.map((t) => t.text).join() != source) return null;
    if (_hlCache.length > 400) _hlCache.clear();
    _hlCache[source] = tokens;
    return tokens;
  }
}

const _finished = 2;

typedef _StartC =
    Int32 Function(
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Int32,
    );
typedef _StartD =
    int Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, int);
typedef _SendC = Void Function(Pointer<Utf8>);
typedef _SendD = void Function(Pointer<Utf8>);
typedef _VoidC = Void Function();
typedef _VoidD = void Function();
typedef _IntC = Int32 Function();
typedef _IntD = int Function();
typedef _TakeC = Pointer<Uint8> Function(Pointer<Int32>);
typedef _HighlightC = Pointer<Uint8> Function(Pointer<Utf8>, Pointer<Int32>);
typedef _FreeC = Void Function(Pointer<Void>);
typedef _FreeD = void Function(Pointer<Void>);
typedef _VersionC = Pointer<Utf8> Function();

class _Bindings {
  final _StartD start;
  final _VoidD stop;
  final _SendD sendInput;
  final _VoidD endInput;
  final _IntD waitingInput;
  final _IntD state;
  final _IntD exitCode;
  final Pointer<Uint8> Function(Pointer<Int32>) takeOutput;
  final Pointer<Uint8> Function(Pointer<Utf8>, Pointer<Int32>) highlight;
  final _FreeD free;
  final Pointer<Utf8> Function() version;

  _Bindings(DynamicLibrary lib)
    : start = lib.lookupFunction<_StartC, _StartD>('rkm_start'),
      stop = lib.lookupFunction<_VoidC, _VoidD>('rkm_stop'),
      sendInput = lib.lookupFunction<_SendC, _SendD>('rkm_send_input'),
      endInput = lib.lookupFunction<_VoidC, _VoidD>('rkm_end_input'),
      waitingInput = lib.lookupFunction<_IntC, _IntD>('rkm_waiting_input'),
      state = lib.lookupFunction<_IntC, _IntD>('rkm_state'),
      exitCode = lib.lookupFunction<_IntC, _IntD>('rkm_exit_code'),
      takeOutput = lib.lookupFunction<_TakeC, _TakeC>('rkm_take_output'),
      highlight = lib.lookupFunction<_HighlightC, _HighlightC>(
        'rkm_highlight',
      ),
      free = lib.lookupFunction<_FreeC, _FreeD>('rkm_free'),
      version = lib.lookupFunction<_VersionC, _VersionC>('rkm_version');
}
