import 'dart:convert';
import 'package:flutter/services.dart';
import '../models/reading_content_model.dart';

class ReadingService {
  static final ReadingService _instance = ReadingService._internal();
  factory ReadingService() => _instance;
  ReadingService._internal();

  /// 加载指定天数的冷知识内容
  Future<List<ReadingContent>> loadDailyContent(int dayNumber) async {
    try {
      // 根据天数加载对应的JSON文件
      final String dateString = dayNumber.toString().padLeft(2, '0');
      final String jsonString = await rootBundle.loadString('assets/dyn/$dateString.json');
      final List<dynamic> jsonList = json.decode(jsonString);
      
      return jsonList.map((json) => ReadingContent.fromJson(json)).toList();
    } catch (e) {
      print('加载冷知识内容失败: dayNumber=$dayNumber, error=$e');
      // 如果加载失败，返回空列表
      return [];
    }
  }

  /// 获取日期字符串（格式：00, 01, 02, ...）
  String getDateString(int dayNumber) {
    return dayNumber.toString().padLeft(2, '0');
  }
} 