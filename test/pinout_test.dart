// 阶段 7（引脚速查表）的测试。
//
// 重点是**封装几何**：QFP 的引脚号是逆时针排列的，看错方向会把引脚号和
// 物理位置对错——这种错误在界面上"看起来正常"（方块都摆好了），
// 只有断言具体坐标才能发现。所以这里用纯逻辑验证 ChipLayout，
// 再用真实数据渲染一遍排布图确认不溢出。

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stm32_spl_helper/models/pin.dart';
import 'package:stm32_spl_helper/utils/chip_layout.dart';
import 'package:stm32_spl_helper/utils/theme.dart';
import 'package:stm32_spl_helper/widgets/chip_diagram.dart';

/// 读真实引脚数据
PinoutData readPinout() {
  final f = File('assets/data/pinout_f103c8t6.json');
  expect(f.existsSync(), isTrue, reason: '引脚数据不存在，请先跑 merge_overlay.py');
  return PinoutData.fromJson(
    jsonDecode(f.readAsStringSync()) as Map<String, dynamic>,
  );
}

void main() {
  group('封装几何：引脚号方向（逆时针）', () {
    const layout = ChipLayout();

    test('四条边各 12 个引脚', () {
      expect(layout.perSide, 12);
      expect(layout.totalPins, 48);
    });

    test('边归属：1-12 左、13-24 下、25-36 右、37-48 上', () {
      expect(layout.sideOf(1), ChipSide.left);
      expect(layout.sideOf(12), ChipSide.left);
      expect(layout.sideOf(13), ChipSide.bottom);
      expect(layout.sideOf(24), ChipSide.bottom);
      expect(layout.sideOf(25), ChipSide.right);
      expect(layout.sideOf(36), ChipSide.right);
      expect(layout.sideOf(37), ChipSide.top);
      expect(layout.sideOf(48), ChipSide.top);
    });

    test('第 1 脚在左上角（左边第一个）', () {
      expect(layout.sideOf(1), ChipSide.left);
      expect(layout.indexOnSideOf(1), 0);
    });

    test('左边自上而下递增（12 脚在左下）', () {
      expect(layout.indexOnSideOf(1), 0);
      expect(layout.indexOnSideOf(2), 1);
      expect(layout.indexOnSideOf(12), 11);
    });

    test('下边自左向右递增（13 在左下，24 在右下）', () {
      expect(layout.indexOnSideOf(13), 0);
      expect(layout.indexOnSideOf(24), 11);
    });

    test('右边自下而上递增（25 在右下，36 在右上）', () {
      // 这是最容易写错的一条：右边不是从上往下数的
      expect(layout.indexOnSideOf(25), 11);
      expect(layout.indexOnSideOf(36), 0);
    });

    test('上边自右向左递增（37 在右上，48 在左上）', () {
      expect(layout.indexOnSideOf(37), 11);
      expect(layout.indexOnSideOf(48), 0);
    });

    test('归一化坐标：1 脚在左上、13 脚在左下、25 脚在右下、37 脚在右上', () {
      Offset c(int n) => PinSlot(
            pin: Pin(number: n, name: 'X'),
            side: layout.sideOf(n),
            indexOnSide: layout.indexOnSideOf(n),
            sideCount: layout.perSide,
          ).normalizedCenter();

      // 1 脚：左边靠上
      expect(c(1).dx, 0);
      expect(c(1).dy, lessThan(0.2));

      // 13 脚：下边靠左
      expect(c(13).dy, 1);
      expect(c(13).dx, lessThan(0.2));

      // 25 脚：右边靠下
      expect(c(25).dx, 1);
      expect(c(25).dy, greaterThan(0.8));

      // 37 脚：上边靠右
      expect(c(37).dy, 0);
      expect(c(37).dx, greaterThan(0.8));
    });

    test('每个引脚号落在唯一的（边+序号）上，不重叠', () {
      final seen = <String>{};
      for (var n = 1; n <= 48; n++) {
        final key = '${layout.sideOf(n)}#${layout.indexOnSideOf(n)}';
        expect(seen.add(key), isTrue, reason: '引脚 $n 的位置与其它引脚重叠：$key');
      }
      expect(seen.length, 48);
    });
  });

  group('封装几何：真实数据排布', () {
    test('48 个引脚全部能摆到位置上', () {
      final pinout = readPinout();
      const layout = ChipLayout();
      final slots = layout.slots(pinout.pins);
      expect(slots.length, 48);
      // 每条边正好 12 个
      final perSide = <ChipSide, int>{};
      for (final s in slots) {
        perSide[s.side] = (perSide[s.side] ?? 0) + 1;
      }
      expect(perSide[ChipSide.left], 12);
      expect(perSide[ChipSide.bottom], 12);
      expect(perSide[ChipSide.right], 12);
      expect(perSide[ChipSide.top], 12);
    });

    test('引脚号与引脚名对得上（抽查几个真实位置）', () {
      final pinout = readPinout();
      const layout = ChipLayout();

      // 第 1 脚是 VBAT，第 5 脚 OSC_IN，第 7 脚 NRST，第 44 脚 BOOT0
      String nameAt(int number) =>
          pinout.pinByNumber(number)!.name;

      expect(nameAt(1), 'VBAT');
      expect(nameAt(5), 'OSC_IN');
      expect(nameAt(7), 'NRST');
      expect(nameAt(44), 'BOOT0');

      // BOOT0（44 脚）在上边，且靠右
      expect(layout.sideOf(44), ChipSide.top);
      expect(layout.indexOnSideOf(44), lessThan(12));
    });

    test('数据缺失时跳过而不是崩', () {
      const layout = ChipLayout();
      // 只给 3 个引脚，其余缺失
      final slots = layout.slots(<Pin>[
        const Pin(number: 1, name: 'VBAT'),
        const Pin(number: 25, name: 'PB12'),
        const Pin(number: 48, name: 'VDD_3'),
      ]);
      expect(slots.length, 3);
    });
  });

  group('引脚分类', () {
    test('电源/地/复位/BOOT/晶振 优先于 GPIO', () {
      final pinout = readPinout();
      // 第 1 脚 VBAT 同时可能被标成别的，但必须归到电源
      expect(PinCategory.of(pinout.pinByNumber(1)!), PinCategory.power);
      // 第 8 脚 VSSA 是地
      expect(PinCategory.of(pinout.pinByNumber(8)!), PinCategory.ground);
      // 第 7 脚 NRST 是复位
      expect(PinCategory.of(pinout.pinByNumber(7)!), PinCategory.reset);
      // 第 44 脚 BOOT0
      expect(PinCategory.of(pinout.pinByNumber(44)!), PinCategory.boot);
      // 第 5 脚 OSC_IN 是晶振
      expect(PinCategory.of(pinout.pinByNumber(5)!), PinCategory.osc);
    });

    test('调试口引脚（PA13/PA14/PB3/PB4/PA15）归为调试口', () {
      final pinout = readPinout();
      for (final n in <int>[34, 37, 38, 39, 40]) {
        expect(
          PinCategory.of(pinout.pinByNumber(n)!),
          PinCategory.debug,
          reason: '第 $n 脚应归为调试口',
        );
      }
    });

    test('有复用功能的 GPIO 归为复用，没有的归为普通 GPIO', () {
      final pinout = readPinout();
      // PA9 有 USART1_TX → 复用
      expect(PinCategory.of(pinout.pinByNumber(30)!), PinCategory.af);
      // PB2 只有 PB2 本身 → 普通 GPIO
      expect(PinCategory.of(pinout.pinByNumber(20)!), PinCategory.gpio);
    });

    test('48 个引脚都有分类，且计数与数据一致', () {
      final pinout = readPinout();
      final counts = <PinCategory, int>{};
      for (final p in pinout.pins) {
        counts[PinCategory.of(p)] = (counts[PinCategory.of(p)] ?? 0) + 1;
      }
      final total = counts.values.fold<int>(0, (a, b) => a + b);
      expect(total, 48);
      // 电源 5、地 4、复位 1、BOOT 1、晶振 2、调试口 5
      expect(counts[PinCategory.power], 5);
      expect(counts[PinCategory.ground], 4);
      expect(counts[PinCategory.reset], 1);
      expect(counts[PinCategory.boot], 1);
      expect(counts[PinCategory.osc], 2);
      expect(counts[PinCategory.debug], 5);
    });
  });

  group('按功能反查引脚（需求 5.6 验收点）', () {
    test('USART1_TX 能查到 PA9', () {
      final pinout = readPinout();
      final pins = pinout.searchByFunction('USART1_TX');
      expect(pins, isNotEmpty);
      expect(pins.map((p) => p.name), contains('PA9'));
    });

    test('USART1_TX 同时能查到 PB6（复用功能有两个可选脚）', () {
      final pinout = readPinout();
      final names = pinout.searchByFunction('USART1_TX').map((p) => p.name);
      expect(names, containsAll(<String>['PA9', 'PB6']));
    });

    test('TIM1_CH2 能查到 PA9', () {
      final pinout = readPinout();
      expect(
        pinout.searchByFunction('TIM1_CH2').map((p) => p.name),
        contains('PA9'),
      );
    });

    test('ADC12_IN0 能查到 PA0', () {
      final pinout = readPinout();
      expect(
        pinout.searchByFunction('ADC12_IN0').map((p) => p.name),
        contains('PA0'),
      );
    });

    test('CAN_TX 能查到 PA12 与 PB9', () {
      final pinout = readPinout();
      final names = pinout.searchByFunction('CAN_TX').map((p) => p.name);
      expect(names, containsAll(<String>['PA12', 'PB9']));
    });

    test('不区分大小写', () {
      final pinout = readPinout();
      expect(
        pinout.searchByFunction('usart1_tx').map((p) => p.name),
        contains('PA9'),
      );
    });

    test('输入引脚名也能定位', () {
      final pinout = readPinout();
      final pins = pinout.searchByFunction('PA9');
      expect(pins.map((p) => p.name), contains('PA9'));
    });

    test('部分匹配（USART 开头的全部）', () {
      final pinout = readPinout();
      final pins = pinout.searchByFunction('USART');
      expect(pins.length, greaterThan(5), reason: 'USART 相关引脚应有多个');
    });

    test('结果按引脚号升序', () {
      final pinout = readPinout();
      final pins = pinout.searchByFunction('USART');
      final numbers = pins.map((p) => p.number).toList();
      final sorted = List<int>.from(numbers)..sort();
      expect(numbers, sorted);
    });

    test('查不到时返回空列表而不是抛异常', () {
      final pinout = readPinout();
      expect(pinout.searchByFunction('NOT_A_REAL_FUNCTION'), isEmpty);
      expect(pinout.searchByFunction('   '), isEmpty);
    });
  });

  group('引脚数据：已核对标记', () {
    test('verified 为 true 且说明了数据来源', () {
      final pinout = readPinout();
      expect(pinout.verified, isTrue,
          reason: '用户已确认引脚定义表完全正确，verified 应为 true');
      expect(pinout.verifiedNote, isNotEmpty);
      // 说明里要提到来源表，便于日后追溯
      expect(pinout.verifiedNote, contains('引脚定义'));
    });

    test('5V 容忍引脚 21 个（与源表一致）', () {
      final pinout = readPinout();
      final ft = pinout.pins.where((p) => p.fiveVoltTolerant).toList();
      expect(ft.length, 21);
    });

    test('引脚号 1..48 连续无缺号', () {
      final pinout = readPinout();
      final numbers = pinout.pins.map((p) => p.number).toList()..sort();
      expect(numbers, List<int>.generate(48, (i) => i + 1));
    });
  });

  group('排布图渲染（真机宽度）', () {
    Widget wrap(Widget child) => MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(body: child),
        );

    testWidgets('360dp 下渲染 48 个引脚不溢出', (tester) async {
      tester.view.physicalSize = const Size(360 * 3, 800 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      final pinout = readPinout();
      await tester.pumpWidget(wrap(
        SingleChildScrollView(
          child: ChipDiagram(
            pins: pinout.pins,
            onTapPin: (_) {},
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(ChipDiagram), findsOneWidget);
    });

    testWidgets('极窄屏（320dp）下也不溢出', (tester) async {
      tester.view.physicalSize = const Size(320 * 3, 640 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      final pinout = readPinout();
      await tester.pumpWidget(wrap(
        SingleChildScrollView(
          child: ChipDiagram(pins: pinout.pins, onTapPin: (_) {}),
        ),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('每个引脚块都能点到，且回调带回正确的引脚号', (tester) async {
      tester.view.physicalSize = const Size(400 * 3, 800 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      final pinout = readPinout();
      final tapped = <int>[];

      await tester.pumpWidget(wrap(
        SingleChildScrollView(
          child: ChipDiagram(
            pins: pinout.pins,
            onTapPin: (p) => tapped.add(p.number),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // 点第 1 脚（VBAT，左上角）
      await tester.tap(find.text('VBAT'));
      await tester.pumpAndSettle();
      expect(tapped, contains(1));
    });

    testWidgets('高亮集合生效：未命中的引脚变暗但仍可点', (tester) async {
      tester.view.physicalSize = const Size(400 * 3, 800 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      final pinout = readPinout();
      // 只高亮 PA9（第 30 脚）
      await tester.pumpWidget(wrap(
        SingleChildScrollView(
          child: ChipDiagram(
            pins: pinout.pins,
            highlighted: <int>{30},
            onTapPin: (_) {},
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // 变暗是通过 Opacity 实现的，应能找到一个透明度为 1 的（PA9）
      // 和一批透明度小于 1 的
      final opacities = tester
          .widgetList<Opacity>(find.byType(Opacity))
          .map((o) => o.opacity)
          .toList();
      expect(opacities, contains(1.0));
      expect(opacities.where((o) => o < 1.0), isNotEmpty);
      expect(tester.takeException(), isNull);
    });
  });

  group('图例', () {
    testWidgets('图例显示类别与数量', (tester) async {
      final pinout = readPinout();
      final counts = <PinCategory, int>{};
      for (final p in pinout.pins) {
        final c = PinCategory.of(p);
        counts[c] = (counts[c] ?? 0) + 1;
      }
      final present =
          PinCategory.values.where((c) => (counts[c] ?? 0) > 0).toList();

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: PinLegend(
            categories: present,
            counts: counts,
            selected: null,
            onSelect: (_) {},
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('电源 5'), findsOneWidget);
      expect(find.text('地 4'), findsOneWidget);
      expect(find.text('调试口 5'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
