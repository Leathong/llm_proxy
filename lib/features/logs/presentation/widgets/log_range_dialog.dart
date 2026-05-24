import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:llm_proxy/features/logs/presentation/providers/unified_log_providers.dart';

class LogRangeDialog extends ConsumerStatefulWidget {
  final UnifiedLogState state;

  const LogRangeDialog({super.key, required this.state});

  @override
  ConsumerState<LogRangeDialog> createState() => _LogRangeDialogState();
}

class _LogRangeDialogState extends ConsumerState<LogRangeDialog> {
  late int _total;
  late double _tempStart;
  late double _tempEnd;
  late TextEditingController _startCtrl;
  late TextEditingController _endCtrl;

  UnifiedLogState get _state => widget.state;

  @override
  void initState() {
    super.initState();
    _total = _state.allEntries.length;
    final curStart = _state.rangeStart ?? 0;
    final curEnd = _state.rangeEnd ?? _total;
    _tempStart = curStart.toDouble();
    _tempEnd = curEnd.toDouble();
    _startCtrl = TextEditingController(text: '${curStart + 1}');
    _endCtrl = TextEditingController(text: '$curEnd');
  }

  @override
  void dispose() {
    _startCtrl.dispose();
    _endCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
                  const Icon(Icons.linear_scale, size: 20, color: Colors.blueGrey),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text('统计区间',
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
              const SizedBox(height: 16),
              Text(
                '共 $_total 条，选择统计范围（1 起始）：',
                style: const TextStyle(fontSize: 13, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  SizedBox(
                    width: 80,
                    child: TextField(
                      controller: _startCtrl,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      decoration: const InputDecoration(
                        labelText: '起始',
                        isDense: true,
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                        border: OutlineInputBorder(),
                      ),
                      style: const TextStyle(fontSize: 13),
                      onChanged: (v) {
                        final parsed = int.tryParse(v);
                        if (parsed == null) return;
                        final clamped = parsed.clamp(1, _tempEnd.toInt());
                        if (clamped != parsed) {
                          _startCtrl.text = '$clamped';
                          _startCtrl.selection = TextSelection.collapsed(
                              offset: _startCtrl.text.length);
                        }
                        setDialogState(() {
                          _tempStart = (clamped - 1).toDouble();
                        });
                      },
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Text('—',
                        style:
                            TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  ),
                  SizedBox(
                    width: 80,
                    child: TextField(
                      controller: _endCtrl,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      decoration: const InputDecoration(
                        labelText: '结束',
                        isDense: true,
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                        border: OutlineInputBorder(),
                      ),
                      style: const TextStyle(fontSize: 13),
                      onChanged: (v) {
                        final parsed = int.tryParse(v);
                        if (parsed == null) return;
                        final clamped =
                            parsed.clamp(_tempStart.toInt() + 1, _total);
                        if (clamped != parsed) {
                          _endCtrl.text = '$clamped';
                          _endCtrl.selection = TextSelection.collapsed(
                              offset: _endCtrl.text.length);
                        }
                        setDialogState(() {
                          _tempEnd = clamped.toDouble();
                        });
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              RangeSlider(
                values: RangeValues(_tempStart, _tempEnd),
                min: 0,
                max: _total.toDouble(),
                divisions: _total > 1 ? _total : null,
                labels: RangeLabels(
                  '${_tempStart.toInt() + 1}',
                  '${_tempEnd.toInt()}',
                ),
                onChanged: (v) {
                  setDialogState(() {
                    _tempStart = v.start;
                    _tempEnd = v.end;
                  });
                  _startCtrl.text = '${v.start.toInt() + 1}';
                  _endCtrl.text = '${v.end.toInt()}';
                },
              ),
              Text(
                '显示 ${_tempStart.toInt() + 1} ~ ${_tempEnd.toInt()}，共 ${(_tempEnd - _tempStart).toInt()} 条',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (_state.hasMore)
                    TextButton.icon(
                      onPressed: () async {
                        await ref
                            .read(unifiedLogProvider.notifier)
                            .loadMore();
                        final newState = ref.read(unifiedLogProvider);
                        final newTotal = newState.allEntries.length;
                        setDialogState(() {
                          _total = newTotal;
                          if (_tempEnd.toInt() > newTotal) {
                            _tempEnd = newTotal.toDouble();
                            _endCtrl.text = '$newTotal';
                          }
                        });
                      },
                      label: const Text('加载下一页'),
                    )
                  else
                    const SizedBox.shrink(),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton(
                        onPressed: () {
                          ref.read(unifiedLogProvider.notifier).clearRange();
                          Navigator.of(ctx).pop();
                        },
                        child: const Text('清除'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: () {
                          ref
                              .read(unifiedLogProvider.notifier)
                              .setRange(_tempStart.toInt(), _tempEnd.toInt());
                          Navigator.of(ctx).pop();
                        },
                        child: const Text('应用'),
                      ),
                    ],
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
