import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:raku_engine/raku_engine.dart';

/// The output of one program run, kept for display: stdout and stderr in the
/// order they arrived, and how the run ended.
class RunSession extends ChangeNotifier {
  /// Output beyond this many characters is dropped from the front, so a
  /// chatty program cannot make the output view unusably slow.
  static const _keep = 200000;

  final List<RakuOutput> chunks = [];
  RakuRun? _run;
  RakuResult? result;
  bool trimmed = false;
  int _chars = 0;
  StreamSubscription<RakuOutput>? _sub;

  bool get running => _run != null && result == null;
  bool get hasOutput => chunks.isNotEmpty;

  /// The program is waiting for the user to type something.
  bool get waiting => running && (_run?.waiting.value ?? false);

  /// Start [code]. With [interactive], a read from standard input waits for
  /// [send] — the program asks, the user answers — instead of seeing end of
  /// input once [input] is used up.
  void start(
    String code, {
    String input = '',
    String fileName = 'main.raku',
    Duration? timeout,
    bool interactive = false,
  }) {
    _sub?.cancel();
    _run?.waiting.removeListener(notifyListeners);
    chunks.clear();
    _chars = 0;
    trimmed = false;
    result = null;
    final run = RakuEngine.instance.run(
      code,
      input: input,
      fileName: fileName,
      timeout: timeout,
      interactive: interactive,
    );
    _run = run;
    run.waiting.addListener(notifyListeners);
    _sub = run.output.listen((o) {
      if (!identical(run, _run)) return;
      _append(o);
      notifyListeners();
    });
    run.done.then((r) {
      if (!identical(run, _run)) return;
      result = r;
      notifyListeners();
    });
    notifyListeners();
  }

  /// Give the waiting program a line of input, echoing it into the output
  /// as a terminal would.
  void send(String line) {
    if (!running) return;
    _append(RakuOutput('$line\n', isInput: true));
    _run!.sendInput(line);
    notifyListeners();
  }

  /// End the input (^D).
  void endInput() {
    if (!running) return;
    _run!.endInput();
    notifyListeners();
  }

  void _append(RakuOutput o) {
    if (chunks.isNotEmpty &&
        chunks.last.isError == o.isError &&
        chunks.last.isInput == o.isInput) {
      chunks[chunks.length - 1] = RakuOutput(
        chunks.last.text + o.text,
        isError: o.isError,
        isInput: o.isInput,
      );
    } else {
      chunks.add(o);
    }
    _chars += o.text.length;
    while (_chars > _keep && chunks.isNotEmpty) {
      final over = _chars - _keep;
      final first = chunks.first;
      if (first.text.length <= over) {
        chunks.removeAt(0);
        _chars -= first.text.length;
      } else {
        chunks[0] = RakuOutput(
          first.text.substring(over),
          isError: first.isError,
          isInput: first.isInput,
        );
        _chars -= over;
      }
      trimmed = true;
    }
  }

  void stop() => _run?.stop();

  /// Forget the output (stopping the program if it is still running).
  void clear() {
    if (running) _run?.stop();
    _run?.waiting.removeListener(notifyListeners);
    _sub?.cancel();
    _sub = null;
    _run = null;
    result = null;
    chunks.clear();
    _chars = 0;
    trimmed = false;
    notifyListeners();
  }

  @override
  void dispose() {
    if (running) _run?.stop();
    _run?.waiting.removeListener(notifyListeners);
    _run = null; // a run that ends after this must not notify a disposed session
    _sub?.cancel();
    super.dispose();
  }
}
