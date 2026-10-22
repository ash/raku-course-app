import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models.dart';
import '../progress.dart';
import '../theme.dart';
import '../widgets/code_view.dart';
import '../widgets/rich_text_span.dart';

/// The Final Test: the course's hundred questions, one at a time, each checked
/// the moment it is answered, forward only — as on the course site. Answers
/// are saved as they are given, so leaving and coming back resumes the test.
class FinalTestScreen extends StatefulWidget {
  final List<FinalQuestion> questions;
  final Progress progress;
  final Color accent;

  const FinalTestScreen({
    super.key,
    required this.questions,
    required this.progress,
    required this.accent,
  });

  static const quizId = 'final-test';
  static const _stateKey = 'final_test_answers';

  /// How far an unfinished test has got, or null if none is in progress.
  static Future<int?> answeredSoFar(int total) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_stateKey);
      if (raw == null) return null;
      final n = (jsonDecode(raw) as List).length;
      return n > 0 && n < total ? n : null;
    } catch (_) {
      return null;
    }
  }

  @override
  State<FinalTestScreen> createState() => _FinalTestScreenState();
}

class _FinalTestScreenState extends State<FinalTestScreen> {
  final List<Object?> _answers = [];
  SharedPreferences? _prefs;
  bool _loaded = false;

  // the question on screen
  final Set<int> _picked = {};
  bool? _bool;
  final _input = TextEditingController();
  bool _checked = false;

  List<FinalQuestion> get _qs => widget.questions;
  int get _index => _answers.length - (_checked ? 1 : 0);
  bool get _finished => _answers.length == _qs.length && !_checked;
  int get _score {
    var s = 0;
    for (var i = 0; i < _answers.length; i++) {
      if (_qs[i].check(_answers[i])) s++;
    }
    return s;
  }

