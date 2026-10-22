# Course of Raku — mobile app

A Flutter app (iOS + Android) that presents the **Course of Raku** by Andrew
Shitov for offline reading: lessons, interactive quizzes, and exercises across
all of the course — and runs the code. On iOS and Android the app carries the
[Raku++](https://raku.online) engine, so course examples have Run buttons and
there is a Playground for writing programs (see [engine/README.md](engine/README.md)).

The course content itself lives in a **separate** repository
(`raku-course`) and is never modified by this app. Content is imported at
build time by a sync script and bundled as a single JSON asset, so the app is
fully offline with no backend.

## Architecture

```
raku-course/  ──(tool/sync.raku)──►  assets/data/content.json  ──►  bundled in the app
   (source)        build-time                (digested)              (offline)
```

* **`tool/sync.raku`** — the only place course markdown is parsed. It walks
  `raku-course/_data/toc/en.yaml` (English only), reads each lesson/quiz/
  exercise `index.md`, strips Liquid/HTML, and emits a pre-digested
  `content.json` (blocks, quizzes, exercises, a flat ordered "spine", and a
  precomputed search index). It also runs every Raku block once with
  `rakupp` and marks the ones that run on their own (`run: true`), which are
  the ones that get a Run button.
* **`tool/examples.raku`** — the Playground's example programs, taken from
  Raku++'s `examples/` at the engine's tag.
* **`packages/raku_engine`** — the engine as an FFI plugin; `lib/run_session.dart`,
  `widgets/raku_code_block.dart` and `screens/playground_screen.dart` use it.
* **`lib/models.dart`** — `Course` loads the JSON in a background isolate. The
  course is both a navigation **tree** (`Part → TocNode → …`) and a flat
  ordered **spine** (`pages`) used for prev/next, search, and progress.
* **`lib/screens/`** — Home, PartBrowser (drill-down tree), Reader
  (spine-aware), QuizPlayer (interactive choice + reveal), Exercise
  (prompt + reveal solution), Search, About.
* **`lib/progress.dart`** — completion, quiz scores, and "continue" via
  `shared_preferences` (no database).

## Re-syncing content when the course is updated

```sh
raku tool/sync.raku /path/to/raku-course > assets/data/content.json   # ~30 s
flutter pub get        # only if assets changed structurally
```

Then rebuild and ship an app update. The script prints a summary to STDERR:

```
Runnable Raku blocks: 1144 of 1331
Parts: 7  Lessons: 377  Quizzes: 209  Exercises: 395
```

Runs under Raku++ (`raku` → `rakupp`) or Rakudo, with the `YAMLish` module;
the run check needs `rakupp` on `PATH` (or `$RAKUPP`), and `--no-run-check`
skips it.

## Running

The engine binaries are not in the repository. Build them first from a
[Raku++](https://github.com/ash/rakupp) checkout (`RAKUPP_REPO`, default
`~/raku++`) — see [engine/README.md](engine/README.md):

```sh
engine/build-ios.sh               # → packages/raku_engine/ios/RakuEngine.xcframework
engine/build-android.sh           # → packages/raku_engine/android/src/main/jniLibs/
```

```sh
flutter pub get
flutter run                       # on a connected device / simulator
flutter test                      # widget smoke tests over the real content
flutter build apk                 # Android
flutter build ios                 # iOS (open ios/Runner.xcworkspace to sign)
```

## Credits

Course content © Andrew Shitov — <https://github.com/ash/raku-course>,
created with support from The Perl and Raku Foundation.
