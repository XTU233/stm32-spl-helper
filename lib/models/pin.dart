import '../utils/json_parse.dart';

/// 引脚分组，用于引脚页顶部的筛选栏。
enum PinGroup {
  power('power', '电源'),
  ground('ground', '地'),
  reset('reset', '复位'),
  boot('boot', 'BOOT'),
  gpio('gpio', 'GPIO'),
  osc('osc', '晶振'),
  debug('debug', '调试口'),
  vref('vref', '参考电压'),
  other('other', '其它');

  /// JSON 中的原始字符串
  final String raw;

  /// 中文显示名
  final String labelZh;

  const PinGroup(this.raw, this.labelZh);

  /// 解析分组；无法识别时归入 [other]。
  static PinGroup fromRaw(String raw) {
    for (final g in PinGroup.values) {
      if (g.raw == raw) return g;
    }
    return PinGroup.other;
  }
}

/// 引脚复用功能的种类。
enum PinFunctionKind {
  /// 复用功能，如 USART1_TX、TIM1_CH2
  af('af', '复用功能'),

  /// 普通 GPIO
  gpio('gpio', 'GPIO'),

  /// 电源
  power('power', '电源'),

  /// 地
  ground('ground', '地'),

  /// 调试口
  debug('debug', '调试口'),

  /// BOOT 配置
  boot('boot', 'BOOT'),

  /// 晶振
  osc('osc', '晶振'),

  /// 复位
  reset('reset', '复位'),

  /// 其它
  other('other', '其它');

  final String raw;

  /// 中文显示名
  final String labelZh;

  const PinFunctionKind(this.raw, this.labelZh);

  static PinFunctionKind fromRaw(String raw) {
    for (final k in PinFunctionKind.values) {
      if (k.raw == raw) return k;
    }
    return PinFunctionKind.other;
  }
}

/// 一个外设实例在某根引脚上提供的一个信号。
///
/// 例如"SPI1 的 SCK 可以走 PA5（默认）或 PB3（需重映射）"就是两条，
/// 它们 [signal] 相同（SCK）、[pin] 不同。
class PeripheralPinSignal {
  /// 信号名，如 "SCK"、"TX"、"CH1"
  ///
  /// 从复用功能名里剥掉外设前缀得到：`SPI1_SCK` → `SCK`。
  final String signal;

  /// 该信号所在的引脚
  final Pin pin;

  /// 完整复用功能名，如 "SPI1_SCK"
  final String fullName;

  /// 是否需要重映射才能用这个引脚
  final bool remapRequired;

  /// 重映射说明
  final String remapNoteZh;

  const PeripheralPinSignal({
    required this.signal,
    required this.pin,
    required this.fullName,
    this.remapRequired = false,
    this.remapNoteZh = '',
  });

  /// 引脚名，如 "PA5"
  String get pinName => pin.name;

  /// 引脚号
  int get pinNumber => pin.number;
}

/// 某引脚上复用功能的归类维度：外设 id → 引脚列表。
///
/// 直接按 [PinFunction.peripheralId] 分组即可，因为解析引脚表时
/// 已经把每个复用功能归到了对应外设（`SPI1_SCK` → SPI）。
/// 数据里没有 `peripheralId` 的（理论上不该有）归到"其它"。
const String otherPeripheralId = '其它';

/// 一个外设实例（如 SPI1）的全部可用引脚。
class PeripheralPinout {
  /// 外设实例名，如 "SPI1"、"USART1"、"TIM2"
  ///
  /// 注意是**实例**而不是外设类别：SPI1 与 SPI2 的引脚完全不同，
  /// 用户问"SPI 用哪些脚"时真正想知道的是 SPI1 或 SPI2。
  final String instance;

  /// 外设类别 id，如 "SPI"（用于跳转到外设详情页）
  final String peripheralId;

  /// 该实例的全部信号（按信号名分组）
  final List<PeripheralPinSignal> signals;

  const PeripheralPinout({
    required this.instance,
    required this.peripheralId,
    required this.signals,
  });

  /// 涉及的引脚（去重，按引脚号升序）。
  List<Pin> get pins {
    final seen = <int, Pin>{};
    for (final s in signals) {
      seen.putIfAbsent(s.pin.number, () => s.pin);
    }
    final list = seen.values.toList()
      ..sort((a, b) => a.number.compareTo(b.number));
    return list;
  }