  @override
  void initState() {
    super.initState();
    _restore();
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _restore() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      final raw = _prefs!.getString(FinalTestScreen._stateKey);
      if (raw != null) {
        final saved = jsonDecode(raw) as List;
        if (saved.length <= _qs.length) _answers.addAll(saved);
      }
    } catch (_) {}
    if (mounted) setState(() => _loaded = true);
  }

  void _save() => _prefs?.setString(
    FinalTestScreen._stateKey,
    jsonEncode(_answers),
  );

  Object? get _chosen {
    final q = _qs[_index];
    return switch (q.type) {
      'boolean' => _bool,
      'input' => _input.text,
      'multi' => (_picked.toList()..sort()),
      _ => _picked.isEmpty ? null : _picked.first,
    };
  }

  bool get _canCheck {
    final q = _qs[_index];
    return switch (q.type) {
      'boolean' => _bool != null,
      'input' => _input.text.trim().isNotEmpty,
      _ => _picked.isNotEmpty,
    };
  }

  void _check() {
    FocusScope.of(context).unfocus();
    setState(() {
      _answers.add(_chosen);
      _checked = true;
    });
    _save();
    if (_answers.length == _qs.length) {
      widget.progress.recordQuiz(FinalTestScreen.quizId, _score, _qs.length);
    }
  }

  void _next() => setState(() {
    _checked = false;
    _picked.clear();
    _bool = null;
    _input.clear();
  });

  void _restart() {
    _prefs?.remove(FinalTestScreen._stateKey);
    setState(() {
      _answers.clear();
      _next();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('The Final Test')),
      body: !_loaded
          ? const SizedBox.shrink()
          : _finished
          ? _Result(
              questions: _qs,
              answers: _answers,
              score: _score,
              best: widget.progress.bestScore(FinalTestScreen.quizId),
              accent: widget.accent,
              onRestart: _restart,
            )
          : _question(context),
      bottomNavigationBar: !_loaded || _finished ? null : _bar(context),
    );
  }

  Widget _question(BuildContext context) {
    final p = context.palette;
    final q = _qs[_index];
    final right = _checked && q.check(_answers.last);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        Row(
          children: [
            Text(
              'Question ${_index + 1} of ${_qs.length}',
              style: TextStyle(
                color: widget.accent,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            Flexible(
              child: Text(
                'Part ${q.part} · ${q.topic}',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: p.textDim, fontSize: 12.5),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: (_index + (_checked ? 1 : 0)) / _qs.length,
            minHeight: 5,
            backgroundColor: p.surface2,
            valueColor: AlwaysStoppedAnimation(widget.accent),
          ),
        ),
        const SizedBox(height: 18),
        RichParagraph(
          q.question,
          style: TextStyle(color: p.text, fontSize: 17, height: 1.45),
        ),
        if (q.code != null) CodeView(code: q.code!),
        const SizedBox(height: 10),
        if (q.type == 'multi' && !_checked)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Select all that apply.',
              style: TextStyle(color: p.textDim, fontSize: 13),
            ),
          ),
        ..._answerArea(context, q),
        if (_checked) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: (right ? Colors.green : Colors.red).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border(
                left: BorderSide(
                  color: right ? Colors.green : Colors.red,
                  width: 3,
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  right ? '✓ Correct' : '✗ Not quite',
                  style: TextStyle(
                    color: right ? Colors.green : Colors.red,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                if (!right && (q.type == 'input' || q.type == 'boolean')) ...[
                  const SizedBox(height: 6),
                  RichParagraph(
                    'Answer: `${q.answerText}`',
                    style: TextStyle(color: p.text, fontSize: 14.5),
                  ),
                ],
                const SizedBox(height: 6),
                RichParagraph(
                  q.explain,
                  style: TextStyle(color: p.text, fontSize: 14.5, height: 1.45),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  List<Widget> _answerArea(BuildContext context, FinalQuestion q) {
    final p = context.palette;
    switch (q.type) {
      case 'boolean':
        return [
          Row(
            children: [
              for (final v in [true, false]) ...[
                Expanded(
                  child: _Tile(
                    label: v ? 'True' : 'False',
                    selected: _checked ? _answers.last == v : _bool == v,
                    correct: _checked ? q.answer == v : null,
                    accent: widget.accent,
                    onTap: _checked ? null : () => setState(() => _bool = v),
                  ),
                ),
                if (v) const SizedBox(width: 10),
              ],
            ],
          ),
        ];
      case 'input':
        return [
          TextField(
            controller: _input,
            enabled: !_checked,
            autocorrect: false,
            enableSuggestions: false,
            smartQuotesType: SmartQuotesType.disabled,
            smartDashesType: SmartDashesType.disabled,
            textCapitalization: TextCapitalization.none,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _canCheck && !_checked ? _check() : null,
            style: TextStyle(
              fontFamily: kMonoFont,
              fontFamilyFallback: kMonoFallback,
              fontSize: 16,
              color: p.text,
            ),
            decoration: const InputDecoration(
              hintText: 'Type your answer…',
              border: OutlineInputBorder(),
            ),
          ),
        ];
      default:
        final multi = q.type == 'multi';
        final given = _checked ? _answers.last : null;
        return [
          for (var i = 0; i < q.options.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _Tile(
                label: q.options[i],
                multi: multi,
                selected: _checked
                    ? (multi ? (given as List).contains(i) : given == i)
                    : _picked.contains(i),
                correct: _checked
                    ? (multi ? (q.answer as List).contains(i) : q.answer == i)
                    : null,
                accent: widget.accent,
                onTap: _checked
                    ? null
                    : () => setState(() {
                        if (multi) {
                          _picked.contains(i)
                              ? _picked.remove(i)
                              : _picked.add(i);
                        } else {
                          _picked
                            ..clear()
                            ..add(i);
                        }
                      }),
              ),
            ),
        ];
    }
  }

  Widget _bar(BuildContext context) {
    final p = context.palette;
    final last = _answers.length == _qs.length;
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        12 + MediaQuery.paddingOf(context).bottom,
      ),
      decoration: BoxDecoration(
        color: p.surface,
        border: Border(top: BorderSide(color: p.stroke)),
      ),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: widget.accent,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          onPressed: _checked
              ? (last ? () => setState(() => _checked = false) : _next)
              : (_canCheck ? _check : null),
          child: Text(
            _checked
                ? (last ? 'See your result →' : 'Next question →')
                : 'Check answer',
          ),
        ),
      ),
    );
  }
}

/// An answer option: selectable before checking, then green or red.
class _Tile extends StatelessWidget {
  final String label;
  final bool selected;
  final bool? correct;
  final bool multi;
  final Color accent;
  final VoidCallback? onTap;

  const _Tile({
    required this.label,
    required this.selected,
    required this.correct,
    required this.accent,
    required this.onTap,
    this.multi = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    Color border = p.stroke;
    Color bg = p.surface;
    Widget? trailing;
    if (correct != null) {
      if (correct!) {
        border = Colors.green;
        bg = Colors.green.withValues(alpha: 0.10);
        trailing = const Icon(Icons.check_rounded, color: Colors.green);
      } else if (selected) {
        border = Colors.red;
        bg = Colors.red.withValues(alpha: 0.10);
        trailing = const Icon(Icons.close_rounded, color: Colors.red);
      }
    } else if (selected) {
      border = accent;
      bg = accent.withValues(alpha: 0.10);
    }
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: border, width: 1.5),
          ),
          child: Row(
            children: [
              Icon(
                multi
                    ? (selected
                          ? Icons.check_box_rounded
                          : Icons.check_box_outline_blank_rounded)
                    : (selected
                          ? Icons.radio_button_checked_rounded
                          : Icons.radio_button_unchecked_rounded),
                size: 20,
                color: selected ? accent : p.textDim,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: RichParagraph(
                  label,
                  style: TextStyle(color: p.text, fontSize: 15, height: 1.4),
                ),
              ),
              ?trailing,
            ],
          ),
        ),
      ),
    );
  }
}

