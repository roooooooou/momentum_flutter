import 'dart:convert';
import 'dart:math';
import 'package:flutter/services.dart';
import '../models/vocab_content_model.dart';

class VocabService {
  static final VocabService _instance = VocabService._internal();
  factory VocabService() => _instance;
  VocabService._internal();

  /// 加载指定天数的单词内容
  Future<List<VocabContent>> loadDailyVocab(int dayNumber) async {
    try {
      // 根据天数加载对应的JSON文件
      final String dateString = dayNumber.toString().padLeft(2, '0');
      final String jsonString = await rootBundle.loadString('assets/vocab/$dateString.json');
      final List<dynamic> jsonList = json.decode(jsonString);
      
      return jsonList.map((json) => VocabContent.fromJson(json)).toList();
    } catch (e) {
      print('載入單字內容失敗: dayNumber=$dayNumber, error=$e');
      // 如果加载失败，返回空列表
      return [];
    }
  }

  /// 解析事件標題中的週/日資訊，例如: vocab_1_1 或 vocab-w1-d3
  /// 返回 (week, day)，若失敗回傳 null
  List<int>? parseWeekDayFromTitle(String title) {
    final lower = title.toLowerCase();
    final patterns = <RegExp>[
      RegExp(r'^\s*vocab[_-]?(\d+)[_-](\d+)\s*$'),
      RegExp(r'^\s*vocab[_-]?w(\d+)[_-]?d(\d+)\s*$'),
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

  /// 解析測驗事件標題中的週資訊，例如: vocab-w1-test 或 vocab_w2_test
  /// 返回 week，若失敗回傳 null
  int? parseWeekFromTestTitle(String title) {
    final lower = title.toLowerCase().trim();
    final patterns = <RegExp>[
      RegExp(r'^vocab[-_]?w(\d+)[-_]?test$'),
      RegExp(r'^vocab[-_]?(\d+)[-_]?test$'),
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

  /// 讀取週/日對應的新舊單字數量（從 meta.counts）
  Future<Map<String, int>> loadWeeklyCounts(int week, int day) async {
    final path = 'assets/vocab/week${week}_day${day}.json';
    final jsonString = await rootBundle.loadString(path);
    final Map<String, dynamic> data = json.decode(jsonString);
    final counts = (data['meta']?['counts'] ?? {}) as Map<String, dynamic>;
    return {
      'new': (counts['new'] as num?)?.toInt() ?? 0,
      'review': (counts['review_due'] as num?)?.toInt() ?? 0,
    };
  }

  /// 讀取每週測驗題庫（assets/vocab/week{week}_test.json）
  Future<List<VocabContent>> loadWeeklyTestQuiz(int week) async {
    try {
      final path = 'assets/vocab/week${week}_test.json';
      final jsonString = await rootBundle.loadString(path);
      final Map<String, dynamic> data = json.decode(jsonString);
      final List<dynamic> items = (data['items'] as List?) ?? [];

      return items.map<VocabContent>((raw) {
        final m = raw as Map<String, dynamic>;
        final sentence = (m['sentence'] ?? '').toString();
        final options = (m['options'] as List?)?.map((e) => e.toString()).toList() ?? <String>[];
        String answer = '';
        if (m.containsKey('answer_word')) {
          answer = (m['answer_word'] ?? '').toString();
        } else if (m.containsKey('answer_index')) {
          final idx = (m['answer_index'] as num?)?.toInt() ?? -1;
          if (idx >= 0 && idx < options.length) {
            answer = options[idx];
          }
        }

        return VocabContent(
          word: '',
          definition: (m['en_definition'] ?? '').toString(),
          example: sentence,
          options: options,
          answer: answer,
          partOfSpeech: (m['part_of_speech'] ?? '').toString(),
          zhExplanation: '',
          exampleZh: '',
        );
      }).toList();
    } catch (e) {
      print('載入週測驗失敗: week=$week, error=$e');
      return [];
    }
  }

  /// 讀取週/日對應的單字清單，優先使用 items_shuffled
  Future<List<VocabContent>> loadWeeklyVocab(int week, int day) async {
    try {
      final path = 'assets/vocab/week${week}_day${day}.json';
      final jsonString = await rootBundle.loadString(path);
      final Map<String, dynamic> data = json.decode(jsonString);

      List<dynamic> items = [];
      if (data['items_shuffled'] is List) {
        items = data['items_shuffled'];
      } else {
        final newItems = (data['new_items'] as List?) ?? [];
        final reviewItems = (data['review_items'] as List?) ?? [];
        items = [...newItems, ...reviewItems];
      }

      return items.map<VocabContent>((raw) {
        final m = raw as Map<String, dynamic>;
        final word = (m['word'] ?? '').toString();
        final definition = (m['en_definition'] ?? m['definition'] ?? '').toString();
        final example = (m['example_en'] ?? m['example'] ?? '').toString();
        return VocabContent(
          word: word,
          definition: definition,
          example: example,
          options: const [],
          answer: '',
          partOfSpeech: (m['part_of_speech'] ?? m['pos'] ?? '').toString(),
          zhExplanation: (m['zh_explanation'] ?? m['zh_meaning'] ?? '').toString(),
          exampleZh: (m['example_zh'] ?? '').toString(),
        );
      }).toList();
    } catch (e) {
      print('載入週日單字失敗: week=$week, day=$day, error=$e');
      return [];
    }
  }

  /// 从所有单词中随机选择5个生成测验题目
  List<VocabContent> generateQuizQuestions(List<VocabContent> allVocab) {
    if (allVocab.length <= 5) {
      return allVocab;
    }
    
    // 随机选择5个单词
    final random = Random();
    final selectedIndices = <int>{};
    final questions = <VocabContent>[];
    
    while (selectedIndices.length < 5) {
      final index = random.nextInt(allVocab.length);
      if (!selectedIndices.contains(index)) {
        selectedIndices.add(index);
        questions.add(allVocab[index]);
      }
    }
    
    return questions;
  }

  /// 获取日期字符串（格式：00, 01, 02, ...）
  String getDateString(int dayNumber) {
    return dayNumber.toString().padLeft(2, '0');
  }
} 