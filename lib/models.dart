import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// One block inside a lesson / quiz prompt / exercise body.
///
/// type: 'p' | 'h' | 'code' | 'codeOutput' | 'output' | 'ul' | 'ol' | 'tip'
class Block {
  final String type;
  final String value;
  final String? lang; // code blocks
  /// A Raku block that runs on its own (checked by tool/sync.raku), so the
  /// reader can offer a Run button for it.
  final bool runnable;
  final int? level; // headings (2..4)
  final List<String> items; // ul / ol

  const Block({
    required this.type,
    this.value = '',
    this.lang,
    this.level,
    this.items = const [],
    this.runnable = false,
  });

  bool get isRaku => type == 'code' && (lang == null || lang == 'raku');

  factory Block.fromJson(Map<String, dynamic> j) => Block(
    type: j['t'] as String,
    value: (j['v'] ?? '') as String,
    lang: j['lang'] as String?,
    level: j['level'] as int?,
    items: (j['items'] as List?)?.cast<String>() ?? const [],
    runnable: (j['run'] ?? false) as bool,
  );
}

List<Block> _blocks(dynamic list) =>
    (list as List? ?? const []).map((b) => Block.fromJson(b)).toList();

/// One answer in a multiple-choice ('choice') quiz.
class QuizOption {
  final String text;
  final bool correct;
  final String? why;

  const QuizOption({required this.text, required this.correct, this.why});

  factory QuizOption.fromJson(Map<String, dynamic> j) => QuizOption(
    text: j['text'] as String,
    correct: (j['ok'] ?? false) as bool,
    why: j['why'] as String?,
  );
}

/// One row in a 'reveal' quiz (fill-in / code-completion).
class QuizRow {
  final String question;
  final String answer;
  final String? why;

  const QuizRow({required this.question, required this.answer, this.why});

  factory QuizRow.fromJson(Map<String, dynamic> j) => QuizRow(
    question: (j['q'] ?? '') as String,
    answer: (j['a'] ?? '') as String,
    why: j['why'] as String?,
  );
}

/// A quiz attached to a lesson. Two kinds:
///  * 'choice' — interactive multiple choice ([options])
///  * 'reveal' — show the question, then reveal the answer ([rows])
class Quiz {
  final String kind;
  final String title;
  final List<Block> prompt;
  final List<QuizOption> options;
  final List<QuizRow> rows;
  final bool multiSelect;

  const Quiz({
    required this.kind,
    required this.title,
    required this.prompt,
    required this.options,
    required this.rows,
    required this.multiSelect,
  });

  bool get isChoice => kind == 'choice';

  factory Quiz.fromJson(Map<String, dynamic> j) => Quiz(
    kind: (j['kind'] ?? 'choice') as String,
    title: (j['title'] ?? 'Quiz') as String,
    prompt: _blocks(j['prompt']),
    options: (j['options'] as List? ?? const [])
        .map((o) => QuizOption.fromJson(o))
        .toList(),
    rows: (j['rows'] as List? ?? const [])
        .map((r) => QuizRow.fromJson(r))
        .toList(),
    multiSelect: (j['multi'] ?? false) as bool,
  );
}

class Exercise {
  final String id;
  final String title;
  final List<Block> prompt;
  final List<Block> solution;

  const Exercise({
    required this.id,
    required this.title,
    required this.prompt,
    required this.solution,
  });

  bool get hasSolution => solution.isNotEmpty;

  factory Exercise.fromJson(Map<String, dynamic> j) => Exercise(
    id: j['id'] as String,
    title: j['title'] as String,
    prompt: _blocks(j['prompt']),
    solution: _blocks(j['solution']),
  );
}

/// One question of the Final Test. [type] is 'choice' (answer: an option
/// index), 'multi' (a list of indices), 'boolean' (true/false) or 'input'
/// (accepted strings, compared case-insensitively with whitespace collapsed).
class FinalQuestion {
  final int part;
  final String topic;
  final String type;
  final String question;
  final String? code;
  final List<String> options;
  final Object answer;
  final String explain;

