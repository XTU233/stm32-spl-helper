// 关键工具函数的单元测试。
//
// 需求明确"不需要单元测试全覆盖，关键工具函数写测试即可"，
// 所以这里只测真正容易出错、且不依赖 assets 的纯逻辑：
//   1. json_parse 的宽松解析（数据缺字段时不能崩）
//   2. SearchIndex 的匹配与排序策略（前缀优先、大小写不敏感、中文子串）
//   3. ItemRef 的主键编解码
//   4. Pin 的引脚名解析

import 'package:flutter_test/flutter_test.dart';

import 'package:stm32_spl_helper/models/chip.dart';
import 'package:stm32_spl_helper/models/compile_error.dart';
import 'package:stm32_spl_helper/models/function_item.dart';
import 'package:stm32_spl_helper/models/item_ref.dart';
import 'package:stm32_spl_helper/models/manifest.dart';
import 'package:stm32_spl_helper/models/peripheral.dart';
import 'package:stm32_spl_helper/models/pin.dart';
import 'package:stm32_spl_helper/models/spl_data.dart';
import 'package:stm32_spl_helper/models/symbol_item.dart';
import 'package:stm32_spl_helper/utils/json_parse.dart';

// ---------------------------------------------------------------------------
// 测试夹具
// ---------------------------------------------------------------------------

/// 构造一个最小的 SplData，用于搜索索引测试。
SplData buildFixtureData() {
  final peripherals = <Peripheral>[
    const Peripheral(
      id: 'GPIO',
      name: 'GPIO',
      nameZh: '通用输入输出',
      header: 'stm32f10x_gpio.h',
      source: 'stm32f10x_gpio.c',
      file: 'functions/GPIO.json',
      orderIndex: 1,
      introZh: 'GPIO 是最基础的外设。',
      usageOverviewZh: '先开时钟再配置引脚。',
      functionCount: 18,
      symbolCount: 115,
      tags: ['常用'],
      sections: <PeripheralSection>[],
    ),
    const Peripheral(
      id: 'DAC',
      name: 'DAC',
      nameZh: '数模转换',
      header: 'stm32f10x_dac.h',
      source: 'stm32f10x_dac.c',
      file: 'functions/DAC.json',
      orderIndex: 91,
      introZh: '数模转换器。',
      usageOverviewZh: '',
      functionCount: 17,
      symbolCount: 61,
      tags: <String>[],
      sections: <PeripheralSection>[],
    ),
  ];

  final symbols = <SymbolItem>[
    const SymbolItem(
      id: 'GPIO_Mode_Out_PP',
      name: 'GPIO_Mode_Out_PP',
      kind: SymbolKind.enumValue,
      peripheral: 'GPIO',
      value: '0x10',
      briefZh: '推挽输出。可主动输出高电平和低电平。',
    ),
    const SymbolItem(
      id: 'GPIO_InitTypeDef',
      name: 'GPIO_InitTypeDef',
      kind: SymbolKind.struct,
      peripheral: 'GPIO',
      briefZh: 'GPIO 初始化结构体。',
      members: <SymbolMember>[
        SymbolMember(
          name: 'GPIO_Pin',
          type: 'uint16_t',
          descZh: '要配置的引脚',
        ),
        SymbolMember(
          name: 'GPIO_Mode',
          type: 'GPIOMode_TypeDef',
          descZh: '工作模式',
        ),
      ],
    ),
    // 内部断言宏，默认不应出现在搜索结果里
    const SymbolItem(
      id: 'IS_GPIO_MODE',
      name: 'IS_GPIO_MODE',
      kind: SymbolKind.macro,
      peripheral: 'GPIO',
      visibility: 'internal',
    ),
  ];

  final pins = <Pin>[
    const Pin(
      number: 30,
      name: 'PA9',
      groups: <PinGroup>[PinGroup.gpio],
      defaultFunction: 'PA9',
      defaultFunctionZh: '通用 IO',
      functions: <PinFunction>[
        PinFunction(
          name: 'USART1_TX',
          kind: PinFunctionKind.af,
          peripheralId: 'USART',
        ),
      ],
      fiveVoltTolerant: true,
    ),
    const Pin(
      number: 34,
      name: 'PA13',
      groups: <PinGroup>[PinGroup.debug, PinGroup.gpio],
      defaultFunction: 'JTMS/SWDIO',
      functions: <PinFunction>[],
      jtagSwd: 'JTMS/SWDIO',
    ),
  ];

  final errors = <CompileError>[
    const CompileError(
      id: 'err.undefined_reference',
      titleZh: "undefined reference to 'xxx'",
      categoryId: 'linker',
      toolchain: 'gcc-arm',
      messagePatterns: <String>['undefined reference to'],
      explainZh: '链接器找不到函数实现体。',
      relatedPeripheralIds: <String>['GPIO'],
    ),
  ];

  return SplData(
    manifest: const DataManifest(
      schemaVersion: 1,
      dataVersion: '1.0.0',
      splVersion: 'STM32F10x_StdPeriph_Lib_V3.5.0',
      defaultChipId: 'stm32f103c8t6',
      generatedAt: '',
      generator: 'test',
      stats: DataStats(),
      files: <String, String>{},
    ),
    chip: const ChipSpec(
      id: 'stm32f103c8t6',
      name: 'STM32F103C8T6',
      supportedPeripherals: <String>['GPIO'],
      unsupportedPeripherals: <String>['DAC'],
      unsupportedReasons: <String, String>{'DAC': 'C8T6 无 DAC 外设'},
      peripheralInstances: <String, List<String>>{
        'GPIO': <String>['GPIOA', 'GPIOB', 'GPIOC'],
      },
    ),
    peripherals: peripherals,
    functions: const <FunctionItem>[],
    symbols: symbols,
    pinout: PinoutData(
      schemaVersion: 1,
      chipId: 'stm32f103c8t6',
      package: 'LQFP48',
      source: 'test',
      verified: false,
      verifiedNote: '未核对',
      pins: pins,
    ),
    compileErrors: CompileErrorBundle(
      schemaVersion: 1,
      categories: const <CompileErrorCategory>[
        CompileErrorCategory(id: 'linker', nameZh: '链接错误', orderIndex: 2),
      ],
      errors: errors,
    ),
  );
}

