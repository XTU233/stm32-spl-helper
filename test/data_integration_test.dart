// 用真实生成的数据做的集成测试。
//
// 与 models_test.dart 里的假数据不同，这个测试直接读 assets/data/ 下
// 解析脚本产出的真实 JSON，验证"数据 → 模型 → 可跳转"这条链路是通的。
//
// 价值：阶段 4 的核心是关键词跳转，而跳转依赖 symbolRefs 白名单与符号表的
// 一致性。这类问题用假数据测不出来，必须用真数据。

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:stm32_spl_helper/data/search_index.dart';
import 'package:stm32_spl_helper/models/chip.dart';
import 'package:stm32_spl_helper/models/compile_error.dart';
import 'package:stm32_spl_helper/models/function_item.dart';
import 'package:stm32_spl_helper/models/item_ref.dart';
import 'package:stm32_spl_helper/models/manifest.dart';
import 'package:stm32_spl_helper/models/peripheral.dart';
import 'package:stm32_spl_helper/models/pin.dart';
import 'package:stm32_spl_helper/models/spl_data.dart';
import 'package:stm32_spl_helper/models/symbol_item.dart';
import 'package:stm32_spl_helper/utils/symbol_matcher.dart';

/// 数据目录
final Directory dataDir = Directory('assets/data');

/// 读一个 JSON 文件
Map<String, dynamic> readJson(String relative) {
  final f = File('${dataDir.path}/$relative');
  expect(f.existsSync(), isTrue, reason: '数据文件不存在：${f.path}');
  return jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
}

