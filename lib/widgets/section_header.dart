import 'package:flutter/material.dart';

import '../utils/theme.dart';

/// 区块标题（函数详情页的各段之间用）。
///
/// 带图标、中文标题与可选副标题，视觉上与正文拉开层次。
///
/// 阶段 10 调整：图标放进一个淡色圆角底片里，让区块之间有明显"锚点感"；
/// 间距改用 AppSpace 刻度，与全站统一。
class SectionHeader extends StatelessWidget {
  /// 左侧图标
  final IconData icon;

  /// 中文标题
  final String title;

  /// 副标题（说明这个区块是干什么的）
  final String? subtitle;

  /// 标题颜色，默认用主题主色
  final Color? color;

  const SectionHeader({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = color ?? scheme.primary;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.md,
        AppSpace.xl,
        AppSpace.md,
        AppSpace.sm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 24,
            height: 24,
            margin: const EdgeInsets.only(top: 0.5),
            decoration: BoxDecoration(
              color: c.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Icon(icon, size: 14, color: c),
          ),
          const SizedBox(width: AppSpace.sm + 2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.25,
                      fontWeight: FontWeight.w700,
                      color: c,
                    ),
                  ),
                ),
                if (subtitle != null && subtitle!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      subtitle!,
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.4,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
