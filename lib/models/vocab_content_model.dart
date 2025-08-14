class VocabContent {
  final String word;
  final String definition;
  final String example;
  final List<String> options;
  final String answer;
  final String partOfSpeech; // 詞性
  final String zhExplanation; // 中文意思
  final String exampleZh; // 例句中文

  VocabContent({
    required this.word,
    required this.definition,
    required this.example,
    required this.options,
    required this.answer,
    this.partOfSpeech = '',
    this.zhExplanation = '',
    this.exampleZh = '',
  });

  factory VocabContent.fromJson(Map<String, dynamic> json) {
    return VocabContent(
      word: json['word'] ?? '',
      definition: (json['en_definition'] ?? json['definition'] ?? '').toString(),
      example: (json['example_en'] ?? json['example'] ?? '').toString(),
      options: List<String>.from(json['options'] ?? []),
      answer: json['answer'] ?? '',
      partOfSpeech: (json['part_of_speech'] ?? json['pos'] ?? '').toString(),
      zhExplanation: (json['zh_explanation'] ?? json['zh_meaning'] ?? '').toString(),
      exampleZh: (json['example_zh'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'word': word,
      'definition': definition,
      'example': example,
      'options': options,
      'answer': answer,
      'part_of_speech': partOfSpeech,
      'zh_explanation': zhExplanation,
      'example_zh': exampleZh,
    };
  }
}