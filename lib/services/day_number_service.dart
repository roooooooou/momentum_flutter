import 'package:shared_preferences/shared_preferences.dart';

class DayNumberService {
  static final DayNumberService _instance = DayNumberService._internal();
  factory DayNumberService() => _instance;
  DayNumberService._internal();

  /// 获取用户创建账号的日期
  Future<DateTime?> _getAccountCreationDate() async {
    final prefs = await SharedPreferences.getInstance();
    final creationDateString = prefs.getString('account_creation_date');
    if (creationDateString != null) {
      return DateTime.parse(creationDateString);
    }
    return null;
  }

  /// 设置用户创建账号的日期
  Future<void> setAccountCreationDate(DateTime date) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('account_creation_date', date.toIso8601String());
  }

  /// 计算指定日期相对于账号创建日期的天数
  Future<int> calculateDayNumber(DateTime date) async {
    final creationDate = await _getAccountCreationDate();
    if (creationDate == null) {
      // 如果没有设置创建日期，使用当前日期作为创建日期
      await setAccountCreationDate(date);
      return 0;
    }

    final daysSinceCreation = date.difference(creationDate).inDays;
    return daysSinceCreation;
  }

  /// 获取今天的dayNumber
  Future<int> getTodayDayNumber() async {
    return await calculateDayNumber(DateTime.now());
  }
} 