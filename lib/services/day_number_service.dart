import 'package:shared_preferences/shared_preferences.dart';

class DayNumberService {
  static final DayNumberService _instance = DayNumberService._internal();
  factory DayNumberService() => _instance;
  DayNumberService._internal();

  /// 將日期正規化為「本地午夜」（避免因時間差導致日數計算重覆或偏差）
  DateTime _toLocalMidnight(DateTime d) {
    final local = d.toLocal();
    return DateTime(local.year, local.month, local.day);
  }

  /// 获取用户创建账号的日期
  Future<DateTime?> _getAccountCreationDate() async {
    final prefs = await SharedPreferences.getInstance();
    final creationDateString = prefs.getString('account_creation_date');
    if (creationDateString != null) {
      final parsed = DateTime.parse(creationDateString);
      return _toLocalMidnight(parsed);
    }
    return null;
  }

  /// 设置用户创建账号的日期
  Future<void> setAccountCreationDate(DateTime date) async {
    final prefs = await SharedPreferences.getInstance();
    final normalized = _toLocalMidnight(date);
    await prefs.setString('account_creation_date', normalized.toIso8601String());
  }

  /// 计算指定日期相对于账号创建日期的天数
  Future<int> calculateDayNumber(DateTime date) async {
    final creationDate = await _getAccountCreationDate();
    if (creationDate == null) {
      // 如果没有设置创建日期，使用当前日期作为创建日期
      await setAccountCreationDate(date);
      return 0;
    }

    final target = _toLocalMidnight(date);
    final daysSinceCreation = target.difference(creationDate).inDays;
    return daysSinceCreation;
  }

  /// 是否已設定基準日
  Future<bool> hasCreationDate() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('account_creation_date') != null;
  }

  /// 取得或初始化基準日（若未設定，使用 fallback 設定並回傳）
  Future<DateTime> getOrInitCreationDate({DateTime? fallback}) async {
    final existing = await _getAccountCreationDate();
    if (existing != null) return existing;
    final base = _toLocalMidnight(fallback ?? DateTime.now());
    await setAccountCreationDate(base);
    return base;
  }

  /// 获取今天的dayNumber
  Future<int> getTodayDayNumber() async {
    return await calculateDayNumber(DateTime.now());
  }
} 