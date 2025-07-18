import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/chat_provider.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/option_button.dart';
import '../widgets/loading_indicator.dart';
import '../models/enums.dart';
import '../models/event_model.dart';
import '../services/auth_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/calendar_service.dart';
import '../services/analytics_service.dart';

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
  ChatProvider? _chatProvider; // 保存ChatProvider引用

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
  }

  @override
  void dispose() {
    // 🎯 實驗數據收集：如果用戶沒有明確行動就離開，記錄為leave
    if (!_hasExplicitAction && _chatProvider != null) {
      // 使用保存的引用而不是context.read
      _chatProvider!.endChatSession(
        ChatResult.leave,
        commitPlan: _chatProvider!.hasCommitmentToPlan,
      );
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
    // 如果對話已結束，根據AI建議自動執行操作，只顯示關閉按鈕
    if (chat.isDialogueEnded) {
      // 🎯 自動根據AI建議執行操作
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_hasExplicitAction) {
          _autoExecuteSuggestedAction(chat);
        }
      });

      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 只顯示關閉按鈕
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
    final suggestedAction = chat.suggestedAction;
    ChatResult result;

    // 根據AI建議映射到對應的ChatResult
    switch (suggestedAction) {
      case 'start_now':
        result = ChatResult.start;
        break;
      case 'snooze':
        result = ChatResult.snooze;
        break;
      default:
        // pending 或其他情況，預設為 snooze
        result = ChatResult.snooze;
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
      
      // 如果AI建議開始任務，實際啟動任務
      if (result == ChatResult.start) {
        await _startTask(chat);
        
        // 記錄分析事件
        await AnalyticsService().logTaskStarted('chat');

        // 顯示成功訊息
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('任務「${chat.taskTitle}」已開始！'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      // 顯示錯誤訊息
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('操作失敗：$e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }
  
  /// 處理用戶明確的行動選擇（保留原有方法以備其他地方使用）
  void _handleActionChoice(ChatResult result, ChatProvider chat) async {
    _hasExplicitAction = true;
    
    try {
      // 🎯 實驗數據收集：記錄聊天結束
      await chat.endChatSession(
        result,
        commitPlan: result == ChatResult.start, // 選擇開始任務表示有commitment
      );
      
      // 如果用戶選擇開始任務，實際啟動任務
      if (result == ChatResult.start) {
        await _startTask(chat);
        
        // 記錄分析事件
        await AnalyticsService().logTaskStarted('chat');

        // 顯示成功訊息
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('任務「${chat.taskTitle}」已開始！'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      // 顯示錯誤訊息
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('操作失敗：$e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
    
    if (mounted) {
      Navigator.of(context).pop();
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
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('events')
        .doc(chat.eventId)
        .get();
    
    if (!doc.exists) {
      throw Exception('找不到任務事件');
    }
    
    final event = EventModel.fromDoc(doc);
    
    // 🎯 調用CalendarService真正啟動任務
    await CalendarService.instance.startEvent(uid, event);
    
    print('Task started successfully: ${event.title}');
  }
}
