class ReadingContent {
  final String title;
  final String content;
  final String question;
  final List<String> options;
  final String answer;

  ReadingContent({
    required this.title,
    required this.content,
    required this.question,
    required this.options,
    required this.answer,
  });

  factory ReadingContent.fromJson(Map<String, dynamic> json) {
    return ReadingContent(
      title: json['title'] ?? '',
      content: json['content'] ?? '',
      question: json['question'] ?? '',
      options: List<String>.from(json['options'] ?? []),
      answer: json['answer'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'content': content,
      'question': question,
      'options': options,
      'answer': answer,
    };
  }
} 