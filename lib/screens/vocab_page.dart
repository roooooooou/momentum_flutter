import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/event_model.dart';
import '../models/vocab_content_model.dart';
import '../services/vocab_service.dart';
import '../services/vocab_analytics_service.dart';
import '../services/calendar_service.dart';
import '../models/enums.dart';
import 'quiz_screen.dart';
import '../services/analytics_service.dart';

class VocabPage extends StatefulWidget {
  final EventModel event;
  
  const VocabPage({
    super.key,
    required this.event,
  });

  @override
  State<VocabPage> createState() => _VocabPageState();
}

class _VocabPageState extends State<VocabPage> with WidgetsBindingObserver {
  List<VocabContent> _vocabList = [];
  bool _isLoading = true;
  final PageController _pageController = PageController();
  int _currentPage = 0;
  final VocabService _vocabService = VocabService();
  final VocabAnalyticsService _analyticsService = VocabAnalyticsService();
  final CalendarService _calendarService = CalendarService.instance;
  
  // 数据收集相关
  Map<int, DateTime> _cardStartTimes = {};
  String? _currentUserId;
  bool _isAppActive = true;
  bool _reviewEndedLogged = false; // 複習結束是否已記錄
  DateTime? _startTime; // 記錄頁面開始時間

  @override
  void initState() {
    super.initState();
    _startTime = DateTime.now(); // 記錄開始時間
    WidgetsBinding.instance.addObserver(this);
    _currentUserId = FirebaseAuth.instance.currentUser?.uid;
    _loadVocab();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // 保險：視圖銷毀時視為結束複習
    _endReviewIfAny();
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
      
      // 记录离开学习页面
      if (_currentUserId != null) {
        _analyticsService.recordLeaveSession(
          uid: _currentUserId!,
          eventId: widget.event.id,
        );
      }
      
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
    // 显示确认对话框
    final shouldExit = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('離開學習'),
          content: const Text('您確定要離開單字學習嗎？學習進度已保存，事件已暫停。'),
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
      if (_currentUserId != null) {
        await _analyticsService.recordLeaveSession(
          uid: _currentUserId!,
          eventId: widget.event.id,
        );
      }
      
      // 暂停事件
      await _pauseEvent();
      // 結束複習（若有）
      await _endReviewIfAny();
      
      Navigator.of(context).pop();
    }
  }

  Future<void> _loadVocab() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // 根據事件標題解析週/日，直接讀取對應 weekX_dayY.json
      final wd = _vocabService.parseWeekDayFromTitle(widget.event.title);
      List<VocabContent> vocabList = [];
      if (wd != null) {
        vocabList = await _vocabService.loadWeeklyVocab(wd[0], wd[1]);
      } else {
        // 若標題不符合規則，暫不載入
        vocabList = [];
      }
      setState(() {
        _vocabList = vocabList;
        _isLoading = false;
      });
      
      // 开始词汇学习会话数据收集
      if (_currentUserId != null && vocabList.isNotEmpty) {
        await _analyticsService.startVocabSession(
          uid: _currentUserId!,
          eventId: widget.event.id,
          vocabList: vocabList,
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
          SnackBar(content: Text('載入單字失敗: $e')),
        );
      }
    }
  }

  bool _showListView = false; // 新增：控制列表视图

  void _toggleView() {
    // 從學習視圖切到列表前，先記錄當前卡片停留時間
    if (!_showListView) {
      _recordCurrentCardDwellTime();
    }
    setState(() {
      _showListView = !_showListView;
    });
    // 從列表切回學習視圖，開始當前卡片計時
    if (!_showListView) {
      _cardStartTimes[_currentPage] = DateTime.now();
    }
  }

  void _selectWord(int index) {
    // 從列表視圖選擇單字 → 切回學習視圖
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
        // 記錄 task_complete 事件
        if (_startTime != null) {
          final duration = DateTime.now().difference(_startTime!);
          AnalyticsService().logTaskComplete(
            taskType: 'vocab',
            eventId: widget.event.id,
            durationSeconds: duration.inSeconds,
          );
        }

        // 先記錄當前卡片停留時間
        _recordCurrentCardDwellTime();

        // 記錄學習完成，寫入 endTime
        await _analyticsService.completeLearningSession(
          uid: user.uid,
          eventId: widget.event.id,
        );

        // 记录事件完成
        await ExperimentEventHelper.recordEventCompletion(
          uid: user.uid,
          eventId: widget.event.id,
          chatId: widget.event.chatId,
        );
        // 結束複習（若有）
        await _endReviewIfAny();
      }
      
      // 跳回home screen
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e) {
      print('完成任務時出錯: $e');
      // 即使出错也要跳回home screen
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  /// 若是從「開始複習」進入，本頁離開時自動結束複習
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('單字學習'),
        backgroundColor: Colors.blue,
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
            tooltip: _showListView ? '切換到學習視圖' : '切換到列表視圖',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : _vocabList.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.book_outlined,
                        size: 64,
                        color: Colors.grey,
                      ),
                      SizedBox(height: 16),
                                              Text(
                          '暫無單字內容',
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
                  : _buildLearningView(),
      bottomNavigationBar: _vocabList.isNotEmpty && !_showListView
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
                  backgroundColor: Colors.blue,
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
              const Icon(Icons.translate, color: Colors.blue),
              const SizedBox(width: 8),
              Text(
                '單字列表 (${_vocabList.length}個)',
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
            itemCount: _vocabList.length,
            itemBuilder: (context, index) {
              final vocab = _vocabList[index];
              final isSelected = index == _currentPage;
              
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                elevation: isSelected ? 4 : 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: isSelected 
                      ? BorderSide(color: Colors.blue, width: 2)
                      : BorderSide.none,
                ),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: isSelected ? Colors.blue : Colors.grey.shade300,
                    child: Text(
                      '${index + 1}',
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.grey.shade600,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  title: Text(
                    vocab.word,
                    style: TextStyle(
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      color: isSelected ? Colors.blue.shade800 : Colors.black87,
                      fontSize: 18,
                    ),
                  ),
                  subtitle: Text(
                    vocab.definition,
                    style: TextStyle(
                      color: isSelected ? Colors.blue.shade600 : Colors.grey.shade600,
                    ),
                  ),
                  trailing: isSelected 
                      ? const Icon(Icons.check_circle, color: Colors.blue)
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
              backgroundColor: Colors.blue,
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
        // 页面指示器：使用 Wrap 避免小圓點總寬度超出螢幕而溢位
        Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          alignment: Alignment.center,
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: List.generate(
              _vocabList.length,
              (index) => Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _currentPage == index
                      ? Colors.blue
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
                '${_currentPage + 1} / ${_vocabList.length}',
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
        
        // 单词卡片内容
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
            itemCount: _vocabList.length,
            itemBuilder: (context, index) {
              final vocab = _vocabList[index];
              return _buildVocabCard(vocab, index);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildVocabCard(VocabContent vocab, int index) {
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
                Colors.blue.shade50,
                Colors.white,
                Colors.indigo.shade50,
              ],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 單字 + 詞性（右側小字）
                  Row(
                    children: [
                      Expanded(
                        child: Center(
                          child: Text(
                            vocab.word,
                            style: const TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue,
                              height: 1.2,
                            ),
                          ),
                        ),
                      ),
                      if (vocab.partOfSpeech.isNotEmpty)
                        Text(
                          vocab.partOfSpeech,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.blueGrey.shade600,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // 定義（EN）
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '定義（EN）：',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue.shade700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          vocab.definition,
                          style: const TextStyle(
                            fontSize: 16,
                            height: 1.6,
                            color: Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // 中文意思
                  if (vocab.zhExplanation.isNotEmpty) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.blue.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '中文意思：',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue.shade700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            vocab.zhExplanation,
                            style: const TextStyle(
                              fontSize: 16,
                              height: 1.6,
                              color: Colors.black87,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),
                  ],

                  // 例句（合併 EN + ZH）
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.indigo.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.indigo.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '例句：',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.indigo.shade700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          vocab.example + (vocab.exampleZh.isNotEmpty ? '\n' + vocab.exampleZh : ''),
                          style: const TextStyle(
                            fontSize: 16,
                            height: 1.6,
                            color: Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),

                  // 底部裝飾
                  Container(
                    width: double.infinity,
                    height: 4,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(2),
                      gradient: LinearGradient(
                        colors: [
                          Colors.blue.shade300,
                          Colors.indigo.shade300,
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
} 