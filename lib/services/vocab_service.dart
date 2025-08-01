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