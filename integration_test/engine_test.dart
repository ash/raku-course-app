// The Raku++ engine inside the app, exercised on a simulator or device:
//
//   flutter test integration_test/engine_test.dart -d <device>
//
// Everything here goes through the same RakuEngine the Run buttons use.
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:raku_engine/raku_engine.dart';

Future<(String out, String err, RakuResult r)> run_(
  String code, {
  String input = '',
  Duration? stopAfter,
  Duration? timeout,
}) async {
  final out = StringBuffer(), err = StringBuffer();
  final run = RakuEngine.instance.run(code, input: input, timeout: timeout);
  run.output.listen((o) => (o.isError ? err : out).write(o.text));
  if (stopAfter != null) Future.delayed(stopAfter, run.stop);
  final r = await run.done.timeout(const Duration(seconds: 30));
  // let the stream deliver its last event
  await Future<void>.delayed(Duration.zero);
  return (out.toString(), err.toString(), r);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final engine = RakuEngine.instance;

  test('engine loads', () {
    expect(engine.isAvailable, isTrue, reason: engine.loadError);
    expect(engine.version, startsWith('5.'));
  });

  test('runs a program', () async {
    final (out, err, r) = await run_(r'say (1..10).grep(*.is-prime).sum');
    expect(out, '17\n');
    expect(err, '');
    expect(r.exitCode, 0);
  });

  test('a fresh interpreter per run', () async {
    expect((await run_(r'class Point { has $.x }; say Point.new(x => 1).x')).$1, '1\n');
    expect((await run_(r'class Point { has $.y }; say Point.new(y => 2).y')).$1, '2\n');
  });

  test('compile errors are reported, exit 1', () async {
    final (out, err, r) = await run_(r'say $undeclared;');
    expect(r.exitCode, 1);
    expect(err, contains('undeclared'));
  });

  test('runtime errors and die', () async {
    final (_, err, r) = await run_(r'die "boom"');
    expect(r.exitCode, 1);
    expect(err, contains('boom'));
  });

  test('exit code from exit()', () async {
    expect((await run_(r'exit 7')).$3.exitCode, 7);
  });

  test('stdin feeds get/lines, then EOF', () async {
    final (out, _, _) = await run_(
      r'say "Hi, {get}!"; say lines().elems',
      input: 'Anna\nb\nc\n',
    );
    expect(out, 'Hi, Anna!\n2\n');
    expect((await run_(r'say get // "eof"')).$1, 'eof\n');
  });

  test('note goes to stderr, in order', () async {
    final (out, err, _) = await run_(r'say 1; note 2; say 3');
    expect(out, '1\n3\n');
    expect(err, '2\n');
  });

  test('Unicode output survives the byte stream', () async {
    final (out, _, _) = await run_(r'say "Ŗāķū — 🦋 «»"; say "é".chars');
    expect(out, 'Ŗāķū — 🦋 «»\n1\n');
  });

  test('Stop ends an infinite loop with exit 130', () async {
    final (_, err, r) = await run_(
      r'loop { }',
      stopAfter: const Duration(milliseconds: 300),
    );
    expect(r.stopped, isTrue);
    expect(err, contains('Interrupted'));
  });

  test('Stop ends an Int loop running as a native kernel', () async {
    final (_, _, r) = await run_(
      r'my $i = 0; while True { $i++ }',
      stopAfter: const Duration(milliseconds: 300),
    );
    expect(r.stopped, isTrue);
  });

  test('try cannot swallow a Stop', () async {
    final (_, _, r) = await run_(
      r'loop { try { my $x = 1 + 1 } }',
      stopAfter: const Duration(milliseconds: 300),
    );
    expect(r.stopped, isTrue);
  });

  test('timeout stops a run', () async {
    final (_, _, r) = await run_(
      r'loop { }',
      timeout: const Duration(milliseconds: 300),
    );
    expect(r.stopped, isTrue);
  });

  test('runaway output is capped and stopped', () async {
    final (out, err, r) = await run_(r'loop { say "x" x 50 }');
    expect(out.length, lessThanOrEqualTo(1 << 20));
    expect(err, contains('output stopped'));
    expect(r.exitCode, isNot(0));
  });

  test('a new run replaces a running one', () async {
    final first = engine.run(r'loop { }');
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final (out, _, r) = await run_(r'say "second"');
    expect((await first.done).stopped, isTrue);
    expect(out, 'second\n');
    expect(r.exitCode, 0);
  });

  test('the engine is usable after a stop', () async {
    expect((await run_(r'say 6 * 7')).$1, '42\n');
  });

  test('deep recursion works on the big-stack thread', () async {
    final (out, err, r) = await run_(
      r'sub f($n) { $n == 0 ?? 0 !! 1 + f($n - 1) }; say f(5000)',
    );
    expect(err, '');
    expect(out, '5000\n');
    expect(r.exitCode, 0);
  });

  test('runaway recursion is an error, not a crash', () async {
    final (_, err, r) = await run_(r'sub f { f() }; f()');
    expect(r.exitCode, isNot(0));
    expect(err, isNotEmpty);
  });

  test('threads: start/await and hyper', () async {
    final (out, _, r) = await run_(
      r'say await (^4).map: -> $i { start { $i * 10 } }; '
      r'say (1..1000).hyper.map(* ** 2).sum',
    );
    expect(out, '(0 10 20 30)\n333833500\n');
    expect(r.exitCode, 0);
  });

  test('file IO in the scratch directory', () async {
    final (out, _, r) = await run_(
      r"'note.txt'.IO.spurt('saved'); say 'note.txt'.IO.slurp; unlink 'note.txt'",
    );
    expect(out, 'saved\n');
    expect(r.exitCode, 0);
  });

  test('grammars', () async {
    final (out, _, _) = await run_(
      r'grammar G { token TOP { <num>+ % "," }; token num { \d+ } }; '
      r'say G.parse("1,22,333")<num>.map(+*).sum',
    );
    expect(out, '356\n');
  });

  test('highlighting comes from the engine and is lossless', () {
    const src = r'my @a = 1, 2; say "sum: {@a.sum}"; # done\n';
    final tokens = engine.highlight(src)!;
    expect(tokens.map((t) => t.text).join(), src);
    expect(
      tokens.firstWhere((t) => t.text == 'my').kind,
      RakuTokenKind.keyword,
    );
    expect(
      tokens.any((t) => t.kind == RakuTokenKind.comment && t.text.contains('done')),
      isTrue,
    );
  });

  Future<void> waitFor(RakuRun run) async {
    for (var i = 0; i < 100 && !run.waiting.value; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    expect(run.waiting.value, isTrue, reason: 'program should be waiting for input');
  }

  test('interactive: prompt waits, then reads what is sent', () async {
    final out = StringBuffer();
    final run = engine.run(
      r'my $name = prompt "Name: "; say "Hi, $name!"',
      interactive: true,
      timeout: const Duration(seconds: 2),
    );
    run.output.listen((o) => out.write(o.text));
    await waitFor(run);
    expect(out.toString(), 'Name: ');
    // waiting does not count against the time limit
    await Future<void>.delayed(const Duration(seconds: 3));
    expect(run.isFinished, isFalse);
    run.sendInput('Anna');
    final r = await run.done.timeout(const Duration(seconds: 10));
    await Future<void>.delayed(Duration.zero);
    expect(r.exitCode, 0);
    expect(out.toString(), 'Name: Hi, Anna!\n');
  });

  test('interactive: lines() reads until end of input', () async {
    final out = StringBuffer();
    final run = engine.run(r'say .uc for lines(); say "done"', interactive: true);
    run.output.listen((o) => out.write(o.text));
    await waitFor(run);
    run.sendInput('one');
    run.sendInput('two');
    await Future<void>.delayed(const Duration(milliseconds: 200));
    run.endInput();
    final r = await run.done.timeout(const Duration(seconds: 10));
    await Future<void>.delayed(Duration.zero);
    expect(out.toString(), 'ONE\nTWO\ndone\n');
    expect(r.exitCode, 0);
  });

  test('interactive: Stop while waiting for input', () async {
    final run = engine.run(r'loop { my $x = get; last unless $x.defined; say $x }', interactive: true);
    await waitFor(run);
    run.stop();
    final r = await run.done.timeout(const Duration(seconds: 10));
    expect(r.stopped, isTrue);
    expect((await run_('say "still fine"')).$1, 'still fine\n');
  });
}
