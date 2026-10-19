import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../pages/function_detail_page.dart';
import '../pages/symbol_detail_page.dart';
import '../providers/app_providers.dart';

/// 可点击关键词文本。
///
/// 把文本里出现的库内符号（函数名、宏名、枚举名、结构体名）渲染成可点击的
/// 蓝色文字，点击跳转到对应详情页（需求 5.3 的关键词点击跳转）。
///
/// 用 [whitelist] 限定可跳转范围：函数详情页传该函数的 symbolRefs，
/// 这样只链接真正相关的符号，不会把注释里偶然同名的普通词也变成链接。
class KeywordText extends ConsumerWidget {
  /// 要渲染的文本
  final String text;

  /// 白名单：非空时只链接这些名字
  final Set<String>? whitelist;

  /// 文字样式
  final TextStyle? style;

  /// 最大行数
  final int? maxLines;

  /// 超出时的截断方式
  final TextOverflow? overflow;

  /// 文本对齐
  final TextAlign? textAlign;

  const KeywordText(
    this.text, {
    super.key,
    this.whitelist,
    this.style,
    this.maxLines,
    this.overflow,
    this.textAlign,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final matcher = ref.watch(symbolMatcherProvider);
    if (matcher == null) {
      // 索引还没建好，先按纯文本渲染，避免闪烁
      return Text(
        text,
        style: style,
        maxLines: maxLines,
        overflow: overflow,
        textAlign: textAlign,
      );
    }

    final segments = matcher.segment(text, whitelist: whitelist);
    // 没有任何链接时退回普通 Text，省掉 RichText 的开销
    if (segments.every((s) => !s.isLink)) {
      return Text(
        text,
        style: style,
        maxLines: maxLines,
        overflow: overflow,
        textAlign: textAlign,
      );
    }

    final base = style ?? DefaultTextStyle.of(context).style;
    final scheme = Theme.of(context).colorScheme;
    final linkStyle = base.copyWith(
      color: scheme.primary,
      fontWeight: FontWeight.w600,
      decoration: TextDecoration.underline,
      decorationStyle: TextDecorationStyle.dotted,
      decorationColor: scheme.primary.withValues(alpha: 0.5),
    );

    return Text.rich(
      TextSpan(
        children: <InlineSpan>[
          for (final seg in segments)
            if (seg.isLink)
              TextSpan(
                text: seg.text,
                style: linkStyle,
                recognizer: TapGestureRecognizer()
                  ..onTap = () => openSymbol(context, ref, seg.name!),
              )
            else
              TextSpan(text: seg.text, style: base),
        ],
      ),
      maxLines: maxLines,
      overflow: overflow ?? TextOverflow.clip,
      textAlign: textAlign,
    );
  }
}

/// 跳转到符号或函数详情页。
///
/// 抽成顶层函数，供 KeywordText、参数表、代码块、相关函数列表共用。
/// 用 Navigator.push 保证"点进去能返回原位置"（需求 5.3）。
void openSymbol(BuildContext context, WidgetRef ref, String name) {
  final data = ref.read(splDataProvider).valueOrNull;
  if (data == null) return;

  // 函数优先：同名时函数比符号更可能是用户想看的
  if (data.isKnownFunction(name)) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FunctionDetailPage(functionId: name),
      ),
    );
    return;
  }
  if (data.isKnownSymbol(name)) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SymbolDetailPage(symbolId: name),
      ),
    );
    return;
  }

  // 都不认识：给出提示而不是静默无反应
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('未收录符号 $name')),
  );
}

/// 把一段文本按符号切成可点击的行内片段。
///
/// 供参数表、返回值说明等处复用（这些地方不需要整段 Text，只要 spans）。
List<InlineSpan> buildKeywordSpans(
  BuildContext context,
  WidgetRef ref,
  String text, {
  Set<String>? whitelist,
  TextStyle? style,
}) {
  final matcher = ref.read(symbolMatcherProvider);
  final base = style ?? DefaultTextStyle.of(context).style;
  if (matcher == null) {
    return <InlineSpan>[TextSpan(text: text, style: base)];
  }

  final scheme = Theme.of(context).colorScheme;
  final linkStyle = base.copyWith(
    color: scheme.primary,
    fontWeight: FontWeight.w600,
    decoration: TextDecoration.underline,
    decorationStyle: TextDecorationStyle.dotted,
    decorationColor: scheme.primary.withValues(alpha: 0.5),
  );

  return <InlineSpan>[
    for (final seg in matcher.segment(text, whitelist: whitelist))
      if (seg.isLink)
        TextSpan(
          text: seg.text,
          style: linkStyle,
          recognizer: TapGestureRecognizer()
            ..onTap = () => openSymbol(context, ref, seg.name!),
        )
      else
        TextSpan(text: seg.text, style: base),
  ];
}
