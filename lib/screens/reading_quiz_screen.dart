import 'package:flutter/material.dart';
import '../models/event_model.dart';
import '../models/reading_content_model.dart';
import '../services/reading_analytics_service.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ReadingQuizScreen extends StatefulWidget {
  final List<ReadingQuestion> questions;
  final EventModel event;
  const ReadingQuizScreen({super.key, required this.questions, required this.event});

  @override
  State<ReadingQuizScreen> createState() => _ReadingQuizScreenState();
}

class _ReadingQuizScreenState extends State<ReadingQuizScreen> {
  int _idx = 0;
  String? _selected;
  int _correct = 0;
  bool _showResult = false;
  late final List<String> _userAnswers;
  final ReadingAnalyticsService _analyticsService = ReadingAnalyticsService();

  @override
  void initState() {
    super.initState();
    _userAnswers = List.filled(widget.questions.length, '');
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
      // 簡單計分：與 answerLetter 比較
      _correct = 0;
      for (var i = 0; i < widget.questions.length; i++) {
        if (_userAnswers[i] == widget.questions[i].answerLetter) _correct++;
      }
      await _analyticsService.completeQuiz(
        uid: user.uid,
        eventId: widget.event.id,
        correctAnswers: _correct,
        totalQuestions: widget.questions.length,
      );
    }
    if (!mounted) return;
    setState(() => _showResult = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_showResult) {
      final score = (_correct / (widget.questions.isEmpty ? 1 : widget.questions.length) * 100).round();
      return Scaffold(
        appBar: AppBar(title: const Text('閱讀測驗結果')),
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
        title: Text('閱讀測驗 ${_idx + 1}/${widget.questions.length}')
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

