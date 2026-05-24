import 'package:flutter/material.dart';

class FilterDropdown extends StatelessWidget {
  final String label;
  final String? value;
  final List<String> items;
  final ValueChanged<String?> onChanged;
  final VoidCallback? onClear;

  const FilterDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Text('$label: ',
              style: const TextStyle(fontSize: 12, color: Colors.grey)),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String?>(
                value: value,
                isExpanded: true,
                isDense: true,
                hint: const Text('全部', style: TextStyle(fontSize: 12)),
                style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurface),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('全部', style: TextStyle(fontSize: 12)),
                  ),
                  ...items.map((item) => DropdownMenuItem<String?>(
                        value: item,
                        child: Text(item,
                            style: const TextStyle(fontSize: 12),
                            overflow: TextOverflow.ellipsis),
                      )),
                ],
                onChanged: onChanged,
              ),
            ),
          ),
          if (value != null)
            GestureDetector(
              onTap: onClear,
              child: const Icon(Icons.clear, size: 16, color: Colors.grey),
            ),
        ],
      ),
    );
  }
}
