import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'models.dart';
import 'progress.dart';
import 'screens/home_screen.dart';
import 'theme.dart';
import 'theme_controller.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // In a release build a widget that throws while building is drawn as a
  // plain grey box — on a whole screen, that is a blank screen with no clue.
  // Draw the error instead.
  ErrorWidget.builder = (details) => _ErrorPanel(details.exceptionAsString());

  // An error nobody awaited (a failed link launch, a preference write) is
  // logged, not allowed to take the app down or replace it.
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('Unhandled: $error\n$stack');
    return true;
  };

  runApp(const RakuCourseApp());
}

class RakuCourseApp extends StatefulWidget {
  const RakuCourseApp({super.key});

  @override
  State<RakuCourseApp> createState() => _RakuCourseAppState();
}

class _RakuCourseAppState extends State<RakuCourseApp> {
  final _progress = Progress();
  final _theme = ThemeController();
  late Future<Course> _future = _bootstrap();

  Future<Course> _bootstrap() async {
    // The course is everything; saved progress and the theme choice only
    // decorate it. Load them side by side, and never let preferences that
    // are slow or broken hold the course back.
    final course = Course.load();
    await Future.wait([
      _progress.init(),
      _theme.init(),
    ]).timeout(const Duration(seconds: 3)).catchError((Object e) {
      debugPrint('Preferences unavailable: $e');
      return <void>[];
    });
    return course;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _theme,
      builder: (context, _) => MaterialApp(
        title: 'Learn Raku',
        debugShowCheckedModeBanner: false,
        theme: buildLightTheme(),
        darkTheme: buildDarkTheme(),
        themeMode: _theme.mode,
        home: FutureBuilder<Course>(
          future: _future,
          builder: (context, snap) {
            if (snap.hasError) {
              return _LoadFailed(
                message: '${snap.error}',
                onRetry: () => setState(() => _future = _bootstrap()),
              );
            }
            if (!snap.hasData) return const _Loading();
            return HomeScreen(
              course: snap.data!,
              progress: _progress,
              theme: _theme,
            );
          },
        ),
      ),
    );
  }
}

/// Shown for the moment the course takes to load: the app's name, never an
/// empty screen.
class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🦋', style: TextStyle(fontSize: 56)),
            const SizedBox(height: 14),
            Text(
              'Learn Raku',
              style: TextStyle(
                color: p.text,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 24),
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                color: AppColors.rakuAccent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadFailed extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _LoadFailed({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'The course could not be loaded.',
                textAlign: TextAlign.center,
                style: TextStyle(color: p.text, fontSize: 17),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(color: p.textDim, fontSize: 13),
              ),
              const SizedBox(height: 20),
              FilledButton(onPressed: onRetry, child: const Text('Try again')),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  final String message;
  const _ErrorPanel(this.message);

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF18161F),
      padding: const EdgeInsets.all(16),
      alignment: Alignment.center,
      child: Text(
        'Something went wrong showing this part of the app.\n\n$message',
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
        style: const TextStyle(color: Color(0xFFECECF1), fontSize: 13),
      ),
    );
  }
}
