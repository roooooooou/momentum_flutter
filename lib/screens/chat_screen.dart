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
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(chat),
              decoration: const InputDecoration(
                hintText: '分享你的想法...',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(12))),
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.send),
            onPressed: () => _send(chat),
          ),
        ],
      ),
    );
  }

  void _send(ChatProvider chat) {
    final text = _controller.text;
    _controller.clear();
    chat.sendUserMessage(text);
  }
}
