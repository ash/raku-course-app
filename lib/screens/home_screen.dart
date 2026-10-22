import 'package:flutter/material.dart';
import 'package:raku_engine/raku_engine.dart';
import '../models.dart';
import '../progress.dart';
import '../theme.dart';
import '../theme_controller.dart';
import 'about_screen.dart';
import 'part_browser_screen.dart';
import 'playground_screen.dart';
import 'reader_screen.dart';
import 'search_screen.dart';

class HomeScreen extends StatelessWidget {
  final Course course;
  final Progress progress;
  final ThemeController theme;

  const HomeScreen({
    super.key,
    required this.course,
    required this.progress,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      body: AnimatedBuilder(
        animation: progress,
        builder: (context, _) => CustomScrollView(
          slivers: [
            SliverAppBar(
              pinned: true,
              backgroundColor: p.bg,
              actions: [
                if (RakuEngine.instance.isAvailable)
                  IconButton(
                    tooltip: 'Playground',
                    icon: const Icon(Icons.code_rounded),
                    onPressed: () => openPlayground(context),
                  ),
                IconButton(
                  tooltip: 'Search',
                  icon: const Icon(Icons.search_rounded),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => SearchScreen(
                        course: course,
                        progress: progress,
                      ),
                    ),
                  ),
                ),
                AnimatedBuilder(
                  animation: theme,
                  builder: (context, _) => IconButton(
                    tooltip: 'Theme',
                    icon: Icon(ThemeController.iconFor(theme.mode)),
                    onPressed: theme.cycle,
                  ),
                ),
                IconButton(
                  tooltip: 'About',
                  icon: const Icon(Icons.info_outline_rounded),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AboutScreen(course: course),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
              ],
              title: const Text('Course of Raku'),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  Text(
                    course.tagline,
                    style: TextStyle(color: p.textDim, fontSize: 15),
                  ),
                  const SizedBox(height: 18),
                  _StatsRow(course: course, progress: progress),
                  const SizedBox(height: 18),
                  if (RakuEngine.instance.isAvailable) ...[
                    const _PlaygroundCard(),
                    const SizedBox(height: 16),
                  ],
                  _ContinueCard(course: course, progress: progress),
                  const SizedBox(height: 8),
                  for (final part in course.parts)
                    _PartCard(
                      course: course,
                      part: part,
                      progress: progress,
                    ),
                  const SizedBox(height: 16),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  final Course course;
  final Progress progress;
  const _StatsRow({required this.course, required this.progress});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final pct = course.lessonCount == 0
        ? 0
        : (progress.totalDone / course.lessonCount * 100).round();
    final stats = <(String, String)>[
      ('$pct%', 'done'),
      ('${course.lessonCount}', 'lessons'),
      ('${course.quizCount}', 'quizzes'),
      ('${course.exerciseCount}', 'exercises'),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: p.stroke),
      ),
      child: Row(
        children: [
          for (final s in stats)
            Expanded(
              child: Column(
                children: [
                  Text(
                    s.$1,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: AppColors.rakuAccent,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    s.$2,
                    style: TextStyle(color: p.textDim, fontSize: 12),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ContinueCard extends StatelessWidget {
  final Course course;
  final Progress progress;
  const _ContinueCard({required this.course, required this.progress});

  @override
  Widget build(BuildContext context) {
    final id = progress.lastPage;
    if (id == null) return const SizedBox.shrink();
    final page = course.byId(id);
    if (page == null) return const SizedBox.shrink();
    final accent = AppColors.partColor(page.partIndex);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Material(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => openReader(context, course, progress, page),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.play_circle_fill_rounded, color: accent, size: 32),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Continue',
                        style: TextStyle(
                          color: context.palette.textDim,
                          fontSize: 12,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        page.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: context.palette.text,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PartCard extends StatelessWidget {
  final Course course;
  final Part part;
  final Progress progress;
  const _PartCard({
    required this.course,
    required this.part,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final accent = AppColors.partColor(part.index);
    final frac = progress.fractionFor(part.pageIds);
    final done = progress.doneCountFor(part.pageIds);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: p.surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            // Single-page parts (e.g. "About this course") have no sections to
            // browse — open the page directly instead of a one-item list.
            if (part.pageIds.length == 1) {
              final page = course.byId(part.pageIds.first);
              if (page != null) {
                openReader(context, course, progress, page);
                return;
              }
            }
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => PartBrowserScreen(
                  course: course,
                  part: part,
                  progress: progress,
                ),
              ),
            );
          },
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: p.stroke),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: Text(
                        course.badgeFor(part),
                        style: TextStyle(
                          color: accent,
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        part.title,
                        style: TextStyle(
                          color: p.text,
                          fontSize: 16.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded, color: p.textDim),
                  ],
                ),
                if (part.description.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    part.description,
                    style: TextStyle(
                      color: p.textDim,
                      fontSize: 13.5,
                      height: 1.45,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: frac,
                    minHeight: 6,
                    backgroundColor: p.surface2,
                    valueColor: AlwaysStoppedAnimation(accent),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '$done / ${part.pageIds.length} lessons',
                  style: TextStyle(color: p.textDim, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

void openPlayground(BuildContext context) => Navigator.push(
  context,
  MaterialPageRoute(builder: (_) => const PlaygroundScreen.main()),
);

class _PlaygroundCard extends StatelessWidget {
  const _PlaygroundCard();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Material(
      color: AppColors.codeBg,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => openPlayground(context),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.rakuAccent.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  color: AppColors.rakuAccent,
                  size: 28,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Playground',
                      style: TextStyle(
                        color: AppColors.codeText,
                        fontSize: 16.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Write and run Raku right on your device — and run '
                      'the course examples here, too.',
                      style: TextStyle(
                        color: AppColors.codeDim,
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: p.textDim),
            ],
          ),
        ),
      ),
    );
  }
}