  /// 信号名 → 该信号可用的引脚（按引脚号升序）。
  ///
  /// 这是本功能的核心视图：用户想知道"SPI1 的 SCK 接哪个脚"，
  /// 答案可能不止一个（PA5 默认，PB3 需重映射）。
  Map<String, List<PeripheralPinSignal>> get bySignal {
    final map = <String, List<PeripheralPinSignal>>{};
    for (final s in signals) {
      map.putIfAbsent(s.signal, () => <PeripheralPinSignal>[]).add(s);
    }
    for (final list in map.values) {
      list.sort((a, b) => a.pinNumber.compareTo(b.pinNumber));
    }
    return map;
  }

  /// 不需要重映射就能用的信号（首选接线方案）。
  List<PeripheralPinSignal> get defaultSignals =>
      signals.where((s) => !s.remapRequired).toList();

  /// 需要重映射的信号。
  List<PeripheralPinSignal> get remapSignals =>
      signals.where((s) => s.remapRequired).toList();

  /// 是否所有信号都有默认引脚（true 表示这个外设开箱即用）。
  bool get fullyDefault => remapSignals.isEmpty;
}

/// 单个引脚复用功能项。
class PinFunction {
  /// 功能名，如 "USART1_TX"、"TIM1_CH2"
  final String name;

  /// 功能种类
  final PinFunctionKind kind;

  /// 是否需要重映射配置（GPIO_PinRemapConfig）
  final bool remapRequired;

  /// 关联的外设 id，用于跳转到外设页
  final String peripheralId;

  /// 重映射配置说明，如 "需 AFIO 时钟 + GPIO_PinRemapConfig(GPIO_Remap_SWJ_JTAGDisable, ENABLE)"
  final String remapNoteZh;

  const PinFunction({
    required this.name,
    required this.kind,
    this.remapRequired = false,
    this.peripheralId = '',
    this.remapNoteZh = '',
  });

  factory PinFunction.fromJson(Map<String, dynamic> json) => PinFunction(
        name: asString(json['name']),
        kind: PinFunctionKind.fromRaw(asString(json['kind'])),
        remapRequired: asBool(json['remapRequired']),
        peripheralId: asString(json['peripheralId']),
        remapNoteZh: asString(json['remapNoteZh']),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'name': name,
        'kind': kind.raw,
        'remapRequired': remapRequired,
        'peripheralId': peripheralId,
        'remapNoteZh': remapNoteZh,
      };
}

/// 单个引脚。
class Pin {
  /// 引脚号，LQFP48 为 1..48
  final int number;

  /// 引脚名，如 "PA9"、"VBAT"
  final String name;

  /// 所属分组（可多个，如 PD0 同时是 gpio 和 osc）
  final List<PinGroup> groups;

  /// 默认功能名
  final String defaultFunction;

  /// 默认功能中文说明
  final String defaultFunctionZh;

  /// 可复用功能列表
  final List<PinFunction> functions;

  /// 是否 5V 容忍
  final bool fiveVoltTolerant;

  /// 被 JTAG/SWD 占用时的信号名，如 "JTMS/SWDIO"；未占用为 null
  final String? jtagSwd;

  /// 中文备注
  final String notesZh;

  /// 相关库函数 id（如 GPIO_PinRemapConfig），可点击跳转
  final List<String> relatedFunctionIds;

  const Pin({
    required this.number,
    required this.name,
    this.groups = const <PinGroup>[],
    this.defaultFunction = '',
    this.defaultFunctionZh = '',
    this.functions = const <PinFunction>[],
    this.fiveVoltTolerant = false,
    this.jtagSwd,
    this.notesZh = '',
    this.relatedFunctionIds = const <String>[],
  });

  /// 是否被调试口占用（详情弹窗里要特别标注）
  bool get isDebugOccupied => jtagSwd != null;

  /// 是否是普通 GPIO 引脚（名字形如 PXn）
  bool get isGpio => RegExp(r'^P[A-G]\d{1,2}$').hasMatch(name);

  /// 端口名，如 "PA9" → "GPIOA"；非 GPIO 返回空串
  String get portName {
    if (!isGpio) return '';
    return 'GPIO${name[1]}';
  }

  /// 引脚位序号，如 "PA9" → 9；非 GPIO 返回 -1
  int get bitIndex {
    if (!isGpio) return -1;
    return int.tryParse(name.substring(2)) ?? -1;
  }

