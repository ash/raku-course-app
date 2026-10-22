import 'package:flutter/material.dart';
import 'package:raku_engine/raku_engine.dart';
import '../run_session.dart';
import '../screens/playground_screen.dart';
import '../theme.dart';
import 'code_view.dart';
import 'run_output.dart';

/// A Raku code block from the course. With the engine present it gains an
/// Edit button (opens the code in the Playground) and — when tool/sync.raku
/// found that the block runs on its own — a Run button, whose output appears
/// under the code.
class RakuCodeBlock extends StatefulWidget {
  final String code;
  final bool runnable;

  const RakuCodeBlock({super.key, required this.code, this.runnable = false});

  @override
  State<RakuCodeBlock> createState() => _RakuCodeBlockState();
}

class _RakuCodeBlockState extends State<RakuCodeBlock> {
  RunSession? _session;

  @override
  void dispose() {
    _session?.dispose();
    super.dispose();
  }

  void _run() {
    final s = _session ??= RunSession();
    // A lesson snippet that has run for 20 s is stuck, not slow. One that
    // asks for input waits for it here, and that time does not count.
    s.start(
      widget.code,
      fileName: 'example.raku',
      timeout: const Duration(seconds: 20),
      interactive: true,
    );
    setState(() {});
  }

  void _close() {
    _session?.clear();
    setState(() => _session = null);
  }

  void _edit() => Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => PlaygroundScreen(initialCode: widget.code),
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (!RakuEngine.instance.isAvailable) return CodeView(code: widget.code);
    final session = _session;
    return CodeView(
      code: widget.code,
      actions: [
        IconButton(
          tooltip: 'Edit in Playground',
          onPressed: _edit,
          icon: const Icon(Icons.edit_note_rounded, size: 20),
          color: AppColors.codeDim,
          visualDensity: VisualDensity.compact,
        ),
        if (widget.runnable)
          session == null
              ? _RunButton(onPressed: _run)
              : AnimatedBuilder(
                  animation: session,
                  builder: (_, _) => session.running
                      ? _RunButton(stop: true, onPressed: session.stop)
                      : _RunButton(onPressed: _run),
                ),
      ],
      footer: session == null
          ? null
          : RunOutputView(session: session, onClose: _close),
    );
  }
}

class _RunButton extends StatelessWidget {
  final bool stop;
  final VoidCallback onPressed;
  const _RunButton({this.stop = false, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 2, top: 4, bottom: 2),
      child: FilledButton.icon(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: stop ? AppColors.codeBorder : AppColors.rakuAccent,
          foregroundColor: Colors.white,
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          minimumSize: const Size(0, 30),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        icon: Icon(stop ? Icons.stop_rounded : Icons.play_arrow_rounded, size: 18),
        label: Text(stop ? 'Stop' : 'Run'),
      ),
    );
  }
}
