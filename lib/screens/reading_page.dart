import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/event_model.dart';
import '../models/reading_content_model.dart';
import '../services/reading_service.dart';
import '../services/reading_analytics_service.dart';
import '../services/calendar_service.dart';
import '../models/enums.dart';
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

class _ReadingPageState extends State<ReadingPage> with WidgetsBindingObserver {
  List<ReadingContent> _contents = [];
  bool _isLoading = true;
  final PageController _pageController = PageController();
  int _currentPage = 0;
  final ReadingService _readingService = ReadingService();
  final ReadingAnalyticsService _analyticsService = ReadingAnalyticsService();
  final CalendarService _calendarService = CalendarService.instance;
  
  // 数据收集相关
  Map<int, DateTime> _cardStartTimes = {};
  String? _currentUserId;
  bool _isAppActive = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _currentUserId = FirebaseAuth.instance.currentUser?.uid;
    _loadContent();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pageController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      // App进入后台或非活跃状态，停止计时并暂停事件
      _isAppActive = false;
      _recordCurrentCardDwellTime();
      _pauseEvent(); // 暂停事件
    } else if (state == AppLifecycleState.resumed) {
      // App恢复活跃状态，重新开始计时
      _isAppActive = true;
      _cardStartTimes[_currentPage] = DateTime.now();
      
      // 如果事件是暂停状态，继续事件
      if (widget.event.status == TaskStatus.paused) {
        _continueEvent();
      }
    }
  }

  void _recordCurrentCardDwellTime() {
    if (_currentUserId != null && _cardStartTimes.containsKey(_currentPage) && _isAppActive) {
      final endTime = DateTime.now();
      final startTime = _cardStartTimes[_currentPage]!;
      final dwellTimeMs = endTime.difference(startTime).inMilliseconds;
      
      _analyticsService.recordCardDwellTime(
        uid: _currentUserId!,
        eventId: widget.event.id,
        cardIndex: _currentPage,
        dwellTimeMs: dwellTimeMs,
      );
    }
  }

  Future<void> _pauseEvent() async {
    if (_currentUserId != null) {
      try {
        await _calendarService.stopEvent(_currentUserId!, widget.event);
        print('事件已暫停: ${widget.event.title}');
      } catch (e) {
        print('暫停事件失敗: $e');
      }
    }
  }

  Future<void> _continueEvent() async {
    if (_currentUserId != null) {
      try {
        await _calendarService.continueEvent(_currentUserId!, widget.event);
        print('事件已繼續: ${widget.event.title}');
      } catch (e) {
        print('繼續事件失敗: $e');
      }
    }
  }

  Future<void> _handleBackPress() async {
    // 记录当前卡片的停留时间
    _recordCurrentCardDwellTime();
    
    // 暂停事件
    await _pauseEvent();
    
    // 显示确认对话框
    final shouldExit = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('離開閱讀'),
          content: const Text('您確定要離開閱讀學習嗎？學習進度已保存，事件已暫停。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('確定'),
            ),
          ],
        );
      },
    ) ?? false;
    
    if (shouldExit && mounted) {
      Navigator.of(context).pop();
    }
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
      
      // 开始阅读会话数据收集
      if (_currentUserId != null && contents.isNotEmpty) {
        await _analyticsService.startReadingSession(
          uid: _currentUserId!,
          eventId: widget.event.id,
          contents: contents,
        );
        // 记录第一张卡片的开始时间
        _cardStartTimes[0] = DateTime.now();
      }
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

  void _startQuiz() async {
    // 记录最后一张卡片的停留时间
    if (_currentUserId != null && _cardStartTimes.containsKey(_currentPage) && _isAppActive) {
      final endTime = DateTime.now();
      final startTime = _cardStartTimes[_currentPage]!;
      final dwellTimeMs = endTime.difference(startTime).inMilliseconds;
      
      await _analyticsService.recordCardDwellTime(
        uid: _currentUserId!,
        eventId: widget.event.id,
        cardIndex: _currentPage,
        dwellTimeMs: dwellTimeMs,
      );
    }
    
    // 开始测验数据收集
    if (_currentUserId != null) {
      await _analyticsService.startQuiz(
        uid: _currentUserId!,
        eventId: widget.event.id,
      );
    }
    
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
        title: Text('科普文章 - ${widget.event.title}'),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => _handleBackPress(),
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : _contents.isEmpty
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
                        'no content',
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    // 页面指示器
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(
                          _contents.length,
                          (index) => Container(
                            width: 8,
                            height: 8,
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _currentPage == index
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
                            '${_currentPage + 1} / ${_contents.length}',
                            style: const TextStyle(
                              fontSize: 14,
                              color: Colors.grey,
                            ),
                          ),
                          Text(
                            '左右滑动切换',
                            style: const TextStyle(
                              fontSize: 14,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    // 单字卡内容
                    Expanded(
                      child: PageView.builder(
                        controller: _pageController,
                        onPageChanged: (index) {
                          // 记录前一张卡片的停留时间
                          if (_currentUserId != null && _cardStartTimes.containsKey(_currentPage) && _isAppActive) {
                            final endTime = DateTime.now();
                            final startTime = _cardStartTimes[_currentPage]!;
                            final dwellTimeMs = endTime.difference(startTime).inMilliseconds;
                            
                            _analyticsService.recordCardDwellTime(
                              uid: _currentUserId!,
                              eventId: widget.event.id,
                              cardIndex: _currentPage,
                              dwellTimeMs: dwellTimeMs,
                            );
                          }
                          
                          setState(() {
                            _currentPage = index;
                          });
                          
                          // 记录新卡片的开始时间
                          _cardStartTimes[index] = DateTime.now();
                        },
                        itemCount: _contents.length,
                        itemBuilder: (context, index) {
                          final content = _contents[index];
                          return _buildCard(content, index);
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

  Widget _buildCard(ReadingContent content, int index) {
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
                // 标题
                Text(
                  content.title,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                    height: 1.3,
                  ),
                ),
                
                const SizedBox(height: 24),
                
                // 内容
                Expanded(
                  child: SingleChildScrollView(
                    child: Text(
                      content.content,
                      style: const TextStyle(
                        fontSize: 16,
                        height: 1.8,
                        color: Colors.black54,
                      ),
                    ),
                  ),
                ),
                
                const SizedBox(height: 20),
                
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