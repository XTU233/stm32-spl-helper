import '../utils/json_parse.dart';

/// 外设模型（对应 `assets/data/peripherals.json` 里的一项）。
///
/// 一个外设 = 一个 SPL 模块，如 GPIO、RCC、USART。
/// 外设本身不直接持有函数对象，只持有 [PeripheralSection]，
/// section 里存的是函数 id，函数正文在 `functions/<外设>.json` 里。
/// 这样首页只需加载轻量的 peripherals.json 即可渲染列表。
class Peripheral {
  /// 外设标识，如 "GPIO"
  final String id;

  /// 英文名，如 "GPIO"
  final String name;

  /// 中文名，如 "通用输入输出"
  final String nameZh;

  /// 头文件名，如 "stm32f10x_gpio.h"
  final String header;

  /// 源文件名，如 "stm32f10x_gpio.c"
  final String source;

  /// 函数数据文件相对路径，如 "functions/GPIO.json"
  final String file;

  /// 首页排序权重，越小越靠前（由 overlay 指定，GPIO=1、RCC=2…）
  final int orderIndex;

  /// 总体中文说明
  final String introZh;

  /// 使用总览：先做什么后做什么
  final String usageOverviewZh;

  /// 函数数量
  final int functionCount;

  /// 符号数量
  final int symbolCount;

  /// 标签，如 ["常用", "基础"]
  final List<String> tags;

  /// 函数分组
  final List<PeripheralSection> sections;

  const Peripheral({
    required this.id,
    required this.name,
    required this.nameZh,
    required this.header,
    required this.source,
    required this.file,
    required this.orderIndex,
    required this.introZh,
    required this.usageOverviewZh,
    required this.functionCount,
    required this.symbolCount,
    required this.tags,
    required this.sections,
  });

  /// 详情页顶部的一句话简介：优先用总览的第一句，没有就用总体说明。
  String get oneLineIntro {
    final text = usageOverviewZh.isNotEmpty ? usageOverviewZh : introZh;
    if (text.isEmpty) return '';
    // 按中文句号/换行截取第一句，避免卡片上出现整段文字
    final cut = text.split(RegExp(r'[。\n]')).first;
    return cut.isEmpty ? text : '$cut。';
  }

  /// 所有函数 id（按 section 顺序拼接），供索引与统计使用。
  List<String> get allFunctionIds =>
      sections.expand((s) => s.functionIds).toList(growable: false);

  factory Peripheral.fromJson(Map<String, dynamic> json) => Peripheral(
        id: asString(json['id']),
        name: asString(json['name']),
        nameZh: asString(json['nameZh'], fallback: asString(json['name'])),
        header: asString(json['header']),
        source: asString(json['source']),
        file: asString(json['file']),
        orderIndex: asInt(json['orderIndex'], fallback: 1000),
        introZh: asString(json['introZh']),
        usageOverviewZh: asString(json['usageOverviewZh']),
        functionCount: asInt(json['functionCount']),
        symbolCount: asInt(json['symbolCount']),
        tags: asStringList(json['tags']),
        sections: asMapList(json['sections'])
            .map(PeripheralSection.fromJson)
            .toList(growable: false),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'nameZh': nameZh,
        'header': header,
        'source': source,
        'file': file,
        'orderIndex': orderIndex,
        'introZh': introZh,
        'usageOverviewZh': usageOverviewZh,
        'functionCount': functionCount,
        'symbolCount': symbolCount,
        'tags': tags,
        'sections': sections.map((s) => s.toJson()).toList(),
      };
}

/// 函数分组：对应 ST 头文件里的一行分节注释。
///
/// 例如 `/*  Initialization and Configuration functions ***/`
/// 会被翻译成 title="初始化与配置函数"、titleEn 保留英文原文。
class PeripheralSection {
  /// 分组 id，形如 "GPIO#sec1"，函数通过 sectionId 反查所属分组
  final String id;

  /// 中文标题
  final String title;

  /// 英文原标题（ST 原文，可能为空）
  final String? titleEn;

  /// 该分组下的函数 id 列表（顺序与头文件一致）
  final List<String> functionIds;

  const PeripheralSection({
    required this.id,
    required this.title,
    this.titleEn,
    required this.functionIds,
  });

  factory PeripheralSection.fromJson(Map<String, dynamic> json) =>
      PeripheralSection(
        id: asString(json['id']),
        title: asString(json['title']),
        titleEn: asStringOrNull(json['titleEn']),
        functionIds: asStringList(json['functionIds']),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'title': title,
        'titleEn': titleEn,
        'functionIds': functionIds,
      };
}

/// `peripherals.json` 顶层结构。
class PeripheralBundle {
  final int schemaVersion;
  final List<Peripheral> peripherals;

  const PeripheralBundle({
    required this.schemaVersion,
    required this.peripherals,
  });

  factory PeripheralBundle.fromJson(Map<String, dynamic> json) =>
      PeripheralBundle(
        schemaVersion: asInt(json['schemaVersion'], fallback: 1),
        peripherals: asMapList(json['peripherals'])
            .map(Peripheral.fromJson)
            .toList(growable: false),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'schemaVersion': schemaVersion,
        'peripherals': peripherals.map((p) => p.toJson()).toList(),
      };
}
