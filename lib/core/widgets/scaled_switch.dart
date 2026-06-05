import 'package:flutter/material.dart';
import 'package:llm_proxy/core/theme/app_colors.dart';

/// 缩放为 0.6 的自定义 Switch，解决缩放后样式异常的问题
class ScaledSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;

  const ScaledSwitch({super.key, required this.value, this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 36,
      height: 24,
      child: Transform.scale(
        scale: 0.6,
        child: Switch(
          value: value,
          onChanged: onChanged,
        ),
      ),
    );
  }
}

/// 替代 SwitchListTile 的组合组件，使用 ScaledSwitch
class SwitchTile extends StatelessWidget {
  final Widget title;
  final Widget? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  const SwitchTile({
    super.key,
    required this.title,
    this.subtitle,
    required this.value,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: .zero,
      dense: true,
      visualDensity: const VisualDensity(horizontal: 0, vertical: -4),
      title: title,
      minTileHeight: 0,
      horizontalTitleGap: 0,
      titleTextStyle: const TextStyle(fontSize: 14, color: AppColors.greyDark, fontWeight: .w400),
      subtitle: subtitle,
      subtitleTextStyle: const TextStyle(fontSize: 12, color: AppColors.grey, fontWeight: FontWeight.w300),
      trailing: ScaledSwitch(value: value, onChanged: onChanged),
      onTap: onChanged != null ? () => onChanged!(!value) : null,
    );
  }
}
