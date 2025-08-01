class VocabContent {
  final String word;
  final String definition;
  final String example;
  final List<String> options;
  final String answer;

  VocabContent({
    required this.word,
    required this.definition,
    required this.example,
    required this.options,
    required this.answer,
  });

  factory VocabContent.fromJson(Map<String, dynamic> json) {
    return VocabContent(
      word: json['word'] ?? '',
      definition: json['definition'] ?? '',
      example: json['example'] ?? '',
      options: List<String>.from(json['options'] ?? []),
      answer: json['answer'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'word': word,
      'definition': definition,
      'example': example,
      'options': options,
      'answer': answer,
    };
  }
} 