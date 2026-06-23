enum SystemPromptMode {
  replace('replace'),
  append('append');

  final String value;
  const SystemPromptMode(this.value);

  static SystemPromptMode fromValue(String value) {
    return SystemPromptMode.values.firstWhere(
      (e) => e.value == value,
      orElse: () => SystemPromptMode.replace,
    );
  }
}

class SystemPrompt {
  final int id;
  final String name;
  final String content;
  final SystemPromptMode mode;

  const SystemPrompt({
    required this.id,
    required this.name,
    required this.content,
    this.mode = SystemPromptMode.replace,
  });

  SystemPrompt copyWith({
    int? id,
    String? name,
    String? content,
    SystemPromptMode? mode,
  }) {
    return SystemPrompt(
      id: id ?? this.id,
      name: name ?? this.name,
      content: content ?? this.content,
      mode: mode ?? this.mode,
    );
  }
}
