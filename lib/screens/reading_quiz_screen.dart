import 'package:flutter/material.dart';
import '../models/event_model.dart';
import '../models/reading_content_model.dart';
import '../models/enums.dart';
import '../services/reading_analytics_service.dart';
import '../services/calendar_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/analytics_service.dart';
import '../services/experiment_config_service.dart';

class ReadingQuizScreen extends StatefulWidget {
  final List<ReadingQuestion> questions;
  final EventModel event;
  const ReadingQuizScreen({super.key, required this.questions, required this.event});

  @override
  State<ReadingQuizScreen> createState() => _ReadingQuizScreenState();
}

class _ReadingQuizScreenState extends State<ReadingQuizScreen> with WidgetsBindingObserver {
  int _idx = 0;
  String? _selected;
  int _correct = 0;
  bool _showResult = false;
  late final List<String> _userAnswers;
  final ReadingAnalyticsService _analyticsService = ReadingAnalyticsService();
  final CalendarService _calendarService = CalendarService.instance;
  bool _reviewEndedLogged = false;
  DateTime? _quizStartTime; // 記錄測驗開始時間
  String? _currentUserId; // 當前用戶ID
  bool _isQuizActive = true; // 測驗是否處於活躍狀態

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this); // 添加生命週期觀察者
    _currentUserId = FirebaseAuth.instance.currentUser?.uid;
    _userAnswers = List.filled(widget.questions.length, '');
    _quizStartTime = DateTime.now(); // 記錄測驗開始時間
    _startQuiz(); // 開始測驗追蹤
  }

  /// 開始測驗追蹤
  Future<void> _startQuiz() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await _analyticsService.startQuiz(
        uid: user.uid,
        eventId: widget.event.id,
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this); // 移除生命週期觀察者
    // 頁面銷毀時，視為結束複習
    _endReviewIfAny();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      // App進入後台或非活躍狀態，暫停測驗任務
      _isQuizActive = false;
      _pauseQuizEvent();
    } else if (state == AppLifecycleState.resumed) {
      // App恢復活躍狀態，如果任務被暫停則繼續
      _isQuizActive = true;
      _resumeQuizEvent();
    }
  }

  void _select(String letter) {
    setState(() {
      _selected = letter;
      _userAnswers[_idx] = letter;
    });
  }

  Future<void> _finish() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      // 獲取使用者分組
      final isControlGroup = await ExperimentConfigService.instance.isControlGroup(user.uid);
      final userGroup = isControlGroup ? 'control' : 'experiment';

      // 簡單計分：與 answerLetter 比較
      _correct = 0;
      for (var i = 0; i < widget.questions.length; i++) {
        if (_userAnswers[i] == widget.questions[i].answerLetter) _correct++;
      }
      // 計算測驗時間
      int quizTimeMs = 0;
      if (_quizStartTime != null) {
        quizTimeMs = DateTime.now().difference(_quizStartTime!).inMilliseconds;
      }
      
      // 記錄 quiz_complete 事件
      AnalyticsService().logQuizComplete(
        userGroup: userGroup,
        quizType: 'reading',
        eventId: widget.event.id,
        score: (widget.questions.isNotEmpty ? (_correct / widget.questions.length * 100).round() : 0),
        correctAnswers: _correct,
        totalQuestions: widget.questions.length,
        durationSeconds: quizTimeMs ~/ 1000,
      );

      await _analyticsService.completeQuiz(
        uid: user.uid,
        eventId: widget.event.id,
        correctAnswers: _correct,
        totalQuestions: widget.questions.length,
        quizTimeMs: quizTimeMs, // 傳遞測驗時間
      );
      
      // 记录事件完成
      await ExperimentEventHelper.recordEventCompletion(
        uid: user.uid,
        eventId: widget.event.id,
        chatId: widget.event.chatId,
      );
    }
    if (!mounted) return;
    await _endReviewIfAny();
    setState(() => _showResult = true);
  }

  Future<void> _endReviewIfAny() async {
    if (_reviewEndedLogged) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      try {
        await ExperimentEventHelper.recordReviewEnd(uid: uid, eventId: widget.event.id);
      } catch (_) {}
    }
    _reviewEndedLogged = true;
  }

  /// 暫停測驗任務
  Future<void> _pauseQuizEvent() async {
    if (_currentUserId != null && _isQuizActive) {
      try {
        await _calendarService.stopEvent(_currentUserId!, widget.event);
        print('測驗任務已暫停: ${widget.event.title}');
      } catch (e) {
        print('暫停測驗任務失敗: $e');
      }
    }
  }

  /// 恢復測驗任務
  Future<void> _resumeQuizEvent() async {
    if (_currentUserId != null) {
      try {
        // 檢查任務是否為暫停狀態，如果是則繼續
        if (widget.event.status == TaskStatus.paused) {
          await _calendarService.continueEvent(_currentUserId!, widget.event);
          print('測驗任務已恢復: ${widget.event.title}');
        }
      } catch (e) {
        print('恢復測驗任務失敗: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_showResult) {
      final score = (_correct / (widget.questions.isEmpty ? 1 : widget.questions.length) * 100).round();
      return Scaffold(
        appBar: AppBar(
        title: const Text('閱讀測驗結果'),
        automaticallyImplyLeading: false,
      ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('$score 分', style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Text('正確 $_correct / ${widget.questions.length}'),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
                child: const Text('返回首頁'),
              ),
            ],
          ),
        ),
      );
    }

    final q = widget.questions[_idx];
    return Scaffold(
      appBar: AppBar(
        title: Text('閱讀測驗 ${_idx + 1}/${widget.questions.length}'),
        automaticallyImplyLeading: false,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(q.stem, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, height: 1.4)),
            const SizedBox(height: 16),
            ...q.options.asMap().entries.map((e) {
              final letter = String.fromCharCode(65 + e.key); // A B C D
              final opt = e.value;
              final selected = _selected == letter;
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                child: InkWell(
                  onTap: () => _select(letter),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      border: Border.all(color: selected ? Colors.blue : Colors.grey.shade300, width: 2),
                      borderRadius: BorderRadius.circular(12),
                      color: selected ? Colors.blue.shade50 : Colors.white,
                    ),
                    child: Row(children: [
                      CircleAvatar(radius: 14, backgroundColor: selected ? Colors.blue : Colors.grey.shade300, child: Text(letter, style: TextStyle(color: selected ? Colors.white : Colors.black54))),
                      const SizedBox(width: 12),
                      Expanded(child: Text(opt, style: TextStyle(color: selected ? Colors.blue.shade800 : Colors.black87))),
                    ]),
                  ),
                ),
              );
            }).toList(),
            const Spacer(),
            Row(children: [
              if (_idx > 0)
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => setState(() { _idx--; _selected = _userAnswers[_idx].isEmpty ? null : _userAnswers[_idx]; }),
                    child: const Text('上一題'),
                  ),
                ),
              if (_idx > 0) const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: _selected == null ? null : () {
                    if (_idx < widget.questions.length - 1) {
                      setState(() { _idx++; _selected = _userAnswers[_idx].isEmpty ? null : _userAnswers[_idx]; });
                    } else {
                      _finish();
                    }
                  },
                  child: Text(_idx == widget.questions.length - 1 ? '完成測驗' : '下一題'),
                ),
              ),
            ])
          ],
        ),
      ),
    );
  }
}

