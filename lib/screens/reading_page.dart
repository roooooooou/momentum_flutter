import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/event_model.dart';
import '../models/reading_content_model.dart';
import '../services/reading_service.dart';
import '../services/reading_analytics_service.dart';
import '../services/calendar_service.dart';
import '../models/enums.dart';
import '../services/analytics_service.dart';
import '../services/experiment_config_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // Added for DocumentReference

class ReadingPage extends StatefulWidget {
  final EventModel event;
  final String source; // 任務來源
  
  const ReadingPage({
    super.key,
    required this.event,
    required this.source,
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
  DocumentReference? _sessionRef; // 新增：保存當前會話的引用
  Map<int, DateTime> _cardStartTimes = {};
  String? _currentUserId;
  bool _isAppActive = true;
  bool _showListView = false; // 新增：控制列表视图
  DateTime? _pageLoadTime; // 記錄頁面載入時間
  DateTime? _pauseStartTime; // 記錄暫停開始時間
  Duration _totalPausedDuration = Duration.zero; // 累計總暫停時間
  bool _sessionEnded = false; // 確保 session end 只記錄一次

  // 將 **...** 片段渲染為粗體
  List<TextSpan> _parseBoldSpans(String text, TextStyle baseStyle, TextStyle boldStyle) {
    final List<TextSpan> spans = [];
    final regex = RegExp(r'\*\*(.+?)\*\*');
    int lastIndex = 0;
    for (final match in regex.allMatches(text)) {
      if (match.start > lastIndex) {
        spans.add(TextSpan(text: text.substring(lastIndex, match.start), style: baseStyle));
      }
      final boldText = match.group(1) ?? '';
      spans.add(TextSpan(text: boldText, style: boldStyle));
      lastIndex = match.end;
    }
    if (lastIndex < text.length) {
      spans.add(TextSpan(text: text.substring(lastIndex), style: baseStyle));
    }
    return spans;
  }

  @override
  void initState() {
    super.initState();
    _pageLoadTime = DateTime.now(); // 記錄載入時間
    WidgetsBinding.instance.addObserver(this);
    _currentUserId = FirebaseAuth.instance.currentUser?.uid;
    _loadContent();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // 記錄 learning_session_end 事件
    _logEndSession();
    // 保險：視圖銷毀時結束複習（若此頁也作為複習內容使用）
    _endReviewIfAny();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _logEndSession() async {
    if (_sessionEnded) return; // 防止重複記錄
    _sessionEnded = true;

    if (_currentUserId != null && _pageLoadTime != null) {
      final isControlGroup = await ExperimentConfigService.instance.isControlGroup(_currentUserId!);
      final userGroup = isControlGroup ? 'control' : 'experiment';
      final totalDuration = DateTime.now().difference(_pageLoadTime!);
      final activeDuration = totalDuration - _totalPausedDuration;
      final durationInSeconds = activeDuration.inSeconds > 0 ? activeDuration.inSeconds : 0;

      final isReview = widget.source == 'home_screen_review';

      // 只記錄學習會話結束，複習會話結束在 _endReviewIfAny() 中處理
      if (!isReview) {
        AnalyticsService().logLearningSessionEnd(
          userGroup: userGroup,
          learningType: 'reading',
          eventId: widget.event.id,
          durationSeconds: durationInSeconds,
          itemsViewed: _currentPage + 1,
          totalItems: _contents.length,
        );
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      // App进入后台或非活跃状态，停止计时并暂停事件
      _isAppActive = false;
      _pauseStartTime = DateTime.now(); // 記錄暫停開始時間
      _recordCurrentCardDwellTime();
      
      // 记录离开学习页面
      if (_sessionRef != null) {
        _analyticsService.recordLeaveSession(sessionRef: _sessionRef!);
      }
      
      _pauseEvent(); // 暂停事件
    } else if (state == AppLifecycleState.resumed) {
      // App恢复活跃状态，重新开始计时
      _isAppActive = true;
      // 計算並累計暫停時間
      if (_pauseStartTime != null) {
        final pausedDuration = DateTime.now().difference(_pauseStartTime!);
        _totalPausedDuration += pausedDuration;
        _pauseStartTime = null;
      }
      _cardStartTimes[_currentPage] = DateTime.now();
      
      // 如果事件是暂停状态，继续事件
      if (widget.event.status == TaskStatus.paused) {
        _continueEvent();
      }
    }
  }

  void _recordCurrentCardDwellTime() {
    if (_sessionRef != null && _cardStartTimes.containsKey(_currentPage) && _isAppActive) {
      final endTime = DateTime.now();
      final startTime = _cardStartTimes[_currentPage]!;
      final dwellTimeMs = endTime.difference(startTime).inMilliseconds;
      
      _analyticsService.recordCardDwellTime(
        sessionRef: _sessionRef!,
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
      // 只有在用户确认离开时才记录数据
      _recordCurrentCardDwellTime();
      
      // 记录离开学习页面
      if (_sessionRef != null) {
        await _analyticsService.recordLeaveSession(sessionRef: _sessionRef!);
      }
      
      // 暂停事件
      await _pauseEvent();
      // 結束複習（若有）
      await _endReviewIfAny();
      
      Navigator.of(context).pop();
    }
  }

  Future<void> _loadContent() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // 根據事件標題解析週/日，讀取對應文章與題目
      final wd = _readingService.parseWeekDayFromTitle(widget.event.title);
      List<ReadingContent> contents = [];
      if (wd != null) {
        contents = await _readingService.loadDailyReadingWithQuestions(wd[0], wd[1]);
      }
      
      setState(() {
        _contents = contents;
        _isLoading = false;
      });
      
      // 开始阅读/复习会话数据收集
      if (_currentUserId != null && contents.isNotEmpty) {
        // GA Event: learning_session_start or review_session_start
        final isControlGroup = await ExperimentConfigService.instance.isControlGroup(_currentUserId!);
        final userGroup = isControlGroup ? 'control' : 'experiment';
        final isReview = widget.source == 'home_screen_review';

        if (isReview) {
          // 複習會話的開始記錄已整合到 startReadingSession 中
        } else {
          AnalyticsService().logLearningSessionStart(
            userGroup: userGroup,
            learningType: 'reading',
            eventId: widget.event.id,
            itemCount: contents.length,
          );
        }

        // 新的 startReadingSession
        final sessionRef = await _analyticsService.startReadingSession(
          uid: _currentUserId!,
          eventId: widget.event.id,
          source: widget.source,
          contents: contents,
        );
        setState(() {
          _sessionRef = sessionRef;
        });
        
        // 记录第一张卡片的开始时间
        _cardStartTimes[0] = DateTime.now();
      }
    } catch (e) {
      print('Load content error: $e'); // 添加调试信息
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

  void _toggleView() {
    // 從閱讀切到列表，先記錄當前卡片停留時間
    if (!_showListView) {
      _recordCurrentCardDwellTime();
    }
    setState(() {
      _showListView = !_showListView;
    });
    // 從列表切回閱讀，重新開始計時
    if (!_showListView) {
      _cardStartTimes[_currentPage] = DateTime.now();
    }
  }

  void _selectArticle(int index) {
    setState(() {
      _currentPage = index;
      _showListView = false;
    });
    // 等下一個 frame 確保 PageView 已掛載再跳頁，並開始新卡片計時
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_pageController.hasClients) {
        _pageController.jumpToPage(index);
        _cardStartTimes[index] = DateTime.now();
      }
    });
  }

  Future<void> _completeTask() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final isControlGroup = await ExperimentConfigService.instance.isControlGroup(user.uid);
        final userGroup = isControlGroup ? 'control' : 'experiment';
        final isReview = widget.source == 'home_screen_review';

        // 记录 session 结束
        _recordCurrentCardDwellTime();
        if (_sessionRef != null) {
          await _analyticsService.completeReadingSession(sessionRef: _sessionRef!);
        }
        
        // 如果是学习，而不是复习，才记录任务完成
        if (!isReview) {
          if (_pageLoadTime != null) {
            final totalDuration = DateTime.now().difference(_pageLoadTime!);
            final activeDuration = totalDuration - _totalPausedDuration;
            AnalyticsService().logTaskComplete(
              userGroup: userGroup,
              taskType: 'reading',
              eventId: widget.event.id,
              durationSeconds: activeDuration.inSeconds > 0 ? activeDuration.inSeconds : 0,
            );
          }
          await ExperimentEventHelper.recordEventCompletion(
            uid: user.uid,
            eventId: widget.event.id,
            chatId: widget.event.chatId,
          );
        }

        // 结束复习（若有）
        await _endReviewIfAny();
      }
      
      // 跳回home screen
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (e) {
      print('完成任務時出錯: $e');
      // 即使出错也要跳回home screen
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    }
  }

