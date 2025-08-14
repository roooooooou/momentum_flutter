import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/calendar_service.dart';
import '../services/analytics_service.dart';
import '../services/experiment_config_service.dart';
import '../services/data_path_service.dart';
import '../services/notification_service.dart';
import '../models/event_model.dart';
import 'package:flutter/foundation.dart';
import 'package:googleapis/calendar/v3.dart' as cal;
import 'day_number_service.dart';

/// Wraps FirebaseAuth + Google Sign‑In with Calendar scope.
class AuthService {
  AuthService._();
  static final instance = AuthService._();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [
      'email',
      // Calendar read / write
      'https://www.googleapis.com/auth/calendar',
      'https://www.googleapis.com/auth/calendar.events',
    ],
  );

  Stream<User?> get authStateChanges => _auth.authStateChanges();
  User? get currentUser => _auth.currentUser;
  GoogleSignInAccount? get googleAccount => _googleSignIn.currentUser;

  Future<UserCredential> signInWithGoogle() async {
    final googleUser = await _googleSignIn.signIn();
    if (googleUser == null) {
      throw FirebaseAuthException(
        code: 'ERROR_ABORTED_BY_USER',
        message: 'Sign-in aborted by user',
      );
    }

    // IMPORTANT: 尝试初始化Calendar API，但不要让错误阻止登录
    try {
      await CalendarService.instance.init(googleUser);
    } catch (e) {
      print('Calendar initialization failed: $e');
      // 不抛出错误，继续登录流程
    }

    final googleAuth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );
    
    final userCredential = await _auth.signInWithCredential(credential);
    
    // 🎯 確保在 Firestore 中創建用戶文檔
    await _ensureUserDocument(userCredential.user!);

    // Log login event
    await AnalyticsService().logLogin();
    
    return userCredential;
  }

  Future<void> signInSilently() async {
    // 1. 先試著拿 Google 帳號（記憶體或 cookie 裡）
    final googleAccount =
        _googleSignIn.currentUser ?? await _googleSignIn.signInSilently();

    if (googleAccount == null) return; // 沒帳號 → 視為未登入
    
    // 尝试初始化Calendar，但不要让错误阻止登录
    try {
      await CalendarService.instance.init(googleAccount); // **** 關鍵 ****
    } catch (e) {
      print('Calendar initialization failed in signInSilently: $e');
    }

    // 2. Firebase 可能已經有 user，就不用再 sign-in
    if (_auth.currentUser == null) {
      final auth = await googleAccount.authentication;
      final cred = GoogleAuthProvider.credential(
        accessToken: auth.accessToken,
        idToken: auth.idToken,
      );
      await _auth.signInWithCredential(cred);
    }
    
    // 🎯 確保在 Firestore 中創建用戶文檔
    if (_auth.currentUser != null) {
      await _ensureUserDocument(_auth.currentUser!);
    }
    
    // Log login event if user is signed in
    if (_auth.currentUser != null) {
      await AnalyticsService().logLogin();
    }
  }

  Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _auth.signOut();
  }

  Future<String?> getAccessToken() async {
    final user = await _googleSignIn.signInSilently();
    final auth = await user?.authentication;
    return auth?.accessToken;
  }
  
  /// 🎯 確保用戶在 Firestore 中有對應的文檔
  Future<void> _ensureUserDocument(User user) async {
    try {
      final userRef = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid);
      
      final userDoc = await userRef.get();
      
      if (!userDoc.exists) {
        // 創建用戶文檔
        await userRef.set({
          'email': user.email,
          'displayName': user.displayName,
          'photoURL': user.photoURL,
          'createdAt': FieldValue.serverTimestamp(),
          'lastSignInAt': FieldValue.serverTimestamp(),
        });
        
        print('🎯 用戶文檔已創建: ${user.uid}');

        // 新增：初始化時寫入 manual_week_assignment（預設 'A'，可於 Firestore 手動改為 'B'）
        try {
          const assign = 'A';
          await userRef.set({'manual_week_assignment': assign}, SetOptions(merge: true));
          if (kDebugMode) {
            print('🎯 已初始化 manual_week_assignment=$assign');
          }
        } catch (e) {
          if (kDebugMode) {
            print('初始化 manual_week_assignment 失敗: $e');
          }
        }
        
        // 设置账号创建日期
        await DayNumberService().setAccountCreationDate(DateTime.now());
        
        // 新用户：分配日期分组并获取未来15天的任务
        await _initializeNewUser(user.uid);
        
      } else {
        // 更新最後登錄時間
        await userRef.update({
          'lastSignInAt': FieldValue.serverTimestamp(),
        });
        
        print('🎯 用戶文檔已更新: ${user.uid}');
        
        // 舊的日期分組遺留判斷移除
      }
    } catch (e) {
      print('🎯 創建/更新用戶文檔失敗: $e');
      // 不拋出錯誤，避免影響登錄流程
    }
  }

  /// 初始化新用户：分配日期分组并获取未来15天的任务
  Future<void> _initializeNewUser(String uid) async {
    try {
      if (kDebugMode) {
        print('🎯 开始初始化新用户: $uid');
      }

      // 1. 分配日期分组
      await ExperimentConfigService.instance.getUserGroup(uid);
      
      // 2. 获取未来15天的任务并分配到对应组别
      await _fetchAndDistributeFutureTasks(uid);
      
      if (kDebugMode) {
        print('🎯 新用户初始化完成: $uid');
      }
    } catch (e) {
      if (kDebugMode) {
        print('🎯 新用户初始化失败: $e');
      }
    }
  }

  /// 迁移现有用户到日期分组
  Future<void> _migrateExistingUser(String uid) async {
    try {
      if (kDebugMode) {
        print('🎯 开始迁移现有用户: $uid');
      }

      // 分配日期分组
      await ExperimentConfigService.instance.getUserGroup(uid);
      
      if (kDebugMode) {
        print('🎯 现有用户迁移完成: $uid');
      }
    } catch (e) {
      if (kDebugMode) {
        print('🎯 现有用户迁移失败: $e');
      }
    }
  }

  /// 获取未来15天的任务并分配到对应组别
  Future<void> _fetchAndDistributeFutureTasks(String uid) async {
    try {
      if (kDebugMode) {
        print('🎯 开始获取未来15天任务: $uid');
      }

      // 确保Calendar API已初始化
      if (!CalendarService.instance.isInitialized) {
        if (kDebugMode) {
          print('🎯 Calendar API未初始化，跳过任务获取');
        }
        return;
      }

      final now = DateTime.now();
      final start = DateTime(now.year, now.month, now.day).toUtc();
      final end = start.add(const Duration(days: 15)); // 未来15天

      if (kDebugMode) {
        print('🎯 查询时间范围: $start 到 $end');
      }

      // 查找名为 "experiment" 的日历
      String targetCalendarId = 'primary'; // 默认使用主日历
      
      try {
        final calendarList = await CalendarService.instance.getCalendarList();
        for (final calendar in calendarList.items ?? <cal.CalendarListEntry>[]) {
          if (calendar.summary?.toLowerCase() == 'experiment' || 
              calendar.summary?.toLowerCase() == 'experiments') {
            targetCalendarId = calendar.id!;
            if (kDebugMode) {
              print('🎯 找到 experiment 日历，ID: $targetCalendarId');
            }
            break;
          }
        }
      } catch (e) {
        if (kDebugMode) {
          print('🎯 获取日历列表失败: $e，使用主日历');
        }
      }

      // 获取Google Calendar事件
      final apiEvents = await CalendarService.instance.getEvents(
        targetCalendarId,
        start: start,
        end: end,
      );

      if (kDebugMode) {
        print('🎯 从日历获取到 ${apiEvents!.items?.length ?? 0} 个事件');
      }

      // 按日期分组事件（使用台湾时区）
      final eventsByDate = <String, List<cal.Event>>{};
      
      for (final event in apiEvents!.items ?? <cal.Event>[]) {
        if (event.id != null && event.start?.dateTime != null && event.end?.dateTime != null) {
          // 转换为台湾时区
          final eventDate = event.start!.dateTime!.toLocal();
          final dateKey = '${eventDate.year}-${eventDate.month.toString().padLeft(2, '0')}-${eventDate.day.toString().padLeft(2, '0')}';
          
          eventsByDate.putIfAbsent(dateKey, () => []).add(event);
        }
      }

      // 为每个日期的事件分配到对应组别
      final batch = FirebaseFirestore.instance.batch();
      int totalEvents = 0;

      for (final entry in eventsByDate.entries) {
        final dateKey = entry.key;
        final events = entry.value;
        
        // 解析日期（使用台湾时区）
        final dateParts = dateKey.split('-');
        final date = DateTime(int.parse(dateParts[0]), int.parse(dateParts[1]), int.parse(dateParts[2]));
        
        // 依日期決定 w1/w2 集合
        final eventsCollection = await DataPathService.instance.getDateEventsCollection(uid, date);

        // 添加事件到对应週別
        for (final event in events) {
          final eventDate = event.start!.dateTime!.toLocal();
          // 計算 dayNumber（以本地基準日起算）
          int? dayNumber;
          try {
            dayNumber = await DayNumberService().calculateDayNumber(eventDate);
          } catch (_) {}
          final eventData = {
            'title': event.summary ?? 'Untitled',
            'description': event.description ?? '',
            'googleEventId': event.id,
            'googleCalendarId': targetCalendarId,
            'scheduledStartTime': Timestamp.fromDate(event.start!.dateTime!),
            'scheduledEndTime': Timestamp.fromDate(event.end!.dateTime!),
            'date': Timestamp.fromDate(eventDate), // 添加日期字段
            if (dayNumber != null) 'dayNumber': dayNumber,
            'isActive': true,
            'isDone': false,
            'lifecycleStatus': 1, // active status
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          };

          final eventDoc = eventsCollection.doc(event.id);
          batch.set(eventDoc, eventData);
          totalEvents++;
        }
      }

      // 提交所有更改
      if (totalEvents > 0) {
        await batch.commit();
        if (kDebugMode) {
          print('🎯 成功分配 $totalEvents 个事件到对应组别');
        }
      } else {
        if (kDebugMode) {
          print('🎯 没有找到需要分配的事件');
        }
      }

      // 🎯 新增：排定15天的daily report通知
      await _scheduleDailyReportNotificationsForNext15Days(uid);
      
      // 🎯 新增：排定15天的事件通知
      await _scheduleEventNotificationsForNext15Days(uid);

    } catch (e) {
      if (kDebugMode) {
        print('🎯 获取和分配未来任务失败: $e');
      }
    }
  }

  /// 🎯 新增：为未来15天排定daily report通知
  Future<void> _scheduleDailyReportNotificationsForNext15Days(String uid) async {
    try {
      if (kDebugMode) {
        print('🎯 开始排定未来15天的daily report通知: $uid');
      }

      final now = DateTime.now();
      
      // 为未来15天的每一天排定通知
      for (int i = 0; i < 15; i++) {
        final targetDate = now.add(Duration(days: i));
        
        // 检查该日期是否有任务
        final hasTasks = await _checkIfHasTasksOnDate(uid, targetDate);
        
        if (hasTasks) {
          // 排定该日期的daily report通知（晚上10点）
          await _scheduleDailyReportNotificationForDate(targetDate, i);
          
          if (kDebugMode) {
            print('🎯 已排定 ${targetDate.year}-${targetDate.month.toString().padLeft(2, '0')}-${targetDate.day.toString().padLeft(2, '0')} 的daily report通知');
          }
        } else {
          if (kDebugMode) {
            print('🎯 ${targetDate.year}-${targetDate.month.toString().padLeft(2, '0')}-${targetDate.day.toString().padLeft(2, '0')} 没有任务，跳过通知排定');
          }
        }
      }

      if (kDebugMode) {
        print('🎯 未来15天的daily report通知排定完成');
      }
    } catch (e) {
      if (kDebugMode) {
        print('🎯 排定daily report通知失败: $e');
      }
    }
  }

  /// 🎯 新增：检查指定日期是否有任务
  Future<bool> _checkIfHasTasksOnDate(String uid, DateTime date) async {
    try {
      // 依日期決定 w1/w2 集合
      final eventsCollection = await DataPathService.instance.getDateEventsCollection(uid, date);
      
      // 查询该日期的事件
      final startOfDay = DateTime(date.year, date.month, date.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));
      
      final query = eventsCollection
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
          .where('date', isLessThan: Timestamp.fromDate(endOfDay));
      
      final snapshot = await query.get();
      
      return snapshot.docs.isNotEmpty;
    } catch (e) {
      if (kDebugMode) {
        print('🎯 检查日期任务失败: $e');
      }
      return false;
    }
  }

  /// 🎯 新增：为指定日期排定daily report通知
  Future<void> _scheduleDailyReportNotificationForDate(DateTime targetDate, int dayOffset) async {
    try {
      // 使用唯一的通知ID（基于日期偏移）
      final notificationId = 1000000 + dayOffset; // 使用1000000+偏移量作为唯一ID
      
      // 使用 NotificationService 的公共方法
      final success = await NotificationService.instance.scheduleDailyReportNotificationForDate(targetDate, notificationId);
      
      if (success && kDebugMode) {
        print('🎯 已排定通知ID $notificationId，日期: ${targetDate.year}-${targetDate.month.toString().padLeft(2, '0')}-${targetDate.day.toString().padLeft(2, '0')} 22:00');
      }
    } catch (e) {
      if (kDebugMode) {
        print('🎯 排定单日通知失败: $e');
      }
    }
  }

  /// 🎯 新增：为未来15天排定事件通知
  Future<void> _scheduleEventNotificationsForNext15Days(String uid) async {
    try {
      if (kDebugMode) {
        print('🎯 开始排定未来15天的事件通知: $uid');
      }

      final now = DateTime.now();
      
      // 为未来15天的每一天获取事件并排定通知
      for (int i = 0; i < 15; i++) {
        final targetDate = now.add(Duration(days: i));
        
        // 依日期決定 w1/w2 事件集合
        final eventsCollection = await DataPathService.instance.getDateEventsCollection(uid, targetDate);
        
        // 查询该日期的事件
        final startOfDay = DateTime(targetDate.year, targetDate.month, targetDate.day);
        final endOfDay = startOfDay.add(const Duration(days: 1));
        
        final query = eventsCollection
            .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
            .where('date', isLessThan: Timestamp.fromDate(endOfDay));
        
        final snapshot = await query.get();
        
        if (snapshot.docs.isNotEmpty) {
          // 将文档转换为EventModel
          final events = snapshot.docs.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return EventModel.fromDoc(doc);
          }).toList();
          
          // 使用NotificationScheduler排定通知
          await NotificationScheduler().sync(events);
          
          if (kDebugMode) {
            print('🎯 已为 ${targetDate.year}-${targetDate.month.toString().padLeft(2, '0')}-${targetDate.day.toString().padLeft(2, '0')} 排定 ${events.length} 个事件的通知');
          }
        } else {
          if (kDebugMode) {
            print('🎯 ${targetDate.year}-${targetDate.month.toString().padLeft(2, '0')}-${targetDate.day.toString().padLeft(2, '0')} 没有活跃事件，跳过通知排定');
          }
        }
      }

      if (kDebugMode) {
        print('🎯 未来15天的事件通知排定完成');
      }
    } catch (e) {
      if (kDebugMode) {
        print('🎯 排定事件通知失败: $e');
      }
    }
  }
}