  factory Pin.fromJson(Map<String, dynamic> json) => Pin(
        number: asInt(json['number']),
        name: asString(json['name']),
        groups: asStringList(json['groups']).map(PinGroup.fromRaw).toList(),
        defaultFunction: asString(json['defaultFunction']),
        defaultFunctionZh: asString(json['defaultFunctionZh']),
        functions: asMapList(json['functions'])
            .map(PinFunction.fromJson)
            .toList(growable: false),
        fiveVoltTolerant: asBool(json['fiveVoltTolerant']),
        jtagSwd: asStringOrNull(json['jtagSwd']),
        notesZh: asString(json['notesZh']),
        relatedFunctionIds: asStringList(json['relatedFunctionIds']),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'number': number,
        'name': name,
        'groups': groups.map((g) => g.raw).toList(),
        'defaultFunction': defaultFunction,
        'defaultFunctionZh': defaultFunctionZh,
        'functions': functions.map((f) => f.toJson()).toList(),
        'fiveVoltTolerant': fiveVoltTolerant,
        'jtagSwd': jtagSwd,
        'notesZh': notesZh,
        'relatedFunctionIds': relatedFunctionIds,
      };
}

/// `pinout_f103c8t6.json` 顶层结构。
class PinoutData {
  final int schemaVersion;
  final String chipId;

  /// 封装，如 "LQFP48"
  final String package;

  /// 数据来源说明
  final String source;

  /// 是否已人工核对数据手册。false 时引脚页顶部显示黄色提示条。
  final bool verified;

  /// 未核对时的提示文字
  final String verifiedNote;

  final List<Pin> pins;

  /// 功能名 → 引脚列表 的反查索引（内存构建，不来自 JSON）
  final Map<String, List<Pin>> functionsIndex;

  /// 外设实例名 → 该实例的可用引脚（内存构建，不来自 JSON）
  ///
  /// 键是**实例**（SPI1、USART2、TIM1），不是类别（SPI、USART、TIM），
  /// 因为 SPI1 与 SPI2 的引脚完全不同，按类别聚合反而没法用。
  final Map<String, PeripheralPinout> peripheralIndex;

  PinoutData({
    required this.schemaVersion,
    required this.chipId,
    required this.package,
    required this.source,
    required this.verified,
    required this.verifiedNote,
    required this.pins,
    Map<String, List<Pin>>? functionsIndex,
    Map<String, PeripheralPinout>? peripheralIndex,
  })  : functionsIndex = functionsIndex ?? _buildFunctionsIndex(pins),
        peripheralIndex = peripheralIndex ?? buildPeripheralIndex(pins);

  /// 构建"外设实例 → 可用引脚"的索引。
  ///
  /// 从复用功能名里解析实例名：
  ///   `SPI1_SCK`     → 实例 SPI1，信号 SCK
  ///   `USART2_CTS`   → 实例 USART2，信号 CTS
  ///   `TIM2_CH1_ETR` → 实例 TIM2，信号 CH1_ETR
  ///   `ADC12_IN0`    → 实例 ADC12，信号 IN0
  ///   `I2C1_SMBAI`   → 实例 I2C1，信号 SMBAI
  ///
  /// 解析规则：取第一个下划线之前的部分作为实例名，其余作为信号名。
  /// 这是 SPL 头文件里复用功能名的通行写法，48 个引脚的数据全部符合。
  ///
  /// 没有下划线的（如 `MCO`、`TRACESWO`）没有实例前缀，归到"其它"。
  static Map<String, PeripheralPinout> buildPeripheralIndex(List<Pin> pins) {
    // 实例名 → 信号列表
    final byInstance = <String, List<PeripheralPinSignal>>{};
    // 实例名 → 外设类别 id
    final categoryOf = <String, String>{};

    for (final pin in pins) {
      for (final fn in pin.functions) {
        if (fn.kind != PinFunctionKind.af) continue;

        final underscore = fn.name.indexOf('_');
        final hasInstance = underscore > 0;
        final instance = hasInstance ? fn.name.substring(0, underscore) : otherPeripheralId;
        final signal = hasInstance ? fn.name.substring(underscore + 1) : fn.name;

        byInstance.putIfAbsent(instance, () => <PeripheralPinSignal>[]).add(
              PeripheralPinSignal(
                signal: signal,
                pin: pin,
                fullName: fn.name,
                remapRequired: fn.remapRequired,
                remapNoteZh: fn.remapNoteZh,
              ),
            );
        // 同一个实例的所有功能应指向同一个外设类别，取先出现的即可
        if (hasInstance && fn.peripheralId.isNotEmpty) {
          categoryOf.putIfAbsent(instance, () => fn.peripheralId);
        }
      }
    }

    final index = <String, PeripheralPinout>{};
    byInstance.forEach((instance, signals) {
      // 去重：同一实例同一引脚同一信号只留一条
      final seen = <String>{};
      final unique = <PeripheralPinSignal>[];
      for (final s in signals) {
        if (seen.add('${s.fullName}@${s.pinNumber}')) unique.add(s);
      }
      index[instance] = PeripheralPinout(
        instance: instance,
        peripheralId: categoryOf[instance] ?? otherPeripheralId,
        signals: unique,
      );
    });
    return index;
  }

