import 'package:flutter/material.dart';

/// 把文本按关键词切成"命中 / 未命中"的片段，用于搜索结果高亮。
///
/// 需求 5.4 要求"结果高亮"。实现上不做正则（用户输入里可能有 `.`、`*`
/// 这类元字符，直接进正则会出错或匹配到意外内容），改用大小写不敏感的
/// 逐位置比较，行为可预期。
class HighlightSpan {
  /// 片段文本
  final String text;

  /// 是否为命中片段
  final bool hit;

  const HighlightSpan(this.text, this.hit);
}

/// 高亮工具。
class Highlighter {
  /// 把 [text] 按 [keyword] 切成片段。
  ///
  /// 命中的是**所有**出现位置（如搜 `gpio` 时 `GPIO_InitGPIO` 两处都标）。
  /// 关键词为空时返回单个未命中片段。
  static List<HighlightSpan> split(String text, String keyword) {
    if (text.isEmpty) return const <HighlightSpan>[];
    final k = keyword.trim();
    if (k.isEmpty) return <HighlightSpan>[HighlightSpan(text, false)];

    final lowerText = text.toLowerCase();
    final lowerKey = k.toLowerCase();

    final spans = <HighlightSpan>[];
    var cursor = 0;

    while (true) {
      final idx = lowerText.indexOf(lowerKey, cursor);
      if (idx < 0) break;
      if (idx > cursor) {
        spans.add(HighlightSpan(text.substring(cursor, idx), false));
      }
      spans.add(HighlightSpan(text.substring(idx, idx + k.length), true));
      cursor = idx + k.length;
    }

    if (cursor < text.length) {
      spans.add(HighlightSpan(text.substring(cursor), false));
    }
    // 一次都没命中时返回整段未命中，保证调用方能拿到原文
    if (spans.isEmpty) return <HighlightSpan>[HighlightSpan(text, false)];
    return spans;
  }

  /// 文本是否命中关键词。
  static bool matches(String text, String keyword) {
    final k = keyword.trim();
    if (k.isEmpty) return false;
    return text.toLowerCase().contains(k.toLowerCase());
  }

  /// 构建带高亮样式的 [TextSpan] 列表。
  ///
  /// [base] 是未命中片段的样式，[hitStyle] 叠加在命中片段上。
  static List<TextSpan> spans(
    String text,
    String keyword, {
    TextStyle? base,
    required TextStyle hitStyle,
  }) {
    return <TextSpan>[
      for (final s in split(text, keyword))
        TextSpan(
          text: s.text,
          style: s.hit ? (base == null ? hitStyle : base.merge(hitStyle)) : base,
        ),
    ];
  }
}

/// 结果标题高亮文本。
///
/// 标题默认用等宽字体（函数名/宏名），命中部分加粗并换成主题色，
/// 外加浅色背景块，扫一眼就能看出"为什么这条被搜出来"。
class HighlightedText extends StatelessWidget {
  /// 完整文本
  final String text;

  /// 要高亮的关键词
  final String keyword;

  /// 基础样式
  final TextStyle? style;

  /// 最大行数
  final int? maxLines;

  /// 溢出方式
  final TextOverflow? overflow;

  /// 是否加背景色块。标题用 true，说明文字用 false（避免整段花掉）。
  final bool withBackground;

  const HighlightedText(
    this.text,
    this.keyword, {
    super.key,
    this.style,
    this.maxLines,
    this.overflow,
    this.withBackground = true,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hitStyle = TextStyle(
      color: scheme.primary,
      fontWeight: FontWeight.w800,
      backgroundColor:
          withBackground ? scheme.primary.withValues(alpha: 0.14) : null,
    );

    // 没命中就退化成普通 Text，省掉 RichText 的开销
    if (!Highlighter.matches(text, keyword)) {
      return Text(
        text,
        style: style,
        maxLines: maxLines,
        overflow: overflow,
      );
    }

    return Text.rich(
      TextSpan(
        children: Highlighter.spans(
          text,
          keyword,
          base: style,
          hitStyle: hitStyle,
        ),
      ),
      style: style,
      maxLines: maxLines,
      overflow: overflow ?? TextOverflow.ellipsis,
    );
  }
}
