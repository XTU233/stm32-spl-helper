import 'package:flutter/material.dart';

import '../models/pin.dart';
import '../utils/chip_layout.dart';
import '../utils/theme.dart';

/// LQFP48 封装的可视化排布图。
///
/// 需求 5.6 的第一条："用 LQFP48 的引脚排布图展示"。
///
/// 画法：中间一个方形代表芯片本体，四条边各排 12 个引脚小块，
/// 块上写引脚名（如 PA9）。引脚号在块的外侧，内圈写复用功能缩写。
///
/// 参数 [highlighted] 用于反查/筛选后高亮：命中的引脚加粗描边，
/// 未命中的降低透明度，这样一眼能看出"哪些脚能用 USART1_TX"。
class ChipDiagram extends StatelessWidget {
  /// 全部引脚
  final List<Pin> pins;

  /// 需要高亮的引脚号；为空表示全部正常显示
  final Set<int> highlighted;

  /// 点击引脚
  final void Function(Pin pin) onTapPin;

  const ChipDiagram({
    super.key,
    required this.pins,
    required this.onTapPin,
    this.highlighted = const <int>{},
  });

  @override
  Widget build(BuildContext context) {
    const layout = ChipLayout();
    final slots = layout.slots(pins);

    return LayoutBuilder(
      builder: (context, constraints) {
        // 方形区域，边长取可用宽度的较大值（引脚名要写得下）
        final size = constraints.maxWidth < 520
            ? constraints.maxWidth
            : 520.0;
        return Center(
          child: SizedBox(
            width: size,
            height: size,
            child: Stack(
              children: <Widget>[
                // 芯片本体
                Positioned(
                  left: size * _bodyInset,
                  top: size * _bodyInset,
                  right: size * _bodyInset,
                  bottom: size * _bodyInset,
                  child: _ChipBody(pinCount: pins.length),
                ),
                // 引脚块
                for (final slot in slots) _positioned(slot, size, context),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 引脚块占封装外框的比例（向外伸出的引脚长度）
  static const double _bodyInset = 0.135;

  /// 引脚块自身的尺寸比例
  static const double _padWidthRatio = 0.125;
  static const double _padHeightRatio = 0.058;

  Widget _positioned(PinSlot slot, double size, BuildContext context) {
    final c = slot.normalizedCenter();
    final isHit = highlighted.isEmpty || highlighted.contains(slot.pin.number);
    final padW = size * _padWidthRatio;
    final padH = size * _padHeightRatio;

    // 归一化中心 → 像素左上角
    final left = c.dx * size - padW / 2;
    final top = c.dy * size - padH / 2;

    return Positioned(
      left: left,
      top: top,
      width: padW,
      height: padH,
      child: _PinPad(
        pin: slot.pin,
        dimmed: !isHit,
        onTap: () => onTapPin(slot.pin),
      ),
    );
  }
}

/// 芯片本体（中间的方块）。
class _ChipBody extends StatelessWidget {
  final int pinCount;

  const _ChipBody({required this.pinCount});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant, width: 1.5),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          // 第 1 脚的定位标记（封装图惯例：圆点标在 1 脚角落）
          Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.55),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    'STM32F103',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'C8T6 · LQFP$pinCount',
                    style: TextStyle(
                      fontSize: 10.5,
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.85),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // 1 脚标注文字
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              '逆时针编号 · 左上为第 1 脚',
              style: TextStyle(
                fontSize: 9,
                color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 单个引脚小块。
class _PinPad extends StatelessWidget {
  final Pin pin;
  final bool dimmed;
  final VoidCallback onTap;

  const _PinPad({
    required this.pin,
    required this.dimmed,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final category = PinCategory.of(pin);
    final bg = category.color;
    // 次要信息：第一个复用功能（电源脚没有则留空）
    final af = pin.functions
        .where((f) => f.kind == PinFunctionKind.af)
        .map((f) => f.name)
        .firstOrNull;

    return Opacity(
      opacity: dimmed ? 0.28 : 1,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(4),
          child: Container(
            decoration: BoxDecoration(
              color: bg.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: bg.withValues(alpha: dimmed ? 0.3 : 0.75),
                width: dimmed ? 1 : 1.4,
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: FittedBox(
              // 引脚块高度在多种屏宽下未必能同时容纳两行文字，
              // 用 FittedBox 整体缩放而不是让 Column 溢出。
              // 早先直接放 Column，在 360dp 下溢出了 0.92 像素。
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  // 引脚号（小字，放上面）
                  Text(
                    '${pin.number}',
                    style: TextStyle(
                      fontSize: 8,
                      height: 1.0,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  // 引脚名 / 复用功能
                  Text(
                    af == null ? pin.name : '${pin.name} $af',
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    softWrap: false,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamilyFallback: AppFonts.mono,
                      fontSize: 9.5,
                      height: 1.1,
                      fontWeight: FontWeight.w700,
                      color: bg,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 图例：按功能类别列出配色。
class PinLegend extends StatelessWidget {
  /// 要显示的类别（一般是当前数据里实际出现的）
  final List<PinCategory> categories;

  /// 每类的引脚数
  final Map<PinCategory, int> counts;

  /// 当前选中的类别；null 表示不筛选
  final PinCategory? selected;

  /// 点击类别
  final void Function(PinCategory? category) onSelect;

  const PinLegend({
    super.key,
    required this.categories,
    required this.counts,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
      child: Wrap(
        spacing: 7,
        runSpacing: 7,
        children: <Widget>[
          for (final c in categories)
            InkWell(
              onTap: () => onSelect(selected == c ? null : c),
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: c.color.withValues(
                    alpha: selected == c ? 0.26 : 0.12,
                  ),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: c.color.withValues(
                      alpha: selected == c ? 0.9 : 0.4,
                    ),
                    width: selected == c ? 1.6 : 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: c.color,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      '${c.labelZh} ${counts[c] ?? 0}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
