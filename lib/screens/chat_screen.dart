import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/chat_provider.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/option_button.dart';
import '../widgets/loading_indicator.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.taskTitle});
  final String taskTitle; // 帶入對應任務名稱

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    // 在下一個frame讓AI主動開始對話
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ChatProvider>().startConversation();
    });
  }

  @override
  void dispose() {
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
              child: ListView.builder(
                reverse: true,
                padding: const EdgeInsets.symmetric(vertical: 12),
                itemCount: chat.messages.length,
                itemBuilder: (_, i) {
                  final msg = chat.messages[chat.messages.length - 1 - i];
                  return ChatBubble(message: msg);
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
    // 如果對話已結束，顯示回到上一頁的按鈕
    if (chat.isDialogueEnded) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back),
            label: const Text('Back'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
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
}
