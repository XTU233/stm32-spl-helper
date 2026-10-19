import '../utils/json_parse.dart';
import 'ai_reserved.dart';

/// 芯片能力描述（对应 `assets/data/chips/<chipId>.json`）。
///
/// 这是"以后加 STM32F4 只加数据文件、不改代码"的关键：
/// 首页"仅显示本型号支持的外设"开关、外设实例列表（GPIOA/GPIOB…）、
/// Flash/RAM 提示，全部读本模型，Dart 代码里不出现任何型号字面量。
class ChipSpec {
  /// 芯片 id，如 "stm32f103c8t6"
  final String id;

  /// 英文名，如 "STM32F103C8T6"
  final String name;

  /// 中文名与补充说明
  final String nameZh;

  /// 封装，如 "LQFP48"
  final String package;

  /// 内核，如 "ARM Cortex-M3"
  final String core;

  /// Flash 大小（KB）
  final int flashKb;

  /// RAM 大小（KB）
  final int ramKb;

  /// 最高主频（MHz）
  final int maxFreqMhz;

  /// 供电范围说明
  final String voltageRange;

  /// 数据手册编号，如 "DS5319"
  final String dataSheet;

  /// 引脚数据文件相对路径
  final String pinoutFile;

  /// 本型号支持的外设 id 列表
  final List<String> supportedPeripherals;

  /// 本型号不支持的外设 id 列表
  final List<String> unsupportedPeripherals;

  /// 不支持原因，键为外设 id
  final Map<String, String> unsupportedReasons;

  /// 外设实例，如 {"GPIO": ["GPIOA", "GPIOB", ...]}
  final Map<String, List<String>> peripheralInstances;

  /// 中文备注
  final String notesZh;

  /// 预留 AI 字段
  final AiReserved ai;

  const ChipSpec({
    required this.id,
    required this.name,
    this.nameZh = '',
    this.package = '',
    this.core = '',
    this.flashKb = 0,
    this.ramKb = 0,
    this.maxFreqMhz = 0,
    this.voltageRange = '',
    this.dataSheet = '',
    this.pinoutFile = '',
    this.supportedPeripherals = const <String>[],
    this.unsupportedPeripherals = const <String>[],
    this.unsupportedReasons = const <String, String>{},
    this.peripheralInstances = const <String, List<String>>{},
    this.notesZh = '',
    this.ai = AiReserved.empty,
  });

  /// 该外设是否被本型号支持。
  ///
  /// 判断顺序：先看 [unsupportedPeripherals]（明确不支持），
  /// 再看 [supportedPeripherals]（明确支持）；两边都没有时按支持处理，
  /// 避免新外设因为没登记就被隐藏。
  bool supportsPeripheral(String peripheralId) {
    if (unsupportedPeripherals.contains(peripheralId)) return false;
    if (supportedPeripherals.isEmpty) return true;
    return supportedPeripherals.contains(peripheralId);
  }

  /// 取不支持原因，没有则返回通用文案。
  String unsupportedReason(String peripheralId) =>
      unsupportedReasons[peripheralId] ?? '该型号不支持此$peripheralId外设';

  /// 取外设实例列表，如 ["GPIOA", "GPIOB"]；未登记时返回空列表。
  List<String> instancesOf(String peripheralId) =>
      peripheralInstances[peripheralId] ?? const <String>[];

  /// 一句话芯片描述，如 "ARM Cortex-M3 · 64KB Flash / 20KB RAM · 72MHz"
  String get summary =>
      '$core · ${flashKb}KB Flash / ${ramKb}KB RAM · ${maxFreqMhz}MHz';

  factory ChipSpec.fromJson(Map<String, dynamic> json) {
    final rawInstances = asObject(json['peripheralInstances']);
    final rawReasons = asObject(json['unsupportedReasons']);
    return ChipSpec(
      id: asString(json['id']),
      name: asString(json['name']),
      nameZh: asString(json['nameZh']),
      package: asString(json['package']),
      core: asString(json['core']),
      flashKb: asInt(json['flashKb']),
      ramKb: asInt(json['ramKb']),
      maxFreqMhz: asInt(json['maxFreqMhz']),
      voltageRange: asString(json['voltageRange']),
      dataSheet: asString(json['dataSheet']),
      pinoutFile: asString(json['pinoutFile']),
      supportedPeripherals: asStringList(json['supportedPeripherals']),
      unsupportedPeripherals: asStringList(json['unsupportedPeripherals']),
      unsupportedReasons: rawReasons.map(
        (k, v) => MapEntry(k, asString(v)),
      ),
      peripheralInstances: rawInstances.map(
        (k, v) => MapEntry(k, asStringList(v)),
      ),
      notesZh: asString(json['notesZh']),
      ai: json['ai'] == null
          ? AiReserved.empty
          : AiReserved.fromJson(asObject(json['ai'])),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'nameZh': nameZh,
        'package': package,
        'core': core,
        'flashKb': flashKb,
        'ramKb': ramKb,
        'maxFreqMhz': maxFreqMhz,
        'voltageRange': voltageRange,
        'dataSheet': dataSheet,
        'pinoutFile': pinoutFile,
        'supportedPeripherals': supportedPeripherals,
        'unsupportedPeripherals': unsupportedPeripherals,
        'unsupportedReasons': unsupportedReasons,
        'peripheralInstances': peripheralInstances,
        'notesZh': notesZh,
        'ai': ai.isEmpty ? null : ai.toJson(),
      };
}
