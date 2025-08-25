import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import '../services/data_path_service.dart';
import '../services/experiment_config_service.dart';
import '../models/event_model.dart';
import '../models/daily_report_model.dart';
import '../models/enums.dart';

/// 每日報告畫面 - 簡化版問卷
class DailyReportScreen extends StatefulWidget {
  const DailyReportScreen({super.key});

  @override
  State<DailyReportScreen> createState() => _DailyReportScreenState();
}

class _DailyReportScreenState extends State<DailyReportScreen> {
  // 任務資料
  List<EventModel> _todayEvents = [];
  bool _isLoading = true;
  bool _hasDelayedTasks = false;
  bool _hasIncompleteTasks = false;
  bool _hasCompletedReadingTasks = false; // 是否有完成的閱讀任務
  bool _hasCompletedVocabTasks = false;   // 是否有完成的單字任務

  // 問卷答案狀態
  // 1. 今天延遲任務的原因（多選）
  final Set<String> _selectedDelayReasons = {};
  final TextEditingController _delayOtherController = TextEditingController();
  
  // 2. 今天開始但沒有完成任務的原因？（多選）
  final Set<String> _selectedIncompleteReasons = {};
  final TextEditingController _incompleteOtherController = TextEditingController();
  
  // 3. 今天的文章閱讀對我來說是有趣、有幫助的（1-5）
  int _readingHelpfulness = 3;
  
  // 4. 完成今天單字任務對我**學業**有幫助（1-5）
  int _vocabHelpfulness = 3;
  
  // 5. 對今天自己學習的表現的感受（1-5分）
  int _overallSatisfaction = 3;
  
  // 6. 我有能力在預定時間內完成明天的學習任務（1-5分）
  int _tomorrowConfidence = 3;
  
