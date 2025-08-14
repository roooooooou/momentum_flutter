import 'package:flutter/material.dart';
import '../models/vocab_content_model.dart';
import '../models/event_model.dart';
import '../models/enums.dart';
import '../services/vocab_analytics_service.dart';
import 'package:firebase_auth/firebase_auth.dart';

class VocabScreen extends StatefulWidget {
  final List<VocabContent> contents;
  final EventModel event;
  
  const VocabScreen({
    super.key,
    required this.contents,
    required this.event,
  });

  @override
  State<VocabScreen> createState() => _VocabScreenState();
}

class _VocabScreenState extends State<VocabScreen> {
  int _currentWordIndex = 0;
  final PageController _pageController = PageController();
  final VocabAnalyticsService _analyticsService = VocabAnalyticsService();
  
  // 数据收集相关
  Map<int, DateTime> _wordStartTimes = {};
  String? _currentUserId;
  bool _isAppActive = true;
  bool _showListView = false; // 控制列表视图

  @override
  void initState() {
    super.initState();
    _currentUserId = FirebaseAuth.instance.currentUser?.uid;
    _wordStartTimes[0] = DateTime.now();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _toggleView() {
    setState(() {
      _showListView = !_showListView;
    });
  }

  void _selectWord(int index) {
    setState(() {
      _currentWordIndex = index;
      _showListView = false;
    });
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  Future<void> _completeTask() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
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
      print('完成任務時出錯: $e');
      // 即使出错也要跳回home screen
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('單字學習 - ${widget.event.title}'),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
        actions: [
          // 切换视图按钮
          IconButton(
            icon: Icon(_showListView ? Icons.view_agenda : Icons.list),
            onPressed: _toggleView,
            tooltip: _showListView ? '切換到學習視圖' : '切換到列表視圖',
          ),
        ],
      ),
      body: _showListView
          ? _buildListView()
          : _buildLearningView(),
      bottomNavigationBar: !_showListView
          ? Container(
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
                onPressed: _completeTask,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  '完成任務',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildListView() {
    return Column(
      children: [
        // 列表标题
        Container(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(Icons.translate, color: Colors.green),
              const SizedBox(width: 8),
              Text(
                '單字列表 (${widget.contents.length}個)',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        
        // 单字列表
        Expanded(
          child: ListView.builder(
            itemCount: widget.contents.length,
            itemBuilder: (context, index) {
              final content = widget.contents[index];
              final isSelected = index == _currentWordIndex;
              
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                elevation: isSelected ? 4 : 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: isSelected 
                      ? BorderSide(color: Colors.green, width: 2)
                      : BorderSide.none,
                ),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: isSelected ? Colors.green : Colors.grey.shade300,
                    child: Text(
                      '${index + 1}',
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.grey.shade600,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  title: Text(
                    content.word,
                    style: TextStyle(
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      color: isSelected ? Colors.green.shade800 : Colors.black87,
                      fontSize: 18,
                    ),
                  ),
                  subtitle: Text(
                    content.definition,
                    style: TextStyle(
                      color: isSelected ? Colors.green.shade600 : Colors.grey.shade600,
                    ),
                  ),
                  trailing: isSelected 
                      ? const Icon(Icons.check_circle, color: Colors.green)
                      : const Icon(Icons.arrow_forward_ios, color: Colors.grey),
                  onTap: () => _selectWord(index),
                ),
              );
            },
          ),
        ),
        
        // 完成任务按钮
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          child: ElevatedButton(
            onPressed: _completeTask,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              '完成任務',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLearningView() {
    return Column(
      children: [
        // 页面指示器
        Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              widget.contents.length,
              (index) => Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _currentWordIndex == index
                      ? Colors.green
                      : Colors.grey.shade300,
                ),
              ),
            ),
          ),
        ),
        
        // 页面计数器
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${_currentWordIndex + 1} / ${widget.contents.length}',
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.grey,
                ),
              ),
              Text(
                '左右滑動切換',
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
        ),
        
        // 单字卡片内容
        Expanded(
          child: PageView.builder(
            controller: _pageController,
            onPageChanged: (index) {
              setState(() {
                _currentWordIndex = index;
              });
            },
            itemCount: widget.contents.length,
            itemBuilder: (context, index) {
              final content = widget.contents[index];
              return _buildWordCard(content, index);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildWordCard(VocabContent content, int index) {
    return Container(
      margin: const EdgeInsets.all(16),
      child: Card(
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.green.shade50,
                Colors.white,
                Colors.blue.shade50,
              ],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 单字
                Center(
                  child: Text(
                    content.word,
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                ),
                
                const SizedBox(height: 16),
                
                // 音标（暂时不显示，因为JSON中没有这个字段）
                // if (content.phonetic.isNotEmpty)
                //   Center(
                //     child: Text(
                //       content.phonetic,
                //       style: const TextStyle(
                //         fontSize: 18,
                //         color: Colors.grey,
                //         fontStyle: FontStyle.italic,
                //       ),
                //     ),
                //   ),
                
                const SizedBox(height: 24),
                
                // 词性（暂时不显示，因为JSON中没有这个字段）
                // if (content.partOfSpeech.isNotEmpty)
                //   Container(
                //     padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                //     decoration: BoxDecoration(
                //       color: Colors.green.shade100,
                //       borderRadius: BorderRadius.circular(16),
                //     ),
                //     child: Text(
                //       content.partOfSpeech,
                //       style: TextStyle(
                //         fontSize: 14,
                //         color: Colors.green.shade800,
                //         fontWeight: FontWeight.w500,
                //       ),
                //     ),
                //   ),
                
                const SizedBox(height: 16),
                
                // 意思
                Text(
                  '意思：',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                
                const SizedBox(height: 8),
                
                Text(
                  content.definition,
                  style: const TextStyle(
                    fontSize: 18,
                    height: 1.5,
                    color: Colors.black54,
                  ),
                ),
                
                const SizedBox(height: 20),
                
                // 例句
                if (content.example.isNotEmpty) ...[
                  Text(
                    '例句：',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  
                  const SizedBox(height: 8),
                  
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Text(
                      content.example,
                      style: const TextStyle(
                        fontSize: 16,
                        height: 1.5,
                        color: Colors.black54,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
                
                const Spacer(),
                
                // 底部装饰
                Container(
                  width: double.infinity,
                  height: 4,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(2),
                    gradient: LinearGradient(
                      colors: [
                        Colors.green.shade300,
                        Colors.blue.shade300,
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
} 