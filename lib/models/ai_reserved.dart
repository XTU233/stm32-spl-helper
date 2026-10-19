import '../utils/json_parse.dart';

/// 预留的 AI 字段容器（本期恒为 null 内容，不参与任何逻辑）。
///
/// 保留原因：需求明确"不做 AI 问答，但数据结构上预留字段"。
/// 将来接入本地摘要/问答时，直接往 [summary] 和 [qa] 里填即可，
/// 不需要改动任何模型类的解析代码。
class AiReserved {
  /// 中文/英文摘要（预留）
  final String? summary;

  /// 问答对列表，每项形如 `{"q": "...", "a": "..."}`（预留）
  final List<Map<String, dynamic>> qa;

  /// 指向离线向量库的引用键（预留，不联网）
  final String? embeddingRef;

  /// 其它扩展字段，避免以后加内容还要改类
  final Map<String, dynamic> extra;

  const AiReserved({
    this.summary,
    this.qa = const <Map<String, dynamic>>[],
    this.embeddingRef,
    this.extra = const <String, dynamic>{},
  });

  /// 空实例：数据里没有 ai 字段时统一用它，避免到处判空。
  static const AiReserved empty = AiReserved();

  bool get isEmpty =>
      summary == null && qa.isEmpty && embeddingRef == null && extra.isEmpty;

  factory AiReserved.fromJson(Map<String, dynamic> json) {
    return AiReserved(
      summary: asStringOrNull(json['summary']),
      qa: asMapList(json['qa']),
      embeddingRef: asStringOrNull(json['embeddingRef']),
      extra: asObject(json['extra']),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'summary': summary,
        'qa': qa,
        'embeddingRef': embeddingRef,
        'extra': extra,
      };
}
