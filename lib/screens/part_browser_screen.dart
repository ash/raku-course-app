import 'package:flutter/material.dart';
import '../models.dart';
import '../progress.dart';
import '../theme.dart';
import 'reader_screen.dart';

class PartBrowserScreen extends StatelessWidget {
  final Course course;
  final Part part;
  final Progress progress;

  const PartBrowserScreen({
    super.key,
    required this.course,
    required this.part,
    required this.progress,
  });

  Color get accent => AppColors.partColor(part.index);

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      appBar: AppBar(title: Text(part.title)),
      body: AnimatedBuilder(
        animation: progress,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 32),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress.fractionFor(part.pageIds),
                  minHeight: 6,
                  backgroundColor: p.surface2,
                  valueColor: AlwaysStoppedAnimation(accent),
                ),
              ),
            ),
            for (final node in part.toc)
              _NodeTile(
                course: course,
                progress: progress,
                node: node,
                accent: accent,
                depth: 0,
              ),
          ],
        ),
      ),
    );
  }
}

class _NodeTile extends StatelessWidget {
  final Course course;
  final Progress progress;
  final TocNode node;
  final Color accent;
  final int depth;

  const _NodeTile({
    required this.course,
    required this.progress,
    required this.node,
    required this.accent,
    required this.depth,
  });

  void _open(BuildContext context) {
    final page = node.pageId == null ? null : course.byId(node.pageId!);
    if (page != null) openReader(context, course, progress, page);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final hasPage = node.pageId != null && course.byId(node.pageId!) != null;
    final done = hasPage && progress.isDone(node.pageId!);

    // A grouping node (subpart heading) with no own page: expandable header.
    if (!hasPage && node.hasChildren) {
      return Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: depth == 0,
          tilePadding: EdgeInsets.only(left: 8.0 + depth * 12, right: 8),
          childrenPadding: EdgeInsets.zero,
          title: Text(
            node.title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: p.text,
            ),
          ),
          iconColor: accent,
          collapsedIconColor: p.textDim,
          children: [
            for (final child in node.children)
              _NodeTile(
                course: course,
                progress: progress,
                node: child,
                accent: accent,
                depth: depth + 1,
              ),
          ],
        ),
      );
    }

    // A node with children AND its own page → expandable, header opens page.
    if (hasPage && node.hasChildren) {
      return Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: EdgeInsets.only(left: 8.0 + depth * 12, right: 8),
          childrenPadding: EdgeInsets.zero,
          leading: _doneIcon(done, context),
          title: GestureDetector(
            onTap: () => _open(context),
            child: Text(
              node.title,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: p.text,
              ),
            ),
          ),
          subtitle: _badges(context),
          iconColor: accent,
          collapsedIconColor: p.textDim,
          children: [
            for (final child in node.children)
              _NodeTile(
                course: course,
                progress: progress,
                node: child,
                accent: accent,
                depth: depth + 1,
              ),
          ],
        ),
      );
    }

    // Leaf lesson row.
    return Padding(
      padding: EdgeInsets.only(left: 8.0 + depth * 12, right: 8),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        dense: true,
        leading: _doneIcon(done, context),
        title: Text(
          node.title,
          style: TextStyle(fontSize: 14.5, color: p.text),
        ),
        subtitle: _badges(context),
        onTap: hasPage ? () => _open(context) : null,
      ),
    );
  }

  Widget _doneIcon(bool done, BuildContext context) => Icon(
    done ? Icons.check_circle_rounded : Icons.circle_outlined,
    size: 18,
    color: done ? accent : context.palette.textDim,
  );

  Widget? _badges(BuildContext context) {
    final parts = <String>[];
    if (node.quizzes > 0) {
      parts.add('${node.quizzes} ${node.quizzes == 1 ? 'quiz' : 'quizzes'}');
    }
    if (node.exercises > 0) {
      parts.add(
        '${node.exercises} ${node.exercises == 1 ? 'exercise' : 'exercises'}',
      );
    }
    if (parts.isEmpty) return null;
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Text(
        parts.join(', '),
        style: TextStyle(color: context.palette.textDim, fontSize: 11.5),
      ),
    );
  }
}
