import 'package:flutter/material.dart';
import 'package:raku_engine/raku_engine.dart';
import '../theme.dart';

/// What a [CodeView] shows: Raku source, a terminal session, program output,
/// or code in some other language (shown plain).
enum CodeKind { raku, terminal, output, other }

/// Renders a code block. Raku is highlighted with the Raku++ engine's own
/// tokenizer when the engine is present, and with a small built-in one when
/// it is not. The block is intentionally dark in BOTH light and dark themes
/// so syntax colours stay legible everywhere.
class CodeView extends StatelessWidget {
  final String code;
  final CodeKind kind;

  /// Widgets at the right end of the header row (e.g. Run / Edit buttons).
  final List<Widget> actions;

  /// Shown under the code, inside the same dark card (e.g. a run's output).
  final Widget? footer;

  const CodeView({
    super.key,
    required this.code,
    this.kind = CodeKind.raku,
    this.actions = const [],
    this.footer,
  });

  static TextStyle get monoStyle => TextStyle(
    fontFamily: kMonoFont,
    fontFamilyFallback: kMonoFallback,
    fontSize: 13.5,
    height: 1.5,
  );

  @override
  Widget build(BuildContext context) {
    final label = switch (kind) {
      CodeKind.terminal => 'TERMINAL',
      CodeKind.output => 'OUTPUT',
      CodeKind.raku => actions.isEmpty ? null : 'RAKU',
      CodeKind.other => null,
    };
    final icon = switch (kind) {
      CodeKind.terminal => Icons.terminal_rounded,
      CodeKind.output => Icons.subdirectory_arrow_right_rounded,
      _ => Icons.code_rounded,
    };
    final plain = kind != CodeKind.raku;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.codeBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.codeBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (label != null || actions.isNotEmpty)
            Padding(
              padding: EdgeInsets.fromLTRB(14, actions.isEmpty ? 10 : 4, 6, 0),
              child: Row(
                children: [
                  if (label != null) ...[
                    Icon(icon, size: 13, color: AppColors.codeDim),
                    const SizedBox(width: 5),
                    Text(
                      label,
                      style: const TextStyle(
                        color: AppColors.codeDim,
                        fontSize: 10,
                        letterSpacing: 1.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                  const Spacer(),
                  ...actions,
                ],
              ),
            ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              14,
              label != null || actions.isNotEmpty ? 6 : 12,
              14,
              12,
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SelectableText.rich(
                TextSpan(
                  style: monoStyle.copyWith(
                    color: kind == CodeKind.raku
                        ? AppColors.codeText
                        : kind == CodeKind.other
                        ? AppColors.codeText
                        : AppColors.codeOutput,
                  ),
                  children: plain ? null : highlightRaku(code),
                  text: plain ? code : null,
                ),
              ),
            ),
          ),
          ?footer,
        ],
      ),
    );
  }
}

const _cmt = TextStyle(
  color: AppColors.codeComment,
  fontStyle: FontStyle.italic,
);
const _str = TextStyle(color: AppColors.codeString);
const _rx = TextStyle(color: AppColors.codeRegex);
const _num = TextStyle(color: AppColors.codeNumber);
const _sig = TextStyle(color: AppColors.codeSigil, fontWeight: FontWeight.w600);
const _kw = TextStyle(color: AppColors.codeKeyword, fontWeight: FontWeight.w600);
const _type = TextStyle(color: AppColors.codeType);
const _base = TextStyle(color: AppColors.codeText);

/// Raku source as coloured spans — the engine's tokenizer when available.
List<InlineSpan> highlightRaku(String code) {
  final tokens = RakuEngine.instance.highlight(code);
  if (tokens == null) return _fallbackTokenize(code);
  return [
    for (final t in tokens)
      TextSpan(
        text: t.text,
        style: switch (t.kind) {
          RakuTokenKind.keyword || RakuTokenKind.builtin => _kw,
          RakuTokenKind.variable => _sig,
          RakuTokenKind.string => _str,
          RakuTokenKind.regex => _rx,
          RakuTokenKind.comment => _cmt,
          RakuTokenKind.number => _num,
          RakuTokenKind.type => _type,
          _ => _base,
        },
      ),
  ];
}

const _keywords = {
  'my', 'our', 'has', 'state', 'sub', 'method', 'multi', 'class', 'role',
  'module', 'package', 'grammar', 'token', 'rule', 'regex', 'enum',
  'subset', 'constant', 'return', 'if', 'elsif', 'else', 'unless', 'with',
  'without', 'for', 'while', 'until', 'repeat', 'loop', 'given', 'when',
  'default', 'gather', 'take', 'do', 'use', 'need', 'require', 'import',
  'is', 'does', 'but', 'and', 'or', 'not', 'so', 'say', 'put', 'print',
  'note', 'die', 'try', 'CATCH', 'last', 'next', 'redo', 'proceed',
  'succeed', 'where', 'True', 'False', 'Nil', 'Any', 'self',
};

final _idStart = RegExp(r'[A-Za-z_]');
final _idChar = RegExp(r'[A-Za-z0-9_-]');
final _digit = RegExp(r'[0-9]');
final _numChar = RegExp(r'[0-9_a-fA-FxXeE.]');

/// The app's original lightweight highlighter, for when the engine is absent.
List<InlineSpan> _fallbackTokenize(String code) {
  final spans = <InlineSpan>[];
  final n = code.length;
  int i = 0;

  void add(String s, TextStyle st) => spans.add(TextSpan(text: s, style: st));

  while (i < n) {
    final c = code[i];

    if (c == '#') {
      int j = i;
      while (j < n && code[j] != '\n') {
        j++;
      }
      add(code.substring(i, j), _cmt);
      i = j;
      continue;
    }

    if (c == r'$' || c == '@' || c == '%' || c == '&') {
      int j = i + 1;
      if (j < n && (code[j] == '.' || code[j] == '!' || code[j] == '^')) {
        j++;
      }
      while (j < n && _idChar.hasMatch(code[j])) {
        j++;
      }
      if (j > i + 1) {
        add(code.substring(i, j), _sig);
        i = j;
        continue;
      }
    }

    if (c == '"' || c == "'") {
      final q = c;
      int j = i + 1;
      while (j < n) {
        if (code[j] == '\\') {
          j += 2;
          continue;
        }
        if (code[j] == q) {
          j++;
          break;
        }
        j++;
      }
      add(code.substring(i, j.clamp(0, n)), _str);
      i = j.clamp(0, n);
      continue;
    }

    if (_digit.hasMatch(c)) {
      int j = i;
      while (j < n && _numChar.hasMatch(code[j])) {
        j++;
      }
      add(code.substring(i, j), _num);
      i = j;
      continue;
    }

    if (_idStart.hasMatch(c)) {
      int j = i;
      while (j < n && _idChar.hasMatch(code[j])) {
        j++;
      }
      final word = code.substring(i, j);
      add(word, _keywords.contains(word) ? _kw : _base);
      i = j;
      continue;
    }

    add(c, _base);
    i++;
  }
  return spans;
}