void main() {
  // 数据目录不存在时直接失败，避免"静默跳过"掩盖问题
  setUpAll(() {
    expect(
      dataDir.existsSync(),
      isTrue,
      reason: 'assets/data 不存在，请先运行 tools/merge_overlay.py',
    );
  });

  group('真实数据：结构与规模', () {
    test('manifest 声明的统计与实际文件一致', () {
      final manifest = readJson('manifest.json');
      final stats = manifest['stats'] as Map<String, dynamic>;

      final peripherals = readJson('peripherals.json')['peripherals'] as List;
      expect(peripherals.length, stats['peripheralCount']);

      final symbols = readJson('symbols.json')['symbols'] as List;
      expect(symbols.length, stats['apiSymbolCount']);

      final registers = readJson('registers.json')['symbols'] as List;
      expect(registers.length, stats['registerSymbolCount']);

      final errors = readJson('compile_errors.json')['errors'] as List;
      expect(errors.length, stats['compileErrorCount']);

      final pinout = readJson('pinout_f103c8t6.json')['pins'] as List;
      expect(pinout.length, stats['pinCount']);
    });

    test('每个外设都有对应的函数文件且数量一致', () {
      final peripherals = readJson('peripherals.json')['peripherals'] as List;
      for (final raw in peripherals) {
        final p = Peripheral.fromJson(raw as Map<String, dynamic>);
        final bundle = readJson('functions/${p.id}.json');
        final funcs = (bundle['functions'] as List)
            .map((e) => FunctionItem.fromJson(e as Map<String, dynamic>))
            .toList();
        expect(
          funcs.length,
          p.functionCount,
          reason: '${p.id} 的 functionCount 与实际不符',
        );
      }
    });

    test('分组里的函数 id 都能在函数文件里找到（无死链）', () {
      final peripherals = readJson('peripherals.json')['peripherals'] as List;
      for (final raw in peripherals) {
        final p = Peripheral.fromJson(raw as Map<String, dynamic>);
        final bundle = readJson('functions/${p.id}.json');
        final ids = {
          for (final e in bundle['functions'] as List)
            (e as Map<String, dynamic>)['id'] as String,
        };
        for (final sec in p.sections) {
          for (final fid in sec.functionIds) {
            expect(ids, contains(fid), reason: '${p.id} 的分组引用了不存在的 $fid');
          }
        }
      }
    });
  });

  group('真实数据：关键词跳转链路', () {
    /// 构建与 APP 运行时同款的匹配器
    SymbolMatcher buildRealMatcher() {
      final peripherals = readJson('peripherals.json')['peripherals'] as List;
      final functionNames = <String>{};
      for (final raw in peripherals) {
        final p = Peripheral.fromJson(raw as Map<String, dynamic>);
        functionNames.addAll(p.allFunctionIds);
      }
      final symbols = (readJson('symbols.json')['symbols'] as List)
          .map((e) => SymbolItem.fromJson(e as Map<String, dynamic>))
          .map((s) => s.name);
      return SymbolMatcher(functions: functionNames, symbols: symbols);
    }

    test('GPIO_Init 的示例代码里，需求点名的符号可点击', () {
      final bundle = readJson('functions/GPIO.json');
      final funcs = (bundle['functions'] as List)
          .map((e) => FunctionItem.fromJson(e as Map<String, dynamic>))
          .toList();
      final init = funcs.firstWhere((f) => f.id == 'GPIO_Init');

      // 需求 5.3 原文点名的三个符号
      expect(
        init.symbolRefs,
        contains('GPIO_Mode_Out_PP'),
        reason: '示例代码里的 GPIO_Mode_Out_PP 必须在白名单里才能点击',
      );
      expect(init.symbolRefs, contains('GPIO_InitTypeDef'));
      expect(init.symbolRefs, contains('RCC_APB2Periph_GPIOC'));

      // 白名单里的名字必须真的能在符号表/函数表里解析到
      final matcher = buildRealMatcher();
      for (final ref in init.symbolRefs) {
        expect(
          matcher.canResolve(ref),
          isTrue,
          reason: '白名单里的 $ref 无法解析，会变成死链',
        );
      }
    });

    test('示例代码里出现的库内符号都能被匹配器识别为可点击', () {
      final matcher = buildRealMatcher();
      final bundle = readJson('functions/GPIO.json');
      final funcs = (bundle['functions'] as List)
          .map((e) => FunctionItem.fromJson(e as Map<String, dynamic>))
          .toList();
      final init = funcs.firstWhere((f) => f.id == 'GPIO_Init');

      final whitelist = init.symbolRefs.toSet();
      final matched = matcher
          .findMatches(init.exampleCode, whitelist: whitelist)
          .map((m) => m.name)
          .toSet();

      expect(matched, contains('GPIO_Mode_Out_PP'));
      expect(matched, contains('GPIO_InitTypeDef'));
      expect(matched, contains('RCC_APB2PeriphClockCmd'));
      expect(matched, contains('GPIO_Pin_13'));
    });

    test('全部外设：symbolRefs 无死链', () {
      final matcher = buildRealMatcher();
      final peripherals = readJson('peripherals.json')['peripherals'] as List;

      var checked = 0;
      final deadLinks = <String>[];
      for (final raw in peripherals) {
        final p = Peripheral.fromJson(raw as Map<String, dynamic>);
        final bundle = readJson('functions/${p.id}.json');
        for (final e in bundle['functions'] as List) {
          final f = FunctionItem.fromJson(e as Map<String, dynamic>);
          for (final ref in f.symbolRefs) {
            checked++;
            if (!matcher.canResolve(ref)) {
              deadLinks.add('${f.id} -> $ref');
            }
          }
        }
      }
      expect(checked, greaterThan(1000), reason: '引用总数偏少，可能没重算 symbolRefs');
      expect(deadLinks, isEmpty, reason: '存在死链：${deadLinks.take(10)}');
    });

    test('相关函数 id 全部存在（点击不会 404）', () {
      final peripherals = readJson('peripherals.json')['peripherals'] as List;
      final allFunctionIds = <String>{};
      final allBundles = <String, List<FunctionItem>>{};
      for (final raw in peripherals) {
        final p = Peripheral.fromJson(raw as Map<String, dynamic>);
        final bundle = readJson('functions/${p.id}.json');
        final funcs = (bundle['functions'] as List)
            .map((e) => FunctionItem.fromJson(e as Map<String, dynamic>))
            .toList();
        allBundles[p.id] = funcs;
        allFunctionIds.addAll(funcs.map((f) => f.id));
      }

      final missing = <String>[];
      for (final funcs in allBundles.values) {
        for (final f in funcs) {
          for (final rid in f.relatedFunctions) {
            if (!allFunctionIds.contains(rid)) {
              missing.add('${f.id} -> $rid');
            }
          }
        }
      }
      expect(missing, isEmpty, reason: '相关函数引用不存在：${missing.take(10)}');
    });

    test('符号的 usedBy 反向索引指向真实函数', () {
      final peripherals = readJson('peripherals.json')['peripherals'] as List;
      final allFunctionIds = <String>{};
      for (final raw in peripherals) {
        final p = Peripheral.fromJson(raw as Map<String, dynamic>);
        final bundle = readJson('functions/${p.id}.json');
        for (final e in bundle['functions'] as List) {
          allFunctionIds.add((e as Map<String, dynamic>)['id'] as String);
        }
      }

      final symbols = (readJson('symbols.json')['symbols'] as List)
          .map((e) => SymbolItem.fromJson(e as Map<String, dynamic>));

      var withUsedBy = 0;
      final missing = <String>[];
      for (final s in symbols) {
        if (s.usedBy.isEmpty) continue;
        withUsedBy++;
        for (final fid in s.usedBy) {
          if (!allFunctionIds.contains(fid)) {
            missing.add('${s.name} -> $fid');
          }
        }
      }
      expect(withUsedBy, greaterThan(50), reason: 'usedBy 反向索引可能没重建');
      expect(missing, isEmpty, reason: 'usedBy 指向不存在的函数：${missing.take(10)}');
    });
  });

  // 回归：真机反馈"除了库函数名，其它点什么都提示未收录符号"。
  //
  // 根因是解析脚本产出的符号只有 name 没有 id，而 SymbolItem.fromJson 读的是 id，
  // 于是 SplData.symbolById 的键全是 null、索引实际为空，
  // isKnownSymbol() 恒为 false → 任何宏/枚举/结构体都提示"未收录符号"。
  //
  // 这类 bug 用假数据测不出来（假数据手写了 id），必须直接校验真实 JSON 的字段。
  group('真实数据：符号 id 索引（真机「未收录符号」回归）', () {
    test('每个符号都有非空 id，且 id 与 name 一致', () {
      for (final file in <String>['symbols.json', 'registers.json']) {
        final list = readJson(file)['symbols'] as List;
        expect(list, isNotEmpty, reason: '$file 为空');

        final missingId = <String>[];
        final mismatched = <String>[];
        for (final raw in list) {
          final m = raw as Map<String, dynamic>;
          final id = m['id'];
          final name = m['name'];
          if (id == null || (id as String).isEmpty) {
            missingId.add('$name');
          } else if (id != name) {
            mismatched.add('$id != $name');
          }
        }
        expect(missingId, isEmpty,
            reason: '$file 里有 ${missingId.length} 个符号缺 id，'
                '会导致 App 端 symbolById 索引缺失：${missingId.take(10)}');
        expect(mismatched, isEmpty,
            reason: '$file 里有 id 与 name 不一致的符号：${mismatched.take(10)}');
      }
    });

    test('符号 id 全局唯一（重复会让索引互相覆盖）', () {
      final seen = <String, String>{};
      final dup = <String>[];
      for (final file in <String>['symbols.json', 'registers.json']) {
        for (final raw in readJson(file)['symbols'] as List) {
          final m = raw as Map<String, dynamic>;
          final id = m['id'] as String;
          final prev = seen[id];
          if (prev != null) {
            dup.add('$id ($prev 与 $file)');
          } else {
            seen[id] = file;
          }
        }
      }
      expect(dup, isEmpty, reason: '符号 id 重复：${dup.take(10)}');
    });

    test('SplData.isKnownSymbol 能解析真实符号（不会被判成未收录）', () {
      final data = SplData(
        manifest: DataManifest.fromJson(readJson('manifest.json')),
        chip: ChipSpec.fromJson(readJson('chips/stm32f103c8t6.json')),
        peripherals: <Peripheral>[],
        functions: const <FunctionItem>[],
        symbols: (readJson('symbols.json')['symbols'] as List)
            .map((e) => SymbolItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        pinout: PinoutData.fromJson(readJson('pinout_f103c8t6.json')),
        compileErrors:
            CompileErrorBundle.fromJson(readJson('compile_errors.json')),
      );

      // 这些是函数详情页里高频出现的可点击词，逐个确认能解析
      for (final name in <String>[
        'GPIO_Mode_Out_PP', // 枚举值
        'GPIO_InitTypeDef', // 结构体
        'GPIOA', // 外设基址宏
        'ENABLE', // 枚举值
        'DISABLE',
        'FunctionalState', // 枚举类型
        'GPIO_TypeDef', // 结构体
        'FlagStatus',
        'RESET',
        'SET',
      ]) {
        expect(data.isKnownSymbol(name), isTrue,
            reason: '$name 应能被解析，否则点击会提示「未收录符号」');
      }
    });

    test('函数详情的 symbolRefs 全部可解析（点击不报未收录）', () {
      final peripherals = readJson('peripherals.json')['peripherals'] as List;

      final symbolNames = <String>{
        for (final raw in readJson('symbols.json')['symbols'] as List)
          (raw as Map<String, dynamic>)['id'] as String,
      };
      final registerNames = <String>{
        for (final raw in readJson('registers.json')['symbols'] as List)
          (raw as Map<String, dynamic>)['id'] as String,
      };
      final functionNames = <String>{};
      for (final raw in peripherals) {
        final p = Peripheral.fromJson(raw as Map<String, dynamic>);
        functionNames.addAll(p.allFunctionIds);
      }

      final known = <String>{...symbolNames, ...registerNames, ...functionNames};
      final dead = <String>[];
      for (final raw in peripherals) {
        final p = Peripheral.fromJson(raw as Map<String, dynamic>);
        final bundle = readJson('functions/${p.id}.json');
        for (final e in bundle['functions'] as List) {
          final f = FunctionItem.fromJson(e as Map<String, dynamic>);
          for (final ref in f.symbolRefs) {
            if (!known.contains(ref)) dead.add('${f.id} -> $ref');
          }
        }
      }
      expect(dead, isEmpty,
          reason: 'symbolRefs 里有解析不了的名字，点击会提示未收录：${dead.take(10)}');
    });

    test('SymbolMatcher 能链接的词，SplData 都能跳转（两端数据源一致）', () {
      final peripherals = readJson('peripherals.json')['peripherals'] as List;
      final symbols = (readJson('symbols.json')['symbols'] as List)
          .map((e) => SymbolItem.fromJson(e as Map<String, dynamic>))
          .toList();

      final data = SplData(
        manifest: DataManifest.fromJson(readJson('manifest.json')),
        chip: ChipSpec.fromJson(readJson('chips/stm32f103c8t6.json')),
        peripherals: peripherals
            .map((e) => Peripheral.fromJson(e as Map<String, dynamic>))
            .toList(),
        functions: const <FunctionItem>[],
        symbols: symbols,
        pinout: PinoutData.fromJson(readJson('pinout_f103c8t6.json')),
        compileErrors:
            CompileErrorBundle.fromJson(readJson('compile_errors.json')),
      );

      // KeywordText 用 SymbolMatcher 决定"哪些词画成链接"，
      // openSymbol 用 SplData 决定"能不能跳"。
      // 两边数据源一旦不一致，就会出现"点了链接却提示未收录"。
      final matcher = SymbolMatcher(
        functions: <String>{
          for (final p in data.peripherals) ...p.allFunctionIds,
        },
        symbols: symbols.map((s) => s.name),
      );

      final broken = <String>[];
      for (final name in matcher.allNames) {
        if (!data.isKnownFunction(name) && !data.isKnownSymbol(name)) {
          broken.add(name);
        }
      }
      expect(broken, isEmpty,
          reason: '${broken.length} 个词会被渲染成链接但跳转不了：${broken.take(10)}');
    });
  });

  group('真实数据：寄存器位域', () {
    test('函数声明的寄存器能匹配到寄存器位定义', () {
      final registers = (readJson('registers.json')['symbols'] as List)
          .map((e) => SymbolItem.fromJson(e as Map<String, dynamic>))
          .toList();
      final byRegister = <String, int>{};
      for (final s in registers) {
        if (s.registerName != null) {
          byRegister[s.registerName!] = (byRegister[s.registerName!] ?? 0) + 1;
        }
      }
      expect(byRegister.length, greaterThan(300), reason: '寄存器分节数偏少');

      // GPIO_Init 声明了 GPIOx_CRL / GPIOx_CRH，归一化后应能匹配到
      expect(byRegister.containsKey('GPIO_CRL'), isTrue);
      expect(byRegister.containsKey('GPIO_CRH'), isTrue);
      expect(byRegister['GPIO_CRL']!, greaterThan(0));

      // TIM_TimeBaseInit 声明了 TIMx_PSC / TIMx_ARR
      expect(byRegister.containsKey('TIM_PSC'), isTrue);
      expect(byRegister.containsKey('TIM_ARR'), isTrue);
    });
  });

  group('真实数据：芯片能力与不支持外设', () {
    test('C8T6 不支持的外设被正确标注', () {
      final chip = readJson('chips/stm32f103c8t6.json');
      final unsupported = (chip['unsupportedPeripherals'] as List).cast<String>();
      expect(unsupported, containsAll(<String>['DAC', 'FSMC', 'SDIO', 'CEC']));
      expect(unsupported, isNot(contains('GPIO')));
      expect(unsupported, isNot(contains('USART')));
    });

    test('GPIO 实例列表不含 GPIOD（LQFP48 未引出）', () {
      final chip = readJson('chips/stm32f103c8t6.json');
      final instances =
          (chip['peripheralInstances'] as Map<String, dynamic>)['GPIO'] as List;
      expect(instances, containsAll(<String>['GPIOA', 'GPIOB', 'GPIOC']));
      expect(instances, isNot(contains('GPIOD')));
    });
  });

  group('真实数据：引脚', () {
    test('48 个引脚编号连续，调试口位置正确', () {
      final pins = readJson('pinout_f103c8t6.json')['pins'] as List;
      final numbers = pins
          .map((e) => (e as Map<String, dynamic>)['number'] as int)
          .toList()
        ..sort();
      expect(numbers, List<int>.generate(48, (i) => i + 1));

      final debugPins = <int>[];
      for (final raw in pins) {
        final m = raw as Map<String, dynamic>;
        if (m['jtagSwd'] != null) debugPins.add(m['number'] as int);
      }
      expect(debugPins..sort(), <int>[34, 37, 38, 39, 40]);
    });

    test('引脚数据已核对，并在提示里写明数据来源', () {
      final pinout = readJson('pinout_f103c8t6.json');
      // 用户已确认《STM32F103C8T6引脚定义.xlsx》完全正确，
      // 该表是 DS5319 Table 5 的转录，因此这里应为已核对。
      expect(pinout['verified'], isTrue);
      final note = pinout['verifiedNote'] as String;
      expect(note, isNotEmpty);
      // 说明里要能追溯来源，否则日后没人知道"已核对"是核对到哪里
      expect(note, contains('引脚定义'));
    });

    test('PA9 的复用功能含 USART1_TX（可反查）', () {
      final pins = readJson('pinout_f103c8t6.json')['pins'] as List;
      final pa9 = pins.firstWhere(
        (e) => (e as Map<String, dynamic>)['number'] == 30,
      ) as Map<String, dynamic>;
      final fnNames = (pa9['functions'] as List)
          .map((f) => (f as Map<String, dynamic>)['name'] as String)
          .toList();
      expect(fnNames, contains('USART1_TX'));
      expect(fnNames, contains('TIM1_CH2'));
      expect(pa9['fiveVoltTolerant'], isTrue);
    });
  });

  group('真实数据：中文覆盖', () {
    test('全部 488 个函数都有中文简述与使用说明', () {
      final peripherals = readJson('peripherals.json')['peripherals'] as List;

      final noBrief = <String>[];
      final noUsage = <String>[];
      var total = 0;
      for (final raw in peripherals) {
        final p = Peripheral.fromJson(raw as Map<String, dynamic>);
        // 只解析函数的外设才有函数文件
        if (p.functionCount == 0) continue;
        final bundle = readJson('functions/${p.id}.json');
        for (final e in bundle['functions'] as List) {
          final f = FunctionItem.fromJson(e as Map<String, dynamic>);
          total++;
          if (f.briefZh.isEmpty) noBrief.add(f.id);
          if (f.usageZh.isEmpty) noUsage.add(f.id);
        }
      }

      expect(total, 488, reason: '函数总数变了，请同步核对中文覆盖');
      // 真机反馈：早期的中文只写到 MISC，从 EXTI 起全是 ST 英文原文。
      // 现在要求全库覆盖，这两条断言就是"别再退回半英文"的守门人。
      expect(noBrief, isEmpty,
          reason: '${noBrief.length} 个函数缺中文简述（应显示 ST 英文原文）：'
              '${noBrief.take(10)}');
      expect(noUsage, isEmpty,
          reason: '${noUsage.length} 个函数缺 usageZh：${noUsage.take(10)}');
    });

    test('每个外设的中文覆盖都与函数总数一致', () {
      final peripherals = readJson('peripherals.json')['peripherals'] as List;
      final gaps = <String>[];
      for (final raw in peripherals) {
        final p = Peripheral.fromJson(raw as Map<String, dynamic>);
        if (p.functionCount == 0) continue;
        final bundle = readJson('functions/${p.id}.json');
        final funcs = bundle['functions'] as List;
        expect(funcs.length, p.functionCount,
            reason: '${p.id} 的 functionCount 与实际不符');
        final zh = funcs
            .where((e) =>
                ((e as Map<String, dynamic>)['briefZh'] as String).isNotEmpty)
            .length;
        if (zh != funcs.length) {
          gaps.add('${p.id}: $zh/${funcs.length}');
        }
      }
      expect(gaps, isEmpty, reason: '这些外设的中文覆盖不全：$gaps');
    });

    test('四个重点外设的中文是完整的', () {
      for (final pid in <String>['GPIO', 'RCC', 'USART', 'TIM']) {
        final bundle = readJson('functions/$pid.json');
        final funcs = (bundle['functions'] as List)
            .map((e) => FunctionItem.fromJson(e as Map<String, dynamic>))
            .toList();
        final missing = funcs.where((f) => f.briefZh.isEmpty).toList();
        expect(
          missing,
          isEmpty,
          reason: '$pid 有 ${missing.length} 个函数缺中文简述',
        );
        // 使用说明也该有
        final noUsage = funcs.where((f) => f.usageZh.isEmpty).length;
        expect(
          noUsage,
          0,
          reason: '$pid 有 $noUsage 个函数缺 usageZh',
        );
      }
    });

    test('中文覆盖数与 manifest 统计一致', () {
      final peripherals = readJson('peripherals.json')['peripherals'] as List;
      var withZh = 0;
      var total = 0;
      for (final raw in peripherals) {
        final p = Peripheral.fromJson(raw as Map<String, dynamic>);
        final bundle = readJson('functions/${p.id}.json');
        for (final e in bundle['functions'] as List) {
          total++;
          if (((e as Map<String, dynamic>)['briefZh'] as String).isNotEmpty) {
            withZh++;
          }
        }
      }
      expect(total, 488);
      expect(withZh, 488, reason: '中文简述应已全库覆盖');
    });
  });

  group('真实数据：函数名在首屏可搜（真机 bug 回归）', () {
    // 复现问题：函数详情按需加载，首屏 functions 为空。
    // 早先搜索索引只索引已加载的函数，导致首屏搜不到函数名。
    SplData buildWithoutFunctions() {
      final peripherals =
          (readJson('peripherals.json')['peripherals'] as List)
              .map((e) => Peripheral.fromJson(e as Map<String, dynamic>))
              .toList();
      return SplData(
        manifest: DataManifest.fromJson(readJson('manifest.json')),
        chip: ChipSpec.fromJson(readJson('chips/stm32f103c8t6.json')),
        peripherals: peripherals,
        functions: const <FunctionItem>[], // 关键：未加载
        symbols: const <SymbolItem>[],
        pinout: PinoutData.fromJson(readJson('pinout_f103c8t6.json')),
        compileErrors:
            CompileErrorBundle.fromJson(readJson('compile_errors.json')),
      );
    }

    test('未加载函数详情时，函数名仍能搜到', () {
      final index = SearchIndex.build(buildWithoutFunctions());
      final hits = index.search('NVIC_Init');
      expect(
        hits.any(
          (h) => h.itemType == ItemType.function && h.id == 'NVIC_Init',
        ),
        isTrue,
        reason: '首屏未加载函数详情时，NVIC_Init 也应能搜到（回归 bug）',
      );
    });

    test('前缀匹配优先：搜 GPIO_Init 时 GPIO_Init 排第一', () {
      final index = SearchIndex.build(buildWithoutFunctions());
      final hits = index.search('GPIO_Init');
      expect(hits, isNotEmpty);
      expect(hits.first.id, 'GPIO_Init');
    });

    test('大小写不敏感：搜 uart 能命中 USART 相关函数', () {
      final index = SearchIndex.build(buildWithoutFunctions());
      final hits = index.search('uart');
      expect(
        hits.where((h) => h.itemType == ItemType.function),
        isNotEmpty,
        reason: '需求验收点：搜索 uart 应能搜到 USART 相关函数',
      );
    });
  });

  group('真实数据：列表返回值摘要长度（真机 bug 回归）', () {
    test('所有函数的 displayReturn 都是短标签', () {
      final peripherals = readJson('peripherals.json')['peripherals'] as List;
      final tooLong = <String>[];
      var checked = 0;
      for (final raw in peripherals) {
        final p = Peripheral.fromJson(raw as Map<String, dynamic>);
        final bundle = readJson('functions/${p.id}.json');
        for (final e in bundle['functions'] as List) {
          final f = FunctionItem.fromJson(e as Map<String, dynamic>);
          checked++;
          // 列表右侧是短标签位，过长会挤压函数名导致竖排
          if (f.displayReturn.length > 20) {
            tooLong.add('${f.id} -> ${f.displayReturn}');
          }
        }
      }
      expect(checked, 488);
      expect(
        tooLong,
        isEmpty,
        reason: '这些函数的 displayReturn 过长，会把函数名挤成竖排：'
            '${tooLong.take(5)}',
      );
    });
  });

  group('真实数据：编译错误', () {
    test('15 条错误都有中文解释与解决步骤', () {
      final bundle = readJson('compile_errors.json');
      final errors = bundle['errors'] as List;
      expect(errors.length, 15);

      final catIds = (bundle['categories'] as List)
          .map((c) => (c as Map<String, dynamic>)['id'] as String)
          .toSet();

      for (final raw in errors) {
        final e = raw as Map<String, dynamic>;
        expect((e['explainZh'] as String).isNotEmpty, isTrue,
            reason: '${e['id']} 缺中文解释');
        expect((e['solutions'] as List).isNotEmpty, isTrue,
            reason: '${e['id']} 缺解决步骤');
        expect(catIds, contains(e['categoryId']),
            reason: '${e['id']} 的分类不存在');
      }
    });

    test('需求点名的 15 类错误都有覆盖', () {
      final errors = readJson('compile_errors.json')['errors'] as List;
      final allText = errors
          .map((e) => jsonEncode(e))
          .join(' ')
          .toLowerCase();

      // 需求 5.7 列出的关键词，逐个确认有覆盖
      const keywords = <String>[
        'undefined reference',
        'no such file or directory',
        'stm32f10x_conf.h',
        'please select first the target',
        'no space in execution regions',
        'l6218e',
        'flash download failed',
        'could not stop cortex-m',
        'st-link',
        '乱码',
        'assert_param',
        'hardfault',
        'is undefined',
        'multiple definition',
        '循环包含',
      ];
      for (final kw in keywords) {
        expect(allText, contains(kw), reason: '缺少对「$kw」的覆盖');
      }
    });
  });
}