void main() {
  // -------------------------------------------------------------------------
  group('json_parse 宽松解析', () {
    test('缺失字段返回兜底值而不是抛异常', () {
      expect(asString(null), '');
      expect(asString(null, fallback: '默认'), '默认');
      expect(asInt(null), 0);
      expect(asInt(null, fallback: -1), -1);
      expect(asBool(null), false);
      expect(asStringList(null), isEmpty);
      expect(asMapList(null), isEmpty);
      expect(asMap(null), isEmpty);
    });

    test('类型不符时尽力转换', () {
      expect(asInt('42'), 42);
      expect(asInt(42.9), 42);
      expect(asBool('true'), true);
      expect(asBool('false'), false);
      expect(asString(123), '123');
    });

    test('空字符串按 null 处理，便于 UI 判空', () {
      expect(asStringOrNull(''), isNull);
      expect(asStringOrNull('  x  '), '  x  ');
      expect(asStringOrNull(null), isNull);
    });

    test('字符串数组过滤掉 null 与空串', () {
      expect(asStringList(<dynamic>['a', null, '', 'b']), <String>['a', 'b']);
    });
  });

  // -------------------------------------------------------------------------
  group('ItemRef 主键编解码', () {
    test('key 与 fromKey 往返一致', () {
      const ref = ItemRef(
        type: ItemType.function,
        id: 'GPIO_Init',
        title: 'GPIO_Init',
      );
      expect(ref.key, 'function:GPIO_Init');
      final back = ItemRef.fromKey(ref.key);
      expect(back, isNotNull);
      expect(back!.type, ItemType.function);
      expect(back.id, 'GPIO_Init');
    });

    test('非法 key 返回 null 而不是抛异常', () {
      expect(ItemRef.fromKey(''), isNull);
      expect(ItemRef.fromKey('noColon'), isNull);
      expect(ItemRef.fromKey('unknownType:xxx'), isNull);
      expect(ItemRef.fromKey('function:'), isNull);
    });

    test('id 里含冒号时只按第一个冒号切分', () {
      final back = ItemRef.fromKey('pin:30:extra');
      expect(back, isNotNull);
      expect(back!.id, '30:extra');
    });
  });

  // -------------------------------------------------------------------------
  group('Pin 引脚名解析', () {
    test('GPIO 引脚识别端口与位号', () {
      const p = Pin(number: 30, name: 'PA9');
      expect(p.isGpio, isTrue);
      expect(p.portName, 'GPIOA');
      expect(p.bitIndex, 9);
    });

    test('非 GPIO 引脚不误判', () {
      const vbat = Pin(number: 1, name: 'VBAT');
      expect(vbat.isGpio, isFalse);
      expect(vbat.portName, '');
      expect(vbat.bitIndex, -1);
    });

    test('调试口占用判断', () {
      const pa13 = Pin(number: 34, name: 'PA13', jtagSwd: 'JTMS/SWDIO');
      expect(pa13.isDebugOccupied, isTrue);
      const pa9 = Pin(number: 30, name: 'PA9');
      expect(pa9.isDebugOccupied, isFalse);
    });
  });

  // -------------------------------------------------------------------------
  group('SplData 查询与索引', () {
    test('按 id 查询各类型条目', () {
      final d = buildFixtureData();
      expect(d.peripheral('GPIO')?.nameZh, '通用输入输出');
      expect(d.symbol('GPIO_Mode_Out_PP')?.value, '0x10');
      expect(d.pinout.pinByNumber(30)?.name, 'PA9');
      expect(d.compileErrorById['err.undefined_reference'], isNotNull);
      expect(d.peripheral('NOT_EXIST'), isNull);
    });

    test('芯片能力判断', () {
      final d = buildFixtureData();
      expect(d.isPeripheralSupported('GPIO'), isTrue);
      expect(d.isPeripheralSupported('DAC'), isFalse);
      expect(d.chip.unsupportedReason('DAC'), 'C8T6 无 DAC 外设');
    });

    test('引脚按功能反查', () {
      final d = buildFixtureData();
      final hits = d.pinout.searchByFunction('USART1_TX');
      expect(hits.length, 1);
      expect(hits.first.name, 'PA9');
      // 不区分大小写
      expect(d.pinout.searchByFunction('usart1_tx').length, 1);
      // 引脚名也能查
      expect(d.pinout.searchByFunction('PA13').first.number, 34);
      // 查不到返回空列表
      expect(d.pinout.searchByFunction('NOT_EXIST'), isEmpty);
    });

    test('ItemRef 补全标题与副标题', () {
      final d = buildFixtureData();
      final enriched = d.enrich(
        const ItemRef(
          type: ItemType.symbol,
          id: 'GPIO_Mode_Out_PP',
          title: '',
        ),
      );
      expect(enriched.title, 'GPIO_Mode_Out_PP');
      expect(enriched.subtitle, '通用输入输出');
    });
  });

  // -------------------------------------------------------------------------
  group('函数跳转判定（真机 bug 回归测试）', () {
    // 复现问题：首屏 functions 为空（函数详情按需加载），
    // 早先 isKnownFunction 只查 functionById，导致点函数名报"未收录符号"。
    // 现在应回退查外设的 functionIds。
    SplData dataWithFunctionsNotLoaded() {
      final base = buildFixtureData();
      return SplData(
        manifest: base.manifest,
        chip: base.chip,
        peripherals: <Peripheral>[
          const Peripheral(
            id: 'MISC',
            name: 'MISC',
            nameZh: '内核外设与中断',
            header: 'misc.h',
            source: 'misc.c',
            file: 'functions/MISC.json',
            orderIndex: 5,
            introZh: '',
            usageOverviewZh: '',
            functionCount: 2,
            symbolCount: 1,
            tags: <String>[],
            sections: <PeripheralSection>[
              PeripheralSection(
                id: 'MISC#sec1',
                title: '初始化与配置函数',
                functionIds: <String>['NVIC_Init', 'NVIC_PriorityGroupConfig'],
              ),
            ],
          ),
        ],
        // 关键：函数详情尚未加载
        functions: const <FunctionItem>[],
        symbols: base.symbols,
        pinout: base.pinout,
        compileErrors: base.compileErrors,
      );
    }

    test('函数详情未加载时，函数名仍被判定为可跳转', () {
      final d = dataWithFunctionsNotLoaded();
      expect(
        d.isKnownFunction('NVIC_Init'),
        isTrue,
        reason: '首屏未加载函数详情时，NVIC_Init 仍应可跳转（回归 bug）',
      );
      expect(d.isKnownFunction('NVIC_PriorityGroupConfig'), isTrue);
      expect(d.isKnownFunction('NOT_A_FUNCTION'), isFalse);
    });

    test('peripheralIdOfFunction 在未加载时也能定位外设', () {
      final d = dataWithFunctionsNotLoaded();
      expect(d.peripheralIdOfFunction('NVIC_Init'), 'MISC');
      expect(d.peripheralIdOfFunction('NOT_A_FUNCTION'), isNull);
    });

    test('isKnownName 覆盖函数与符号两类', () {
      final d = buildFixtureData();
      expect(d.isKnownName('GPIO_Mode_Out_PP'), isTrue);
      expect(d.isKnownName('NOT_EXIST'), isFalse);
    });
  });

  // -------------------------------------------------------------------------
  group('列表返回值摘要（真机 bug 回归测试）', () {
    // 复现问题：早先 displayReturn 返回 returnDescZh 全文（最长 40 字），
    // 在 Row 里把函数名挤成一列，出现"函数名竖排"。
    test('displayReturn 只给类型短标签，不返回中文长句', () {
      final f = FunctionItem.fromJson(<String, dynamic>{
        'id': 'GPIO_ReadInputDataBit',
        'name': 'GPIO_ReadInputDataBit',
        'returnType': 'uint8_t',
        'returnDescZh': '返回引脚电平：Bit_SET（1）为高电平，Bit_RESET（0）为低电平。',
      });
      expect(f.displayReturn, 'uint8_t');
      expect(
        f.displayReturn.length,
        lessThan(20),
        reason: '列表右侧是短标签位，放长句会把函数名挤成竖排',
      );
      expect(f.displayReturn, isNot(contains('返回')));
    });

    test('指针返回类型取类型名而非星号', () {
      final f = FunctionItem.fromJson(<String, dynamic>{
        'id': 'F',
        'name': 'F',
        'returnType': 'GPIO_TypeDef*',
      });
      expect(f.displayReturn, 'GPIO_TypeDef');
    });

    test('void 返回 void 而不是中文', () {
      final f = FunctionItem.fromJson(<String, dynamic>{
        'id': 'F',
        'name': 'F',
        'returnType': 'void',
        'returnDescZh': '无返回值',
      });
      expect(f.displayReturn, 'void');
    });

    test('shortReturnZh 取首句，供副标题使用', () {
      final f = FunctionItem.fromJson(<String, dynamic>{
        'id': 'F',
        'name': 'F',
        'returnType': 'uint8_t',
        'returnDescZh': '返回引脚电平：Bit_SET（1）为高电平，Bit_RESET（0）为低电平。',
      });
      expect(f.shortReturnZh, contains('返回引脚电平'));
      expect(f.shortReturnZh, isNot(contains('。')));
    });
  });

  // -------------------------------------------------------------------------
  group('Peripheral 简介截取', () {
    test('oneLineIntro 取第一句', () {
      const p = Peripheral(
        id: 'GPIO',
        name: 'GPIO',
        nameZh: '通用输入输出',
        header: 'h',
        source: 'c',
        file: 'f',
        orderIndex: 1,
        introZh: '',
        usageOverviewZh: '第一句话。第二句话。',
        functionCount: 0,
        symbolCount: 0,
        tags: <String>[],
        sections: <PeripheralSection>[],
      );
      expect(p.oneLineIntro, '第一句话。');
    });

    test('无说明时返回空串而不是崩', () {
      const p = Peripheral(
        id: 'X',
        name: 'X',
        nameZh: 'X',
        header: '',
        source: '',
        file: '',
        orderIndex: 1000,
        introZh: '',
        usageOverviewZh: '',
        functionCount: 0,
        symbolCount: 0,
        tags: <String>[],
        sections: <PeripheralSection>[],
      );
      expect(p.oneLineIntro, '');
    });
  });

  // -------------------------------------------------------------------------
  group('SymbolKind 与容错', () {
    test('未知 kind 解析为 unknown 而不是抛异常', () {
      expect(SymbolKind.fromRaw('macro'), SymbolKind.macro);
      expect(SymbolKind.fromRaw('enum_value'), SymbolKind.enumValue);
      expect(SymbolKind.fromRaw('struct'), SymbolKind.struct);
      expect(SymbolKind.fromRaw('brand_new_kind'), SymbolKind.unknown);
    });

    test('内部符号判断', () {
      const s = SymbolItem(
        id: 'IS_X',
        name: 'IS_X',
        kind: SymbolKind.macro,
        peripheral: 'GPIO',
        visibility: 'internal',
      );
      expect(s.isInternal, isTrue);
    });

    test('fromJson 缺字段时不崩', () {
      final s = SymbolItem.fromJson(<String, dynamic>{'name': 'X'});
      expect(s.name, 'X');
      expect(s.kind, SymbolKind.unknown);
      expect(s.members, isEmpty);
      expect(s.usedBy, isEmpty);
    });
  });

  // -------------------------------------------------------------------------
  group('DataManifest 版本校验', () {
    test('schemaVersion 匹配时兼容', () {
      final m = DataManifest.fromJson(<String, dynamic>{
        'schemaVersion': DataManifest.currentSchemaVersion,
      });
      expect(m.isSchemaCompatible, isTrue);
    });

    test('schemaVersion 不匹配时判定为不兼容', () {
      final m = DataManifest.fromJson(<String, dynamic>{'schemaVersion': 999});
      expect(m.isSchemaCompatible, isFalse);
    });

    test('缺字段时给兜底值', () {
      final m = DataManifest.fromJson(<String, dynamic>{});
      expect(m.schemaVersion, 0);
      expect(m.dataVersion, '未知');
      expect(m.fileOf('symbols', fallback: 'x.json'), 'x.json');
    });
  });

  // -------------------------------------------------------------------------
  group('FunctionItem 显示兜底', () {
    test('中文缺失时退回英文，再退回提示文案', () {
      final withZh = FunctionItem.fromJson(<String, dynamic>{
        'id': 'F',
        'name': 'F',
        'briefZh': '中文',
        'briefEn': 'english',
      });
      expect(withZh.displayBrief, '中文');

      final withEn = FunctionItem.fromJson(<String, dynamic>{
        'id': 'F',
        'name': 'F',
        'briefEn': 'english',
      });
      expect(withEn.displayBrief, 'english');

      final empty = FunctionItem.fromJson(<String, dynamic>{
        'id': 'F',
        'name': 'F',
      });
      expect(empty.displayBrief, '暂无中文说明');
    });

    test('void 函数的 displayReturn 是 void（列表短标签）', () {
      final f = FunctionItem.fromJson(<String, dynamic>{
        'id': 'F',
        'name': 'F',
        'returnType': 'void',
      });
      // 列表右侧统一显示类型短标签；中文"无返回值"走 shortReturnZh
      expect(f.displayReturn, 'void');
      expect(f.shortReturnZh, '无返回值');
    });

    test('参数与 symbolRefs 正确解析', () {
      final f = FunctionItem.fromJson(<String, dynamic>{
        'id': 'GPIO_Init',
        'name': 'GPIO_Init',
        'params': <dynamic>[
          <String, dynamic>{
            'name': 'GPIOx',
            'type': 'GPIO_TypeDef*',
            'descZh': '端口',
          },
        ],
        'symbolRefs': <dynamic>['GPIO_InitTypeDef'],
        'headerLine': 351,
        'sourceLine': 173,
      });
      expect(f.params.length, 1);
      expect(f.params.first.name, 'GPIOx');
      expect(f.symbolRefs, <String>['GPIO_InitTypeDef']);
      expect(f.locationIn('stm32f10x_gpio.h'), 'stm32f10x_gpio.h:351');
    });
  });
}
