import 'dart:convert';
import 'package:flutter/services.dart';
import '../models/reading_content_model.dart';

class ReadingService {
  static final ReadingService _instance = ReadingService._internal();
  factory ReadingService() => _instance;
  ReadingService._internal();

  /// 解析 reading 事件標題：reading-w{week}-d{day}
  List<int>? parseWeekDayFromTitle(String title) {
    final lower = title.toLowerCase().trim();
    final patterns = <RegExp>[
      RegExp(r'^reading[-_]?w(\d+)[-_]?d(\d+)$'),
      RegExp(r'^reading[-_]?(\d+)[-_]?(\d+)$'),
    ];
    for (final p in patterns) {
      final m = p.firstMatch(lower);
      if (m != null && m.groupCount >= 2) {
        final w = int.tryParse(m.group(1)!);
        final d = int.tryParse(m.group(2)!);
        if (w != null && d != null) return [w, d];
      }
    }
    return null;
  }

  /// 解析週測驗標題：reading-w{week}-test / reading_w{week}_test
  int? parseWeekFromTestTitle(String title) {
    final lower = title.toLowerCase().trim();
    final patterns = <RegExp>[
      RegExp(r'^reading[-_]?w(\d+)[-_]?test$'),
      RegExp(r'^reading[-_]?(\d+)[-_]?test$'),
    ];
    for (final p in patterns) {
      final m = p.firstMatch(lower);
      if (m != null && m.groupCount >= 1) {
        final w = int.tryParse(m.group(1)!);
        if (w != null) return w;
      }
    }
    return null;
  }

  /// 讀取每日文章（assets/dyn/w{week}_d{day}.json）
  Future<List<ReadingContent>> loadDailyArticles(int week, int day) async {
    try {
      final path = 'assets/dyn/w${week}_d${day}.json';
      final jsonString = await rootBundle.loadString(path);
      final Map<String, dynamic> data = json.decode(jsonString);
      final List<dynamic> articles = (data['articles'] as List?) ?? [];
      return articles
          .map<ReadingContent>((e) => ReadingContent.fromArticleJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      print('載入閱讀文章失敗: week=$week, day=$day, error=$e');
      return [];
    }
  }

  /// 讀取每日題目（assets/dyn/week{week}_summary_with_questions.json -> dayX）
  Future<Map<String, List<ReadingQuestion>>> loadDayQuestions(int week, int day) async {
    try {
      final path = 'assets/dyn/week${week}_summary_with_questions.json';
      final jsonString = await rootBundle.loadString(path);
      final Map<String, dynamic> data = json.decode(jsonString);
      final days = (data['days'] as Map<String, dynamic>?);
      if (days == null) return {};
      final key = 'day$day';
      final List<dynamic> items = (days[key] as List?) ?? [];
      final Map<String, List<ReadingQuestion>> out = {};
      for (final it in items) {
        final m = it as Map<String, dynamic>;
        final rid = m['rid']?.toString() ?? '';
        final List<dynamic> qList = (m['questions'] as List?) ?? [];
        out[rid] = qList.map((q) => ReadingQuestion.fromJson(q as Map<String, dynamic>)).toList();
      }
      return out;
    } catch (e) {
      print('載入閱讀題目失敗: week=$week, day=$day, error=$e');
      return {};
    }
  }

  /// 讀取整週題庫（彙整所有 day 的 questions）
  Future<List<ReadingQuestion>> loadWeeklyQuestions(int week) async {
    try {
      final path = 'assets/dyn/week${week}_summary_with_questions.json';
      final jsonString = await rootBundle.loadString(path);
      final Map<String, dynamic> data = json.decode(jsonString);
      final days = (data['days'] as Map<String, dynamic>?) ?? {};
      final List<ReadingQuestion> out = [];
      for (final entry in days.entries) {
        final List<dynamic> items = (entry.value as List?) ?? [];
        for (final it in items) {
          final m = it as Map<String, dynamic>;
          final List<dynamic> qList = (m['questions'] as List?) ?? [];
          out.addAll(qList.map((q) => ReadingQuestion.fromJson(q as Map<String, dynamic>)));
        }
      }
      return out;
    } catch (e) {
      print('載入整週閱讀題目失敗: week=$week, error=$e');
      return [];
    }
  }

  /// 合併文章與題目
  Future<List<ReadingContent>> loadDailyReadingWithQuestions(int week, int day) async {
    final articles = await loadDailyArticles(week, day);
    final qmap = await loadDayQuestions(week, day);
    return articles.map((a) {
      final qs = qmap[a.rid] ?? const [];
      return ReadingContent(
        rid: a.rid,
        category: a.category,
        title: a.title,
        shortTitle: a.shortTitle,
        content: a.content,
        questions: qs,
      );
    }).toList();
  }

  /// 获取日期字符串（格式：00, 01, 02, ...）
  String getDateString(int dayNumber) {
    return dayNumber.toString().padLeft(2, '0');
  }
} 