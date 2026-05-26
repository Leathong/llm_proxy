import 'package:flutter/material.dart';

/// 缩放为 0.7 的自定义 Switch，解决缩放后样式异常的问题
class ScaledSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;

  const ScaledSwitch({super.key, required this.value, this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Transform.scale(
      scale: 0.7,
      child: Switch(
        value: value,
        onChanged: onChanged,
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
      title: title,
      subtitle: subtitle,
      trailing: ScaledSwitch(value: value, onChanged: onChanged),
      onTap: onChanged != null ? () => onChanged!(!value) : null,
    );
  }
}
