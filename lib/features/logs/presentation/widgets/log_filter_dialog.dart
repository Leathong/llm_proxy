import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:llm_proxy/core/theme/app_colors.dart';
import 'package:llm_proxy/features/logs/presentation/providers/log_providers.dart';
import 'package:llm_proxy/features/logs/presentation/widgets/log_filter_dropdown.dart';

class LogFilterDialog extends ConsumerStatefulWidget {
  final LogState state;

  const LogFilterDialog({super.key, required this.state});

  @override
  ConsumerState<LogFilterDialog> createState() => _LogFilterDialogState();
}

class _LogFilterDialogState extends ConsumerState<LogFilterDialog> {
  late TextEditingController _keywordCtrl;
  late String _tempKeyword;
  late String? _tempModelFilter;
  late String? _tempEndpointFilter;

  LogState get _state => widget.state;

  @override
  void initState() {
    super.initState();
    final filter = _state.filter;
    _keywordCtrl = TextEditingController(text: filter.keyword);
    _tempKeyword = filter.keyword;
    _tempModelFilter = filter.modelFilter;
    _tempEndpointFilter = filter.endpointFilter;
  }

  @override
  void dispose() {
    _keywordCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final models = LogFilter.availableModels(_state.allEntries);
    final endpoints = LogFilter.availableEndpoints(_state.allEntries);

    return StatefulBuilder(
      builder: (ctx, setDialogState) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.filter_list, size: 20, color: AppColors.primary),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text('过滤日志',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.of(ctx).pop(),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _keywordCtrl,
                decoration: InputDecoration(
                  hintText: '搜索模型、转发目标、路径...',
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  border:
                      OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _keywordCtrl.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            _keywordCtrl.clear();
                            setDialogState(() => _tempKeyword = '');
                          },
                        )
                      : null,
                ),
                style: const TextStyle(fontSize: 14),
                onChanged: (v) => setDialogState(() => _tempKeyword = v),
              ),
              if (models.isNotEmpty || endpoints.isNotEmpty) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    if (models.isNotEmpty)
                      Expanded(
                        child: FilterDropdown(
                          label: '模型',
                          value: _tempModelFilter,
                          items: models,
                          onChanged: (v) =>
                              setDialogState(() => _tempModelFilter = v),
                          onClear: _tempModelFilter != null
                              ? () => setDialogState(
                                  () => _tempModelFilter = null)
                              : null,
                        ),
                      ),
                    if (models.isNotEmpty && endpoints.isNotEmpty)
                      const SizedBox(width: 8),
                    if (endpoints.isNotEmpty)
                      Expanded(
                        child: FilterDropdown(
                          label: '转发目标',
                          value: _tempEndpointFilter,
                          items: endpoints,
                          onChanged: (v) =>
                              setDialogState(() => _tempEndpointFilter = v),
                          onClear: _tempEndpointFilter != null
                              ? () => setDialogState(
                                  () => _tempEndpointFilter = null)
                              : null,
                        ),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () {
                      ref
                          .read(logProvider.notifier)
                          .setFilter(const LogFilter());
                      Navigator.of(ctx).pop();
                    },
                    child: const Text('清除'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () {
                      ref.read(logProvider.notifier).setFilter(
                          LogFilter(
                            keyword: _tempKeyword,
                            modelFilter: _tempModelFilter,
                            endpointFilter: _tempEndpointFilter,
                          ));
                      Navigator.of(ctx).pop();
                    },
                    child: const Text('应用'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
