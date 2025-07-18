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
  bool _isLoading = true;

  // 问卷答案状态
  final Set<String> _selectedDelayedTasks = {};
  final Set<String> _selectedDelayReasons = {};
  final TextEditingController _delayOtherController = TextEditingController();
  
  final Set<String> _selectedChatHelp = {};
  final TextEditingController _chatOtherController = TextEditingController();
  
  int _overallRating = 3;
  int _aiHelpRating = 3;
  bool _noChatToday = false; // 今日沒有跟Coach聊天
  
  final Set<String> _selectedLikelyDelayedTasks = {};
  final TextEditingController _notesController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadEventData();
  }

  @override
  void dispose() {
    _delayOtherController.dispose();
    _chatOtherController.dispose();
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

      // 今日事件
      final todayQuery = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('events')
          .where('scheduledStartTime', isGreaterThanOrEqualTo: Timestamp.fromDate(today.toUtc()))
          .where('scheduledStartTime', isLessThan: Timestamp.fromDate(tomorrow.toUtc()))
          .orderBy('scheduledStartTime')
          .get();

      // 明日事件
      final tomorrowQuery = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('events')
          .where('scheduledStartTime', isGreaterThanOrEqualTo: Timestamp.fromDate(tomorrow.toUtc()))
          .where('scheduledStartTime', isLessThan: Timestamp.fromDate(dayAfterTomorrow.toUtc()))
          .orderBy('scheduledStartTime')
          .get();

      setState(() {
        _todayEvents = todayQuery.docs.map(EventModel.fromDoc).toList();
        _tomorrowEvents = tomorrowQuery.docs.map(EventModel.fromDoc).toList();
        
        // 筛选出延迟或未完成的任务
        _delayedEvents = _todayEvents.where((event) {
          final status = event.computedStatus;
          return !event.isDone && (status == TaskStatus.overdue || status == TaskStatus.notStarted);
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
        chatHelpfulness: _selectedChatHelp.toList(),
        chatOtherHelp: _chatOtherController.text.trim().isEmpty 
            ? null : _chatOtherController.text.trim(),
        overallSatisfaction: _overallRating,
        aiHelpRating: _aiHelpRating,
        noChatToday: _noChatToday,
        likelyDelayedTaskIds: _selectedLikelyDelayedTasks.toList(),
        notes: _notesController.text.trim().isEmpty 
            ? null : _notesController.text.trim(),
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
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSection1DelayedTasks(),
                  const SizedBox(height: 24),
                  _buildSection2ChatHelp(),
                  const SizedBox(height: 24),
                  _buildSection3OverallRating(),
                  const SizedBox(height: 24),
                  _buildSection4AIHelpRating(),
                  const SizedBox(height: 24),
                  _buildSection5LikelyDelayedTasks(),
                  const SizedBox(height: 24),
                  _buildSection6Notes(),
                  const SizedBox(height: 32),
                  _buildSubmitButton(),
                ],
              ),
            ),
    );
  }

  Widget _buildSection1DelayedTasks() {
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

  Widget _buildSection2ChatHelp() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '2. 今日 AI Coach 聊天介入是否對你有幫助？',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              '（多選）',
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
      {'id': 'clarify_task', 'text': '幫助我釐清任務怎麼做'},
      {'id': 'motivation', 'text': '讓我比較有動力'},
      {'id': 'no_help', 'text': '沒有幫助'},
      {'id': 'uncertain', 'text': '不確定'},
      {'id': 'no_chat', 'text': '今天沒有跟Coach聊天'},
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



  Widget _buildSection3OverallRating() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '3. 對今天自己執行任務的整體感受',
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
                  onTap: () => setState(() => _overallRating = rating),
                  child: Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: _overallRating >= rating ? Colors.amber : Colors.grey[300],
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
                '評分: $_overallRating / 5',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection4AIHelpRating() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '4. 對 AI Coach 介入後的任務感覺',
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
                final isEnabled = !_noChatToday;
                return GestureDetector(
                  onTap: isEnabled ? () => setState(() {
                    _aiHelpRating = rating;
                  }) : null,
                  child: Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: isEnabled
                          ? (_aiHelpRating >= rating ? Colors.blue : Colors.grey[300])
                          : Colors.grey[200],
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.star, 
                      color: isEnabled ? Colors.white : Colors.grey[400],
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 12),
            
            // 添加"今日沒有跟Coach聊天"選項
            CheckboxListTile(
              title: const Text('今日沒有跟Coach聊天'),
              value: _noChatToday,
              onChanged: (bool? value) {
                setState(() {
                  _noChatToday = value ?? false;
                  if (_noChatToday) {
                    _aiHelpRating = 1; // 重置評分為最低
                  }
                });
              },
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 8),
            
            Center(
              child: Text(
                _noChatToday ? '無法評分' : '評分: $_aiHelpRating / 5',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: _noChatToday ? Colors.grey : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection5LikelyDelayedTasks() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '5. 明天最有可能延遲的任務是什麼？',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              '（請勾選一個最有可能延遲的任務）',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            
            if (_tomorrowEvents.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('📅 明日沒有安排任務'),
              )
            else
              ..._tomorrowEvents.map((event) => CheckboxListTile(
                title: Text(event.title),
                subtitle: Text(event.timeRange),
                value: _selectedLikelyDelayedTasks.contains(event.id),
                onChanged: (bool? value) {
                  setState(() {
                    if (value == true) {
                      _selectedLikelyDelayedTasks.add(event.id);
                    } else {
                      _selectedLikelyDelayedTasks.remove(event.id);
                    }
                  });
                },
              )),
          ],
        ),
      ),
    );
  }

  Widget _buildSection6Notes() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '6. 有沒有什麼狀況或心得要記錄？',
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