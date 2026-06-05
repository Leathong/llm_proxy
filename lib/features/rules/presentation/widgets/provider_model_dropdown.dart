import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:llm_proxy/features/rules/domain/entities/provider_model.dart';
import 'package:llm_proxy/features/rules/presentation/providers/rules_providers.dart';

/// 可复用的 Provider 模型下拉选择器
/// 使用 PopupMenuButton 实现下拉菜单，无需弹窗
class ProviderModelDropdown extends ConsumerWidget {
  final int? providerModelId;
  final ValueChanged<ProviderModel> onChanged;
  final bool compact;

  const ProviderModelDropdown({
    super.key,
    required this.providerModelId,
    required this.onChanged,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final providerModelsAsync = ref.watch(allProviderModelsProvider);
    final providersAsync = ref.watch(modelProvidersProvider);

    return providerModelsAsync.when(
      loading: () => const SizedBox(
        height: 32,
        child: Center(
          child: SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ),
      error: (e, _) => Text(
        '加载失败',
        style: TextStyle(color: Colors.red, fontSize: compact ? 11 : 12),
      ),
      data: (providerModels) {
        final enabledModels = providerModels.where((m) => m.enabled).toList();
        final providers = providersAsync.asData?.value ?? [];

        // 构建 provider 名称映射
        final providerNameMap = <int, String>{};
        final providerFormatMap = <int, String>{};
        for (final p in providers) {
          providerNameMap[p.id] = p.name;
          providerFormatMap[p.id] = p.format;
        }

        // 按 providerId 分组
        final groupedModels = <int, List<ProviderModel>>{};
        for (final m in enabledModels) {
          groupedModels.putIfAbsent(m.providerId, () => []).add(m);
        }

        // 获取选中模型的显示文本
        String? selectedText;
        if (providerModelId != null) {
          final selectedModel =
              enabledModels.where((m) => m.id == providerModelId).firstOrNull;
          if (selectedModel != null) {
            final pName = providerNameMap[selectedModel.providerId] ??
                'Provider #${selectedModel.providerId}';
            selectedText = '$pName / ${selectedModel.modelId}';
          }
        }

        // 构建分组下拉菜单项
        final menuItems = _buildMenuItems(
          context,
          groupedModels,
          providerNameMap,
          providerFormatMap,
        );

        // 选中回调
        void onSelect(String modelIdStr) {
          final modelId = int.parse(modelIdStr);
          final selected =
              enabledModels.firstWhere((m) => m.id == modelId);
          onChanged(selected);
        }

        // compact 模式：简洁的 Row 布局
        if (compact) {
          return PopupMenuButton<String>(
            offset: const Offset(0, 24),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(maxWidth: 320),
            itemBuilder: (_) => menuItems,
            onSelected: onSelect,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      selectedText ?? '未关联',
                      style: TextStyle(
                        fontSize: 12,
                        color: selectedText != null ? null : Colors.grey[600],
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(Icons.arrow_drop_down, size: 18,
                      color: Colors.grey[600]),
                ],
              ),
            ),
          );
        }

        // 非 compact 模式：使用 InputDecorator 保留完整表单样式
        return PopupMenuButton<String>(
          offset: const Offset(0, 48),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(maxWidth: 400),
          itemBuilder: (_) => menuItems,
          onSelected: onSelect,
          child: const InputDecorator(
            decoration: InputDecoration(
              labelText: '关联模型',
              hintText: '选择模型',
              suffixIcon: Icon(Icons.arrow_drop_down, size: 24),
            ),
            child: SizedBox(height: 20),
          ),
        );
      },
    );
  }

  /// 构建分组下拉菜单项列表
  List<PopupMenuEntry<String>> _buildMenuItems(
    BuildContext context,
    Map<int, List<ProviderModel>> groupedModels,
    Map<int, String> providerNameMap,
    Map<int, String> providerFormatMap,
  ) {
    final items = <PopupMenuEntry<String>>[];
    final primaryColor = Theme.of(context).colorScheme.primary;

    for (final entry in groupedModels.entries) {
      final providerId = entry.key;
      final models = entry.value;
      final providerName =
          providerNameMap[providerId] ?? 'Provider #$providerId';
      final format = providerFormatMap[providerId] ?? '';

      // Provider 分组标题（不可点击）
      items.add(
        PopupMenuItem<String>(
          enabled: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$providerName  [$format]',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              Text(
                '${models.length} 个模型',
                style: TextStyle(fontSize: 11, color: Colors.grey[600]),
              ),
            ],
          ),
        ),
      );

      // 该分组下的模型列表
      for (final m in models) {
        final isSelected = m.id == providerModelId;
        items.add(
          PopupMenuItem<String>(
            height: 32,
            value: m.id.toString(),
            child: Row(
              children: [
                if (isSelected)
                  Icon(Icons.check, size: 18, color: primaryColor)
                else
                  const SizedBox(width: 18),
                const SizedBox(width: 8),
                Text(
                  m.modelId,
                  style: TextStyle(
                    fontWeight:
                        isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        );
      }

      // 分组之间添加分隔线
      items.add(const PopupMenuDivider());
    }

    // 移除末尾多余的分隔线
    if (items.isNotEmpty && items.last is PopupMenuDivider) {
      items.removeLast();
    }

    return items;
  }
}
