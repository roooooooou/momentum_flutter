import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import '../models/event_model.dart';
import '../models/daily_report_model.dart';
import '../models/enums.dart';

class DailyReportScreen extends StatefulWidget {
  const DailyReportScreen({super.key});

  @override
  State<DailyReportScreen> createState() => _DailyReportScreenState();
}

class _DailyReportScreenState extends State<DailyReportScreen> {
  // 任务数据
  List<EventModel> _todayEvents = [];
  List<EventModel> _tomorrowEvents = [];
  List<EventModel> _delayedEvents = [];
  List<EventModel> _startedButIncompleteEvents = []; // 今天開始但沒有完成的任務
  bool _isLoading = true;

  // 问卷答案状态
  // 1. 今日延遲的任務
  final Set<String> _selectedDelayedTasks = {};
  final Set<String> _selectedDelayReasons = {};
  final TextEditingController _delayOtherController = TextEditingController();
  
  // 1.5. 今天開始但沒有完成任務的原因（簡答題）
  final TextEditingController _incompleteReasonController = TextEditingController();
  
  // 2. 對今天表現的感受 (1-5)
  int _overallSatisfaction = 3;
  
  // 3. 明天還想不想開始任務
  final TextEditingController _tomorrowMotivationController = TextEditingController();
  
  // 4. 今天有沒有跟Coach聊天
  bool? _hadChatWithCoach; // null = 未選擇
  
  // 5. Coach聊天的幫助評分 (1-5)
  int _coachHelpRating = 3;
  
  // 6. 為什麼沒有跟Coach聊天（第4題為否時顯示）
  final Set<String> _selectedNoChatReasons = {};
  final TextEditingController _noChatOtherController = TextEditingController();
  
  // 7. AI Coach有什麼幫助（第4題為是時顯示）
  final Set<String> _selectedChatHelp = {};
  final TextEditingController _chatOtherController = TextEditingController();
  
  // 8. 明天還想跟AI聊嗎（第4題為是時顯示）
  bool? _wantChatTomorrow; // null = 未選擇
  
  // 9. 希望AI改變什麼（第4題為是時顯示）
  final TextEditingController _aiImprovementController = TextEditingController();
  
