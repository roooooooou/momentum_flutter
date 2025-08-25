class ReadingQuestion {
  final String stem;
  final List<String> options;
  final String answerLetter; // e.g., 'A' | 'B' | 'C' | 'D'
  final String rid; // 來源文章ID，用於抽題時避免同篇多題

  ReadingQuestion({
    required this.stem,
    required this.options,
    required this.answerLetter,
    this.rid = '',
  });

  factory ReadingQuestion.fromJson(Map<String, dynamic> json, {String rid = ''}) {
    return ReadingQuestion(
      stem: json['stem']?.toString() ?? '',
      options: List<String>.from(json['options'] ?? const []),
      answerLetter: json['answer']?.toString() ?? '',
      rid: rid,
    );
  }
}

class ReadingContent {
  final String rid; // 文章ID（與題目對應）
  final String category;
  final String title;
  final String shortTitle;
  final String content; // 文章全文（對應 json 'article'）
  final List<ReadingQuestion> questions; // 可能為空

  ReadingContent({
    required this.rid,
    required this.category,
    required this.title,
    required this.shortTitle,
    required this.content,
    this.questions = const [],
  });

  factory ReadingContent.fromArticleJson(Map<String, dynamic> json) {
    return ReadingContent(
      rid: json['rid']?.toString() ?? '',
      category: json['category']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      shortTitle: json['short_title']?.toString() ?? '',
      content: json['article']?.toString() ?? '',
      questions: const [],
    );
  }
}