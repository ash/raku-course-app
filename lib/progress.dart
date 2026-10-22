import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tracks completed pages, quiz scores, and the last page opened.
class Progress extends ChangeNotifier {
  static const _doneKey = 'done_pages';
  static const _scoresKey = 'quiz_scores';
  static const _lastKey = 'last_page';

  final Set<String> _done = {};
  final Map<String, _Score> _scores = {};
  String? _lastPage;
  SharedPreferences? _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _done
      ..clear()
      ..addAll(_prefs?.getStringList(_doneKey) ?? const []);
    _scores.clear();
    final rawScores = _prefs?.getString(_scoresKey);
    if (rawScores != null && rawScores.isNotEmpty) {
      final m = jsonDecode(rawScores) as Map<String, dynamic>;
      m.forEach((k, v) {
        _scores[k] = _Score(
          best: (v['best'] ?? 0) as int,
          total: (v['total'] ?? 0) as int,
        );
      });
    }
    _lastPage = _prefs?.getString(_lastKey);
    notifyListeners();
  }

  // ---- completion -----------------------------------------------------
  bool isDone(String id) => _done.contains(id);
  int get totalDone => _done.length;

  int doneCountFor(Iterable<String> ids) => ids.where(_done.contains).length;

  double fractionFor(List<String> ids) =>
      ids.isEmpty ? 0 : doneCountFor(ids) / ids.length;

  Future<void> toggle(String id) async {
    if (!_done.add(id)) _done.remove(id);
    await _prefs?.setStringList(_doneKey, _done.toList());
    notifyListeners();
  }

  Future<void> setDone(String id, bool done) async {
    final changed = done ? _done.add(id) : _done.remove(id);
    if (changed) {
      await _prefs?.setStringList(_doneKey, _done.toList());
      notifyListeners();
    }
  }

  // ---- quiz scores ----------------------------------------------------
  int? bestScore(String quizId) => _scores[quizId]?.best;
  int? totalFor(String quizId) => _scores[quizId]?.total;

  Future<void> recordQuiz(String quizId, int score, int total) async {
    final existing = _scores[quizId];
    if (existing == null || score > existing.best) {
      _scores[quizId] = _Score(best: score, total: total);
      await _persistScores();
      notifyListeners();
    }
  }

  Future<void> _persistScores() async {
    final m = {
      for (final e in _scores.entries)
        e.key: {'best': e.value.best, 'total': e.value.total},
    };
    await _prefs?.setString(_scoresKey, jsonEncode(m));
  }

  // ---- continue -------------------------------------------------------
  String? get lastPage => _lastPage;

  Future<void> setLastPage(String id) async {
    if (_lastPage == id) return;
    _lastPage = id;
    await _prefs?.setString(_lastKey, id);
    notifyListeners();
  }
}

class _Score {
  final int best;
  final int total;
  const _Score({required this.best, required this.total});
}
