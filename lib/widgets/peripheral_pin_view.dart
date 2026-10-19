import 'package:flutter/material.dart';

import '../models/pin.dart';
import '../utils/theme.dart';

/// 「按外设看引脚」视图。
///
/// 需求场景：用户要接一个 SPI Flash，问的不是"PA5 是什么"，
/// 而是"SPI1 要接哪几根线"。所以这一屏按**外设实例**组织：
/// 先选外设（SPI1），再逐个信号给出可用引脚。
///
/// 与「排布图」视图互补：那边回答"这个脚能干什么"，这边回答"这个功能用哪些脚"。
class PeripheralPinView extends StatelessWidget {
  /// 当前选中的外设实例
  final String instance;

  /// 该实例的引脚分配
  final PeripheralPinout pinout;

  /// 点击引脚（打开详情）
  final void Function(Pin pin) onTapPin;

  /// 点击"去外设页"（跳到该外设的函数列表）
  final VoidCallback? onOpenPeripheral;

  const PeripheralPinView({
    super.key,
    required this.instance,
    required this.pinout,
    required this.onTapPin,
    this.onOpenPeripheral,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bySignal = pinout.bySignal;

    return ListView(
      padding: const EdgeInsets.only(bottom: 28),
      children: <Widget>[
        // ---- 概要 ----
        Container(
          margin: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: scheme.primaryContainer.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(Icons.account_tree_outlined,
                      size: 17, color: scheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '$instance 共占用 ${pinout.pins.length} 个引脚、'
                      '${bySignal.length} 个信号',
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                pinout.fullyDefault
                    ? '全部信号都有默认引脚，不需要重映射，开箱即用。'
                    : '部分信号有多个可选引脚：'
                        '绿色的默认引脚直接用；橙色的需要先调 GPIO_PinRemapConfig。',
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.55,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              if (onOpenPeripheral != null) ...<Widget>[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    icon: const Icon(Icons.functions, size: 16),
                    label: Text(
                      '查看 ${pinout.peripheralId} 的库函数',
                      style: const TextStyle(fontSize: 12),
                    ),
                    onPressed: onOpenPeripheral,
                  ),
                ),
              ],
            ],
          ),
        ),

        // ---- 逐信号列出引脚 ----
        for (final entry in _sortedSignals(bySignal))
          _SignalBlock(
            signal: entry.key,
            options: entry.value,
            onTapPin: onTapPin,
          ),
      ],
    );
  }

  /// 信号排序：把"看起来像主数据线"的排前面。
  ///
  /// 用户接线时最关心 TX/RX、SCK/MISO/MOSI、SCL/SDA 这几个，
  /// 而 `CH1_ETR`、`SMBAI` 之类靠后。不做复杂排序，
  /// 只把常见的主信号提到前面，其余保持原顺序。
  static List<MapEntry<String, List<PeripheralPinSignal>>> _sortedSignals(
    Map<String, List<PeripheralPinSignal>> bySignal,
  ) {
    const priority = <String>[
      'TX', 'RX', 'SCK', 'MISO', 'MOSI', 'NSS',
      'SCL', 'SDA', 'CTS', 'RTS', 'CK',
    ];
    int rank(String s) {
      final i = priority.indexOf(s);
      return i < 0 ? priority.length : i;
    }

    final entries = bySignal.entries.toList();
    entries.sort((a, b) {
      final byRank = rank(a.key).compareTo(rank(b.key));
      if (byRank != 0) return byRank;
      return a.key.compareTo(b.key);
    });
    return entries;
  }
}

/// 一个信号的引脚选项块。
class _SignalBlock extends StatelessWidget {
  final String signal;
  final List<PeripheralPinSignal> options;
  final void Function(Pin pin) onTapPin;

  const _SignalBlock({
    required this.signal,
    required this.options,
    required this.onTapPin,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // 有多条说明这个信号可以走不同引脚，值得提示用户"选哪个"
    final multiple = options.length > 1;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 5, 12, 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // 信号名标题
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(9),
              ),
            ),
            child: Row(
              children: <Widget>[
                Text(
                  signal,
                  style: TextStyle(
                    fontFamilyFallback: AppFonts.mono,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(width: 8),
                if (multiple)
                  Text(
                    '${options.length} 个可选引脚',
                    style: TextStyle(
                      fontSize: 10.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          for (var i = 0; i < options.length; i++)
            _PinOptionRow(
              option: options[i],
              isFirst: i == 0,
              onTap: () => onTapPin(options[i].pin),
            ),
        ],
      ),
    );
  }
}

/// 一个"信号 → 引脚"的候选行。
class _PinOptionRow extends StatelessWidget {
  final PeripheralPinSignal option;
  final bool isFirst;
  final VoidCallback onTap;

  const _PinOptionRow({
    required this.option,
    required this.isFirst,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final remap = option.remapRequired;
    // 默认引脚用绿（可直接用），需重映射用橙（要额外配置）
    final color = remap ? const Color(0xFFE08A1E) : const Color(0xFF3E9C5A);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.vertical(
        bottom: isFirst && !remap ? Radius.zero : const Radius.circular(9),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 9, 10, 9),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // 状态圆点
            Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.only(top: 4.5),
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 10),
            // 引脚名 + 引脚号
            SizedBox(
              width: 62,
              child: Text(
                option.pinName,
                style: TextStyle(
                  fontFamilyFallback: AppFonts.mono,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ),
            const SizedBox(width: 4),
            // 说明：默认/需重映射 + 重映射提示
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '第 ${option.pinNumber} 脚 · '
                    '${remap ? '需重映射' : '默认引脚'}',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                  if (remap && option.remapNoteZh.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        option.remapNoteZh,
                        style: TextStyle(
                          fontSize: 11,
                          height: 1.5,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 17, color: scheme.outline),
          ],
        ),
      ),
    );
  }
}

/// 外设实例选择条（横向滚动的 chip）。
class PeripheralSelector extends StatelessWidget {
  /// 全部实例名
  final List<String> instances;

  /// 当前选中
  final String selected;

  /// 每个实例的信号数（chip 上显示，让用户知道这个外设占多少脚）
  final int Function(String instance) pinCountOf;

  /// 选择回调
  final ValueChanged<String> onSelect;

  const PeripheralSelector({
    super.key,
    required this.instances,
    required this.selected,
    required this.pinCountOf,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 42,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        children: <Widget>[
          for (final inst in instances)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                selected: inst == selected,
                onSelected: (_) => onSelect(inst),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                label: Text(
                  '$inst ${pinCountOf(inst)}',
                  style: TextStyle(
                    fontFamilyFallback: inst == selected ? null : AppFonts.mono,
                    fontSize: 11.5,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
