import 'package:flutter/material.dart';

import '../utils/theme.dart';

/// 列表区块标题（"标准外设模块"、"最近搜索"、"搜索范围"这类）。
///
/// 与 [SectionHeader]（函数详情页的大区块标题）分工不同：
///   - `SectionHeader` 是页面内的主区块，带副标题，视觉重
///   - `BlockLabel` 是列表内的小分组，单行、轻量，可带数量角标
///
/// 抽出来是为了统一"小标题"的样式。改版前这些标题在
/// 首页、搜索页、我的页各写各的——字号 12.5/13/13.5 混用，
/// 有的带图标底片有的不带，看起来像三套设计拼在一起。
class BlockLabel extends StatelessWidget {
  /// 中文标题
  final String title;

  /// 可选图标
  final IconData? icon;

  /// 可选数量角标（如 "12"）
  final String? count;

  /// 标题颜色，默认主色
  final Color? color;

  /// 右侧附加操作（如"清空"按钮）
  final Widget? trailing;

  /// 上边距
  final double topSpace;

  const BlockLabel(
    this.title, {
    super.key,
    this.icon,
    this.count,
    this.color,
    this.trailing,
    this.topSpace = AppSpace.lg,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = color ?? scheme.primary;

    return Padding(
      padding: EdgeInsets.only(top: topSpace, bottom: AppSpace.sm),
      child: Row(
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 15, color: c),
            const SizedBox(width: 6),
          ] else ...<Widget>[
            // 没有图标时用一小段色条做视觉锚点，保持与有图标时同样的左对齐感
            Container(
              width: 3,
              height: 13,
              margin: const EdgeInsets.only(right: AppSpace.sm),
              decoration: BoxDecoration(
                color: c.withValues(alpha: 0.75),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: c,
              ),
            ),
          ),
          if (count != null)
            Padding(
              padding: const EdgeInsets.only(left: AppSpace.sm),
              child: Text(
                count!,
                style: AppFonts.monoStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ?trailing,
        ],
      ),
    );
  }
}
