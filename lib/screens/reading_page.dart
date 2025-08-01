import 'package:flutter/material.dart';
import '../models/event_model.dart';
import '../models/reading_content_model.dart';
import '../services/reading_service.dart';
import 'quiz_screen.dart';

class ReadingPage extends StatefulWidget {
  final EventModel event;
  
  const ReadingPage({
    super.key,
    required this.event,
  });

  @override
  State<ReadingPage> createState() => _ReadingPageState();
}

class _ReadingPageState extends State<ReadingPage> {
  List<ReadingContent> _contents = [];
  bool _isLoading = true;
  Set<int> _expandedCards = {};
  final ReadingService _readingService = ReadingService();

  @override
  void initState() {
    super.initState();
    _loadContent();
  }

  Future<void> _loadContent() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // 使用event中的dayNumber加载冷知识内容
      final dayNumber = widget.event.dayNumber ?? 0;
      final contents = await _readingService.loadDailyContent(dayNumber);
      setState(() {
        _contents = contents;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      // 显示错误提示
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载内容失败: $e')),
        );
      }
    }
  }

  void _toggleCard(int index) {
    setState(() {
      if (_expandedCards.contains(index)) {
        _expandedCards.remove(index);
      } else {
        _expandedCards.add(index);
      }
    });
  }

  void _startQuiz() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => QuizScreen(
          contents: _contents,
          event: widget.event,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('阅读学习 - ${widget.event.title}'),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : Column(
              children: [
                Expanded(
                  child: _contents.isEmpty
                      ? const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.article_outlined,
                                size: 64,
                                color: Colors.grey,
                              ),
                              SizedBox(height: 16),
                              Text(
                                '暂无内容',
                                style: TextStyle(
                                  fontSize: 18,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _contents.length,
                          itemBuilder: (context, index) {
                            final content = _contents[index];
                            final isExpanded = _expandedCards.contains(index);
                            
                            return Card(
                              margin: const EdgeInsets.only(bottom: 16),
                              elevation: 4,
                              child: InkWell(
                                onTap: () => _toggleCard(index),
                                borderRadius: BorderRadius.circular(12),
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              content.title,
                                              style: const TextStyle(
                                                fontSize: 18,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.black87,
                                              ),
                                            ),
                                          ),
                                          Icon(
                                            isExpanded 
                                                ? Icons.keyboard_arrow_up 
                                                : Icons.keyboard_arrow_down,
                                            color: Colors.grey,
                                          ),
                                        ],
                                      ),
                                      if (isExpanded) ...[
                                        const SizedBox(height: 16),
                                        Container(
                                          width: double.infinity,
                                          height: 1,
                                          color: Colors.grey.shade300,
                                        ),
                                        const SizedBox(height: 16),
                                        Text(
                                          content.content,
                                          style: const TextStyle(
                                            fontSize: 16,
                                            height: 1.6,
                                            color: Colors.black54,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
                // Start Quiz 按钮
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 4,
                        offset: const Offset(0, -2),
                      ),
                    ],
                  ),
                  child: ElevatedButton(
                    onPressed: _contents.isNotEmpty ? _startQuiz : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      '开始测验',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
} 