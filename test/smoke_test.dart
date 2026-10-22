import 'package:flutter/material.dart' hide Page;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:course_of_raku/models.dart';
import 'package:course_of_raku/screens/final_test_screen.dart';
import 'package:course_of_raku/progress.dart';
import 'package:course_of_raku/theme.dart';
import 'package:course_of_raku/screens/reader_screen.dart';
import 'package:course_of_raku/screens/quiz_player_screen.dart';
import 'package:course_of_raku/screens/exercise_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Course course;
  late Progress progress;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    course = await Course.load();
    progress = Progress();
    await progress.init();
  });

  Widget host(Widget child) =>
      MaterialApp(theme: buildLightTheme(), home: child);

  test('content loads with the expected scale', () {
    expect(course.parts.length, 8);
    expect(course.lessonCount, greaterThan(390));
    expect(course.quizCount, greaterThan(210));
    expect(course.exerciseCount, greaterThan(390));
    // bare fences are program output, and most Raku blocks run on their own
    final blocks = [
      for (final p in course.pages) ...p.blocks,
      for (final p in course.pages)
        for (final e in p.exercises) ...e.solution,
    ];
    expect(blocks.where((b) => b.type == 'output').length, greaterThan(300));
    expect(blocks.where((b) => b.isRaku && b.runnable).length, greaterThan(900));
    // spine is contiguous
    for (var i = 0; i < course.pages.length; i++) {
      expect(course.pages[i].order, i);
    }
  });

  testWidgets('reader renders a lesson with quizzes/exercises', (tester) async {
    final page = course.pages.firstWhere(
      (p) => p.quizzes.isNotEmpty && p.exercises.isNotEmpty,
      orElse: () => course.pages.firstWhere((p) => p.blocks.isNotEmpty),
    );
    await tester.pumpWidget(
      host(ReaderScreen(course: course, progress: progress, page: page)),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text(page.title), findsWidgets);
  });

  testWidgets('choice quiz: select and check', (tester) async {
    Quiz? choice;
    Page? owner;
    for (final p in course.pages) {
      for (final q in p.quizzes) {
        if (q.isChoice && q.options.isNotEmpty) {
          choice = q;
          owner = p;
          break;
        }
      }
      if (choice != null) break;
    }
    expect(choice, isNotNull);
    await tester.pumpWidget(
      host(
        QuizPlayerScreen(
          quiz: choice!,
          accent: AppColors.rakuAccent,
          progress: progress,
          quizId: '${owner!.id}::${choice.title}',
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Check answer'), findsOneWidget);
    // Option text renders as rich spans, so tap the first option's
    // radio/checkbox icon rather than matching its text.
    final optIcon = choice.multiSelect
        ? find.byIcon(Icons.check_box_outline_blank_rounded)
        : find.byIcon(Icons.radio_button_unchecked_rounded);
    await tester.tap(optIcon.first);
    await tester.pump();
    await tester.tap(find.text('Check answer'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    // After checking, a result string appears in the bottom bar.
    expect(find.text('Check answer'), findsNothing);
  });

  testWidgets('reveal quiz renders and toggles answers', (tester) async {
    Quiz? reveal;
    for (final p in course.pages) {
      for (final q in p.quizzes) {
        if (!q.isChoice && q.rows.isNotEmpty) {
          reveal = q;
          break;
        }
      }
      if (reveal != null) break;
    }
    expect(reveal, isNotNull);
    await tester.pumpWidget(
      host(
        QuizPlayerScreen(
          quiz: reveal!,
          accent: AppColors.rakuAccent,
          progress: progress,
          quizId: 'x::${reveal.title}',
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Show answers'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('exercise reveals its solution', (tester) async {
    Exercise? ex;
    for (final p in course.pages) {
      for (final e in p.exercises) {
        if (e.hasSolution) {
          ex = e;
          break;
        }
      }
      if (ex != null) break;
    }
    expect(ex, isNotNull);
    await tester.pumpWidget(
      host(ExerciseScreen(exercise: ex!, accent: AppColors.rakuAccent)),
    );
    await tester.pump();
    await tester.tap(find.text('Show solution'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  test('final test: bank loaded, graded like the course site', () {
    final page = course.byId('final-test')!;
    expect(page.finalTest.length, 100);
    expect(page.blocks.any((b) => b.value.contains('<')), isFalse);
    expect(course.badgeFor(course.parts.firstWhere((p) => p.slug == 'final-test')), '⚑');
    expect(course.badgeFor(course.parts.last), '6');

    const choice = FinalQuestion(part: 1, topic: '', type: 'choice', question: '', options: ['a', 'b'], answer: 1, explain: '');
    expect(choice.check(1), isTrue);
    expect(choice.check(0), isFalse);
    const multi = FinalQuestion(part: 1, topic: '', type: 'multi', question: '', options: ['a', 'b', 'c'], answer: [0, 2], explain: '');
    expect(multi.check([2, 0]), isTrue);
    expect(multi.check([0]), isFalse);
    const yes = FinalQuestion(part: 1, topic: '', type: 'boolean', question: '', answer: true, explain: '');
    expect(yes.check(true), isTrue);
    expect(yes.check(false), isFalse);
    const input = FinalQuestion(part: 1, topic: '', type: 'input', question: '', answer: ['#`(', '#`['], explain: '');
    expect(input.check('  #`[ '), isTrue);
    const word = FinalQuestion(part: 1, topic: '', type: 'input', question: '', answer: 'prompt', explain: '');
    expect(word.check(' Prompt'), isTrue);
    expect(word.check('get'), isFalse);
  });

  testWidgets('final test: answer a question and see the feedback', (tester) async {
    final page = course.byId('final-test')!;
    await tester.pumpWidget(host(FinalTestScreen(
      questions: page.finalTest,
      progress: progress,
      accent: AppColors.partColor(page.partIndex),
    )));
    await tester.pumpAndSettle();
    expect(find.text('Question 1 of 100'), findsOneWidget);
    // question 1 is a True/False one
    await tester.tap(find.text('True'));
    await tester.pump();
    await tester.tap(find.text('Check answer'));
    await tester.pumpAndSettle();
    expect(find.text('✓ Correct'), findsOneWidget);
    await tester.tap(find.text('Next question →'));
    await tester.pumpAndSettle();
    expect(find.text('Question 2 of 100'), findsOneWidget);
  });
}
