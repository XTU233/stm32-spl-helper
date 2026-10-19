import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/compile_error.dart';
import '../models/item_ref.dart';
import '../providers/app_providers.dart';
import '../utils/theme.dart';
import '../widgets/code_block.dart';
import '../widgets/item_actions.dart';
import '../widgets/keyword_text.dart';
import '../widgets/recent_view_recorder.dart';
import '../widgets/section_header.dart';
import 'peripheral_detail_page.dart';

/// 编译错误详情页。
///
/// 承载需求 5.7 的完整信息：错误原文、中文解释、产生原因、解决步骤、
/// 相关代码片段、相关函数/符号（可点击跳转）。
///
/// 早先搜索页与列表页点到错误条目只弹"阶段 8 实现"的提示，
/// 现在补上真正的详情页——搜索结果里的"编译错误"类别才有落点。
class CompileErrorDetailPage extends ConsumerWidget {
  /// 错误 id，如 "err.undefined_reference"
  final String errorId;

  const CompileErrorDetailPage({super.key, required this.errorId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dataAsync = ref.watch(splDataProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('错误详情'),
        actions: <Widget>[
          _ErrorActions(errorId: errorId),
        ],
      ),
      body: dataAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败：$e')),
        data: (data) {
          final err = data.compileErrorById[errorId];
          if (err == null) {
            return const Center(child: Text('未收录该错误条目'));
          }
          return _ErrorBody(error: err);
        },
      ),
    );
  }
}

/// 错误详情页的收藏/笔记按钮。
///
/// 单独抽出来是因为 AppBar 在 `dataAsync.when` 外层，拿不到已解析的
/// [CompileError]；这里用 errorId 反查标题，让按钮在加载完成后才出现。
class _ErrorActions extends ConsumerWidget {
  final String errorId;

  const _ErrorActions({required this.errorId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(splDataProvider).valueOrNull;
    final err = data?.compileErrorById[errorId];
    // 还没加载完 / id 无效时不显示按钮，避免出现点不动的星标
    if (err == null) return const SizedBox.shrink();

    return ItemActions(
      item: ItemRef(
        type: ItemType.compileError,
        id: err.id,
        title: err.titleZh,
        subtitle: err.toolchainZh,
      ),
    );
  }
}

class _ErrorBody extends ConsumerWidget {
  final CompileError error;

  const _ErrorBody({required this.error});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final data = ref.watch(splDataProvider).valueOrNull;
    final category = data?.compileErrors.categories
        .where((c) => c.id == error.categoryId)
        .firstOrNull;

