// 「按外设看引脚」视图的测试。
//
// 这个功能的用户问题是"我要用 SPI1，接哪几个脚"，
// 所以测试要验证的是**答案对不对**：SPI1 的四个信号是否都在、
// 默认引脚与重映射引脚是否分得清、ADC 通道是否完整。
//
// 分组逻辑放在 PinoutData 里（纯数据），所以大部分是普通 test；
// 只有视图渲染用 widget test。

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stm32_spl_helper/models/pin.dart';
import 'package:stm32_spl_helper/utils/theme.dart';
import 'package:stm32_spl_helper/widgets/peripheral_pin_view.dart';

PinoutData readPinout() => PinoutData.fromJson(
      jsonDecode(File('assets/data/pinout_f103c8t6.json').readAsStringSync())
          as Map<String, dynamic>,
    );

void main() {
  group('外设实例索引', () {
    test('能列出全部实例，且实例数合理', () {
      final p = readPinout();
      final instances = p.peripheralInstances;
      // 数据里有 SPI1/2、USART1/2/3、I2C1/2、TIM1~4、ADC12、CAN 等
      expect(instances.length, greaterThanOrEqualTo(13));
      expect(instances, contains('SPI1'));
      expect(instances, contains('SPI2'));
      expect(instances, contains('USART1'));
      expect(instances, contains('TIM2'));
      expect(instances, contains('I2C1'));
    });

    test('SPI1 与 SPI2 是两个独立实例（引脚完全不同）', () {
      final p = readPinout();
      final spi1 = p.peripheralPinout('SPI1')!;
      final spi2 = p.peripheralPinout('SPI2')!;
      final pins1 = spi1.pins.map((x) => x.name).toSet();
      final pins2 = spi2.pins.map((x) => x.name).toSet();
      expect(pins1.intersection(pins2), isEmpty,
          reason: 'SPI1 与 SPI2 不应共用引脚');
    });

    test('"其它"排在最后', () {
      final p = readPinout();
      final instances = p.peripheralInstances;
      expect(instances.last, otherPeripheralId);
    });

    test('同一类别的实例相邻（SPI1/SPI2、USART1/2/3）', () {
      final p = readPinout();
      final instances = p.peripheralInstances;
      final spi1 = instances.indexOf('SPI1');
      final spi2 = instances.indexOf('SPI2');
      expect((spi1 - spi2).abs(), 1, reason: 'SPI1 与 SPI2 应相邻');

      final us = <String>['USART1', 'USART2', 'USART3']
          .map(instances.indexOf)
          .toList()
        ..sort();
      expect(us[1] - us[0], 1);
      expect(us[2] - us[1], 1);
    });
  });

  group('SPI1 的引脚分配（典型使用场景）', () {
    test('四个信号齐全：SCK/MISO/MOSI/NSS', () {
      final spi1 = readPinout().peripheralPinout('SPI1')!;
      final signals = spi1.bySignal.keys.toSet();
      expect(signals, containsAll(<String>['SCK', 'MISO', 'MOSI', 'NSS']));
    });

    test('默认引脚是 PA5/PA6/PA7/PA4', () {
      final spi1 = readPinout().peripheralPinout('SPI1')!;
      final defaults = <String, String>{
        for (final s in spi1.defaultSignals) s.signal: s.pinName,
      };
      expect(defaults['SCK'], 'PA5');
      expect(defaults['MISO'], 'PA6');
      expect(defaults['MOSI'], 'PA7');
      expect(defaults['NSS'], 'PA4');
    });

    test('SCK 还有重映射引脚 PB3', () {
      final spi1 = readPinout().peripheralPinout('SPI1')!;
      final sck = spi1.bySignal['SCK']!;
      expect(sck.length, 2);
      final remapped = sck.where((s) => s.remapRequired).toList();
      expect(remapped.length, 1);
      expect(remapped.first.pinName, 'PB3');
      // 重映射必须给出配置说明，否则用户不知道要调什么
      expect(remapped.first.remapNoteZh, isNotEmpty);
    });

    test('SPI1 不是"全默认"（有重映射选项）', () {
      expect(readPinout().peripheralPinout('SPI1')!.fullyDefault, isFalse);
    });

    test('每个信号下的引脚按引脚号升序', () {
      final spi1 = readPinout().peripheralPinout('SPI1')!;
      spi1.bySignal.forEach((signal, list) {
        final numbers = list.map((s) => s.pinNumber).toList();
        final sorted = List<int>.from(numbers)..sort();
        expect(numbers, sorted, reason: '$signal 的引脚未按号排序');
      });
    });

    test('涉及的引脚去重且按号升序', () {
      final spi1 = readPinout().peripheralPinout('SPI1')!;
      final numbers = spi1.pins.map((x) => x.number).toList();
      expect(numbers.toSet().length, numbers.length, reason: '引脚有重复');
      final sorted = List<int>.from(numbers)..sort();
      expect(numbers, sorted);
    });
  });

  group('USART1 的引脚分配', () {
    test('TX/RX 默认在 PA9/PA10', () {
      final u1 = readPinout().peripheralPinout('USART1')!;
      final defaults = <String, String>{
        for (final s in u1.defaultSignals) s.signal: s.pinName,
      };
      expect(defaults['TX'], 'PA9');
      expect(defaults['RX'], 'PA10');
    });

    test('TX 重映射到 PB6、RX 重映射到 PB7', () {
      final u1 = readPinout().peripheralPinout('USART1')!;
      final txRemap =
          u1.bySignal['TX']!.where((s) => s.remapRequired).map((s) => s.pinName);
      final rxRemap =
          u1.bySignal['RX']!.where((s) => s.remapRequired).map((s) => s.pinName);
      expect(txRemap, contains('PB6'));
      expect(rxRemap, contains('PB7'));
    });

    test('硬件流控 CTS/RTS 也在（PA11/PA12）', () {
      final u1 = readPinout().peripheralPinout('USART1')!;
      expect(u1.bySignal.keys, containsAll(<String>['CTS', 'RTS']));
    });
  });

  group('ADC 通道', () {
    test('ADC12 是"全默认"（模拟输入不需要重映射）', () {
      final adc = readPinout().peripheralPinout('ADC12')!;
      expect(adc.fullyDefault, isTrue);
    });

    test('IN0~IN9 十个外部通道齐全，且脚位正确', () {
      final adc = readPinout().peripheralPinout('ADC12')!;
      final map = <String, String>{
        for (final s in adc.signals) s.signal: s.pinName,
      };
      for (var i = 0; i <= 9; i++) {
        expect(map.containsKey('IN$i'), isTrue, reason: '缺 ADC 通道 IN$i');
      }
      expect(map['IN0'], 'PA0');
      expect(map['IN7'], 'PA7');
      expect(map['IN8'], 'PB0');
      expect(map['IN9'], 'PB1');
    });
  });

  group('分类与信号解析', () {
    test('每个实例都带外设类别，可用于跳转到外设页', () {
      final p = readPinout();
      for (final inst in p.peripheralInstances) {
        final po = p.peripheralPinout(inst)!;
        expect(po.peripheralId, isNotEmpty, reason: '$inst 缺外设类别');
      }
      expect(p.peripheralPinout('SPI1')!.peripheralId, 'SPI');
      expect(p.peripheralPinout('USART2')!.peripheralId, 'USART');
      expect(p.peripheralPinout('TIM3')!.peripheralId, 'TIM');
      expect(p.peripheralPinout('I2C1')!.peripheralId, 'I2C');
    });

    test('信号名已剥掉外设前缀（SPI1_SCK → SCK）', () {
      final spi1 = readPinout().peripheralPinout('SPI1')!;
      for (final s in spi1.signals) {
        expect(s.signal.startsWith('SPI1_'), isFalse,
            reason: '信号名应已剥掉前缀：${s.signal}');
        // 完整名保留前缀，便于对照头文件
        expect(s.fullName.startsWith('SPI1_'), isTrue);
      }
    });

    test('复合信号名保留后半段（TIM2_CH1_ETR → CH1_ETR）', () {
      final tim2 = readPinout().peripheralPinout('TIM2')!;
      expect(tim2.bySignal.keys, contains('CH1_ETR'));
    });

    test('没有实例前缀的功能归到"其它"', () {
      final p = readPinout();
      final other = p.peripheralPinout(otherPeripheralId);
      expect(other, isNotNull);
      // MCO / TRACESWO 这类没有下划线前缀
      final names = other!.signals.map((s) => s.fullName).toSet();
      expect(names, contains('MCO'));
    });

    test('取不存在的实例返回 null 而不是抛异常', () {
      expect(readPinout().peripheralPinout('SPI9'), isNull);
    });

    test('同一实例的信号不重复（同脚同名只留一条）', () {
      final p = readPinout();
      for (final inst in p.peripheralInstances) {
        final keys = p
            .peripheralPinout(inst)!
            .signals
            .map((s) => '${s.fullName}@${s.pinNumber}')
            .toList();
        expect(keys.toSet().length, keys.length, reason: '$inst 有重复信号');
      }
    });

    // 这条守门人是这次改造中发现的真实缺口：
    // 21 个"需重映射"的复用功能里，原本只有 4 个写了配置说明，
    // 其余 17 个只标了"需重映射"却不告诉用户调哪个宏——
    // 用户看到"需重映射"却不知道该做什么，等于没说。
    test('每个需重映射的功能都必须带配置说明', () {
      final p = readPinout();
      final missing = <String>[];
      for (final inst in p.peripheralInstances) {
        for (final s in p.peripheralPinout(inst)!.remapSignals) {
          if (s.remapNoteZh.trim().isEmpty) {
            missing.add('${s.fullName}@${s.pinName}');
          }
        }
      }
      expect(missing, isEmpty,
          reason: '这些功能标了"需重映射"却没说怎么配：$missing');
    });

    test('重映射说明里含有可执行的配置线索', () {
      final p = readPinout();
      for (final inst in p.peripheralInstances) {
        for (final s in p.peripheralPinout(inst)!.remapSignals) {
          // 说明里应出现宏名或函数名，否则只是空泛描述
          expect(
            s.remapNoteZh.contains('GPIO_') ||
                s.remapNoteZh.contains('RCC_') ||
                s.remapNoteZh.contains('GPIO_PinRemapConfig'),
            isTrue,
            reason: '${s.fullName} 的说明缺少具体配置：${s.remapNoteZh}',
          );
        }
      }
    });
  });

  group('视图渲染（真机宽度）', () {
    Widget wrap(Widget child) => MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(body: child),
        );

    testWidgets('SPI1 视图列出四个信号与各自引脚', (tester) async {
      tester.view.physicalSize = const Size(360 * 3, 800 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      final spi1 = readPinout().peripheralPinout('SPI1')!;
      await tester.pumpWidget(wrap(
        PeripheralPinView(
          instance: 'SPI1',
          pinout: spi1,
          onTapPin: (_) {},
        ),
      ));
      await tester.pumpAndSettle();

      // 四个信号名都应出现
      for (final s in <String>['SCK', 'MISO', 'MOSI', 'NSS']) {
        expect(find.text(s), findsOneWidget, reason: '缺信号 $s');
      }
      // 默认引脚应出现
      for (final pin in <String>['PA5', 'PA6', 'PA7', 'PA4']) {
        expect(find.text(pin), findsOneWidget, reason: '缺引脚 $pin');
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('重映射引脚带"需重映射"标注', (tester) async {
      tester.view.physicalSize = const Size(360 * 3, 800 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      final spi1 = readPinout().peripheralPinout('SPI1')!;
      await tester.pumpWidget(wrap(
        PeripheralPinView(instance: 'SPI1', pinout: spi1, onTapPin: (_) {}),
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('需重映射'), findsWidgets);
      expect(find.textContaining('默认引脚'), findsWidgets);
    });

    testWidgets('点引脚行会回调正确的引脚', (tester) async {
      tester.view.physicalSize = const Size(360 * 3, 800 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      final spi1 = readPinout().peripheralPinout('SPI1')!;
      final tapped = <int>[];
      await tester.pumpWidget(wrap(
        PeripheralPinView(
          instance: 'SPI1',
          pinout: spi1,
          onTapPin: (p) => tapped.add(p.number),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('PA5'));
      await tester.pumpAndSettle();
      expect(tapped, contains(15)); // PA5 是第 15 脚
    });

    testWidgets('窄屏 320dp 下不溢出', (tester) async {
      tester.view.physicalSize = const Size(320 * 3, 640 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      final spi1 = readPinout().peripheralPinout('SPI1')!;
      await tester.pumpWidget(wrap(
        PeripheralPinView(instance: 'SPI1', pinout: spi1, onTapPin: (_) {}),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('全部 14 个实例在窄屏下都能渲染不溢出', (tester) async {
      tester.view.physicalSize = const Size(360 * 3, 800 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      final pinout = readPinout();
      for (final inst in pinout.peripheralInstances) {
        await tester.pumpWidget(wrap(
          PeripheralPinView(
            instance: inst,
            pinout: pinout.peripheralPinout(inst)!,
            onTapPin: (_) {},
          ),
        ));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$inst 渲染溢出');
      }
    });

    testWidgets('选择条渲染全部实例', (tester) async {
      final pinout = readPinout();
      final instances = pinout.peripheralInstances;
      await tester.pumpWidget(wrap(
        PeripheralSelector(
          instances: instances,
          selected: 'SPI1',
          pinCountOf: (i) => pinout.peripheralPinout(i)?.pins.length ?? 0,
          onSelect: (_) {},
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('SPI1'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });
}
