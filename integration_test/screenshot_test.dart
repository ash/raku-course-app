// App Store screenshot harness.
//
// Each test pumps a real app screen (populated with the bundled course) at the
// simulator's native resolution and asks the driver to save a PNG. It does NOT
// tap through live navigation — screens are pumped directly so the run is
// deterministic across devices.
//
// Run once per device size, e.g.:
//   flutter drive --driver=test_driver/screenshot_driver.dart \
//     --target=integration_test/screenshot_test.dart \
//     -d "iPhone 17 Pro Max" --dart-define=SS_DEVICE=iphone-6.9
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:course_of_raku/models.dart';
import 'package:course_of_raku/progress.dart';
import 'package:course_of_raku/theme.dart';
import 'package:course_of_raku/theme_controller.dart';
import 'package:course_of_raku/screens/home_screen.dart';
import 'package:course_of_raku/screens/part_browser_screen.dart';
import 'package:course_of_raku/screens/reader_screen.dart';
import 'package:course_of_raku/screens/quiz_player_screen.dart';
import 'package:course_of_raku/screens/exercise_screen.dart';
import 'package:course_of_raku/screens/search_screen.dart';
import 'package:course_of_raku/screens/playground_screen.dart';
import 'package:course_of_raku/screens/final_test_screen.dart';