  // 10. 狀況或心得
  final TextEditingController _notesController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadEventData();
  }

  @override
  void dispose() {
    _delayOtherController.dispose();
    _incompleteReasonController.dispose();
    _tomorrowMotivationController.dispose();
    _noChatOtherController.dispose();
    _chatOtherController.dispose();
    _aiImprovementController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadEventData() async {
    final uid = context.read<AuthService>().currentUser?.uid;
    if (uid == null) return;

    try {
      // 获取今日事件
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final tomorrow = today.add(const Duration(days: 1));
      final dayAfterTomorrow = tomorrow.add(const Duration(days: 1));

      // 今日事件 - 只查询活跃事件
      final todayQuery = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('events')
          .where('scheduledStartTime', isGreaterThanOrEqualTo: Timestamp.fromDate(today.toUtc()))
          .where('scheduledStartTime', isLessThan: Timestamp.fromDate(tomorrow.toUtc()))
          .orderBy('scheduledStartTime')
          .get();

      // 明日事件 - 只查询活跃事件
      final tomorrowQuery = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('events')
          .where('scheduledStartTime', isGreaterThanOrEqualTo: Timestamp.fromDate(tomorrow.toUtc()))
          .where('scheduledStartTime', isLessThan: Timestamp.fromDate(dayAfterTomorrow.toUtc()))
          .orderBy('scheduledStartTime')
          .get();

      setState(() {
        _todayEvents = todayQuery.docs
            .map(EventModel.fromDoc)
            .where((event) => event.isActive) // 只显示活跃事件
            .toList();
        
        _tomorrowEvents = tomorrowQuery.docs
            .map(EventModel.fromDoc)
            .where((event) => event.isActive) // 只显示活跃事件
            .toList();
        
        // 筛选出延迟或未完成的任务
        _delayedEvents = _todayEvents.where((event) {
          final status = event.computedStatus;
          return !event.isDone && (status == TaskStatus.overdue || status == TaskStatus.notStarted || status == TaskStatus.paused);
        }).toList();
        
        // 筛选出今天開始但沒有完成的任務（有actualStartTime但isDone=false）
        _startedButIncompleteEvents = _todayEvents.where((event) {
          return event.actualStartTime != null && !event.isDone;
        }).toList();
        
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载数据失败: $e')),
        );
      }
    }
  }

  Future<void> _submitReport() async {
    final uid = context.read<AuthService>().currentUser?.uid;
    if (uid == null) return;

    // 验证必填字段
    if (_hadChatWithCoach == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請回答是否有跟Coach聊天')),
      );
      return;
    }

    if (_hadChatWithCoach == true && _wantChatTomorrow == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請回答明天是否還想跟AI聊天')),
      );
      return;
    }

    try {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      
      final report = DailyReportModel(
        id: const Uuid().v4(),
        uid: uid,
        date: today,
        delayedTaskIds: _selectedDelayedTasks.toList(),
        delayReasons: _selectedDelayReasons.toList(),
        delayOtherReason: _delayOtherController.text.trim().isEmpty 
            ? null : _delayOtherController.text.trim(),
        incompleteReason: _incompleteReasonController.text.trim().isEmpty 
            ? null : _incompleteReasonController.text.trim(),
        overallSatisfaction: _overallSatisfaction,
        tomorrowMotivation: _tomorrowMotivationController.text.trim().isEmpty 
            ? null : _tomorrowMotivationController.text.trim(),
        hadChatWithCoach: _hadChatWithCoach!,
        coachHelpRating: _hadChatWithCoach == true ? _coachHelpRating : null,
        noChatReasons: _selectedNoChatReasons.toList(),
        noChatOtherReason: _noChatOtherController.text.trim().isEmpty 
            ? null : _noChatOtherController.text.trim(),
        chatHelpfulness: _selectedChatHelp.toList(),
        chatOtherHelp: _chatOtherController.text.trim().isEmpty 
            ? null : _chatOtherController.text.trim(),
        wantChatTomorrow: _wantChatTomorrow,
        aiImprovementSuggestions: _aiImprovementController.text.trim().isEmpty 
            ? null : _aiImprovementController.text.trim(),
        notes: _notesController.text.trim().isEmpty 
            ? null : _notesController.text.trim(),
        likelyDelayedTaskIds: [], // 暂时保留空数组
        createdAt: now,
      );

      // 保存到Firebase
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('daily_reports')
          .doc('${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}')
          .set(report.toFirestore());

      // 自动完成未勾选为延迟的任务
      await _completeUnselectedTasks(uid);

      // 重新安排明天的每日報告通知
      try {
        await NotificationService.instance.scheduleDailyReportNotification();
      } catch (e) {
        print('重新安排每日報告通知失敗: $e');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('每日报告已保存！未勾选的任务已标记为完成。'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('保存失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('📋 每日報告'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _todayEvents.isEmpty 
              ? _buildNoTasksToday()
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildQuestion1DelayedTasks(),
                      const SizedBox(height: 24),
                      
                      // 1.5. 條件顯示：今天開始但沒有完成任務的原因
                      if (_startedButIncompleteEvents.isNotEmpty) ...[
                        _buildQuestion1_5IncompleteReason(),
                        const SizedBox(height: 24),
                      ],
                      
                      _buildQuestion2OverallSatisfaction(),
                      const SizedBox(height: 24),
                      _buildQuestion3TomorrowMotivation(),
                      const SizedBox(height: 24),
                      _buildQuestion4HadChatWithCoach(),
                      const SizedBox(height: 24),
                      
                      // 条件显示问题5、6、7、8、9
                      if (_hadChatWithCoach == true) ...[
                        _buildQuestion5CoachHelpRating(),
                        const SizedBox(height: 24),
                        _buildQuestion6ChatHelpfulness(),
                        const SizedBox(height: 24),
                        _buildQuestion7WantChatTomorrow(),
                        const SizedBox(height: 24),
                        _buildQuestion8AIImprovement(),
                        const SizedBox(height: 24),
                      ],
                      
                      if (_hadChatWithCoach == false) ...[
                        _buildQuestion6NoChatReasons(),
                        const SizedBox(height: 24),
                      ],
                      
                      _buildQuestion9Notes(),
                      const SizedBox(height: 32),
                      _buildSubmitButton(),
                    ],
                  ),
                ),
    );
  }

  Widget _buildNoTasksToday() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.beach_access,
              size: 80,
              color: Colors.grey,
            ),
            const SizedBox(height: 24),
            const Text(
              '🎉 今日沒有安排任務',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            const Text(
              '既然今天沒有任務安排，就不需要填寫每日報告了！\n好好休息，為明天的任務做準備吧！',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back),
                label: const Text('返回主頁'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.grey[400],
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuestion1DelayedTasks() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '1. 今日延遲的任務有哪些？',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              '（未勾選的任務會幫你更新成已完成的狀態）',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            
            if (_delayedEvents.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('🎉 今日沒有延遲的任務！'),
              )
            else
              ..._delayedEvents.map((event) => CheckboxListTile(
                title: Text(event.title),
                subtitle: Text(event.timeRange),
                value: _selectedDelayedTasks.contains(event.id),
                onChanged: (bool? value) {
                  setState(() {
                    if (value == true) {
                      _selectedDelayedTasks.add(event.id);
                    } else {
                      _selectedDelayedTasks.remove(event.id);
                    }
                  });
                },
              )),
            
            if (_selectedDelayedTasks.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text(
                '延遲原因（多選）:',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8),
              ..._buildDelayReasonOptions(),
              if (_selectedDelayReasons.contains('other')) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _delayOtherController,
                  decoration: const InputDecoration(
                    hintText: '請填寫其他原因...',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _buildDelayReasonOptions() {
    final reasons = [
      {'id': 'no_time', 'text': '時間不夠'},
      {'id': 'forgot', 'text': '忘記了'},
      {'id': 'no_mood', 'text': '沒心情/懶惰'},
      {'id': 'too_hard', 'text': '任務太難，不知怎麼開始'},
      {'id': 'interrupted', 'text': '突發事件打斷'},
      {'id': 'other', 'text': '其他'},
    ];

    return reasons.map((reason) => CheckboxListTile(
      title: Text(reason['text']!),
      value: _selectedDelayReasons.contains(reason['id']),
      onChanged: (bool? value) {
        setState(() {
          if (value == true) {
            _selectedDelayReasons.add(reason['id']!);
          } else {
            _selectedDelayReasons.remove(reason['id']!);
          }
        });
      },
      dense: true,
    )).toList();
  }

  Widget _buildQuestion1_5IncompleteReason() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '1.5. 今天開始但沒有完成任務的原因？',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              '簡答題',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            
            // 顯示今天開始但沒完成的任務列表
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber[200]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '📝 今天已開始但尚未完成的任務：',
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 8),
                  ..._startedButIncompleteEvents.map((event) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '• ${event.title}',
                      style: const TextStyle(fontSize: 14),
                    ),
                  )),
                ],
              ),
            ),
            
            const SizedBox(height: 16),
            TextField(
              controller: _incompleteReasonController,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: '例如：任務比預期困難、中途被其他事情打斷、缺乏動力繼續...',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuestion2OverallSatisfaction() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '2. 對今天自己執行任務的表現的感受',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              '1 = 非常不滿意，幾乎都沒完成\n5 = 非常滿意，幾乎都做到或超過預期',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: List.generate(5, (index) {
                final rating = index + 1;
                return GestureDetector(
                  onTap: () => setState(() => _overallSatisfaction = rating),
                  child: Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: _overallSatisfaction >= rating ? Colors.amber : Colors.grey[300],
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.star, color: Colors.white),
                  ),
                );
              }),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                '評分: $_overallSatisfaction / 5',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuestion3TomorrowMotivation() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '3. 回顧今天的任務，明天還想不想開始',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              '簡答題',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            
            TextField(
              controller: _tomorrowMotivationController,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: '例如：今天完成得不錯，明天想繼續保持；或者覺得任務太難，明天想調整...',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuestion4HadChatWithCoach() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '4. 今天有沒有跟Coach聊天？',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            
            Column(
              children: [
                RadioListTile<bool>(
                  title: const Text('是'),
                  value: true,
                  groupValue: _hadChatWithCoach,
                  onChanged: (bool? value) {
                    setState(() {
                      _hadChatWithCoach = value;
                      // 清空相反条件的数据
                      if (value == true) {
                        _selectedNoChatReasons.clear();
                        _noChatOtherController.clear();
                      } else {
                        _coachHelpRating = 3; // 重置评分
                        _selectedChatHelp.clear();
                        _chatOtherController.clear();
                        _wantChatTomorrow = null;
                        _aiImprovementController.clear();
                      }
                    });
                  },
                ),
                RadioListTile<bool>(
                  title: const Text('否'),
                  value: false,
                  groupValue: _hadChatWithCoach,
                  onChanged: (bool? value) {
                    setState(() {
                      _hadChatWithCoach = value;
                      // 清空相反条件的数据
                      if (value == false) {
                        _coachHelpRating = 3; // 重置评分
                        _selectedChatHelp.clear();
                        _chatOtherController.clear();
                        _wantChatTomorrow = null;
                        _aiImprovementController.clear();
                      } else {
                        _selectedNoChatReasons.clear();
                        _noChatOtherController.clear();
                      }
                    });
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuestion5CoachHelpRating() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '5. Coach聊天的幫助？',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              '1 = 沒有幫助，甚至讓我分心\n5 = 幫助很大，讓我輕鬆完成',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: List.generate(5, (index) {
                final rating = index + 1;
                return GestureDetector(
                  onTap: () => setState(() => _coachHelpRating = rating),
                  child: Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: _coachHelpRating >= rating ? Colors.blue : Colors.grey[300],
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.star, color: Colors.white),
                  ),
                );
              }),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                '評分: $_coachHelpRating / 5',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuestion6NoChatReasons() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '6. 今天為什麼沒有跟Coach聊天？',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              '多選',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            
            ..._buildNoChatReasonOptions(),
            
            if (_selectedNoChatReasons.contains('other')) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _noChatOtherController,
                decoration: const InputDecoration(
                  hintText: '請填寫其他原因...',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _buildNoChatReasonOptions() {
    final reasons = [
      {'id': 'tasks_completed', 'text': '任務都完成了'},
      {'id': 'no_help', 'text': '沒有幫助'},
      {'id': 'no_time', 'text': '時間不夠'},
      {'id': 'missed_notification', 'text': '錯過通知'},
      {'id': 'dont_want_to_use', 'text': '不想使用'},
      {'id': 'other', 'text': '其他'},
    ];

    return reasons.map((reason) => CheckboxListTile(
      title: Text(reason['text']!),
      value: _selectedNoChatReasons.contains(reason['id']),
      onChanged: (bool? value) {
        setState(() {
          if (value == true) {
            _selectedNoChatReasons.add(reason['id']!);
          } else {
            _selectedNoChatReasons.remove(reason['id']!);
          }
        });
      },
      dense: true,
    )).toList();
  }

  Widget _buildQuestion6ChatHelpfulness() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '6. 今日跟Coach聊一聊有什麼幫助？',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              '多選',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            
            ..._buildChatHelpOptions(),
            
            if (_selectedChatHelp.contains('other')) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _chatOtherController,
                decoration: const InputDecoration(
                  hintText: '請填寫其他幫助...',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _buildChatHelpOptions() {
    final options = [
      {'id': 'start_task', 'text': '幫助我啟動任務'},
      {'id': 'break_down_task', 'text': '幫我分解任務'},
      {'id': 'motivation', 'text': '提供動力'},
      {'id': 'no_help', 'text': '沒有幫助'},
      {'id': 'uncertain', 'text': '不確定'},
      {'id': 'other', 'text': '其他'},
    ];

    return options.map((option) => CheckboxListTile(
      title: Text(option['text']!),
      value: _selectedChatHelp.contains(option['id']),
      onChanged: (bool? value) {
        setState(() {
          if (value == true) {
            _selectedChatHelp.add(option['id']!);
          } else {
            _selectedChatHelp.remove(option['id']!);
          }
        });
      },
      dense: true,
    )).toList();
  }

  Widget _buildQuestion7WantChatTomorrow() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '7. 你明天還想再開始任務前跟Coach聊嗎',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            
            Column(
              children: [
                RadioListTile<bool>(
                  title: const Text('是'),
                  value: true,
                  groupValue: _wantChatTomorrow,
                  onChanged: (bool? value) {
                    setState(() {
                      _wantChatTomorrow = value;
                    });
                  },
                ),
                RadioListTile<bool>(
                  title: const Text('否'),
                  value: false,
                  groupValue: _wantChatTomorrow,
                  onChanged: (bool? value) {
                    setState(() {
                      _wantChatTomorrow = value;
                    });
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuestion8AIImprovement() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '8. 可以改進的話希望Coach可以改變什麼',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              '簡答題',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            
            TextField(
              controller: _aiImprovementController,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: '例如：回應速度、對話風格、提供的建議類型等...',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuestion9Notes() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '9. 有什麼狀況或心得與任務有關想紀錄？',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              '例如：今天臨時有會議，打亂排程；或 LLM 提醒很有用。',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            
            TextField(
              controller: _notesController,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: '請記錄今日的狀況或心得...',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubmitButton() {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
        onPressed: _submitReport,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.deepPurple,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: const Text(
          '📋 提交每日報告',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  /// 自动完成未勾选为延迟的任务
  Future<void> _completeUnselectedTasks(String uid) async {
    try {
      final now = DateTime.now();
      
      // 找出所有延迟事件中未被勾选的任务
      final unselectedTasks = _delayedEvents.where((event) => 
        !_selectedDelayedTasks.contains(event.id)
      ).toList();

      // 批量更新未勾选的任务为完成状态
      final batch = FirebaseFirestore.instance.batch();
      
      for (final event in unselectedTasks) {
        final eventRef = FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('events')
            .doc(event.id);

        batch.update(eventRef, {
          'isDone': true,
          'completedTime': Timestamp.fromDate(now),
          'status': TaskStatus.completed.value,
          'startTrigger': StartTrigger.dailyReport.value, // 使用新的触发方式
          'updatedAt': Timestamp.fromDate(now),
        });
      }

      // 提交批量更新
      await batch.commit();
      
      print('自动完成了 ${unselectedTasks.length} 个未勾选的任务');
    } catch (e) {
      print('自动完成任务失败: $e');
      // 不抛出错误，避免影响报告保存
    }
  }
} 