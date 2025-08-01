import 'package:flutter/material.dart';
import '../models/event_model.dart';
import '../models/vocab_content_model.dart';

import '../services/vocab_analytics_service.dart';
import 'package:firebase_auth/firebase_auth.dart';

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

class _VocabQuizScreenState extends State<VocabQuizScreen> {
  int _currentQuestionIndex = 0;
  String? _selectedAnswer;
  int _correctAnswers = 0;
  bool _showResult = false;
  List<String> _userAnswers = [];
  final VocabAnalyticsService _analyticsService = VocabAnalyticsService();

  @override
  void initState() {
    super.initState();
    _userAnswers = List.filled(widget.questions.length, '');
  }

  void _selectAnswer(String answer) {
    setState(() {
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
        // 记录测验完成数据
        await _analyticsService.completeQuiz(
          uid: user.uid,
          eventId: widget.event.id,
          correctAnswers: _correctAnswers,
          totalQuestions: widget.questions.length,
        );
        
        // 记录事件完成
        await ExperimentEventHelper.recordEventCompletion(
          uid: user.uid,
          eventId: widget.event.id,
          chatId: widget.event.chatId,
        );
      }
      
      // 跳回home screen
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e) {
      print('完成測驗時出錯: $e');
      // 即使出错也要跳回home screen
      Navigator.of(context).popUntil((route) => route.isFirst);
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
                  // 单词
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
                          '單字：',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue.shade700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          currentQuestion.word,
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue,
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // 题目
                  Text(
                    '請選擇正確的定義：',
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
                    final isSelected = _selectedAnswer == optionLetter;
                    
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: InkWell(
                        onTap: () => _selectAnswer(optionLetter),
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