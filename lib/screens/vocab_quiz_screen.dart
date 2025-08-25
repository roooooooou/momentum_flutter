import 'package:flutter/material.dart';
import '../models/event_model.dart';
import '../models/vocab_content_model.dart';
import '../models/enums.dart';
import '../services/vocab_analytics_service.dart';
import '../services/calendar_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/analytics_service.dart';
import '../services/experiment_config_service.dart';

class VocabQuizScreen extends StatefulWidget {
  final List<VocabContent> questions;
  final EventModel event;
  
  const VocabQuizScreen({
    super.key,
    required this.questions,
    required this.event,
  });

  @override
  State<VocabQuizScreen> createState() => _VocabQuizScreenState();
}

class _VocabQuizScreenState extends State<VocabQuizScreen> with WidgetsBindingObserver {
  int _currentQuestionIndex = 0;
  String? _selectedAnswer;
  int _correctAnswers = 0;
  bool _showResult = false;
  List<String> _userAnswers = [];
  final VocabAnalyticsService _analyticsService = VocabAnalyticsService();
  final CalendarService _calendarService = CalendarService.instance;
  String? _attemptSessionId;
  bool _reviewEndedLogged = false; // 自動結束複習的保險旗標
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
    _startAttempt();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this); // 移除生命週期觀察者
    // 頁面銷毀時，視為複習結束
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

  Future<void> _startAttempt() async {
    // no-op: 新儲存路徑不需要建立 attempts doc
  }

  void _selectAnswer(String answer) {
    setState(() {
      // 存選項文字本身，方便與正確答案（文字）比對
      _selectedAnswer = answer;
      _userAnswers[_currentQuestionIndex] = answer;
    });
  }

  void _nextQuestion() {
    if (_selectedAnswer != null) {
      // 检查答案是否正确
      final currentQuestion = widget.questions[_currentQuestionIndex];
      if (_selectedAnswer == currentQuestion.answer) {
        _correctAnswers++;
      }

      if (_currentQuestionIndex < widget.questions.length - 1) {
        setState(() {
          _currentQuestionIndex++;
          _selectedAnswer = _userAnswers[_currentQuestionIndex].isEmpty 
              ? null 
              : _userAnswers[_currentQuestionIndex];
        });
      } else {
        // 测验完成
        setState(() {
          _showResult = true;
        });
      }
    }
  }

  void _previousQuestion() {
    if (_currentQuestionIndex > 0) {
      setState(() {
        _currentQuestionIndex--;
        _selectedAnswer = _userAnswers[_currentQuestionIndex].isEmpty 
            ? null 
            : _userAnswers[_currentQuestionIndex];
      });
    }
  }

  void _restartQuiz() {
    setState(() {
      _currentQuestionIndex = 0;
      _selectedAnswer = null;
      _correctAnswers = 0;
      _showResult = false;
      _userAnswers = List.filled(widget.questions.length, '');
    });
  }

  void _finishQuiz() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        // 獲取使用者分組
        final isControlGroup = await ExperimentConfigService.instance.isControlGroup(user.uid);
        final userGroup = isControlGroup ? 'control' : 'experiment';

        // 儲存測驗結果（答案詳情 + 分數）
        final answers = <Map<String, dynamic>>[];
        for (var i = 0; i < widget.questions.length; i++) {
          answers.add({
            'index': i,
            'question': widget.questions[i].example, // 我們把句子放在 example 欄位
            'options': widget.questions[i].options,
            'answer': widget.questions[i].answer,
            'userAnswer': _userAnswers[i],
            'isCorrect': _userAnswers[i] == widget.questions[i].answer,
          });
        }
        // 與閱讀一致：以週為單位命名 vocab_w{week}
        final dayNum = widget.event.dayNumber;
        final week = (dayNum != null && dayNum > 0) ? (dayNum <= 7 ? 1 : 2) : 0;
        final quizId = 'vocab_w$week';
        // 計算測驗時間
        int quizTimeMs = 0;
        if (_quizStartTime != null) {
          quizTimeMs = DateTime.now().difference(_quizStartTime!).inMilliseconds;
        }
        
        // 記錄 quiz_complete 事件
        AnalyticsService().logQuizComplete(
          userGroup: userGroup,
          quizType: 'vocab',
          eventId: widget.event.id,
          score: (widget.questions.isNotEmpty ? (_correctAnswers / widget.questions.length * 100).round() : 0),
          correctAnswers: _correctAnswers,
          totalQuestions: widget.questions.length,
          durationSeconds: quizTimeMs ~/ 1000,
        );

        await _analyticsService.saveVocabQuizToExperiment(
          uid: user.uid,
          quizId: quizId,
          answers: answers,
          correctAnswers: _correctAnswers,
          totalQuestions: widget.questions.length,
          eventId: widget.event.id,
          week: week,
          quizTimeMs: quizTimeMs, // 傳遞測驗時間
        );
        
        // 记录事件完成
        await ExperimentEventHelper.recordEventCompletion(
          uid: user.uid,
          eventId: widget.event.id,
          chatId: widget.event.chatId,
        );

        // 自動結束複習（若有）
        await _endReviewIfAny();
      }
      
      // 測驗完成後直接跳回首頁（任務已標記為完成）
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (e) {
      print('完成測驗時出錯: $e');
      // 即使出错也要跳回home screen（頁面仍掛載才跳轉）
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    }
  }

  /// 若是從「開始複習」進入，離開測驗頁時自動結束複習
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
      return _buildResultScreen();
    }

    final currentQuestion = widget.questions[_currentQuestionIndex];
    final progress = (_currentQuestionIndex + 1) / widget.questions.length;

    return Scaffold(
      appBar: AppBar(
        title: Text('單詞測驗 (${_currentQuestionIndex + 1}/${widget.questions.length})'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
      ),
      body: Column(
        children: [
          // 进度条
          LinearProgressIndicator(
            value: progress,
            backgroundColor: Colors.grey.shade300,
            valueColor: const AlwaysStoppedAnimation<Color>(Colors.blue),
          ),
          
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 題目敘述：固定顯示句子（sentence）
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: Column(
                      children: [
                        Text(
                          '句子：',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue.shade700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          currentQuestion.example,
                          style: const TextStyle(
                            fontSize: 18,
                            height: 1.5,
                            color: Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // 提示
                  Text(
                    '請選擇正確的單字：',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      height: 1.4,
                    ),
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // 选项
                  ...currentQuestion.options.asMap().entries.map((entry) {
                    final index = entry.key;
                    final option = entry.value;
                    final optionLetter = String.fromCharCode(97 + index); // a, b, c, d
                    final isSelected = _selectedAnswer == option;
                    
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: InkWell(
                        onTap: () => _selectAnswer(option),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: isSelected ? Colors.blue : Colors.grey.shade300,
                              width: 2,
                            ),
                            borderRadius: BorderRadius.circular(12),
                            color: isSelected ? Colors.blue.shade50 : Colors.white,
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isSelected ? Colors.blue : Colors.grey.shade300,
                                ),
                                child: Center(
                                  child: Text(
                                    optionLetter.toUpperCase(),
                                    style: TextStyle(
                                      color: isSelected ? Colors.white : Colors.grey.shade600,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  option,
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: isSelected ? Colors.blue.shade800 : Colors.black87,
                                    fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                  
                  const Spacer(),
                  
                  // 导航按钮
                  Row(
                    children: [
                      if (_currentQuestionIndex > 0)
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _previousQuestion,
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text(
                              '上一題',
                              style: TextStyle(fontSize: 16),
                            ),
                          ),
                        ),
                      if (_currentQuestionIndex > 0) const SizedBox(width: 16),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _selectedAnswer != null ? _nextQuestion : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(
                            _currentQuestionIndex == widget.questions.length - 1 
                                ? '完成測驗' 
                                : '下一題',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultScreen() {
    final score = (_correctAnswers / widget.questions.length * 100).round();
    final isExcellent = score >= 80;
    final isGood = score >= 60;
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('測驗結果'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 结果图标
            Icon(
              isExcellent ? Icons.celebration : (isGood ? Icons.thumb_up : Icons.school),
              size: 80,
              color: isExcellent ? Colors.orange : (isGood ? Colors.blue : Colors.purple),
            ),
            
            const SizedBox(height: 24),
            
            // 分数
            Text(
              '$score分',
              style: const TextStyle(
                fontSize: 48,
                fontWeight: FontWeight.bold,
                color: Colors.blue,
              ),
            ),
            
            const SizedBox(height: 16),
            
            // 评价
            Text(
              isExcellent ? '太棒了！' : (isGood ? '做的很不錯！' : '一起加油！'),
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            
            const SizedBox(height: 8),
            
            Text(
              '答對了 $_correctAnswers 題，共 ${widget.questions.length} 題',
              style: const TextStyle(
                fontSize: 16,
                color: Colors.grey,
              ),
            ),
            
            const SizedBox(height: 16),
            
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _finishQuiz,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  '完成',
                  style: TextStyle(fontSize: 18),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
} 