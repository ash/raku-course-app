import 'package:flutter/material.dart';
import '../models.dart';
import '../theme.dart';
import 'code_view.dart';
import 'raku_code_block.dart';
import 'rich_text_span.dart';

/// Renders a list of [Block]s (lesson body, quiz prompt, exercise text).
class BlockList extends StatelessWidget {
  final List<Block> blocks;
  final Color accent;
  const BlockList({super.key, required this.blocks, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [for (final b in blocks) BlockView(block: b, accent: accent)],
    );
  }
}

class BlockView extends StatelessWidget {
  final Block block;
  final Color accent;
  const BlockView({super.key, required this.block, required this.accent});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    switch (block.type) {
      case 'code':
        if (block.isRaku) {
          return RakuCodeBlock(code: block.value, runnable: block.runnable);
        }
        return CodeView(code: block.value, kind: CodeKind.other);
      case 'codeOutput':
        return CodeView(code: block.value, kind: CodeKind.terminal);
      case 'output':
        return CodeView(code: block.value, kind: CodeKind.output);
      case 'h':
        final level = block.level ?? 2;
        return Padding(
          padding: EdgeInsets.only(top: level <= 2 ? 18 : 12, bottom: 4),
          child: Text(
            block.value,
            style: TextStyle(
              fontSize: level <= 2 ? 18 : 15.5,
              fontWeight: FontWeight.w700,
              color: level <= 2 ? accent : p.text,
              height: 1.3,
            ),
          ),
        );
      case 'ul':
      case 'ol':
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var k = 0; k < block.items.length; k++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 24,
                        child: Text(
                          block.type == 'ol' ? '${k + 1}.' : '•',
                          style: TextStyle(
                            color: accent,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Expanded(
                        child: RichParagraph(
                          block.items[k],
                          style: TextStyle(
                            color: p.text,
                            fontSize: 15.5,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      case 'tip':
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border(left: BorderSide(color: accent, width: 3)),
          ),
          child: RichParagraph(
            block.value,
            style: TextStyle(color: p.text, fontSize: 14.5, height: 1.5),
          ),
        );
      case 'p':
      default:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: RichParagraph(
            block.value,
            style: TextStyle(color: p.text, fontSize: 16, height: 1.55),
          ),
        );
    }
  }
}
