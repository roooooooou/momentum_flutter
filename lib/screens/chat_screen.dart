import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import '../providers/chat_provider.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/option_button.dart';
import '../widgets/loading_indicator.dart';
import '../models/enums.dart';
import '../models/event_model.dart';
import '../models/chat_message.dart';
import '../services/auth_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/calendar_service.dart';
import '../services/analytics_service.dart';
import 'home_screen.dart';
import 'exp_home_screen.dart';
import 'package:momentum/services/data_path_service.dart';
import '../navigation_service.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.taskTitle, this.taskDescription});
  final String taskTitle; // 帶入對應任務名稱
  final String? taskDescription; // 帶入對應任務描述

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();
  bool _hasExplicitAction = false; // 標記用戶是否已經明確選擇行動
  bool _isStartingTask = false; // 標記是否正在開始任務
  ChatProvider? _chatProvider; // 保存ChatProvider引用
  String? _currentUid; // 保存当前用户ID

  @override
  void initState() {
    super.initState();
    // 在下一個frame讓AI主動開始對話
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ChatProvider>().startConversation();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 安全地保存ChatProvider引用，以便在dispose中使用
    _chatProvider = context.read<ChatProvider>();
    _currentUid = context.read<AuthService>().currentUser?.uid;
  }

  @override
  void dispose() {
    // 🎯 實驗數據收集：如果用戶沒有明確行動就離開，記錄為leave
    if (!_hasExplicitAction && _chatProvider != null) {
      // 只有在對話未結束且用戶沒有明確行動時，才記錄為leave
      if (!_chatProvider!.isDialogueEnded) {
        print('ChatScreen dispose: Recording leave because dialogue not ended and no explicit action');
        _chatProvider!.endChatSession(
          ChatResult.leave,
          commitPlan: _chatProvider!.hasCommitmentToPlan,
        );
      } else {
        print('ChatScreen dispose: Not recording leave because dialogue already ended');
      }
    } else if (_hasExplicitAction) {
      print('ChatScreen dispose: Not recording leave because explicit action was taken');
    }
    
    // 如果用户采取了明确行动（如开始任务），延迟刷新主页面
    if (_hasExplicitAction && _currentUid != null) {
      Future.delayed(const Duration(milliseconds: 300), () {
        final context = NavigationService.context;
        if (context != null) {
          try {
            HomeScreen.forceRefreshCommitPlans(context, _currentUid!);
            ExpHomeScreen.forceRefreshCommitPlans(context, _currentUid!);
            print('ChatScreen dispose: Triggered delayed commit plan refresh');
          } catch (e) {
            print('ChatScreen dispose: Failed to trigger delayed refresh: $e');
          }
        }
      });
    }
    
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatProvider>();

    return Scaffold(
      appBar: AppBar(title: Text(widget.taskTitle)),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Builder(
                builder: (context) {
                  
                  return ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    itemCount: chat.messages.length,
                    itemBuilder: (_, i) {
                      final msg = chat.messages[chat.messages.length - 1 - i];
                      return ChatBubble(message: msg);
                    },
                  );
                },
              ),
            ),
            if (chat.isLoading) const LoadingIndicator(),
            _buildInputArea(chat),
          ],
        ),
      ),
    );
  }

  Widget _buildInputArea(ChatProvider chat) {
    // 添加调试信息
    if (kDebugMode) {
      print('ChatScreen: isDialogueEnded = ${chat.isDialogueEnded}');
      print('ChatScreen: suggestedAction = ${chat.suggestedAction}');
      print('ChatScreen: messages.length = ${chat.messages.length}');
      if (chat.messages.isNotEmpty) {
        final lastAssistantMessage = chat.messages.lastWhere(
          (msg) => msg.role == ChatRole.assistant,
          orElse: () => ChatMessage(role: ChatRole.assistant, content: ''),
        );
        print('ChatScreen: lastAssistantMessage.endOfDialogue = ${lastAssistantMessage.endOfDialogue}');
        print('ChatScreen: lastAssistantMessage.extra = ${lastAssistantMessage.extra}');
      }
    }
    
    // 如果對話已結束，根據AI建議自動執行操作，只顯示關閉按鈕
    if (chat.isDialogueEnded) {
      // 🎯 自動根據AI建議執行操作
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_hasExplicitAction) {
          _autoExecuteSuggestedAction(chat);
        }
      });

      // 根據AI建議的action顯示不同按鈕
      final suggestedAction = chat.suggestedAction;
      
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 只在建議start_now時顯示開始任務按鈕
            if (suggestedAction == 'start_now') ...[
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isStartingTask ? null : () => _startTaskAndClose(chat),
                  icon: _isStartingTask 
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.play_arrow),
                  label: Text(_isStartingTask ? '正在開始...' : '開始任務'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFB8E6B8), // 绿色
                    foregroundColor: Colors.black87,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
            
            // 關閉按鈕（始終顯示）
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
                label: const Text('關閉'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.grey[200],
                  foregroundColor: Colors.grey[700],
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // 正常的輸入區域
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              textInputAction: TextInputAction.send,
              enabled: !chat.isLoading, // 在loading時禁用輸入
              onSubmitted: chat.isLoading ? null : (_) => _send(chat),
              decoration: InputDecoration(
                hintText: chat.isLoading ? 'AI正在思考中...' : '分享你的想法...',
                border: const OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(12))),
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.send),
            onPressed: chat.isLoading ? null : () => _send(chat), // 在loading時禁用發送按鈕
          ),
        ],
      ),
    );
  }

  void _send(ChatProvider chat) {
    if (chat.isLoading || _controller.text.trim().isEmpty || chat.isDialogueEnded) return; // 避免在loading時、空訊息時或對話結束時發送
    final text = _controller.text;
    _controller.clear();
    chat.sendUserMessage(text);
  }
  
  /// 🎯 新增：根據AI建議自動執行操作
  void _autoExecuteSuggestedAction(ChatProvider chat) async {
    // 防止重複執行
    if (_hasExplicitAction) {
      print('Auto execute already performed, skipping');
      return;
    }
    
    final suggestedAction = chat.suggestedAction;
    ChatResult result;

    // 根據AI建議映射到對應的ChatResult
    switch (suggestedAction) {
      case 'start_now':
        // 用戶願意立即開始任務
        result = ChatResult.start;
        break;
      case 'snooze':
        // 用戶有commit plan但不想立即開始
        result = ChatResult.snooze;
        break;
      case 'give_up':
        // 用戶不願意開始任務
        result = ChatResult.giveUp;
        break;
      default:
        // pending 或其他情況，預設為 give_up
        result = ChatResult.giveUp;
        break;
    }

    print('Auto executing suggested action: $suggestedAction -> ${result.name}');

    // 執行對應的操作
    _hasExplicitAction = true;
    
    try {
      // 🎯 實驗數據收集：記錄聊天結束
      await chat.endChatSession(
        result,
        commitPlan: result == ChatResult.start, // 選擇開始任務表示有commitment
      );
      
      // 移除自动开始任务的逻辑，让用户手动选择
      // 即使AI建议开始任务，也不自动启动，由用户点击"开始任务"按钮来决定
      
      // 刷新主页面的commit plan显示
      if (result == ChatResult.start && mounted) {
        final uid = context.read<AuthService>().currentUser?.uid;
        if (uid != null) {
          await HomeScreen.refreshCommitPlans(context, uid);
        }
      }
      
      print('Chat session ended with result: ${result.name}');
    } catch (e) {
      print('Error ending chat session: $e');
    }
  }
  
  /// 實際啟動任務
  Future<void> _startTask(ChatProvider chat) async {
    // 需要導入必要的服務
    final authService = context.read<AuthService>();
    final uid = authService.currentUser?.uid;
    
    if (uid == null) {
      throw Exception('用戶未登入');
    }
    
    // 🎯 從Firestore獲取EventModel實例
    final doc = await DataPathService.instance.getUserEventDoc(uid, chat.eventId).then((ref) => ref.get());
    
    if (!doc.exists) {
      throw Exception('找不到任務事件');
    }
    
    final event = EventModel.fromDoc(doc);
    
    // 🎯 根據任務狀態選擇正確的啟動方法
    if (event.status == TaskStatus.paused) {
      // 如果任務已暫停，使用continueEvent恢復
      print('Task is paused, continuing task: ${event.title}');
      await CalendarService.instance.continueEvent(uid, event);
    } else if (event.actualStartTime == null) {
      // 如果任務未開始，使用startEventFromChat開始（從聊天觸發）
      print('Task not started, starting task from chat: ${event.title}');
      await CalendarService.instance.startEventFromChat(uid, event);
    } else {
      // 如果任務已在進行中，不需要額外操作
      print('Task already in progress: ${event.title}');
    }
    
    print('Task started/continued successfully: ${event.title}');
  }

  /// 開始任務並關閉聊天
  void _startTaskAndClose(ChatProvider chat) async {
    final result = ChatResult.start;
    _hasExplicitAction = true;

    // 设置按钮加载状态
    setState(() {
      _isStartingTask = true;
    });

    // 立即显示加载状态
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('正在開始任務...'),
          backgroundColor: Colors.blue,
          duration: Duration(seconds: 1),
        ),
      );
    }

    // 获取用户ID，在返回主页面后使用
    final uid = context.read<AuthService>().currentUser?.uid;

    // 立即返回主页面，不等待任何异步操作
    if (mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }

    // 在后台执行所有异步操作，不阻塞UI
    _executeBackgroundTasks(chat, result, uid);
  }

  /// 在后台执行任务启动相关的异步操作
  Future<void> _executeBackgroundTasks(ChatProvider chat, ChatResult result, String? uid) async {
    try {
      // 记录聊天结束
      await chat.endChatSession(
        result,
        commitPlan: true,
      );

      // 启动任务
      await _startTask(chat);
      
      // 记录分析数据
      await AnalyticsService().logTaskStarted('chat');

      // 延迟一下再刷新commit plan，确保主页面已经完全加载
      await Future.delayed(const Duration(milliseconds: 500));

      // 刷新主页面的commit plan显示
      if (uid != null) {
        // 使用全局的NavigationService来获取当前context
        final context = NavigationService.context;
        if (context != null) {
          // 尝试强制刷新HomeScreen的commit plans
          try {
            await HomeScreen.forceRefreshCommitPlans(context, uid);
            print('Successfully force refreshed HomeScreen commit plans');
          } catch (e) {
            print('Failed to force refresh HomeScreen commit plans: $e');
          }
          
          // 尝试强制刷新ExpHomeScreen的commit plans
          try {
            await ExpHomeScreen.forceRefreshCommitPlans(context, uid);
            print('Successfully force refreshed ExpHomeScreen commit plans');
          } catch (e) {
            print('Failed to force refresh ExpHomeScreen commit plans: $e');
          }
        } else {
          print('NavigationService.context is null, cannot refresh commit plans');
        }
      }

      print('Task started successfully: ${chat.taskTitle}');
    } catch (e) {
      print('Error in background task execution: $e');
      // 错误处理：在主页面显示错误消息
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('開始任務時發生錯誤: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }
}
