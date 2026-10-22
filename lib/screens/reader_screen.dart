import 'package:flutter/material.dart' hide Page;
import 'package:url_launcher/url_launcher.dart';
import '../models.dart';
import '../progress.dart';
import '../theme.dart';
import '../widgets/block_view.dart';
import '../widgets/rich_text_span.dart';
import 'exercise_screen.dart';
import 'final_test_screen.dart';
import 'quiz_player_screen.dart';

/// Open a page in the reader (replacing the current reader if pushed from one).
void openReader(
  BuildContext context,
  Course course,
  Progress progress,
  Page page,
) {
  progress.setLastPage(page.id);
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) =>
          ReaderScreen(course: course, progress: progress, page: page),
    ),
  );
}

class ReaderScreen extends StatefulWidget {
  final Course course;
  final Progress progress;
  final Page page;

  const ReaderScreen({
    super.key,
    required this.course,
    required this.progress,
    required this.page,
  });

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  late Page page = widget.page;
  final _scroll = ScrollController();

  Color get accent => AppColors.partColor(page.partIndex);

  @override
  void initState() {
    super.initState();
    widget.progress.setLastPage(page.id);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _go(Page? target) {
    if (target == null) return;
    setState(() => page = target);
    widget.progress.setLastPage(page.id);
    _scroll.animateTo(
      0,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  /// Handle a tapped inline link: external URLs open in the browser, internal
  /// course links navigate within the reader.
  void _openLink(String href) {
    final h = href.trim();
    if (h.startsWith('http://') ||
        h.startsWith('https://') ||
        h.startsWith('mailto:')) {
      final uri = Uri.tryParse(h);
      if (uri != null) {
        launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      return;
    }
    final target = _resolveInternal(h);
    if (target != null) {
      // Push a new reader so the app bar back button returns to this page.
      openReader(context, widget.course, widget.progress, target);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('That section is not part of this app.'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  /// Resolve an internal (relative or absolute) course link to a page, using
  /// the current page id as the base for relative paths.
  Page? _resolveInternal(String href) {
    var path = href.split('#').first.split('?').first;
    if (path.isEmpty) return null;
    final List<String> segs;
    if (path.startsWith('/')) {
      segs = path.split('/').where((s) => s.isNotEmpty).toList();
    } else {
      // Relative to the current page, treated as a directory (as on the site).
      segs = page.id.split('/').where((s) => s.isNotEmpty).toList();
      for (final part in path.split('/')) {
        if (part.isEmpty || part == '.') continue;
        if (part == '..') {
          if (segs.isNotEmpty) segs.removeLast();
        } else {
          segs.add(part);
        }
      }
    }
    return widget.course.byId(segs.join('/'));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final partTitle = widget.course.parts[page.partIndex].title;
    return AnimatedBuilder(
      animation: widget.progress,
      builder: (context, _) {
        final done = widget.progress.isDone(page.id);
        return Scaffold(
          appBar: AppBar(
            title: Text(
              partTitle,
              style: TextStyle(color: p.textDim, fontSize: 14),
            ),
            actions: [
              IconButton(
                tooltip: done ? 'Completed' : 'Mark complete',
                icon: Icon(
                  done
                      ? Icons.check_circle_rounded
                      : Icons.check_circle_outline_rounded,
                  color: done ? accent : p.textDim,
                ),
                onPressed: () => widget.progress.toggle(page.id),
              ),
            ],
          ),
          body: LinkScope(
            basePageId: page.id,
            onTap: _openLink,
            child: ListView(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 110),
              children: [
                Text(
                  page.title,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    height: 1.25,
                    color: p.text,
                  ),
                ),
                Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 6),
                  height: 3,
                  width: 48,
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                BlockList(blocks: page.blocks, accent: accent),
                ..._topics(),
                if (page.quizzes.isNotEmpty) _quizzes(),
                if (page.exercises.isNotEmpty) _exercises(page.exercises),
                if (page.finalTest.isNotEmpty) _finalTestCard(),
              ],
            ),
          ),
          bottomNavigationBar: _navBar(),
        );
      },
    );
  }

  Widget _finalTestCard() {
    final p = context.palette;
    final n = page.finalTest.length;
    final best = widget.progress.bestScore(FinalTestScreen.quizId);
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: accent.withValues(alpha: 0.4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$n questions · about 30 minutes',
              style: TextStyle(color: p.textDim, fontSize: 13),
            ),
            if (best != null) ...[
              const SizedBox(height: 4),
              Text(
                'Your best so far: $best / $n',
                style: TextStyle(
                  color: accent,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            const SizedBox(height: 14),
            FutureBuilder<int?>(
              future: FinalTestScreen.answeredSoFar(n),
              builder: (context, snap) {
                final soFar = snap.data;
                return SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => FinalTestScreen(
                            questions: page.finalTest,
                            progress: widget.progress,
                            accent: accent,
                          ),
                        ),
                      );
                      if (mounted) setState(() {});
                    },
                    icon: const Icon(Icons.flag_rounded, size: 18),
                    label: Text(
                      soFar != null
                          ? 'Continue — question ${soFar + 1} of $n'
                          : 'Start the test',
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(IconData icon, String label) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 8),
    child: Row(
      children: [
        Icon(icon, size: 18, color: accent),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            letterSpacing: 1,
            fontWeight: FontWeight.w700,
            color: accent,
          ),
        ),
      ],
    ),
  );

  /// On a section's landing page, list its sub-topics (the children of this
  /// page's navigation node) so the page isn't just intro → exercises.
  List<Widget> _topics() {
    final node = widget.course.nodeFor(page);
    final kids = (node?.children ?? const <TocNode>[])
        .where((k) => k.pageId != null)
        .toList();
    if (kids.isEmpty) return const [];
    return [
      _sectionHeader(Icons.list_alt_rounded, 'TOPICS'),
      for (final kid in kids)
        _entryTile(
          title: kid.title,
          subtitle: _countLabel(kid.quizzes, kid.exercises),
          badge: widget.progress.isDone(kid.pageId!)
              ? Icon(Icons.check_circle_rounded, color: accent, size: 20)
              : null,
          onTap: () {
            final target = widget.course.byId(kid.pageId!);
            if (target != null) {
              openReader(context, widget.course, widget.progress, target);
            }
          },
        ),
    ];
  }

  String _countLabel(int quizzes, int exercises) {
    final parts = <String>[];
    if (quizzes > 0) {
      parts.add('$quizzes ${quizzes == 1 ? 'quiz' : 'quizzes'}');
    }
    if (exercises > 0) {
      parts.add('$exercises ${exercises == 1 ? 'exercise' : 'exercises'}');
    }
    return parts.join(' · ');
  }

  Widget _quizzes() {
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(Icons.quiz_rounded, 'QUIZZES'),
        for (final quiz in page.quizzes)
          _entryTile(
            title: quiz.title,
            subtitle: quiz.isChoice
                ? '${quiz.options.length} options'
                : 'Self-check',
            badge: _scoreBadge(quiz),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => QuizPlayerScreen(
                  quiz: quiz,
                  accent: accent,
                  progress: widget.progress,
                  quizId: '${page.id}::${quiz.title}',
                ),
              ),
            ),
          ),
        const SizedBox(height: 4),
        Text(
          'Tip: try the exercises and quizzes before revealing answers.',
          style: TextStyle(color: p.textDim, fontSize: 12.5),
        ),
      ],
    );
  }

