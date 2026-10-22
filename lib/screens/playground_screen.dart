import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:raku_engine/raku_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../run_session.dart';
import '../theme.dart';
import '../widgets/code_view.dart';
import '../widgets/run_output.dart';

const _welcome = '''# Welcome to the Raku playground!
# Edit this program and press Run.
# It runs right here on your device,
# no internet connection needed.

say 'Hello, World!';

my @squares = (1..10).map(* ** 2);
say "Squares: @squares[]";
say "Their sum is {@squares.sum}";
''';

/// An editor and an output pane, running Raku with the bundled engine.
///
/// [draftKey] names where the code is kept between visits (the main
/// playground, or one per exercise); with no key nothing is saved, which is
/// what "Edit" on a lesson snippet wants.
class PlaygroundScreen extends StatefulWidget {
  final String? initialCode;
  final String? draftKey;
  final String? title;

  const PlaygroundScreen({
    super.key,
    this.initialCode,
    this.draftKey,
    this.title,
  });

  /// The playground reached from the home screen.
  const PlaygroundScreen.main({super.key})
    : initialCode = null,
      draftKey = 'playground',
      title = null;

  @override
  State<PlaygroundScreen> createState() => _PlaygroundScreenState();
}

class _PlaygroundScreenState extends State<PlaygroundScreen> {
  final _code = RakuCodeController();
  final _input = TextEditingController();
  final _focus = FocusNode();
  final _session = RunSession();
  bool _showInput = false;
  bool _loaded = false;
  Timer? _saveTimer;
  SharedPreferences? _prefs;

  String get _draftPref => 'draft:${widget.draftKey}';

  @override
  void initState() {
    super.initState();
    _code.addListener(_scheduleSave);
    _load();
  }

  Future<void> _load() async {
    String? draft;
    if (widget.draftKey != null) {
      try {
        _prefs = await SharedPreferences.getInstance();
        draft = _prefs!.getString(_draftPref);
      } catch (_) {}
    }
    if (!mounted) return;
    _code.text =
        draft ??
        widget.initialCode ??
        (widget.draftKey == 'playground' ? _welcome : '');
    setState(() => _loaded = true);
  }

  void _scheduleSave() {
    if (!_loaded || widget.draftKey == null) return;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 600), _save);
  }

  void _save() => _prefs?.setString(_draftPref, _code.text);

  @override
  void dispose() {
    if (_saveTimer?.isActive ?? false) {
      _saveTimer!.cancel();
      _save();
    }
    _code.dispose();
    _input.dispose();
    _focus.dispose();
    _session.dispose();
    super.dispose();
  }

  void _run() {
    _focus.unfocus();
    // Input typed ahead in the "Program input" box is fed, then end of
    // input; with no such input the program asks as it runs, interactively.
    final preset = _showInput ? _input.text : '';
    _session.start(
      _code.text,
      input: preset,
      fileName: 'playground.raku',
      interactive: preset.isEmpty,
    );
  }

  void _insert(String s) {
    final sel = _code.selection;
    final text = _code.text;
    final start = sel.isValid ? sel.start : text.length;
    final end = sel.isValid ? sel.end : text.length;
    _code.value = TextEditingValue(
      text: text.replaceRange(start, end, s),
      selection: TextSelection.collapsed(offset: start + s.length),
    );
  }

  Future<void> _pickExample() async {
    final picked = await showModalBottomSheet<_Example>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _ExamplesSheet(),
    );
    if (picked == null || !mounted) return;
    final before = _code.text;
    _code.text = picked.code;
    _session.clear();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Loaded “${picked.title}”'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => _code.text = before,
          ),
        ),
      );
  }

  void _copy() {
    Clipboard.setData(ClipboardData(text: _code.text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Code copied'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final engine = RakuEngine.instance;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0 && _focus.hasFocus;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title ?? 'Playground', overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Examples',
            icon: const Icon(Icons.auto_stories_rounded),
            onPressed: _pickExample,
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              switch (v) {
                case 'input':
                  setState(() => _showInput = !_showInput);
                case 'copy':
                  _copy();
                case 'clear':
                  _session.clear();
                case 'reset':
                  _code.text = widget.initialCode ?? _welcome;
                  _session.clear();
              }
            },
            itemBuilder: (_) => [
              CheckedPopupMenuItem(
                value: 'input',
                checked: _showInput,
                child: const Text('Program input'),
              ),
              const PopupMenuItem(value: 'copy', child: Text('Copy code')),
              const PopupMenuItem(value: 'clear', child: Text('Clear output')),
              PopupMenuItem(
                value: 'reset',
                child: Text(
                  widget.initialCode != null ? 'Restore original' : 'Start over',
                ),
              ),
            ],
          ),
        ],
      ),
      body: !engine.isAvailable
          ? _Unavailable(reason: engine.loadError)
          : !_loaded
          ? const SizedBox.shrink()
          : SafeArea(
              top: false,
              child: LayoutBuilder(
                builder: (context, box) {
                  final wide = box.maxWidth >= 720 && box.maxWidth > box.maxHeight;
                  final editor = _EditorCard(
                    controller: _code,
                    focus: _focus,
                    onRun: _run,
                    onInsert: _insert,
                  );
                  final output = _OutputCard(session: _session, onRun: _run);
                  final input = _showInput
                      ? _InputField(
                          controller: _input,
                          onClose: () => setState(() => _showInput = false),
                        )
                      : null;
                  if (wide) {
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(flex: 3, child: editor),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [?input, Expanded(child: output)],
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(flex: 5, child: editor),
                        if (keyboard)
                          _SymbolBar(onInsert: _insert, onRun: _run)
                        else ...[
                          ?input,
                          const SizedBox(height: 10),
                          Expanded(flex: 4, child: output),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ),
    );
  }
}

/// A TextEditingController that colours its text as Raku.
class RakuCodeController extends TextEditingController {
  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    // While an input method is composing (e.g. a CJK keyboard), keep the
    // framework's underline for the composing region.
    if (withComposing && value.isComposingRangeValid) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }
    return TextSpan(style: style, children: highlightRaku(text));
  }
}

