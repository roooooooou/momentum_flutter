import 'package:flutter/material.dart';
import '../models/chat_message.dart';

class ChatBubble extends StatelessWidget {
  const ChatBubble({super.key, required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == ChatRole.user;
    final bubbleColor = isUser
        ? Theme.of(context).colorScheme.primaryContainer
        : Theme.of(context).colorScheme.surfaceVariant;

    final alignment = isUser ? Alignment.centerRight : Alignment.centerLeft;
    final margin = isUser
        ? const EdgeInsets.fromLTRB(60, 4, 12, 4)
        : const EdgeInsets.fromLTRB(12, 4, 60, 4);

    return Align(
      alignment: alignment,
      child: Container(
        margin: margin,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.circular(16),
        ),
        child: SelectableText(message.content),
      ),
    );
  }
}