class _Result extends StatelessWidget {
  final List<FinalQuestion> questions;
  final List<Object?> answers;
  final int score;
  final int? best;
  final Color accent;
  final VoidCallback onRestart;

  const _Result({
    required this.questions,
    required this.answers,
    required this.score,
    required this.best,
    required this.accent,
    required this.onRestart,
  });

  // The course site's verdicts, at the same thresholds.
  String get _verdict {
    final f = score / questions.length;
    if (f == 1) return 'A perfect run. You know your Raku.';
    if (f >= 0.9) return 'Outstanding — a firm command of the whole course.';
    if (f >= 0.75) return 'Strong result. A few topics to revisit.';
    if (f >= 0.5) return 'A solid pass. Review the ones you missed.';
    if (f >= 0.3) return 'A start — worth another pass through the material.';
    return 'Early days. Work back through the parts and try again.';
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
      children: [
        Center(
          child: Text(
            '$score / ${questions.length}',
            style: TextStyle(
              fontSize: 44,
              fontWeight: FontWeight.w800,
              color: accent,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Center(
          child: Text(
            _verdict,
            textAlign: TextAlign.center,
            style: TextStyle(color: p.text, fontSize: 16),
          ),
        ),
        if (best != null && best! > score) ...[
          const SizedBox(height: 6),
          Center(
            child: Text(
              'Your best: $best / ${questions.length}',
              style: TextStyle(color: p.textDim, fontSize: 13),
            ),
          ),
        ],
        const SizedBox(height: 18),
        Center(
          child: OutlinedButton.icon(
            onPressed: onRestart,
            icon: const Icon(Icons.replay_rounded, size: 18),
            label: const Text('Take the test again'),
          ),
        ),
        const SizedBox(height: 26),
        Text(
          'REVIEW',
          style: TextStyle(
            color: accent,
            fontSize: 12,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Every question with the correct answer. Green means you got it right.',
          style: TextStyle(color: p.textDim, fontSize: 13),
        ),
        const SizedBox(height: 10),
        for (var i = 0; i < questions.length; i++)
          _ReviewItem(
            n: i + 1,
            q: questions[i],
            given: answers[i],
          ),
      ],
    );
  }
}

class _ReviewItem extends StatelessWidget {
  final int n;
  final FinalQuestion q;
  final Object? given;
  const _ReviewItem({required this.n, required this.q, required this.given});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final ok = q.check(given);
    final color = ok ? Colors.green : Colors.red;
    final style = TextStyle(color: p.text, fontSize: 14, height: 1.4);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border(left: BorderSide(color: color, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RichParagraph('**$n.** ${q.question}', style: style),
          if (q.code != null) CodeView(code: q.code!),
          const SizedBox(height: 4),
          RichParagraph(
            'Correct answer: ${_code(q.answerText)}',
            style: style.copyWith(color: Colors.green.shade700),
          ),
          if (!ok)
            RichParagraph(
              'You answered: ${_code(q.describe(given))}',
              style: style.copyWith(color: Colors.red.shade400),
            ),
        ],
      ),
    );
  }

  // Option texts already carry their own `code` marks; plain answers get one.
  static String _code(String s) =>
      s.contains('`') || s.isEmpty ? (s.isEmpty ? '—' : s) : '`$s`';
}