  // 7. 有什麼狀況或心得與任務有關想紀錄（簡答）
  final TextEditingController _notesController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadEventData();
  }

  @override
  void dispose() {
    _delayOtherController.dispose();
    _incompleteOtherController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadEventData() async {
    final uid = context.read<AuthService>().currentUser?.uid;
    if (uid == null) return;

    try {
      // 獲取今日事件
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final tomorrow = today.add(const Duration(days: 1));

      // 使用 DataPathService 獲取用戶events集合
      final eventsCollection = await DataPathService.instance.getUserEventsCollection(uid);

      // 今日事件 - 只查詢活躍事件
      final todayQuery = await eventsCollection
          .where('scheduledStartTime', isGreaterThanOrEqualTo: Timestamp.fromDate(today.toUtc()))
          .where('scheduledStartTime', isLessThan: Timestamp.fromDate(tomorrow.toUtc()))
          .orderBy('scheduledStartTime')
          .get();

      setState(() {
        _todayEvents = todayQuery.docs
            .map(EventModel.fromDoc)
            .where((event) => event.isActive) // 只顯示活躍事件
            .toList();
        
        // 檢查是否有未完成的任務（第一題條件）
        _hasIncompleteTasks = _todayEvents.any((event) => !event.isDone);
        
        // 檢查是否有今天開始但沒有完成的任務（第二題條件）
        _hasDelayedTasks = _todayEvents.any((event) {
          return event.actualStartTime != null && !event.isDone;
        });
        
        // 檢查是否有完成的閱讀任務（第三題條件）
        _hasCompletedReadingTasks = _todayEvents.any((event) {
          return event.isDone && 
                 (event.title.toLowerCase().contains('reading') || 
                  event.title.toLowerCase().contains('閱讀') ||
                  event.title.toLowerCase().contains('dyn'));
        });
        
        // 檢查是否有完成的單字任務（第四題條件）
        _hasCompletedVocabTasks = _todayEvents.any((event) {
          return event.isDone && 
                 (event.title.toLowerCase().contains('vocab') || 
                  event.title.toLowerCase().contains('單字') ||
                  event.title.toLowerCase().contains('vocabulary'));
        });
        
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('載入數據失敗: $e')),
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
      
      // 獲取當前日期的組別
      final groupName = await ExperimentConfigService.instance.getDateGroup(uid, today);
      
      final report = DailyReportModel(
        id: const Uuid().v4(),
        uid: uid,
        date: today,
        group: groupName,
        delayReasons: _selectedDelayReasons.toList(),
        delayOtherReason: _delayOtherController.text.trim().isEmpty 
            ? null : _delayOtherController.text.trim(),
        incompleteReasons: _selectedIncompleteReasons.toList(),
        incompleteOtherReason: _incompleteOtherController.text.trim().isEmpty 
            ? null : _incompleteOtherController.text.trim(),
        readingHelpfulness: _readingHelpfulness,
        vocabHelpfulness: _vocabHelpfulness,
        overallSatisfaction: _overallSatisfaction,
        tomorrowConfidence: _tomorrowConfidence,
        notes: _notesController.text.trim().isEmpty 
            ? null : _notesController.text.trim(),
        createdAt: now,
      );

      // 保存到Firebase
      final dateString = '${today.year}${today.month.toString().padLeft(2, '0')}${today.day.toString().padLeft(2, '0')}';
      final dailyReportCollection = await DataPathService.instance.getUserDailyReportCollection(uid, dateString);
      await dailyReportCollection.doc(report.id).set(report.toFirestore());

      // 注意：每日報告通知已由 AuthService 統一管理，此處不需要重新排定

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('每日報告已保存！'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('保存失敗: $e'),
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
                    children: _buildDynamicQuestions(),
                  ),
                ),
    );
  }

  /// 動態生成問題列表，按條件顯示並重新編號
  List<Widget> _buildDynamicQuestions() {
    final List<Widget> questions = [];
    int questionNumber = 1;

    // 第一題：只有當日任務未完成才需要寫
    if (_hasIncompleteTasks) {
      questions.add(_buildQuestion1DelayReasons(questionNumber));
      questions.add(const SizedBox(height: 24));
      questionNumber++;
    }

    // 第二題：今天開始但沒有完成任務的原因
    if (_hasDelayedTasks) {
      questions.add(_buildQuestion2IncompleteReasons(questionNumber));
      questions.add(const SizedBox(height: 24));
      questionNumber++;
    }

    // 第三題：在對應任務有完成時才需要寫（閱讀任務）
    if (_hasCompletedReadingTasks) {
      questions.add(_buildQuestion3ReadingHelpfulness(questionNumber));
      questions.add(const SizedBox(height: 24));
      questionNumber++;
    }

    // 第四題：在對應任務有完成時才需要寫（單字任務）
    if (_hasCompletedVocabTasks) {
      questions.add(_buildQuestion4VocabHelpfulness(questionNumber));
      questions.add(const SizedBox(height: 24));
      questionNumber++;
    }

    // 第五題：總是顯示
    questions.add(_buildQuestion5OverallSatisfaction(questionNumber));
    questions.add(const SizedBox(height: 24));
    questionNumber++;

    // 第六題：總是顯示
    questions.add(_buildQuestion6TomorrowConfidence(questionNumber));
    questions.add(const SizedBox(height: 24));
    questionNumber++;

    // 第七題：總是顯示
    questions.add(_buildQuestion7Notes(questionNumber));
    questions.add(const SizedBox(height: 32));

    // 提交按鈕
    questions.add(_buildSubmitButton());

    return questions;
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

  Widget _buildQuestion1DelayReasons(int questionNumber) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$questionNumber. 今天未完成任務的原因（多選）',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            
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

  Widget _buildQuestion2IncompleteReasons(int questionNumber) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$questionNumber. 今天開始但沒有完成任務的原因？（多選）',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            
            ..._buildIncompleteReasonOptions(),
            
            if (_selectedIncompleteReasons.contains('other')) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _incompleteOtherController,
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

  List<Widget> _buildIncompleteReasonOptions() {
    final reasons = [
      {'id': 'time_ran_out', 'text': '時間用完了'},
      {'id': 'too_difficult', 'text': '任務比預期困難'},
      {'id': 'interrupted', 'text': '中途被其他事情打斷'},
      {'id': 'lost_motivation', 'text': '缺乏動力繼續'},
      {'id': 'technical_issues', 'text': '技術問題/系統錯誤'},
      {'id': 'other', 'text': '其他'},
    ];

    return reasons.map((reason) => CheckboxListTile(
      title: Text(reason['text']!),
      value: _selectedIncompleteReasons.contains(reason['id']),
      onChanged: (bool? value) {
        setState(() {
          if (value == true) {
            _selectedIncompleteReasons.add(reason['id']!);
          } else {
            _selectedIncompleteReasons.remove(reason['id']!);
          }
        });
      },
      dense: true,
    )).toList();
  }

  Widget _buildQuestion3ReadingHelpfulness(int questionNumber) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$questionNumber. 今天的文章閱讀對我來說是有趣、有幫助的',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              '1 = 非常不同意，5 = 非常同意',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            
            _buildRatingScale(_readingHelpfulness, (rating) {
              setState(() => _readingHelpfulness = rating);
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildQuestion4VocabHelpfulness(int questionNumber) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$questionNumber. 完成今天單字任務對我學業有幫助',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              '1 = 非常不同意，5 = 非常同意',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            
            _buildRatingScale(_vocabHelpfulness, (rating) {
              setState(() => _vocabHelpfulness = rating);
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildQuestion5OverallSatisfaction(int questionNumber) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$questionNumber. 對今天自己學習的表現的感受',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              '1 = 非常不滿意，5 = 非常滿意',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            
            _buildRatingScale(_overallSatisfaction, (rating) {
              setState(() => _overallSatisfaction = rating);
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildQuestion6TomorrowConfidence(int questionNumber) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$questionNumber. 我有能力在預定時間內完成明天的學習任務',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              '1 = 非常不同意，5 = 非常同意',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            
            _buildRatingScale(_tomorrowConfidence, (rating) {
              setState(() => _tomorrowConfidence = rating);
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildQuestion7Notes(int questionNumber) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$questionNumber. 有什麼狀況或心得與任務有關想紀錄？',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              '例如：突發事件、系統錯誤、學習心得等',
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

  /// 建立評分量表組件
  Widget _buildRatingScale(int currentRating, Function(int) onRatingChanged) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: List.generate(5, (index) {
            final rating = index + 1;
            return GestureDetector(
              onTap: () => onRatingChanged(rating),
              child: Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: currentRating >= rating ? Colors.amber : Colors.grey[300],
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.star, color: Colors.white),
              ),
            );
          }),
        ),
        const SizedBox(height: 8),
        Text(
          '評分: $currentRating / 5',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ],
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
}