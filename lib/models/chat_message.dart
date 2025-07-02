import 'package:uuid/uuid.dart';

/// 對話角色
enum ChatRole { user, assistant, system, option }

/// 對話訊息資料模型
class ChatMessage {
  final String id;
  final ChatRole role;
  final String content;
  final DateTime createdAt;
  final Map<String, dynamic>? extra; // quick‑reply 或 metadata
  final bool endOfDialogue; // 標記對話是否結束

  ChatMessage({
    String? id,
    required this.role,
    required this.content,
    DateTime? createdAt,
    this.extra,
    this.endOfDialogue = false, // 默認為false
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now();
}
