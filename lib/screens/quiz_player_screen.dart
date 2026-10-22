import 'package:flutter/material.dart';
import '../models.dart';
import '../progress.dart';
import '../theme.dart';
import '../widgets/block_view.dart';
import '../widgets/rich_text_span.dart';

class QuizPlayerScreen extends StatefulWidget {
  final Quiz quiz;
  final Color accent;
  final Progress progress;
  final String quizId;

  const QuizPlayerScreen({
    super.key,
    required this.quiz,
    required this.accent,
    required this.progress,
    required this.quizId,
  });

  @override
  State<QuizPlayerScreen> createState() => _QuizPlayerScreenState();
}

class _QuizPlayerScreenState extends State<QuizPlayerScreen> {
  final Set<int> _selected = {};
  bool _checked = false;
  bool _revealed = false; // for reveal quizzes

  Quiz get quiz => widget.quiz;

  void _toggle(int i) {
    if (_checked) return;
    setState(() {
      if (quiz.multiSelect) {
        _selected.contains(i) ? _selected.remove(i) : _selected.add(i);
      } else {
        _selected
          ..clear()
          ..add(i);
      }
    });
  }

  void _check() {
    setState(() => _checked = true);
    final correctIdx = {
      for (var i = 0; i < quiz.options.length; i++)
        if (quiz.options[i].correct) i,
    };
    final score =
        _selected.where(correctIdx.contains).length +
        // penalise wrong picks by not counting them; count correct hits only
        0;
    widget.progress.recordQuiz(widget.quizId, score, correctIdx.length);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      appBar: AppBar(title: const Text('Quiz')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
        children: [
          Text(
            quiz.title,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: p.text,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 8),
          BlockList(blocks: quiz.prompt, accent: widget.accent),
          const SizedBox(height: 12),
          if (quiz.isChoice)
            ..._choiceBody(context)
          else
            ..._revealBody(context),
        ],
      ),
      bottomNavigationBar: quiz.isChoice ? _choiceBar() : null,
    );
  }

  // -------------------------------------------------------------- choice
  List<Widget> _choiceBody(BuildContext context) {
    final p = context.palette;
    return [
      if (quiz.multiSelect)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            'Select all that apply.',
            style: TextStyle(color: p.textDim, fontSize: 13),
          ),
        ),
      for (var i = 0; i < quiz.options.length; i++) _optionTile(i),
      if (_checked)
        for (var i = 0; i < quiz.options.length; i++)
          if (quiz.options[i].why != null &&
              (quiz.options[i].correct || _selected.contains(i)))
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: p.surface2,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: RichParagraph(
                  '${quiz.options[i].correct ? "✓" : "✗"} ${quiz.options[i].why}',
                  style: TextStyle(color: p.text, fontSize: 13.5, height: 1.4),
                ),
              ),
            ),
    ];
  }

  Widget _optionTile(int i) {
    final p = context.palette;
    final opt = quiz.options[i];
    final selected = _selected.contains(i);
    Color border = p.stroke;
    Color bg = p.surface;
    Widget? trailing;
    if (_checked) {
      if (opt.correct) {
        border = Colors.green;
        bg = Colors.green.withValues(alpha: 0.10);
        trailing = const Icon(Icons.check_rounded, color: Colors.green);
      } else if (selected) {
        border = Colors.red;
        bg = Colors.red.withValues(alpha: 0.10);
        trailing = const Icon(Icons.close_rounded, color: Colors.red);
      }
    } else if (selected) {
      border = widget.accent;
      bg = widget.accent.withValues(alpha: 0.10);
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _toggle(i),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: border, width: 1.5),
            ),
            child: Row(
              children: [
                Icon(
                  quiz.multiSelect
                      ? (selected
                            ? Icons.check_box_rounded
                            : Icons.check_box_outline_blank_rounded)
                      : (selected
                            ? Icons.radio_button_checked_rounded
                            : Icons.radio_button_unchecked_rounded),
                  size: 20,
                  color: selected ? widget.accent : p.textDim,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: RichParagraph(
                    opt.text,
                    style: TextStyle(color: p.text, fontSize: 15, height: 1.4),
                  ),
                ),
                if (trailing != null) trailing,
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _choiceBar() {
    final p = context.palette;
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        12 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: p.surface,
        border: Border(top: BorderSide(color: p.stroke)),
      ),
      child: _checked
          ? Row(
              children: [
                Expanded(
                  child: Text(
                    _resultText(),
                    style: TextStyle(
                      color: p.text,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: widget.accent,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Done'),
                ),
              ],
            )
          : SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: widget.accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: _selected.isEmpty ? null : _check,
                child: const Text('Check answer'),
              ),
            ),
    );
  }

  String _resultText() {
    final correctIdx = {
      for (var i = 0; i < quiz.options.length; i++)
        if (quiz.options[i].correct) i,
    };
    final hits = _selected.where(correctIdx.contains).length;
    final wrong = _selected.where((i) => !correctIdx.contains(i)).length;
    if (hits == correctIdx.length && wrong == 0) return 'Correct! 🎉';
    return '$hits of ${correctIdx.length} correct';
  }

  // -------------------------------------------------------------- reveal
  List<Widget> _revealBody(BuildContext context) {
    final p = context.palette;
    return [
      Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: widget.accent.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border(left: BorderSide(color: widget.accent, width: 3)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.lightbulb_outline_rounded,
              size: 18,
              color: widget.accent,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Self-check. In the full course this is a fill-in task — here, '
                'work out the answer in your head (the ▢ marks the blanks), then '
                'tap “Show answers” to check yourself.',
                style: TextStyle(color: p.text, fontSize: 13.5, height: 1.45),
              ),
            ),
          ],
        ),
      ),
      for (final row in quiz.rows)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: p.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: p.stroke),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (row.question.isNotEmpty)
                  RichParagraph(
                    row.question,
                    style: TextStyle(color: p.text, fontSize: 15, height: 1.4),
                  ),
                if (row.question.isNotEmpty) const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Answer: ',
                      style: TextStyle(
                        color: p.textDim,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        _revealed ? row.answer : '••••••',
                        style: TextStyle(
                          fontFamily: kMonoFont,
                          color: _revealed ? widget.accent : p.textDim,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                if (_revealed && row.why != null) ...[
                  const SizedBox(height: 6),
                  RichParagraph(
                    row.why!,
                    style: TextStyle(
                      color: p.textDim,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      const SizedBox(height: 8),
      SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: widget.accent,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          onPressed: () => setState(() => _revealed = !_revealed),
          icon: Icon(
            _revealed ? Icons.visibility_off_rounded : Icons.visibility_rounded,
            size: 18,
          ),
          label: Text(_revealed ? 'Hide answers' : 'Show answers'),
        ),
      ),
    ];
  }
}