  bool _reviewEndedLogged = false;
  Future<void> _endReviewIfAny() async {
    if (_reviewEndedLogged) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null && widget.source == 'home_screen_review') {
      try {
        // 複習結束統一由 ExperimentEventHelper 處理
        await ExperimentEventHelper.recordReviewEnd(uid: uid, eventId: widget.event.id);
      } catch (_) {}
    }
    _reviewEndedLogged = true;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('文章閱讀'),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => _handleBackPress(),
        ),
        actions: [
          // 切换视图按钮
          IconButton(
            icon: Icon(_showListView ? Icons.view_agenda : Icons.list),
            onPressed: _toggleView,
            tooltip: _showListView ? '切換到閱讀視圖' : '切換到列表視圖',
          ),
        ],
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
              : _showListView
                  ? _buildListView()
                  : _buildReadingView(),
      bottomNavigationBar: _contents.isNotEmpty && !_showListView
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
              const Icon(Icons.article, color: Colors.green),
              const SizedBox(width: 8),
              Text(
                '文章列表 (${_contents.length}篇)',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        
        // 文章列表
        Expanded(
          child: ListView.builder(
            itemCount: _contents.length,
            itemBuilder: (context, index) {
              final content = _contents[index];
              final isSelected = index == _currentPage;
              
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
                    content.title,
                    style: TextStyle(
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      color: isSelected ? Colors.green.shade800 : Colors.black87,
                    ),
                  ),
                  subtitle: Text(
                    '點擊閱讀文章',
                    style: TextStyle(
                      color: isSelected ? Colors.green.shade600 : Colors.grey.shade600,
                    ),
                  ),
                  trailing: isSelected 
                      ? const Icon(Icons.check_circle, color: Colors.green)
                      : const Icon(Icons.arrow_forward_ios, color: Colors.grey),
                  onTap: () => _selectArticle(index),
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

  Widget _buildReadingView() {
    return Column(
      children: [
        // 页面指示器：使用 Wrap 避免小圓點總寬度超出螢幕而溢位
        Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          alignment: Alignment.center,
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: List.generate(
              _contents.length,
              (index) => Container(
                width: 8,
                height: 8,
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
                '左右滑動切換',
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
        ),
        
        // 文章内容
        Expanded(
          child: PageView.builder(
            controller: _pageController,
            onPageChanged: (index) {
              // 记录前一张卡片的停留时间
              if (_sessionRef != null && _cardStartTimes.containsKey(_currentPage) && _isAppActive) {
                final endTime = DateTime.now();
                final startTime = _cardStartTimes[_currentPage]!;
                final dwellTimeMs = endTime.difference(startTime).inMilliseconds;
                
                _analyticsService.recordCardDwellTime(
                  sessionRef: _sessionRef!,
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
      ],
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
                
                // 内容（支援 **粗體**）
                Expanded(
                  child: SingleChildScrollView(
                    child: RichText(
                      text: TextSpan(
                        children: _parseBoldSpans(
                          content.content,
                          const TextStyle(
                            fontSize: 16,
                            height: 1.8,
                            color: Colors.black54,
                          ),
                          const TextStyle(
                            fontSize: 16,
                            height: 1.8,
                            color: Colors.black87,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
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