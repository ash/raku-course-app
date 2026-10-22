import 'package:flutter/material.dart';
import 'package:raku_engine/raku_engine.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/block_view.dart';
import 'playground_screen.dart';

class ExerciseScreen extends StatefulWidget {
  final Exercise exercise;
  final Color accent;

  const ExerciseScreen({
    super.key,
    required this.exercise,
    required this.accent,
  });

  @override
  State<ExerciseScreen> createState() => _ExerciseScreenState();
}

class _ExerciseScreenState extends State<ExerciseScreen> {
  bool _showSolution = false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final ex = widget.exercise;
    return Scaffold(
      appBar: AppBar(title: const Text('Exercise')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          Text(
            ex.title,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: p.text,
              height: 1.3,
            ),
          ),
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 6),
            height: 3,
            width: 48,
            decoration: BoxDecoration(
              color: widget.accent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          if (ex.prompt.isNotEmpty)
            BlockList(blocks: ex.prompt, accent: widget.accent)
          else
            Text(
              'Try this exercise in your Raku environment.',
              style: TextStyle(color: p.textDim, fontSize: 15),
            ),
          const SizedBox(height: 20),
          if (RakuEngine.instance.isAvailable) ...[
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: widget.accent,
                  side: BorderSide(color: widget.accent.withValues(alpha: 0.6)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PlaygroundScreen(
                      title: ex.title,
                      draftKey: 'exercise:${ex.id}',
                      initialCode: '# ${ex.title}\n\n',
                    ),
                  ),
                ),
                icon: const Icon(Icons.code_rounded, size: 18),
                label: const Text('Solve it in the Playground'),
              ),
            ),
            const SizedBox(height: 10),
          ],
          if (ex.hasSolution) ...[
            if (!_showSolution)
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: widget.accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: () => setState(() => _showSolution = true),
                  icon: const Icon(Icons.lightbulb_outline_rounded, size: 18),
                  label: const Text('Show solution'),
                ),
              )
            else ...[
              Row(
                children: [
                  Icon(Icons.lightbulb_rounded, color: widget.accent, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'SOLUTION',
                    style: TextStyle(
                      color: widget.accent,
                      fontSize: 13,
                      letterSpacing: 1,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => setState(() => _showSolution = false),
                    child: const Text('Hide'),
                  ),
                ],
              ),
              BlockList(blocks: ex.solution, accent: widget.accent),
            ],
          ] else
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: p.surface2,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'This exercise is for self-practice — no written solution is '
                'provided.',
                style: TextStyle(color: p.textDim, fontSize: 14, height: 1.4),
              ),
            ),
        ],
      ),
    );
  }
}
