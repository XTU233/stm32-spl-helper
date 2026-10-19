import '../utils/json_parse.dart';

/// `assets/data/manifest.json` 的模型：数据版本与文件清单。
///
/// APP 启动时最先读它，用于：
/// 1. 校验 [schemaVersion]（与代码期望不符时提示用户重新生成数据，而不是崩溃）；
/// 2. 拿到各数据文件的相对路径，做到"路径也是数据驱动"；
/// 3. 设置页展示数据版本与生成时间。
class DataManifest {
  /// 数据结构版本，代码里用 [currentSchemaVersion] 比对
  final int schemaVersion;

  /// 数据内容版本，如 "1.0.0"，每次重新生成数据时由脚本递增
  final String dataVersion;

  /// 数据来源版本，如 "STM32F10x_StdPeriph_Lib_V3.5.0"
  final String splVersion;

  /// 默认芯片 id，如 "stm32f103c8t6"
  final String defaultChipId;

  /// 生成时间（ISO8601 字符串，含时区）
  final String generatedAt;

  /// 生成工具名
  final String generator;

  /// 各类数据的条数统计
  final DataStats stats;

  /// 数据文件相对路径表，键为数据种类
  final Map<String, String> files;

  const DataManifest({
    required this.schemaVersion,
    required this.dataVersion,
    required this.splVersion,
    required this.defaultChipId,
    required this.generatedAt,
    required this.generator,
    required this.stats,
    required this.files,
  });

  /// 当前代码支持的数据结构版本。数据版本升级时同步改这里。
  static const int currentSchemaVersion = 1;

  /// 数据结构版本是否匹配
  bool get isSchemaCompatible => schemaVersion == currentSchemaVersion;

  /// 取某个数据文件的相对路径，缺失时返回 [fallback]。
  String fileOf(String key, {String fallback = ''}) =>
      files[key] ?? fallback;

  factory DataManifest.fromJson(Map<String, dynamic> json) {
    final rawFiles = asObject(json['files']);
    return DataManifest(
      schemaVersion: asInt(json['schemaVersion'], fallback: 0),
      dataVersion: asString(json['dataVersion'], fallback: '未知'),
      splVersion: asString(json['splVersion'], fallback: '未知'),
      defaultChipId: asString(json['defaultChipId'], fallback: 'stm32f103c8t6'),
      generatedAt: asString(json['generatedAt']),
      generator: asString(json['generator']),
      stats: DataStats.fromJson(asObject(json['stats'])),
      files: rawFiles.map((k, v) => MapEntry(k, asString(v))),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'schemaVersion': schemaVersion,
        'dataVersion': dataVersion,
        'splVersion': splVersion,
        'defaultChipId': defaultChipId,
        'generatedAt': generatedAt,
        'generator': generator,
        'stats': stats.toJson(),
        'files': files,
      };
}

/// 数据条数统计，用于设置页展示与自检。
class DataStats {
  final int peripheralCount;
  final int functionCount;
  final int symbolCount;
  final int pinCount;
  final int compileErrorCount;

  const DataStats({
    this.peripheralCount = 0,
    this.functionCount = 0,
    this.symbolCount = 0,
    this.pinCount = 0,
    this.compileErrorCount = 0,
  });

  static const DataStats empty = DataStats();

  factory DataStats.fromJson(Map<String, dynamic> json) => DataStats(
        peripheralCount: asInt(json['peripheralCount']),
        functionCount: asInt(json['functionCount']),
        symbolCount: asInt(json['symbolCount']),
        pinCount: asInt(json['pinCount']),
        compileErrorCount: asInt(json['compileErrorCount']),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'peripheralCount': peripheralCount,
        'functionCount': functionCount,
        'symbolCount': symbolCount,
        'pinCount': pinCount,
        'compileErrorCount': compileErrorCount,
      };
}
