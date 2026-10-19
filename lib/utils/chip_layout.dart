import 'dart:ui';

import '../models/pin.dart';

/// 芯片封装的一条边。
enum ChipSide {
  /// 左侧（引脚号自上而下递增）
  left('左侧'),

  /// 下侧（引脚号自左向右递增）
  bottom('下侧'),

  /// 右侧（引脚号自下而上递增）
  right('右侧'),

  /// 上侧（引脚号自右向左递增）
  top('上侧');

  final String labelZh;

  const ChipSide(this.labelZh);
}

/// 一个引脚在封装图上的位置。
class PinSlot {
  /// 引脚
  final Pin pin;

  /// 所在边
  final ChipSide side;

  /// 在该边上的序号（0 起）
  final int indexOnSide;

  /// 该边的引脚总数
  final int sideCount;

  const PinSlot({
    required this.pin,
    required this.side,
    required this.indexOnSide,
    required this.sideCount,
  });

  /// 归一化坐标（0..1，相对封装外框）。
  ///
  /// 用于把引脚摆到矩形边上：左/右边只关心 y，上/下边只关心 x。
  /// 返回的坐标是引脚**中心**所在位置。
  Offset normalizedCenter() {
    // 把 index 映射到 0..1，并留出边距，避免首尾引脚贴在角上
    final t = sideCount <= 1 ? 0.5 : (indexOnSide + 0.5) / sideCount;
    switch (side) {
      case ChipSide.left:
        return Offset(0, t);
      case ChipSide.right:
        return Offset(1, t);
      case ChipSide.top:
        return Offset(t, 0);
      case ChipSide.bottom:
        return Offset(t, 1);
    }
  }
}

/// LQFP48 封装图的排布。
///
/// QFP 封装的引脚号是**逆时针**排列的：
///   - 第 1 脚在左上角，沿左边向下 → 12 脚
///   - 下边从左到右 → 24 脚
///   - 右边从下到上 → 36 脚
///   - 上边从右到左 → 48 脚
///
/// 这是真实封装的定义，不是审美选择：看错方向会把引脚号和位置对错，
/// 所以这里按标准写死，并用测试锁住。
class ChipLayout {
  /// 每条边上的引脚数（48 / 4 = 12）
  final int perSide;

  /// 总引脚数
  final int totalPins;

  const ChipLayout({this.perSide = 12, this.totalPins = 48});

  /// 计算全部引脚的槽位。传入的引脚按引脚号匹配。
  List<PinSlot> slots(List<Pin> pins) {
    final byNumber = <int, Pin>{for (final p in pins) p.number: p};
    final out = <PinSlot>[];

    for (var number = 1; number <= totalPins; number++) {
      final pin = byNumber[number];
      if (pin == null) continue; // 数据缺失时跳过而不是崩
      final side = sideOf(number);
      out.add(PinSlot(
        pin: pin,
        side: side,
        indexOnSide: indexOnSideOf(number),
        sideCount: perSide,
      ));
    }
    return out;
  }

  /// 引脚号 → 所在边（逆时针）。
  ChipSide sideOf(int number) {
    if (number <= perSide) return ChipSide.left;
    if (number <= perSide * 2) return ChipSide.bottom;
    if (number <= perSide * 3) return ChipSide.right;
    return ChipSide.top;
  }

  /// 引脚号 → 在该边上的序号（0 起）。
  ///
  /// 左边与下边是正序；右边与上边是**逆序**（因为逆时针走回来），
  /// 这正是 QFP 引脚编号方向的体现。
  int indexOnSideOf(int number) {
    final side = sideOf(number);
    final offset = (number - 1) % perSide;
    switch (side) {
      case ChipSide.left:
      case ChipSide.bottom:
        return offset;
      case ChipSide.right:
      case ChipSide.top:
        return perSide - 1 - offset;
    }
  }
}

/// 引脚按功能归类，用于图上着色与筛选。
enum PinCategory {
  power('电源', Color(0xFFD9534F)),
  ground('地', Color(0xFF6C757D)),
  reset('复位', Color(0xFF9C6ADE)),
  boot('BOOT', Color(0xFF8B6B3D)),
  osc('晶振', Color(0xFF2E9E8F)),
  debug('调试口', Color(0xFFE08A1E)),
  gpio('普通 GPIO', Color(0xFF3D7EDB)),
  af('复用功能', Color(0xFF4C9A5B));

  /// 中文名
  final String labelZh;

  /// 图上配色
  final Color color;

  const PinCategory(this.labelZh, this.color);

  /// 判断一个引脚属于哪一类（取最"特别"的那一类）。
  ///
  /// 优先级刻意把电源/地/复位/BOOT/晶振/调试口排在普通 GPIO 之前：
  /// 一个引脚常常同时是 gpio，但用户更关心"它是电源脚"。
  static PinCategory of(Pin pin) {
    final g = pin.groups;
    if (g.contains(PinGroup.power)) return PinCategory.power;
    if (g.contains(PinGroup.ground)) return PinCategory.ground;
    if (g.contains(PinGroup.reset)) return PinCategory.reset;
    if (g.contains(PinGroup.boot)) return PinCategory.boot;
    if (g.contains(PinGroup.osc)) return PinCategory.osc;
    if (g.contains(PinGroup.debug) || pin.jtagSwd != null) {
      return PinCategory.debug;
    }
    // 有复用功能（af）的 GPIO 单独一类，便于找"这个脚能不能接串口"
    if (pin.functions.any((f) => f.kind == PinFunctionKind.af)) {
      return PinCategory.af;
    }
    return PinCategory.gpio;
  }
}