  /// 全部外设实例名，按"名字里带数字的排在后面"以外的自然顺序排列。
  ///
  /// 排序规则：先按外设类别（与外设页的 orderIndex 无关，这里按字母），
  /// 再按实例名。这样 SPI1、SPI2 相邻，USART1、USART2、USART3 相邻。
  List<String> get peripheralInstances {
    final names = peripheralIndex.keys.toList();
    names.sort((a, b) {
      // "其它" 永远排最后
      if (a == otherPeripheralId) return 1;
      if (b == otherPeripheralId) return -1;
      final ca = peripheralIndex[a]!.peripheralId;
      final cb = peripheralIndex[b]!.peripheralId;
      final byCat = ca.compareTo(cb);
      if (byCat != 0) return byCat;
      return a.compareTo(b);
    });
    return names;
  }

  /// 取某外设实例的引脚分配；不存在返回 null。
  PeripheralPinout? peripheralPinout(String instance) =>
      peripheralIndex[instance];

  /// 构建"按功能反查引脚"的索引。
  ///
  /// 键同时收录功能名（USART1_TX）和引脚名（PA9），
  /// 这样输入引脚名也能定位；值按引脚号升序。
  static Map<String, List<Pin>> _buildFunctionsIndex(List<Pin> pins) {
    final index = <String, List<Pin>>{};
    void add(String key, Pin pin) {
      if (key.isEmpty) return;
      final list = index.putIfAbsent(key, () => <Pin>[]);
      if (!list.contains(pin)) list.add(pin);
    }

    for (final pin in pins) {
      add(pin.name, pin);
      for (final fn in pin.functions) {
        add(fn.name, pin);
      }
    }
    for (final list in index.values) {
      list.sort((a, b) => a.number.compareTo(b.number));
    }
    return index;
  }

  /// 按引脚号取引脚，找不到返回 null。
  Pin? pinByNumber(int number) {
    for (final pin in pins) {
      if (pin.number == number) return pin;
    }
    return null;
  }

  /// 按功能名或引脚名反查引脚（不区分大小写，支持部分匹配）。
  List<Pin> searchByFunction(String keyword) {
    final key = keyword.trim().toUpperCase();
    if (key.isEmpty) return const <Pin>[];
    // 完全匹配优先
    final exact = functionsIndex[key];
    if (exact != null) return exact;
    // 退化为包含匹配
    final result = <Pin>[];
    functionsIndex.forEach((name, list) {
      if (name.toUpperCase().contains(key)) {
        for (final pin in list) {
          if (!result.contains(pin)) result.add(pin);
        }
      }
    });
    result.sort((a, b) => a.number.compareTo(b.number));
    return result;
  }

  factory PinoutData.fromJson(Map<String, dynamic> json) {
    final pins = asMapList(json['pins'])
        .map(Pin.fromJson)
        .toList(growable: false)
      ..sort((a, b) => a.number.compareTo(b.number));
    return PinoutData(
      schemaVersion: asInt(json['schemaVersion'], fallback: 1),
      chipId: asString(json['chipId']),
      package: asString(json['package'], fallback: 'LQFP48'),
      source: asString(json['source']),
      verified: asBool(json['verified']),
      verifiedNote: asString(json['verifiedNote']),
      pins: pins,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'schemaVersion': schemaVersion,
        'chipId': chipId,
        'package': package,
        'source': source,
        'verified': verified,
        'verifiedNote': verifiedNote,
        'pins': pins.map((p) => p.toJson()).toList(),
      };
}
