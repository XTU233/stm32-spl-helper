import 'package:flutter/material.dart';

import '../utils/theme.dart';

/// 带按压反馈的卡片容器。
///
/// 阶段 10 统一了"卡片被按下"的观感：轻微缩小 + 边框变主色 + 淡阴影。
/// 之前的页面各用各的（有的用 InkWell 水波纹、有的什么都不给），
/// 统一成一个组件后视觉节奏一致，也方便以后一起调。
///
/// 刻意不用 `InkWell` 的水波纹：这个 App 是信息阅读型，
/// 大面积水波纹在长列表里会显得躁，缩放 + 描边更克制。
class PressableCard extends StatefulWidget {
  /// 卡片内容
  final Widget child;

  /// 点击回调；为 null 时不可点（不显示按压反馈）
  final VoidCallback? onTap;

  /// 圆角，默认用卡片圆角
  final BorderRadius borderRadius;

  /// 背景色；默认取主题的卡片色
  final Color? color;

  /// 是否显示描边
  final bool bordered;

  /// 内容内边距
  final EdgeInsetsGeometry padding;

  const PressableCard({
    super.key,
    required this.child,
    this.onTap,
    this.borderRadius = AppRadius.card,
    this.color,
    this.bordered = true,
    this.padding = const EdgeInsets.all(AppSpace.lg),
  });

  @override
  State<PressableCard> createState() => _PressableCardState();
}

class _PressableCardState extends State<PressableCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = widget.onTap != null;
    // 按下时描边转主色，给"已经选中"的确认感
    final borderColor = _pressed && enabled
        ? scheme.primary.withValues(alpha: 0.55)
        : scheme.outlineVariant;

    return AnimatedScale(
      // 缩放幅度刻意很小（0.985）：再大就有"果冻感"，
      // 与环境类工具 App 的稳重气质不符
      scale: _pressed && enabled ? 0.985 : 1.0,
      duration: AppDuration.fast,
      curve: Curves.easeOut,
      child: AnimatedContainer(
        duration: AppDuration.fast,
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: widget.color ?? Theme.of(context).cardTheme.color,
          borderRadius: widget.borderRadius,
          border: widget.bordered ? Border.all(color: borderColor) : null,
          boxShadow: _pressed && enabled
              ? <BoxShadow>[
                  BoxShadow(
                    color: scheme.primary.withValues(alpha: 0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: widget.borderRadius,
          child: InkWell(
            borderRadius: widget.borderRadius,
            onTap: widget.onTap,
            onHighlightChanged:
                enabled ? (v) => setState(() => _pressed = v) : null,
            child: Padding(padding: widget.padding, child: widget.child),
          ),
        ),
      ),
    );
  }
}

/// 空状态占位。
///
/// 六个页面（收藏/最近/笔记/搜索/引脚/错误）的空状态以前各写各的，
/// 图标大小、行高、文案语气都不一致。统一成一个组件。
class EmptyState extends StatelessWidget {
  /// 顶部图标
  final IconData icon;

  /// 主标题
  final String title;

  /// 说明文字
  final String body;

  /// 可选的操作按钮
  final Widget? action;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpace.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // 图标放进淡色圆底，比光秃秃一个大图标更柔和
            Container(
              width: 62,
              height: 62,
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 28, color: scheme.primary),
            ),
            const SizedBox(height: AppSpace.lg),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpace.sm),
            ConstrainedBox(
              // 说明文字限制最大宽度，宽屏上不会拉成一整行难读的长句
              constraints: const BoxConstraints(maxWidth: 320),
              child: Text(
                body,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.65,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            if (action != null) ...<Widget>[
              const SizedBox(height: AppSpace.xl),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
