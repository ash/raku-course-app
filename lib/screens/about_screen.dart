import 'package:flutter/material.dart';
import 'package:raku_engine/raku_engine.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models.dart';
import '../theme.dart';

class AboutScreen extends StatelessWidget {
  final Course course;
  const AboutScreen({super.key, required this.course});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    TextStyle body = TextStyle(color: p.text, fontSize: 15.5, height: 1.55);
    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
        children: [
          const SizedBox(height: 8),
          Center(
            child: Column(
              children: [
                const Text('🦋', style: TextStyle(fontSize: 56)),
                const SizedBox(height: 12),
                Text(
                  course.appTitle,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: p.text,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  course.tagline,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: p.textDim, fontSize: 14),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          _stat(
            context,
            '${course.parts.where((p) => p.pageIds.length > 1).length}',
            'parts',
          ),
          _stat(context, '${course.lessonCount}', 'lessons'),
          _stat(context, '${course.quizCount}', 'quizzes'),
          _stat(context, '${course.exerciseCount}', 'exercises'),
          const SizedBox(height: 24),
          Text(
            'This app bundles the complete Course of Raku for offline reading. '
            'It covers the essentials of the language through to advanced '
            'topics, object orientation, regexes and grammars, and functional, '
            'concurrent, reactive, and web programming.',
            style: body,
          ),
          if (RakuEngine.instance.isAvailable) ...[
            const SizedBox(height: 12),
            Text(
              'The examples run on the device itself: the app carries Raku++, '
              'a complete implementation of Raku, so the Run buttons and the '
              'Playground work without an internet connection.',
              style: body,
            ),
          ],
          const SizedBox(height: 16),
          Text('The author', style: _h(context)),
          const SizedBox(height: 6),
          Text(
            'The course is written by ${course.credit}, who has followed the '
            'development of Raku since its early days as Perl 6, and is the '
            'author of several books on programming in Raku.',
            style: body,
          ),
          const SizedBox(height: 16),
          Text('Credits', style: _h(context)),
          const SizedBox(height: 4),
          _link(context, Icons.person_outline_rounded, 'Andrew Shitov',
              'author of the course', 'andrewshitov.com'),
          _link(context, Icons.favorite_outline_rounded,
              'The Perl and Raku Foundation', 'supported the course content',
              'perlfoundation.org'),
          _link(context, Icons.memory_rounded, 'Raku++',
              'the Raku engine inside the app', 'raku.online'),
          _link(context, Icons.business_outlined, 'DeepSoft',
              'app development', 'deepsoft.online'),
          _link(context, Icons.code_rounded, 'Source on GitHub',
              'course content repository', 'github.com/ash/raku-course'),
          const SizedBox(height: 16),
          Text('Raku online', style: _h(context)),
          const SizedBox(height: 4),
          _link(context, Icons.public_rounded, 'Course of Raku',
              'read this course online', 'course.raku.org'),
          _link(context, Icons.language_rounded, 'Raku',
              'the language home page', 'raku.org'),
          _link(context, Icons.menu_book_rounded, 'Raku documentation',
              'official language docs', 'docs.raku.org'),
          const SizedBox(height: 24),
          Center(
            child: Text(
              RakuEngine.instance.isAvailable
                  ? 'Version 1.0.0 · Raku++ ${RakuEngine.instance.version}'
                  : 'Version 1.0.0',
              style: TextStyle(color: p.textDim, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _link(
    BuildContext context,
    IconData icon,
    String label,
    String note,
    String display,
  ) {
    final p = context.palette;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => launchUrl(
        Uri.parse('https://$display'),
        mode: LaunchMode.externalApplication,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(icon, size: 18, color: AppColors.rakuAccent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: label,
                          style: TextStyle(
                            color: p.text,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        TextSpan(
                          text: '  —  $note',
                          style: TextStyle(color: p.textDim, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    display,
                    style: const TextStyle(
                      color: AppColors.rakuAccent,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child:
                  Icon(Icons.open_in_new_rounded, size: 15, color: p.textDim),
            ),
          ],
        ),
      ),
    );
  }

  TextStyle _h(BuildContext context) => TextStyle(
    color: AppColors.rakuAccent,
    fontSize: 13,
    letterSpacing: 1,
    fontWeight: FontWeight.w700,
  );

  Widget _stat(BuildContext context, String value, String label) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(
            width: 56,
            child: Text(
              value,
              style: const TextStyle(
                color: AppColors.rakuAccent,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Text(label, style: TextStyle(color: p.text, fontSize: 15)),
        ],
      ),
    );
  }
}
