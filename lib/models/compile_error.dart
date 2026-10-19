import '../utils/json_parse.dart';
import 'ai_reserved.dart';

/// 编译错误分类（对应 `compile_errors.json` 的 categories）。
class CompileErrorCategory {
  /// 分类 id，如 "linker"
  final String id;

  /// 中文名，如 "链接错误"
  final String nameZh;

  /// 英文名，如 "Linker"
  final String nameEn;

  /// 排序权重
  final int orderIndex;

  const CompileErrorCategory({
    required this.id,
    required this.nameZh,
    this.nameEn = '',
    this.orderIndex = 1000,
  });

  factory CompileErrorCategory.fromJson(Map<String, dynamic> json) =>
      CompileErrorCategory(
        id: asString(json['id']),
        nameZh: asString(json['nameZh']),
        nameEn: asString(json['nameEn']),
        orderIndex: asInt(json['orderIndex'], fallback: 1000),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'nameZh': nameZh,
        'nameEn': nameEn,
        'orderIndex': orderIndex,
      };
}

/// 编译/链接/下载错误条目。
///
/// 首期覆盖需求 5.7 列出的 15 类错误。
class CompileError {
  /// 唯一标识，如 "err.undefined_reference"
  final String id;

  /// 中文标题（一般是错误原文的精简形式）
  final String titleZh;

  /// 所属分类 id
  final String categoryId;

  /// 工具链：keil / gcc-arm / st-link / 通用
  final String toolchain;

  /// 用于搜索匹配的错误原文片段
  final List<String> messagePatterns;

  /// 完整错误原文样例（可复制）
  final String messageSample;

  /// 中文解释：这个错误在说什么
  final String explainZh;

  /// 产生原因列表
  final List<String> causes;

  /// 解决步骤（有序）
  final List<String> solutions;

  /// 相关代码/配置片段
  final List<CodeSnippet> codeSnippets;

  /// 相关函数 id
  final List<String> relatedFunctionIds;

  /// 相关符号 id
  final List<String> relatedSymbolIds;

  /// 相关外设 id
  final List<String> relatedPeripheralIds;

  /// 标签，便于搜索
  final List<String> tags;

  /// 预留 AI 字段
  final AiReserved ai;

  const CompileError({
    required this.id,
    required this.titleZh,
    required this.categoryId,
    this.toolchain = '',
    this.messagePatterns = const <String>[],
    this.messageSample = '',
    this.explainZh = '',
    this.causes = const <String>[],
    this.solutions = const <String>[],
    this.codeSnippets = const <CodeSnippet>[],
    this.relatedFunctionIds = const <String>[],
    this.relatedSymbolIds = const <String>[],
    this.relatedPeripheralIds = const <String>[],
    this.tags = const <String>[],
    this.ai = AiReserved.empty,
  });

  /// 搜索用的全部文本（错误原文 + 中文解释 + 标签），小写化后供索引使用
  String get searchableText => <String>[
        titleZh,
        messageSample,
        ...messagePatterns,
        explainZh,
        ...tags,
      ].join(' ');

  /// 工具链的中文显示名。
  ///
  /// 数据里存的是 `keil` / `gcc-arm` / `st-link` / `generic`，
  /// 直接显示英文对不熟悉的人没意义（"generic" 尤其费解），
  /// 所以统一在这里翻译，避免界面各处自己拼字符串。
  String get toolchainZh {
    switch (toolchain) {
      case 'keil':
        return 'Keil MDK';
      case 'gcc-arm':
        return 'GCC ARM';
      case 'st-link':
        return 'ST-Link';
      case 'generic':
        return '通用';
      default:
        return toolchain;
    }
  }

  factory CompileError.fromJson(Map<String, dynamic> json) => CompileError(
        id: asString(json['id']),
        titleZh: asString(json['titleZh']),
        categoryId: asString(json['categoryId']),
        toolchain: asString(json['toolchain']),
        messagePatterns: asStringList(json['messagePatterns']),
        messageSample: asString(json['messageSample']),
        explainZh: asString(json['explainZh']),
        causes: asStringList(json['causes']),
        solutions: asStringList(json['solutions']),
        codeSnippets: asMapList(json['codeSnippets'])
            .map(CodeSnippet.fromJson)
            .toList(growable: false),
        relatedFunctionIds: asStringList(json['relatedFunctionIds']),
        relatedSymbolIds: asStringList(json['relatedSymbolIds']),
        relatedPeripheralIds: asStringList(json['relatedPeripheralIds']),
        tags: asStringList(json['tags']),
        ai: json['ai'] == null
            ? AiReserved.empty
            : AiReserved.fromJson(asObject(json['ai'])),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'titleZh': titleZh,
        'categoryId': categoryId,
        'toolchain': toolchain,
        'messagePatterns': messagePatterns,
        'messageSample': messageSample,
        'explainZh': explainZh,
        'causes': causes,
        'solutions': solutions,
        'codeSnippets': codeSnippets.map((s) => s.toJson()).toList(),
        'relatedFunctionIds': relatedFunctionIds,
        'relatedSymbolIds': relatedSymbolIds,
        'relatedPeripheralIds': relatedPeripheralIds,
        'tags': tags,
        'ai': ai.isEmpty ? null : ai.toJson(),
      };
}

/// 可复制的代码/配置片段。
class CodeSnippet {
  /// 语言，固定 "c" 或 "ini"、"makefile" 等
  final String language;

  /// 片段标题，如 "正确写法"
  final String title;

  /// 片段内容
  final String code;

  const CodeSnippet({
    this.language = 'c',
    this.title = '',
    required this.code,
  });

  factory CodeSnippet.fromJson(Map<String, dynamic> json) => CodeSnippet(
        language: asString(json['language'], fallback: 'c'),
        title: asString(json['title']),
        code: asString(json['code']),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'language': language,
        'title': title,
        'code': code,
      };
}

/// `compile_errors.json` 顶层结构。
class CompileErrorBundle {
  final int schemaVersion;
  final List<CompileErrorCategory> categories;
  final List<CompileError> errors;

  const CompileErrorBundle({
    required this.schemaVersion,
    this.categories = const <CompileErrorCategory>[],
    this.errors = const <CompileError>[],
  });

  factory CompileErrorBundle.fromJson(Map<String, dynamic> json) =>
      CompileErrorBundle(
        schemaVersion: asInt(json['schemaVersion'], fallback: 1),
        categories: asMapList(json['categories'])
            .map(CompileErrorCategory.fromJson)
            .toList(growable: false)
          ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex)),
        errors: asMapList(json['errors'])
            .map(CompileError.fromJson)
            .toList(growable: false),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'schemaVersion': schemaVersion,
        'categories': categories.map((c) => c.toJson()).toList(),
        'errors': errors.map((e) => e.toJson()).toList(),
      };
}