const _device = String.fromEnvironment('SS_DEVICE', defaultValue: 'iphone-6.9');

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // [settle] false is for a screen that never stops animating — a program
  // waiting for input shows a spinner — where pumpAndSettle would never return.
  Future<void> shoot(WidgetTester tester, String slug, {bool settle = true}) async {
    if (settle) await tester.pumpAndSettle();
    // On Android the surface must be converted to an image first; it's a no-op
    // on iOS.
    if (Platform.isAndroid) {
      await binding.convertFlutterSurfaceToImage();
      if (settle) {
        await tester.pumpAndSettle();
      } else {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }
    // In live (drive) mode the native captureScreenshot on iOS grabs the device
    // screen, which lags the framework by a frame or two. Pump a few frames and
    // wait real time so the pumped screen is actually presented before capture.
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await Future<void>.delayed(const Duration(milliseconds: 700));
    await tester.pump();
    await binding.takeScreenshot('$_device/$slug');
  }

  // Tap the first Run button and wait (in real time) for the program to end.
  Future<void> runFirst(WidgetTester tester) async {
    await tester.pumpAndSettle();
    await tester.tap(find.text('Run').first);
    for (var i = 0; i < 100; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (find.textContaining('exit 0').evaluate().isNotEmpty) break;
    }
    await tester.pumpAndSettle();
  }

  Widget app(Widget home, ThemeData theme) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme,
        home: home,
      );

  // A Progress with some completed lessons + a resume point, so the home
  // screen shows real stats and a "Continue" card.
  Future<Progress> seededProgress(Course course) async {
    final progress = Progress();
    final essentials = course.parts.length > 1 ? course.parts[1] : course.parts.first;
    for (final id in essentials.pageIds.take(9)) {
      await progress.setDone(id, true);
    }
    if (course.pages.length > 20) {
      await progress.setLastPage(course.pages[18].id);
    }
    return progress;
  }

  testWidgets('04 home (light)', (tester) async {
    final course = await Course.load();
    final progress = await seededProgress(course);
    final theme = ThemeController();
    await tester.pumpWidget(app(
      HomeScreen(course: course, progress: progress, theme: theme),
      buildLightTheme(),
    ));
    await shoot(tester, '04-home');
  });

  testWidgets('10 part browser', (tester) async {
    final course = await Course.load();
    final progress = await seededProgress(course);
    final part = course.parts.length > 1 ? course.parts[1] : course.parts.first;
    await tester.pumpWidget(app(
      PartBrowserScreen(course: course, part: part, progress: progress),
      buildLightTheme(),
    ));
    await shoot(tester, '10-part');
  });

  testWidgets('01 lesson, example run', (tester) async {
    final course = await Course.load();
    final progress = await seededProgress(course);
    final page = course.byId('essentials/the-main-function') ??
        course.pages.firstWhere(
          (p) => p.partIndex >= 1 && p.blocks.any((b) => b.runnable),
        );
    await tester.pumpWidget(app(
      ReaderScreen(course: course, progress: progress, page: page),
      buildLightTheme(),
    ));
    await runFirst(tester);
    // On a smaller phone the finished run's status line falls below the
    // screen: bring the whole output into view.
    await Scrollable.ensureVisible(
      tester.element(find.textContaining('exit 0').first),
      alignment: 0.9,
    );
    await tester.pumpAndSettle();
    await shoot(tester, '01-lesson-run');
  });

  testWidgets('03 playground', (tester) async {
    // A clean store, so the playground opens on its welcome program.
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(app(
      const PlaygroundScreen.main(),
      buildDarkTheme(),
    ));
    await runFirst(tester);
    await shoot(tester, '03-playground');
  });

  testWidgets('06 quiz (interactive)', (tester) async {
    final course = await Course.load();
    final progress = await seededProgress(course);
    final page = course.pages.firstWhere(
      (p) => p.quizzes.any((q) => q.isChoice),
      orElse: () => course.pages.firstWhere((p) => p.quizzes.isNotEmpty),
    );
    final quiz = page.quizzes.firstWhere(
      (q) => q.isChoice,
      orElse: () => page.quizzes.first,
    );
    await tester.pumpWidget(app(
      QuizPlayerScreen(
        quiz: quiz,
        accent: AppColors.partColor(page.partIndex),
        progress: progress,
        quizId: '${page.id}#quiz',
      ),
      buildLightTheme(),
    ));
    await shoot(tester, '06-quiz');
  });

  testWidgets('07 exercise (+ solution)', (tester) async {
    final course = await Course.load();
    final page = course.pages.firstWhere(
      (p) => p.exercises.any((e) => e.hasSolution),
      orElse: () => course.pages.firstWhere((p) => p.exercises.isNotEmpty),
    );
    final ex = page.exercises.firstWhere(
      (e) => e.hasSolution,
      orElse: () => page.exercises.first,
    );
    await tester.pumpWidget(app(
      ExerciseScreen(
        exercise: ex,
        accent: AppColors.partColor(page.partIndex),
      ),
      buildLightTheme(),
    ));
    await shoot(tester, '07-exercise');
  });

  testWidgets('09 search', (tester) async {
    final course = await Course.load();
    final progress = await seededProgress(course);
    await tester.pumpWidget(app(
      SearchScreen(course: course, progress: progress),
      buildLightTheme(),
    ));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'grammar');
    await tester.pumpAndSettle(const Duration(milliseconds: 600));
    await shoot(tester, '09-search');
  });

  testWidgets('08 home (dark)', (tester) async {
    final course = await Course.load();
    final progress = await seededProgress(course);
    final theme = ThemeController();
    await tester.pumpWidget(app(
      HomeScreen(course: course, progress: progress, theme: theme),
      buildDarkTheme(),
    ));
    await shoot(tester, '08-home-dark');
  });

  testWidgets('05 final test', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final course = await Course.load();
    final page = course.byId('final-test')!;
    // Resume just before a multiple-choice question with code — it makes the
    // better picture — with the questions before it answered correctly.
    final at = page.finalTest.indexWhere((q) => q.type == 'choice' && q.code != null);
    final answered = [
      for (final q in page.finalTest.take(at))
        q.answer is List && q.type == 'input' ? (q.answer as List).first : q.answer,
    ];
    SharedPreferences.setMockInitialValues({'final_test_answers': jsonEncode(answered)});
    final progress = Progress();
    await progress.init();
    await tester.pumpWidget(app(
      FinalTestScreen(
        questions: page.finalTest,
        progress: progress,
        accent: AppColors.partColor(page.partIndex),
      ),
      buildLightTheme(),
    ));
    await tester.pumpAndSettle();
    final q = page.finalTest[at];
    await tester.tap(find.byType(InkWell).at(q.answer as int));
    await tester.pump();
    await tester.tap(find.text('Check answer'));
    await tester.pumpAndSettle();
    await shoot(tester, '05-final-test');
  });

  testWidgets('02 interactive input', (tester) async {
    final course = await Course.load();
    final progress = await seededProgress(course);
    // A lesson whose program asks for a number: run it, and capture the moment
    // it waits, with the reader's answer typed into the input line.
    final page = course.byId('essentials/conditional-checks/elsif')!;
    final runnable = page.blocks.where((b) => b.isRaku && b.runnable).toList();
    final k = runnable.indexWhere((b) => b.value.contains('prompt'));
    await tester.pumpWidget(app(
      ReaderScreen(course: course, progress: progress, page: page),
      buildLightTheme(),
    ));
    await tester.pumpAndSettle();
    final run = find.text('Run').at(k);
    await tester.ensureVisible(run);
    await tester.pumpAndSettle();
    await tester.tap(run);
    // from here a spinner runs, so pump frames rather than settling
    for (var i = 0; i < 50; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (find.text('Waiting for input…').evaluate().isNotEmpty) break;
    }
    await tester.enterText(find.byType(TextField).last, '42');
    // Put the keyboard away (the answer stays in the field): a screenshot has
    // no keyboard in it, so on an iPad it left a blank band where it had been.
    FocusManager.instance.primaryFocus?.unfocus();
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    // Scroll so the input line sits near the bottom of the screen, with the
    // program and its question above it.
    await Scrollable.ensureVisible(
      tester.element(find.byType(TextField).last),
      alignment: 0.85,
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await shoot(tester, '02-input', settle: false);
  });
}