    // 数据已就绪，记一次「最近查看」
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.mounted) {
        recordRecentView(
          ref,
          ItemRef(
            type: ItemType.compileError,
            id: error.id,
            title: error.titleZh,
            subtitle: error.toolchainZh,
          ),
        );
      }
    });

    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: <Widget>[
        // ---- 标题区 ----
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
          color: scheme.errorContainer.withValues(alpha: 0.35),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(Icons.error_outline, size: 18, color: scheme.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      error.titleZh,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: <Widget>[
                  if (category != null)
                    _Chip(label: category.nameZh, color: scheme.primary),
                  if (error.toolchain.isNotEmpty)
                    _Chip(label: error.toolchainZh, color: scheme.tertiary),
                  for (final t in error.tags)
                    _Chip(label: t, color: scheme.onSurfaceVariant),
                ],
              ),
            ],
          ),
        ),

        // ---- 错误原文 ----
        if (error.messageSample.isNotEmpty ||
            error.messagePatterns.isNotEmpty) ...<Widget>[
          const SectionHeader(
            icon: Icons.terminal,
            title: '错误原文',
            subtitle: '编译器/链接器实际输出的文字，认准这几行',
          ),
          if (error.messageSample.isNotEmpty)
            _CopyableOutput(text: error.messageSample),
          if (error.messagePatterns.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '关键字片段（在输出里搜这些能找到本条）',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: <Widget>[
                      for (final p in error.messagePatterns)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerHighest
                                .withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(
                            p,
                            style: TextStyle(
                              fontFamilyFallback: AppFonts.mono,
                              fontSize: 11.5,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
        ],

        // ---- 中文解释 ----
        if (error.explainZh.isNotEmpty) ...<Widget>[
          const SectionHeader(
            icon: Icons.lightbulb_outline,
            title: '这是什么意思',
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: KeywordText(
              error.explainZh,
              style: const TextStyle(fontSize: 13.5, height: 1.7),
            ),
          ),
        ],

        // ---- 产生原因 ----
        if (error.causes.isNotEmpty) ...<Widget>[
          const SectionHeader(
            icon: Icons.help_outline,
            title: '可能的原因',
            subtitle: '按从常见到少见的顺序排查',
          ),
          for (var i = 0; i < error.causes.length; i++)
            _NumberedItem(
              index: i + 1,
              text: error.causes[i],
              color: scheme.tertiary,
            ),
        ],

        // ---- 解决步骤 ----
        if (error.solutions.isNotEmpty) ...<Widget>[
          const SectionHeader(
            icon: Icons.checklist_rtl,
            title: '解决步骤',
            subtitle: '照顺序做，每一步都能排除一类原因',
          ),
          for (var i = 0; i < error.solutions.length; i++)
            _StepItem(index: i + 1, text: error.solutions[i]),
        ],

        // ---- 相关代码 ----
        if (error.codeSnippets.isNotEmpty) ...<Widget>[
          const SectionHeader(
            icon: Icons.code,
            title: '相关代码',
            subtitle: '对照检查你的工程配置与写法',
          ),
          for (final s in error.codeSnippets)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: CodeBlock(
                code: s.code,
                language: s.language,
                title: s.title.isEmpty ? null : s.title,
                horizontalScroll: true,
              ),
            ),
        ],

        // ---- 相关函数 / 符号 / 外设 ----
        if (error.relatedFunctionIds.isNotEmpty) ...<Widget>[
          const SectionHeader(
            icon: Icons.functions,
            title: '相关函数',
            subtitle: '点击查看用法（多数错误是因为少调了其中一个）',
          ),
          _RelatedChips(
            ids: error.relatedFunctionIds,
            onTap: (id) => openSymbol(context, ref, id),
          ),
        ],
        if (error.relatedSymbolIds.isNotEmpty) ...<Widget>[
          const SectionHeader(icon: Icons.tag, title: '相关符号'),
          _RelatedChips(
            ids: error.relatedSymbolIds,
            onTap: (id) => openSymbol(context, ref, id),
          ),
        ],
        if (error.relatedPeripheralIds.isNotEmpty) ...<Widget>[
          const SectionHeader(icon: Icons.memory, title: '相关外设'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                for (final id in error.relatedPeripheralIds)
                  ActionChip(
                    label: Text(
                      data?.peripheral(id)?.nameZh ?? id,
                      style: const TextStyle(fontSize: 12),
                    ),
                    onPressed: () => _openPeripheral(context, id),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  void _openPeripheral(BuildContext context, String id) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PeripheralDetailPage(peripheralId: id),
      ),
    );
  }
}

/// 可复制的错误原文块。
class _CopyableOutput extends StatelessWidget {
  final String text;

  const _CopyableOutput({required this.text});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '编译器输出',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.copy_all, size: 16),
                tooltip: '复制原文',
                visualDensity: VisualDensity.compact,
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: text));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('已复制错误原文'),
                        duration: Duration(milliseconds: 1200),
                      ),
                    );
                  }
                },
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: SelectableText(
              text,
              style: TextStyle(
                fontFamilyFallback: AppFonts.mono,
                fontSize: 12,
                height: 1.55,
                color: scheme.error,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 标签小片。
class _Chip extends StatelessWidget {
  final String label;
  final Color color;

  const _Chip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

/// 序号条目（用于"可能的原因"）。
class _NumberedItem extends StatelessWidget {
  final int index;
  final String text;
  final Color color;

  const _NumberedItem({
    required this.index,
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 3, 16, 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 18,
            height: 18,
            margin: const EdgeInsets.only(top: 1.5),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            alignment: Alignment.center,
            child: Text(
              '$index',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 13, height: 1.6),
            ),
          ),
        ],
      ),
    );
  }
}

/// 有序步骤条目。
class _StepItem extends StatelessWidget {
  final int index;
  final String text;

  const _StepItem({required this.index, required this.text});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 20,
            height: 20,
            margin: const EdgeInsets.only(top: 1),
            decoration: BoxDecoration(
              color: scheme.primary,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              '$index',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: scheme.onPrimary,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 13.5, height: 1.65),
            ),
          ),
        ],
      ),
    );
  }
}

/// 相关函数/符号的名字片，点击跳转。
class _RelatedChips extends StatelessWidget {
  final List<String> ids;
  final void Function(String id) onTap;

  const _RelatedChips({required this.ids, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: <Widget>[
          for (final id in ids)
            ActionChip(
              label: Text(
                id,
                style: TextStyle(
                  fontFamilyFallback: AppFonts.mono,
                  fontSize: 12,
                ),
              ),
              onPressed: () => onTap(id),
            ),
        ],
      ),
    );
  }
}