class _EditorCard extends StatelessWidget {
  final RakuCodeController controller;
  final FocusNode focus;
  final VoidCallback onRun;
  final ValueChanged<String> onInsert;

  const _EditorCard({
    required this.controller,
    required this.focus,
    required this.onRun,
    required this.onInsert,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.codeBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.codeBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: Focus(
        // A hardware keyboard on an iPad: Tab indents instead of leaving the
        // editor, and ⌘/Ctrl-Enter runs.
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;
          final k = HardwareKeyboard.instance;
          if (event.logicalKey == LogicalKeyboardKey.enter &&
              (k.isMetaPressed || k.isControlPressed)) {
            onRun();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.tab && !k.isShiftPressed) {
            onInsert('    ');
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: TextField(
          controller: controller,
          focusNode: focus,
          expands: true,
          maxLines: null,
          keyboardType: TextInputType.multiline,
          textAlignVertical: TextAlignVertical.top,
          autocorrect: false,
          enableSuggestions: false,
          smartQuotesType: SmartQuotesType.disabled,
          smartDashesType: SmartDashesType.disabled,
          textCapitalization: TextCapitalization.none,
          spellCheckConfiguration: const SpellCheckConfiguration.disabled(),
          keyboardAppearance: Brightness.dark,
          cursorColor: AppColors.rakuAccent,
          style: CodeView.monoStyle.copyWith(
            color: AppColors.codeText,
            fontSize: 14,
          ),
          decoration: const InputDecoration(
            border: InputBorder.none,
            contentPadding: EdgeInsets.fromLTRB(14, 12, 14, 12),
            isCollapsed: false,
          ),
        ),
      ),
    );
  }
}

class _OutputCard extends StatelessWidget {
  final RunSession session;
  final VoidCallback onRun;
  const _OutputCard({required this.session, required this.onRun});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.codeBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.codeBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 8, 0),
            child: Row(
              children: [
                const Icon(
                  Icons.subdirectory_arrow_right_rounded,
                  size: 13,
                  color: AppColors.codeDim,
                ),
                const SizedBox(width: 5),
                const Text(
                  'OUTPUT',
                  style: TextStyle(
                    color: AppColors.codeDim,
                    fontSize: 10,
                    letterSpacing: 1.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                AnimatedBuilder(
                  animation: session,
                  builder: (_, _) => FilledButton.icon(
                    onPressed: session.running ? session.stop : onRun,
                    style: FilledButton.styleFrom(
                      backgroundColor: session.running
                          ? AppColors.codeBorder
                          : AppColors.rakuAccent,
                      foregroundColor: Colors.white,
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: Icon(
                      session.running
                          ? Icons.stop_rounded
                          : Icons.play_arrow_rounded,
                      size: 20,
                    ),
                    label: Text(session.running ? 'Stop' : 'Run'),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: RunOutputView(
              session: session,
              fill: true,
              placeholder: 'Press Run to see what your program prints.',
            ),
          ),
        ],
      ),
    );
  }
}

class _InputField extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onClose;
  const _InputField({required this.controller, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: TextField(
        controller: controller,
        minLines: 1,
        maxLines: 4,
        autocorrect: false,
        enableSuggestions: false,
        smartQuotesType: SmartQuotesType.disabled,
        smartDashesType: SmartDashesType.disabled,
        style: TextStyle(
          fontFamily: kMonoFont,
          fontFamilyFallback: kMonoFallback,
          fontSize: 13.5,
          color: p.text,
        ),
        decoration: InputDecoration(
          isDense: true,
          labelText: 'Program input',
          helperText:
              'Fed to get, lines and prompt, then end of input. Leave it '
              'empty to type input while the program runs.',
          helperMaxLines: 2,
          border: const OutlineInputBorder(),
          suffixIcon: IconButton(
            tooltip: 'Hide input',
            icon: const Icon(Icons.close_rounded, size: 18),
            onPressed: onClose,
          ),
        ),
      ),
    );
  }
}

/// The characters Raku needs most and a phone keyboard hides deepest.
class _SymbolBar extends StatelessWidget {
  final ValueChanged<String> onInsert;
  final VoidCallback onRun;
  const _SymbolBar({required this.onInsert, required this.onRun});

