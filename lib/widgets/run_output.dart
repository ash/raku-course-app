import 'package:flutter/material.dart';
import '../run_session.dart';
import '../theme.dart';
import 'code_view.dart';

/// What a program printed, plus a status line ("exit 0 · 12 ms", "Running…").
/// Dark in both themes, like the code it belongs to.
class RunOutputView extends StatelessWidget {
  final RunSession session;

  /// Shown as a close button in the status line, if given.
  final VoidCallback? onClose;

  /// Fill the available height and scroll inside it (the playground's output
  /// pane), instead of growing with the text (under an inline code block).
  final bool fill;

  /// Shown when nothing has run yet (playground only).
  final String? placeholder;

  const RunOutputView({
    super.key,
    required this.session,
    this.onClose,
    this.fill = false,
    this.placeholder,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: session,
      builder: (context, _) {
        final text = _text();
        final body = Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
          child: SelectableText.rich(text),
        );
        return Column(
          mainAxisSize: fill ? MainAxisSize.max : MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!fill) const Divider(height: 1, color: AppColors.codeBorder),
            if (fill)
              Expanded(child: _Scrolling(child: body))
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 360),
                child: _Scrolling(child: body),
              ),
            if (session.waiting) _InputLine(session: session),
            _StatusLine(session: session, onClose: onClose),
          ],
        );
      },
    );
  }

  TextSpan _text() {
    final base = CodeView.monoStyle.copyWith(color: AppColors.codeOutput);
    final children = <InlineSpan>[
      if (session.trimmed)
        const TextSpan(
          text: '… (earlier output trimmed)\n',
          style: TextStyle(color: AppColors.codeDim),
        ),
      for (final c in session.chunks)
        TextSpan(
          text: c.text,
          style: c.isError
              ? const TextStyle(color: AppColors.codeError)
              : c.isInput
              ? const TextStyle(
                  color: AppColors.codeText,
                  fontWeight: FontWeight.w600,
                )
              : null,
        ),
    ];
    if (session.chunks.isEmpty) {
      final note = session.running
          ? ''
          : session.result != null
          ? '(no output)'
          : (placeholder ?? '');
      children.add(
        TextSpan(
          text: note,
          style: const TextStyle(
            color: AppColors.codeDim,
            fontStyle: FontStyle.italic,
          ),
        ),
      );
    }
    return TextSpan(style: base, children: children);
  }
}

/// Shown while the program waits for input: what is typed here is sent to
/// it line by line, as in a terminal.
class _InputLine extends StatefulWidget {
  final RunSession session;
  const _InputLine({required this.session});

  @override
  State<_InputLine> createState() => _InputLineState();
}

class _InputLineState extends State<_InputLine> {
  final _text = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _send() {
    widget.session.send(_text.text);
    _text.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 2, 6, 4),
      padding: const EdgeInsets.only(left: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.rakuAccent.withValues(alpha: 0.7)),
      ),
      child: Row(
        children: [
          const Text(
            '›',
            style: TextStyle(
              color: AppColors.rakuAccent,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _text,
              focusNode: _focus,
              autofocus: true,
              autocorrect: false,
              enableSuggestions: false,
              smartQuotesType: SmartQuotesType.disabled,
              smartDashesType: SmartDashesType.disabled,
              textCapitalization: TextCapitalization.none,
              keyboardAppearance: Brightness.dark,
              textInputAction: TextInputAction.send,
              cursorColor: AppColors.rakuAccent,
              style: CodeView.monoStyle.copyWith(color: AppColors.codeText),
              decoration: const InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: 'Type your input',
                hintStyle: TextStyle(color: AppColors.codeDim, fontSize: 13),
              ),
              onSubmitted: (_) {
                _send();
                _focus.requestFocus();
              },
            ),
          ),
          IconButton(
            tooltip: 'Send',
            onPressed: _send,
            icon: const Icon(Icons.keyboard_return_rounded, size: 18),
            color: AppColors.rakuAccent,
            visualDensity: VisualDensity.compact,
          ),
          TextButton(
            onPressed: widget.session.endInput,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.codeDim,
              visualDensity: VisualDensity.compact,
            ),
            child: const Tooltip(
              message: 'End of input — what ^D does in a terminal',
              child: Text('End', style: TextStyle(fontSize: 12.5)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Keeps the newest output in view while a program is printing.
class _Scrolling extends StatefulWidget {
  final Widget child;
  const _Scrolling({required this.child});

  @override
  State<_Scrolling> createState() => _ScrollingState();
}

class _ScrollingState extends State<_Scrolling> {
  final _c = ScrollController();

  @override
  void didUpdateWidget(covariant _Scrolling old) {
    super.didUpdateWidget(old);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_c.hasClients) return;
      final pos = _c.position;
      // Follow the end only if the reader has not scrolled up to look back.
      if (pos.maxScrollExtent - pos.pixels < 120) _c.jumpTo(pos.maxScrollExtent);
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    controller: _c,
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: widget.child,
    ),
  );
}

class _StatusLine extends StatelessWidget {
  final RunSession session;
  final VoidCallback? onClose;
  const _StatusLine({required this.session, this.onClose});

  @override
  Widget build(BuildContext context) {
    final r = session.result;
    final String status;
    Color color = AppColors.codeDim;
    if (session.waiting) {
      status = 'Waiting for input…';
    } else if (session.running) {
      status = 'Running…';
    } else if (r == null) {
      status = '';
    } else if (r.stopped) {
      status = 'Stopped · ${_ms(r.elapsed)}';
      color = AppColors.codeNumber;
    } else if (r.ok) {
      status = 'exit 0 · ${_ms(r.elapsed)}';
    } else {
      status = 'exit ${r.exitCode} · ${_ms(r.elapsed)}';
      color = AppColors.codeError;
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 4, 2),
      child: Row(
        children: [
          if (session.running) ...[
            const SizedBox(
              width: 11,
              height: 11,
              child: CircularProgressIndicator(
                strokeWidth: 1.6,
                color: AppColors.codeDim,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Text(
            status,
            style: TextStyle(
              color: color,
              fontSize: 11.5,
              fontFamily: kMonoFont,
              fontFamilyFallback: kMonoFallback,
            ),
          ),
          const Spacer(),
          if (session.running)
            TextButton.icon(
              onPressed: session.stop,
              icon: const Icon(Icons.stop_rounded, size: 16),
              label: const Text('Stop'),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.codeText,
                visualDensity: VisualDensity.compact,
              ),
            )
          else if (onClose != null)
            IconButton(
              tooltip: 'Hide output',
              onPressed: onClose,
              icon: const Icon(Icons.close_rounded, size: 16),
              color: AppColors.codeDim,
              visualDensity: VisualDensity.compact,
            )
          else
            const SizedBox(height: 40),
        ],
      ),
    );
  }

  static String _ms(Duration d) => d.inMilliseconds < 1000
      ? '${d.inMilliseconds} ms'
      : '${(d.inMilliseconds / 1000).toStringAsFixed(2)} s';
}
