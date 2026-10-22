import 'dart:async';
import 'package:flutter/material.dart' hide Page;
import '../models.dart';
import '../progress.dart';
import '../theme.dart';
import 'reader_screen.dart';

class SearchScreen extends StatefulWidget {
  final Course course;
  final Progress progress;

  const SearchScreen({
    super.key,
    required this.course,
    required this.progress,
  });

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  List<Page> _results = const [];
  String _query = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () {
      final q = value.trim().toLowerCase();
      if (q.length < 2) {
        setState(() {
          _query = q;
          _results = const [];
        });
        return;
      }
      // Bind the query to the start of a word ("dd" finds "… with dd", not
      // "embedded"). If the query starts with a non-word character (e.g. a
      // sigil like "$x"), fall back to a plain substring match.
      final firstIsWord = RegExp(r'[a-z0-9_]').hasMatch(q[0]);
      final re = firstIsWord ? RegExp(r'\b' + RegExp.escape(q)) : null;
      bool matches(String s) => re != null ? re.hasMatch(s) : s.contains(q);

      final hits = <Page>[];
      for (final page in widget.course.pages) {
        if (matches(page.searchText)) {
          hits.add(page);
          if (hits.length >= 40) break;
        }
      }
      // Title matches first.
      hits.sort((a, b) {
        final at = matches(a.title.toLowerCase()) ? 0 : 1;
        final bt = matches(b.title.toLowerCase()) ? 0 : 1;
        if (at != bt) return at - bt;
        return a.order.compareTo(b.order);
      });
      setState(() {
        _query = q;
        _results = hits;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          onChanged: _onChanged,
          style: TextStyle(color: p.text, fontSize: 17),
          decoration: InputDecoration(
            hintText: 'Search the course…',
            hintStyle: TextStyle(color: p.textDim),
            border: InputBorder.none,
          ),
        ),
        actions: [
          if (_controller.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear_rounded),
              onPressed: () {
                _controller.clear();
                _onChanged('');
              },
            ),
        ],
      ),
      body: _query.length < 2
          ? Center(
              child: Text(
                'Type to search lessons, quizzes and exercises.',
                style: TextStyle(color: p.textDim),
              ),
            )
          : _results.isEmpty
          ? Center(
              child: Text(
                'No matches for "$_query".',
                style: TextStyle(color: p.textDim),
              ),
            )
          : ListView.separated(
              itemCount: _results.length,
              separatorBuilder: (_, _) =>
                  Divider(height: 1, color: p.stroke),
              itemBuilder: (context, i) {
                final page = _results[i];
                final part = widget.course.parts[page.partIndex];
                final accent = AppColors.partColor(page.partIndex);
                return ListTile(
                  leading: Icon(Icons.article_outlined, color: accent),
                  title: Text(
                    page.title,
                    style: TextStyle(color: p.text, fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    part.title,
                    style: TextStyle(color: p.textDim, fontSize: 12.5),
                  ),
                  onTap: () =>
                      openReader(context, widget.course, widget.progress, page),
                );
              },
            ),
    );
  }
}