  static const _keys = [
    ('⇥', '    '),
    (r'$', r'$'),
    ('@', '@'),
    ('%', '%'),
    ('&', '&'),
    ('{', '{'),
    ('}', '}'),
    ('(', '('),
    (')', ')'),
    ('[', '['),
    (']', ']'),
    ('<', '<'),
    ('>', '>'),
    (';', ';'),
    (':', ':'),
    ('"', '"'),
    ("'", "'"),
    ('=', '='),
    ('~', '~'),
    ('.', '.'),
    ('->', '-> '),
    ('=>', ' => '),
    ('#', '#'),
    ('|', '|'),
    ('*', '*'),
    ('^', '^'),
    ('!', '!'),
    ('?', '?'),
    (r'\', r'\'),
    ('«', '«'),
    ('»', '»'),
  ];

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      height: 44,
      margin: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Expanded(
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final (label, text) in _keys)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Material(
                      color: p.surface2,
                      borderRadius: BorderRadius.circular(8),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => onInsert(text),
                        child: Container(
                          constraints: const BoxConstraints(minWidth: 38),
                          alignment: Alignment.center,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Text(
                            label,
                            style: TextStyle(
                              fontFamily: kMonoFont,
                              fontFamilyFallback: kMonoFallback,
                              fontSize: 16,
                              color: p.text,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          FilledButton(
            onPressed: onRun,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.rakuAccent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            child: const Icon(Icons.play_arrow_rounded),
          ),
        ],
      ),
    );
  }
}

class _Unavailable extends StatelessWidget {
  final String? reason;
  const _Unavailable({this.reason});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.memory_rounded, size: 40, color: p.textDim),
            const SizedBox(height: 12),
            Text(
              'The Raku engine is not available on this device yet.',
              textAlign: TextAlign.center,
              style: TextStyle(color: p.text, fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }
}

class _Example {
  final String name;
  final String category;
  final String title;
  final String focus;
  final String code;

  const _Example(this.name, this.category, this.title, this.focus, this.code);

  factory _Example.fromJson(Map<String, dynamic> j) => _Example(
    j['name'] as String,
    j['category'] as String,
    j['title'] as String,
    j['focus'] as String,
    j['code'] as String,
  );
}

Future<List<_Example>>? _examples;

Future<List<_Example>> _loadExamples() => _examples ??= rootBundle
    .loadString('assets/data/examples.json')
    .then(
      (raw) => (jsonDecode(raw) as List)
          .map((e) => _Example.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

class _ExamplesSheet extends StatelessWidget {
  const _ExamplesSheet();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (context, scroll) => FutureBuilder<List<_Example>>(
        future: _loadExamples(),
        builder: (context, snap) {
          final list = snap.data;
          if (list == null) return const SizedBox(height: 200);
          final rows = <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Text(
                'Examples',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: p.text,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                'Programs that ship with the Raku++ engine. Pick one to load it '
                'into the editor.',
                style: TextStyle(color: p.textDim, fontSize: 13.5),
              ),
            ),
          ];
          String? category;
          for (final e in list) {
            if (e.category != category) {
              category = e.category;
              rows.add(
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
                  child: Text(
                    category.toUpperCase(),
                    style: const TextStyle(
                      color: AppColors.rakuAccent,
                      fontSize: 11.5,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              );
            }
            rows.add(
              ListTile(
                title: Text(e.title),
                subtitle: Text(e.focus),
                trailing: Text(
                  '${e.name}.raku',
                  style: TextStyle(
                    color: p.textDim,
                    fontSize: 11.5,
                    fontFamily: kMonoFont,
                    fontFamilyFallback: kMonoFallback,
                  ),
                ),
                onTap: () => Navigator.pop(context, e),
              ),
            );
          }
          rows.add(const SizedBox(height: 24));
          return ListView(controller: scroll, children: rows);
        },
      ),
    );
  }
}
