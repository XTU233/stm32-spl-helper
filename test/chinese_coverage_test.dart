// 中文覆盖的完整性守门测试。
//
// 背景：用户反馈"I2C / SPI 的 Init 结构体点进去，成员说明还是英文"。
// 排查发现是**阶段 1 的历史遗留**——当时只给 5 个重点外设
// （GPIO/RCC/USART/TIM/MISC）写了符号中文，其余 75 个带成员的符号
// 全是英文，共 712 条成员说明缺失；另外 CMSIS/CORTEX 两个外设
// 连简介都没有。
//
// 这类问题用"抽查一两个函数"是发现不了的，必须**穷举断言**。
// 所以这个文件按"用户会点到的粒度"逐层检查，任何一处退回英文就失败。

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:stm32_spl_helper/models/compile_error.dart';
import 'package:stm32_spl_helper/models/peripheral.dart';
import 'package:stm32_spl_helper/models/pin.dart';
import 'package:stm32_spl_helper/models/symbol_item.dart';

Map<String, dynamic> readJson(String rel) => jsonDecode(
      File('assets/data/$rel').readAsStringSync(),
    ) as Map<String, dynamic>;

List<SymbolItem> allSymbols() => <SymbolItem>[
      ...(readJson('symbols.json')['symbols'] as List)
          .map((e) => SymbolItem.fromJson(e as Map<String, dynamic>)),
      ...(readJson('registers.json')['symbols'] as List)
          .map((e) => SymbolItem.fromJson(e as Map<String, dynamic>)),
    ];