  Widget? _scoreBadge(Quiz quiz) {
    if (!quiz.isChoice) return null;
    final best = widget.progress.bestScore('${page.id}::${quiz.title}');
    final total = widget.progress.totalFor('${page.id}::${quiz.title}');
    if (best == null || total == null) return null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '$best/$total',
        style: TextStyle(
          color: accent,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _exercises(List<Exercise> exercises) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(Icons.fitness_center_rounded, 'EXERCISES'),
        for (final ex in exercises)
          _entryTile(
            title: ex.title,
            subtitle: ex.hasSolution ? 'Has solution' : 'Practice',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ExerciseScreen(exercise: ex, accent: accent),
              ),
            ),
          ),
      ],
    );
  }

  Widget _entryTile({
    required String title,
    required String subtitle,
    Widget? badge,
    required VoidCallback onTap,
  }) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: p.surface,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: p.stroke),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: p.text,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (subtitle.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: TextStyle(color: p.textDim, fontSize: 12.5),
                        ),
                      ],
                    ],
                  ),
                ),
                if (badge != null) ...[badge, const SizedBox(width: 8)],
                Icon(Icons.chevron_right_rounded, color: p.textDim),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _navBar() {
    final p = context.palette;
    final prev = widget.course.prev(page);
    final next = widget.course.next(page);
    return Container(
      padding: EdgeInsets.fromLTRB(
        12,
        10,
        12,
        10 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: p.surface,
        border: Border(top: BorderSide(color: p.stroke)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: prev == null ? null : () => _go(prev),
            icon: const Icon(Icons.arrow_back_rounded),
            color: p.text,
            disabledColor: p.stroke,
          ),
          Expanded(
            child: Text(
              '${page.order + 1} / ${widget.course.pages.length}',
              textAlign: TextAlign.center,
              style: TextStyle(color: p.textDim, fontSize: 13),
            ),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: accent,
              foregroundColor: Colors.white,
            ),
            onPressed: next == null
                ? null
                : () {
                    widget.progress.setDone(page.id, true);
                    _go(next);
                  },
            icon: const Icon(Icons.arrow_forward_rounded, size: 18),
            label: const Text('Next'),
          ),
        ],
      ),
    );
  }
}
