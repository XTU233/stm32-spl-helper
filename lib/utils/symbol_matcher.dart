/// 文本中命中的库内符号。
class SymbolMatch {
  /// 符号名
  final String name;

  /// 在原文中的起始下标
  final int start;

  /// 在原文中的结束下标（不含）
  final int end;

  /// 命中处是否为函数（否则是符号）
  final bool isFunction;

  const SymbolMatch({
    required this.name,
    required this.start,
    required this.end,
    required this.isFunction,
  });

  @override
  String toString() => '$name[$start,$end)${isFunction ? '(fn)' : ''}';
}

/// 扫描文本中的已知库内符号。
///
/// 用于 [KeywordText] 与 [CodeBlock] 把函数名、宏名、枚举名、结构体名
/// 渲染成可点击链接（需求 5.3 的关键词点击跳转）。
///
/// 设计取舍：
///   - 用"白名单 + 词边界"而不是全局正则，避免把 `int`、`for` 之类的
///     普通词误判为链接；
///   - 拒绝长度 ≤ 2 的名字（`u8`、`s8`、`OB` 这类），它们在自然语言里
///     出现频率太高，误链接的代价大于收益；
///   - 一次扫描用单个正则找出所有候选标识符，再查表，复杂度 O(n)。
class SymbolMatcher {
  /// 可跳转的函数名集合
  final Set<String> functionNames;

  /// 可跳转的符号名集合
  final Set<String> symbolNames;

  /// 长度下限：短于这个长度的名字不参与链接
  static const int minNameLength = 3;

  /// 标识符扫描正则。C 标识符规则即可覆盖全部库内名字。
  static final RegExp _identifier = RegExp(r'[A-Za-z_][A-Za-z0-9_]*');

  SymbolMatcher({
    required Iterable<String> functions,
    required Iterable<String> symbols,
  })  : functionNames = _filter(functions),
        symbolNames = _filter(symbols);

  /// 过滤掉过短的名字，避免误链接。
  static Set<String> _filter(Iterable<String> names) {
    final set = <String>{};
    for (final n in names) {
      if (n.length >= minNameLength) set.add(n);
    }
    return set;
  }

  /// 全部可跳转的名字（函数 + 符号），用于快速判空。
  Set<String> get allNames => <String>{...functionNames, ...symbolNames};
  /// 是否可跳转。
  bool canResolve(String name) =>
      functionNames.contains(name) || symbolNames.contains(name);

  /// 该名字是否是函数。
  bool isFunction(String name) => functionNames.contains(name);

  /// 扫描 [text]，按出现顺序返回所有命中的库内符号。
  ///
  /// [whitelist] 非空时只认白名单里的名字（函数的 symbolRefs 就是干这个的），
  /// 这样能避免把注释里偶然出现的同名普通词链接起来。
  List<SymbolMatch> findMatches(String text, {Set<String>? whitelist}) {
    if (text.isEmpty) return const <SymbolMatch>[];

    final matches = <SymbolMatch>[];
    for (final m in _identifier.allMatches(text)) {
      final name = m.group(0)!;
      if (name.length < minNameLength) continue;
      if (whitelist != null && !whitelist.contains(name)) continue;

      final isFn = functionNames.contains(name);
      final isSym = symbolNames.contains(name);
      if (!isFn && !isSym) continue;

      matches.add(SymbolMatch(
        name: name,
        start: m.start,
        end: m.end,
        isFunction: isFn,
      ));
    }
    return matches;
  }

  /// 把文本切成"普通片段 / 可点击片段"的序列。
  ///
  /// 返回的片段已按顺序排好且互不重叠，可直接用于构建 TextSpan。
  List<TextSegment> segment(String text, {Set<String>? whitelist}) {
    final matches = findMatches(text, whitelist: whitelist);
    if (matches.isEmpty) {
      return <TextSegment>[TextSegment.plain(text)];
    }

    final segments = <TextSegment>[];
    var cursor = 0;
    for (final m in matches) {
      if (m.start > cursor) {
        segments.add(TextSegment.plain(text.substring(cursor, m.start)));
      }
      segments.add(TextSegment.link(
        text.substring(m.start, m.end),
        name: m.name,
        isFunction: m.isFunction,
      ));
      cursor = m.end;
    }
    if (cursor < text.length) {
      segments.add(TextSegment.plain(text.substring(cursor)));
    }
    return segments;
  }

  /// 从一段文本里抽出所有命中的名字（去重，保持出现顺序）。
  ///
  /// 用于解析脚本侧同款的 symbolRefs 计算，以及详情页"相关符号"推荐。
  List<String> extractNames(String text, {Set<String>? whitelist}) {
    final seen = <String>{};
    for (final m in findMatches(text, whitelist: whitelist)) {
      seen.add(m.name);
    }
    return seen.toList(growable: false);
  }
}

/// 文本片段：普通文本或可点击链接。
class TextSegment {
  /// 片段原文
  final String text;

  /// 非空表示这是可点击的符号名
  final String? name;

  /// 链接目标是否为函数
  final bool isFunction;

  const TextSegment._(this.text, this.name, this.isFunction);

  /// 构造普通片段
  factory TextSegment.plain(String text) => TextSegment._(text, null, false);

  /// 构造可点击片段
  factory TextSegment.link(
    String text, {
    required String name,
    required bool isFunction,
  }) =>
      TextSegment._(text, name, isFunction);

  /// 是否可点击
  bool get isLink => name != null;

  @override
  String toString() => isLink ? '[$text]' : text;
}