  const FinalQuestion({
    required this.part,
    required this.topic,
    required this.type,
    required this.question,
    this.code,
    this.options = const [],
    required this.answer,
    required this.explain,
  });

  factory FinalQuestion.fromJson(Map<String, dynamic> j) => FinalQuestion(
    part: (j['part'] ?? 0) as int,
    topic: (j['topic'] ?? '') as String,
    type: (j['type'] ?? 'choice') as String,
    question: (j['q'] ?? '') as String,
    code: j['code'] as String?,
    options: (j['options'] as List?)?.cast<String>() ?? const [],
    answer: j['answer'] as Object,
    explain: (j['explain'] ?? '') as String,
  );

  static String _norm(Object? s) =>
      '${s ?? ''}'.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

  /// Whether [chosen] is right — the same rules as the course's web test.
  bool check(Object? chosen) {
    switch (type) {
      case 'input':
        final accepts = answer is List ? answer as List : [answer];
        return accepts.any((a) => _norm(a) == _norm(chosen));
      case 'multi':
        if (chosen is! List) return false;
        final want = [...(answer as List).cast<int>()]..sort();
        final got = [...chosen.cast<int>()]..sort();
        return want.join(',') == got.join(',');
      default:
        return chosen == answer;
    }
  }

  /// The correct answer, as text for feedback and review.
  String get answerText => describe(answer);

  String describe(Object? value) {
    switch (type) {
      case 'boolean':
        return value == true ? 'True' : 'False';
      case 'choice':
        return value is int && value < options.length ? options[value] : '';
      case 'multi':
        return value is List
            ? value.cast<int>().map((i) => options[i]).join(', ')
            : '';
      default:
        return value is List ? value.join(' / ') : '${value ?? ''}';
    }
  }
}

/// A single readable page in the linear "spine" of the course.
class Page {
  final String id;
  final String title;
  final String? longTitle;
  final int partIndex;
  final int order;
  final List<Block> blocks;
  final List<Quiz> quizzes;
  final List<Exercise> exercises;
  final String searchText;

  /// The Final Test's questions, on the one page that carries them.
  final List<FinalQuestion> finalTest;

  const Page({
    required this.id,
    required this.title,
    this.longTitle,
    required this.partIndex,
    required this.order,
    required this.blocks,
    required this.quizzes,
    required this.exercises,
    required this.searchText,
    this.finalTest = const [],
  });

  factory Page.fromJson(Map<String, dynamic> j) => Page(
    id: j['id'] as String,
    title: j['title'] as String,
    longTitle: j['longTitle'] as String?,
    partIndex: j['part'] as int,
    order: j['order'] as int,
    blocks: _blocks(j['blocks']),
    quizzes: (j['quizzes'] as List? ?? const [])
        .map((q) => Quiz.fromJson(q))
        .toList(),
    exercises: (j['exercises'] as List? ?? const [])
        .map((e) => Exercise.fromJson(e))
        .toList(),
    searchText: (j['searchText'] ?? '') as String,
    finalTest: (j['finalTest'] as List? ?? const [])
        .map((q) => FinalQuestion.fromJson(q as Map<String, dynamic>))
        .toList(),
  );
}

/// A node in a part's navigation tree.
/// A node may carry a [pageId] (a readable lesson), and/or [children].
class TocNode {
  final String title;
  final String? pageId;
  final int quizzes;
  final int exercises;
  final List<TocNode> children;

  const TocNode({
    required this.title,
    this.pageId,
    this.quizzes = 0,
    this.exercises = 0,
    this.children = const [],
  });

  bool get hasChildren => children.isNotEmpty;

  factory TocNode.fromJson(Map<String, dynamic> j) => TocNode(
    title: j['title'] as String,
    pageId: j['page'] as String?,
    quizzes: (j['quizzes'] ?? 0) as int,
    exercises: (j['exercises'] ?? 0) as int,
    children: (j['children'] as List? ?? const [])
        .map((c) => TocNode.fromJson(c))
        .toList(),
  );
}

