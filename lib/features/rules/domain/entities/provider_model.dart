class ProviderModel {
  final int id;
  final int providerId;
  final String modelId;
  final String? displayName;
  final bool enabled;

  const ProviderModel({
    required this.id,
    required this.providerId,
    required this.modelId,
    this.displayName,
    this.enabled = true,
  });

  ProviderModel copyWith({
    int? id,
    int? providerId,
    String? modelId,
    String? displayName,
    bool? enabled,
  }) {
    return ProviderModel(
      id: id ?? this.id,
      providerId: providerId ?? this.providerId,
      modelId: modelId ?? this.modelId,
      displayName: displayName ?? this.displayName,
      enabled: enabled ?? this.enabled,
    );
  }
}