void main() {
  group('结构体成员中文（用户点 Init 结构体看到的内容）', () {
    test('所有 Init/Config 类结构体的成员都有中文', () {
      final symbols = allSymbols();
      // 用户最常点进去的：各种 xxx_InitTypeDef
      final initTypes =
          symbols.where((s) => s.name.endsWith('InitTypeDef')).toList();

      expect(initTypes.length, greaterThan(15),
          reason: 'InitTypeDef 数量异常，数据可能不完整');

      final missing = <String>[];
      for (final s in initTypes) {
        for (final m in s.members) {
          if (m.descZh.isEmpty) {
            missing.add('${s.name}.${m.name}');
          }
        }
      }
      expect(missing, isEmpty,
          reason: '${missing.length} 个 InitTypeDef 成员缺中文：'
              '${missing.take(15)}');
    });

    test('所有枚举类型的成员都有中文', () {
      final symbols = allSymbols();
      final enums = symbols
          .where((s) => s.kind == SymbolKind.enumType && s.members.isNotEmpty)
          .toList();

      final missing = <String>[];
      for (final s in enums) {
        for (final m in s.members) {
          if (m.descZh.isEmpty) missing.add('${s.name}.${m.name}');
        }
      }
      expect(missing, isEmpty,
          reason: '${missing.length} 个枚举成员缺中文：${missing.take(15)}');
    });

    test('每个带成员的符号，至少成员不能全是英文', () {
      // 这条比上面两条宽松，用来兜住 CMSIS 寄存器这类
      // "量大但不是 Init 结构体"的符号
      final symbols = allSymbols();
      final withMembers =
          symbols.where((s) => s.members.isNotEmpty).toList();

      // ETH_TypeDef 是有意豁免的：STM32F103 全系没有以太网外设
      // （连 ST 自己的 SPL 里都不存在 ETH 驱动），这 63 个寄存器
      // 在本型号上永远用不到，为它写中文只是凑数。
      const exempt = <String>{'ETH_TypeDef'};

      final allEnglish = <String>[];
      for (final s in withMembers) {
        if (exempt.contains(s.name)) continue;
        final hasAnyZh = s.members.any((m) => m.descZh.isNotEmpty);
        if (!hasAnyZh) allEnglish.add(s.name);
      }
      expect(allEnglish, isEmpty,
          reason: '${allEnglish.length} 个带成员的符号成员全是英文：'
              '${allEnglish.take(15)}');
    });

    test('成员中文覆盖率不低于 90%', () {
      // 上一条只要求"不能全是英文"，这条守住整体比例，
      // 防止将来新增结构体时只写了 briefZh 就交差。
      final symbols = allSymbols();
      var total = 0;
      var withZh = 0;
      for (final s in symbols) {
        for (final m in s.members) {
          total++;
          if (m.descZh.isNotEmpty) withZh++;
        }
      }
      expect(total, greaterThan(700), reason: '成员总数异常：$total');
      final ratio = withZh / total;
      expect(ratio, greaterThan(0.90),
          reason: '成员中文覆盖仅 ${(ratio * 100).toStringAsFixed(1)}%'
              '（$withZh/$total），应不低于 90%');
    });
  });

  group('外设简介', () {
    test('每个外设都有中文简介与使用总览', () {
      final peripherals = (readJson('peripherals.json')['peripherals'] as List)
          .map((e) => Peripheral.fromJson(e as Map<String, dynamic>))
          .toList();

      final noIntro = <String>[];
      final noUsage = <String>[];
      for (final p in peripherals) {
        if (p.introZh.isEmpty) noIntro.add(p.id);
        if (p.usageOverviewZh.isEmpty) noUsage.add(p.id);
      }
      expect(noIntro, isEmpty, reason: '缺简介的外设：$noIntro');
      expect(noUsage, isEmpty, reason: '缺使用总览的外设：$noUsage');
    });

    test('每个外设都有中文名', () {
      final peripherals = (readJson('peripherals.json')['peripherals'] as List)
          .map((e) => Peripheral.fromJson(e as Map<String, dynamic>))
          .toList();
      final missing =
          peripherals.where((p) => p.nameZh.isEmpty).map((p) => p.id).toList();
      expect(missing, isEmpty, reason: '缺中文名的外设：$missing');
    });

    test('每个分组都有中文标题', () {
      final peripherals = (readJson('peripherals.json')['peripherals'] as List)
          .map((e) => Peripheral.fromJson(e as Map<String, dynamic>))
          .toList();
      final missing = <String>[];
      for (final p in peripherals) {
        for (final sec in p.sections) {
          if (sec.title.trim().isEmpty) missing.add('${p.id}/${sec.id}');
        }
      }
      expect(missing, isEmpty, reason: '缺中文标题的分组：$missing');
    });
  });

  group('函数（已全量覆盖，防止回退）', () {
    test('488 个函数都有中文简述、使用说明与参数说明', () {
      final peripherals = (readJson('peripherals.json')['peripherals'] as List)
          .map((e) => Peripheral.fromJson(e as Map<String, dynamic>))
          .toList();

      final noBrief = <String>[];
      final noUsage = <String>[];
      final noParam = <String>[];
      var total = 0;

      for (final p in peripherals) {
        if (p.functionCount == 0) continue;
        final bundle = readJson('functions/${p.id}.json');
        for (final e in bundle['functions'] as List) {
          final m = e as Map<String, dynamic>;
          total++;
          final id = m['id'] as String;
          if ((m['briefZh'] as String).isEmpty) noBrief.add(id);
          if ((m['usageZh'] as String).isEmpty) noUsage.add(id);
          for (final param in m['params'] as List) {
            final pm = param as Map<String, dynamic>;
            if ((pm['descZh'] as String? ?? '').isEmpty) {
              noParam.add('$id.${pm['name']}');
            }
          }
        }
      }

      expect(total, 488);
      expect(noBrief, isEmpty, reason: '缺中文简述：${noBrief.take(10)}');
      expect(noUsage, isEmpty, reason: '缺使用说明：${noUsage.take(10)}');
      expect(noParam, isEmpty, reason: '缺参数说明：${noParam.take(10)}');
    });
  });

  group('引脚与编译错误', () {
    test('48 个引脚都有中文默认功能说明', () {
      final pinout = PinoutData.fromJson(readJson('pinout_f103c8t6.json'));
      final missing = pinout.pins
          .where((p) => p.defaultFunctionZh.isEmpty)
          .map((p) => p.number)
          .toList();
      expect(missing, isEmpty, reason: '缺中文说明的引脚：$missing');
    });

    test('15 条编译错误都有中文标题与解释', () {
      final bundle =
          CompileErrorBundle.fromJson(readJson('compile_errors.json'));
      final missing = <String>[];
      for (final e in bundle.errors) {
        if (e.titleZh.isEmpty || e.explainZh.isEmpty) missing.add(e.id);
      }
      expect(missing, isEmpty, reason: '缺中文的编译错误：$missing');
    });
  });

  group('overlay 分文件合并（防止新增文件不生效）', () {
    test('overlay 目录下存在多个 symbols*.json 分文件', () {
      final dir = Directory('data/zh_overlay');
      final files = dir
          .listSync()
          .whereType<File>()
          .where((f) =>
              f.path.split(Platform.pathSeparator).last.startsWith('symbols') &&
              f.path.endsWith('.json'))
          .toList();
      // 早期只有 symbols.json，后来按类别拆分；
      // 这条断言防的是"拆了文件却没接进合并脚本"
      expect(files.length, greaterThan(1),
          reason: '符号中文应拆成多个 symbols*.json 分文件便于维护');
    });

    test('合并脚本支持多文件符号 overlay', () {
      final f = File('tools/merge_overlay.py');
      final src = f.readAsStringSync();
      expect(src, contains('load_symbol_overlays'),
          reason: 'merge_overlay.py 应通过 load_symbol_overlays 读取多文件');
      expect(src, contains('glob("symbols*.json")'),
          reason: '应按通配符读取 symbols*.json');
      expect(src, contains('_deep_merge'),
          reason: '同一符号跨文件补字段需要深合并，否则后写覆盖前写');
    });
  });
}