class Part {
  final int index;
  final String title;
  final String? longTitle;
  final String slug;
  final String description;
  final List<TocNode> toc;
  final List<String> pageIds; // all spine pages in this part, in order

  const Part({
    required this.index,
    required this.title,
    this.longTitle,
    required this.slug,
    required this.description,
    required this.toc,
    required this.pageIds,
  });
}

class Course {
  final String appTitle;
  final String tagline;
  final String credit;
  final List<Part> parts;
  final List<Page> pages; // flat, sorted by order — the spine
  final Map<String, int> pageIndex; // id -> index into pages

  Course({
    required this.appTitle,
    required this.tagline,
    required this.credit,
    required this.parts,
    required this.pages,
    required this.pageIndex,
  });

  Page? byId(String id) {
    final i = pageIndex[id];
    return i == null ? null : pages[i];
  }

  Page? next(Page p) => p.order + 1 < pages.length ? pages[p.order + 1] : null;
  Page? prev(Page p) => p.order > 0 ? pages[p.order - 1] : null;

  /// The navigation node for [page] within its part, or null. Used to list a
  /// section's sub-topics on its landing page.
  TocNode? nodeFor(Page page) {
    TocNode? search(List<TocNode> nodes) {
      for (final n in nodes) {
        if (n.pageId == page.id) return n;
        final found = search(n.children);
        if (found != null) return found;
      }
      return null;
    }

    return search(parts[page.partIndex].toc);
  }

  /// What a part's card shows: ★ for the introduction, a flag for the Final
  /// Test, and otherwise the part's number as the course site counts it —
  /// the Final Test is not a numbered part, so the Addendum is Part 6.
  String badgeFor(Part part) {
    if (part.index == 0) return '★';
    if (part.slug == 'final-test') return '⚑';
    final skipped = parts
        .where((p) => p.slug == 'final-test' && p.index < part.index)
        .length;
    return '${part.index - skipped}';
  }

  int get lessonCount => pages.length;
  int get quizCount =>
      pages.fold(0, (n, p) => n + p.quizzes.length);
  int get exerciseCount =>
      pages.fold(0, (n, p) => n + p.exercises.length);

  /// Parse the (already-decoded) JSON map into a Course. Runs in an isolate.
  static Course _fromMap(Map<String, dynamic> j) {
    final pages = (j['pages'] as List)
        .map((p) => Page.fromJson(p as Map<String, dynamic>))
        .toList()
      ..sort((a, b) => a.order.compareTo(b.order));

    final pageIndex = <String, int>{
      for (var i = 0; i < pages.length; i++) pages[i].id: i,
    };

    // Group page ids by part, preserving spine order.
    final byPart = <int, List<String>>{};
    for (final p in pages) {
      (byPart[p.partIndex] ??= []).add(p.id);
    }

    final parts = (j['parts'] as List).map((pp) {
      final m = pp as Map<String, dynamic>;
      final i = m['i'] as int;
      return Part(
        index: i,
        title: m['title'] as String,
        longTitle: m['longTitle'] as String?,
        slug: m['slug'] as String,
        description: (m['description'] ?? '') as String,
        toc: (m['toc'] as List? ?? const [])
            .map((n) => TocNode.fromJson(n as Map<String, dynamic>))
            .toList(),
        pageIds: byPart[i] ?? const [],
      );
    }).toList();

    return Course(
      appTitle: j['appTitle'] as String,
      tagline: (j['tagline'] ?? '') as String,
      credit: (j['credit'] ?? '') as String,
      parts: parts,
      pages: pages,
      pageIndex: pageIndex,
    );
  }

  static Course _parse(String raw) =>
      _fromMap(jsonDecode(raw) as Map<String, dynamic>);

  static Future<Course> load() async {
    final raw = await rootBundle.loadString('assets/data/content.json');
    // Parse off the UI isolate — the payload is ~1.4 MB — so the first frame
    // stays smooth.
    return compute(_parse, raw);
  }
}
