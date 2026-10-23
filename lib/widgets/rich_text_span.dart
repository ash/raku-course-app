import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../theme.dart';

/// Provides link-tap handling to descendant [RichParagraph]s. When absent,
/// links render as styled-but-inert text (e.g. inside quiz screens).
class LinkScope extends InheritedWidget {
  /// Page id of the page the text belongs to — base for relative links.
  final String? basePageId;

  /// Called with the raw href when a link is tapped.
  final void Function(String href) onTap;

  const LinkScope({
    super.key,
    required this.basePageId,
    required this.onTap,
    required super.child,
  });

  static LinkScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LinkScope>();

  @override
  bool updateShouldNotify(LinkScope old) =>
      basePageId != old.basePageId || onTap != old.onTap;
}

/// Parses a small subset of inline markdown — **bold**, `code`,
/// [links](url), and *italic* / _italic_ — into spans. When [recognizerFor]
/// is supplied, link spans get a tap recognizer for the href; otherwise they
/// are styled but inert.
///
/// Italics need a space or opening punctuation before the first marker and a
/// space or closing punctuation after the last, so `$_`, `@*ARGS`, snake_case
/// and `2 * 3` stay as they are.
List<InlineSpan> parseInline(
  String text,
  TextStyle base, {
  required Color boldColor,
  required Color codeColor,
  required Color linkColor,
  GestureRecognizer? Function(String href)? recognizerFor,
}) {
  final spans = <InlineSpan>[];
  // bold | inline code | [text](url) | *italic* or _italic_
  final pattern = RegExp(
    r'\*\*(.+?)\*\*|`([^`]+?)`|\[([^\]]+)\]\(([^)]+)\)'
    r'|(?<=^|[\s(\[{"' "'" r'“‘—–/])([*_])(?![\s*_])([^*_`]+?)(?<![\s*_])\5'
    r'(?=$|[\s)\]}.,;:!?"' "'" r'”’—–/])',
  );
  int last = 0;
  for (final m in pattern.allMatches(text)) {
    if (m.start > last) {
      spans.add(TextSpan(text: text.substring(last, m.start), style: base));
    }
    if (m.group(1) != null) {
      spans.add(
        TextSpan(
          text: m.group(1),
          style: base.copyWith(fontWeight: FontWeight.w700, color: boldColor),
        ),
      );
    } else if (m.group(2) != null) {
      spans.add(
        TextSpan(
          text: m.group(2),
          style: base.copyWith(
            fontFamily: kMonoFont,
            fontSize: (base.fontSize ?? 15) - 1,
            color: codeColor,
          ),
        ),
      );
    } else if (m.group(3) != null) {
      final href = m.group(4);
      final rec = href == null ? null : recognizerFor?.call(href);
      spans.add(
        TextSpan(
          text: m.group(3),
          recognizer: rec,
          style: base.copyWith(
            color: linkColor,
            decoration: TextDecoration.underline,
            decorationColor: linkColor.withValues(alpha: 0.4),
          ),
        ),
      );
    } else if (m.group(6) != null) {
      spans.add(
        TextSpan(
          text: m.group(6),
          style: base.copyWith(fontStyle: FontStyle.italic),
        ),
      );
    }
    last = m.end;
  }
  if (last < text.length) {
    spans.add(TextSpan(text: text.substring(last), style: base));
  }
  return spans;
}

class RichParagraph extends StatefulWidget {
  final String text;
  final TextStyle style;
  const RichParagraph(this.text, {super.key, required this.style});

  @override
  State<RichParagraph> createState() => _RichParagraphState();
}

class _RichParagraphState extends State<RichParagraph> {
  final List<TapGestureRecognizer> _recognizers = [];

  void _clearRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  @override
  void dispose() {
    _clearRecognizers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final link = LinkScope.maybeOf(context);
    // Recognizers are rebuilt with the spans every build; release the old ones.
    _clearRecognizers();
    return Text.rich(
      TextSpan(
        children: parseInline(
          widget.text,
          widget.style,
          boldColor: p.text,
          codeColor: p.inlineCode,
          linkColor: AppColors.rakuAccent,
          recognizerFor: link == null
              ? null
              : (href) {
                  final r = TapGestureRecognizer()
                    ..onTap = () => link.onTap(href);
                  _recognizers.add(r);
                  return r;
                },
        ),
      ),
    );
  }
}
