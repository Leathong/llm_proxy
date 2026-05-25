class SystemPrompt {
  final int id;
  final String name;
  final String content;

  const SystemPrompt({
    required this.id,
    required this.name,
    required this.content,
  });

  SystemPrompt copyWith({
    int? id,
    String? name,
    String? content,
  }) {
    return SystemPrompt(
      id: id ?? this.id,
      name: name ?? this.name,
      content: content ?? this.content,
    );
  }
}
