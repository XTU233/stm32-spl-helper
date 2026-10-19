import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/compile_error.dart';
import '../providers/app_providers.dart';
import '../utils/highlighter.dart';
import 'compile_error_detail_page.dart';

/// 编译错误速查。
///
/// 需求 5.7：分类展示，每条含错误原文、中文解释、原因、解决步骤、相关代码。
///
/// 本页提供三层收敛（15 条错误虽然不多，但排查时是按"现象"找的）：
///   - **分类筛选**：编译 / 链接 / 下载 / 运行时
///   - **工具链筛选**：Keil / GCC ARM / ST-Link / 通用
///   - **关键词搜索**：直接匹配报错原文，如 `L6218E`、`cannot open`
///
/// 搜索框与全局搜索是两回事：这里只在这 15 条里找，
/// 用户贴一段编译输出进来就能命中对应条目。
class CompileErrorsPage extends ConsumerStatefulWidget {
  const CompileErrorsPage({super.key});

  @override
  ConsumerState<CompileErrorsPage> createState() => _CompileErrorsPageState();
}

class _CompileErrorsPageState extends ConsumerState<CompileErrorsPage> {
  final TextEditingController _query = TextEditingController();

  /// 选中的分类；null 表示全部
  String? _categoryId;

  /// 选中的工具链；null 表示全部
  String? _toolchain;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dataAsync = ref.watch(splDataProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('编译错误速查')),
      body: dataAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败：$e')),
        data: (data) {
          final bundle = data.compileErrors;
          if (bundle.errors.isEmpty) {
            return const Center(child: Text('编译错误数据缺失'));
          }

          final keyword = _query.text.trim();

          // 三层过滤依次收紧
          var visible = bundle.errors.where((e) {
            if (_categoryId != null && e.categoryId != _categoryId) {
              return false;
            }
            if (_toolchain != null && e.toolchain != _toolchain) {
              return false;
            }
            if (keyword.isNotEmpty) {
              if (!_matches(e, keyword)) return false;
            }
            return true;
          }).toList();

          // 分类筛选计数：按当前工具链与关键词算，这样角标随上下文变化
          final base = bundle.errors.where((e) {
            if (_toolchain != null && e.toolchain != _toolchain) return false;
            if (keyword.isNotEmpty && !_matches(e, keyword)) return false;
            return true;
          }).toList();
          final countByCategory = <String, int>{};
          for (final e in base) {
            countByCategory[e.categoryId] =
                (countByCategory[e.categoryId] ?? 0) + 1;
          }

          final toolchains =
              bundle.errors.map((e) => e.toolchain).toSet().toList()..sort();

          final grouped = <String, List<CompileError>>{};
          for (final e in visible) {
            grouped.putIfAbsent(e.categoryId, () => <CompileError>[]).add(e);
          }

          return Column(
            children: <Widget>[
              // ---- 关键词搜索 ----
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                child: TextField(
                  controller: _query,
                  onChanged: (_) => setState(() {}),
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: '粘贴报错原文，如 L6218E、undefined reference、cannot open',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: keyword.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear, size: 19),
                            onPressed: () {
                              _query.clear();
                              setState(() {});
                            },
                          ),
                  ),
                ),
              ),

              // ---- 分类筛选 ----
              SizedBox(
                height: 38,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: <Widget>[
                    _FilterChip(
                      label: '全部',
                      count: base.length,
                      selected: _categoryId == null,
                      onTap: () => setState(() => _categoryId = null),
                    ),
                    for (final c in bundle.categories)
                      if ((countByCategory[c.id] ?? 0) > 0)
                        _FilterChip(
                          label: c.nameZh,
                          count: countByCategory[c.id]!,
                          selected: _categoryId == c.id,
                          onTap: () => setState(
                            () => _categoryId =
                                _categoryId == c.id ? null : c.id,
                          ),
                        ),
                  ],
                ),
              ),

              // ---- 工具链筛选 ----
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 2, 12, 4),
                child: Row(
                  children: <Widget>[
                    Text(
                      '工具链',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SizedBox(
                        height: 30,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: <Widget>[
                            for (final t in toolchains)
                              Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: ChoiceChip(
                                  label: Text(
                                    _toolchainLabel(t),
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                  selected: _toolchain == t,
                                  visualDensity: VisualDensity.compact,
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  onSelected: (_) => setState(
                                    () => _toolchain =
                                        _toolchain == t ? null : t,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              Padding(
                padding: const EdgeInsets.fromLTRB(16, 2, 16, 4),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        visible.length == bundle.errors.length
                            ? '共 ${bundle.errors.length} 条 · '
                                '${bundle.categories.length} 个分类'
                            : '筛出 ${visible.length} / ${bundle.errors.length} 条',
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    if (visible.length != bundle.errors.length)
                      TextButton(
                        onPressed: () => setState(() {
                          _categoryId = null;
                          _toolchain = null;
                          _query.clear();
                        }),
                        child: const Text(
                          '重置筛选',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                  ],
                ),
              ),

              // ---- 列表 ----
              Expanded(
                child: visible.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(28),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Icon(Icons.search_off,
                                  size: 38, color: scheme.outline),
                              const SizedBox(height: 12),
                              Text(
                                keyword.isEmpty
                                    ? '当前筛选下没有条目'
                                    : '没有匹配「$keyword」的错误条目',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView(
                        children: <Widget>[
                          for (final cat in bundle.categories)
                            if (grouped.containsKey(cat.id)) ...<Widget>[
                              Container(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 12, 16, 6),
                                color: scheme.surfaceContainerHighest
                                    .withValues(alpha: 0.35),
                                child: Text(
                                  '${cat.nameZh}'
                                  '（${grouped[cat.id]!.length}）',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                    color: scheme.primary,
                                  ),
                                ),
                              ),
                              for (final e in grouped[cat.id]!)
                                _ErrorTile(error: e, keyword: keyword),
                            ],
                          const SizedBox(height: 24),
                        ],
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// 关键词是否命中该条目。
  ///
  /// 匹配范围刻意覆盖**报错原文**（messageSample + messagePatterns）与
  /// 中文解释，因为用户多半是直接粘贴一段编译器输出过来。
  static bool _matches(CompileError e, String keyword) {
    final k = keyword.toLowerCase();
    if (e.messageSample.toLowerCase().contains(k)) return true;
    if (e.messagePatterns.any((p) => p.toLowerCase().contains(k))) return true;
    if (e.titleZh.toLowerCase().contains(k)) return true;
    if (e.explainZh.toLowerCase().contains(k)) return true;
    if (e.tags.any((t) => t.toLowerCase().contains(k))) return true;
    return false;
  }

  static String _toolchainLabel(String raw) {
    switch (raw) {
      case 'keil':
        return 'Keil MDK';
      case 'gcc-arm':
        return 'GCC ARM';
      case 'st-link':
        return 'ST-Link';
      case 'generic':
        return '通用';
      default:
        return raw;
    }
  }
}

/// 错误条目。
class _ErrorTile extends StatelessWidget {
  final CompileError error;
  final String keyword;

  const _ErrorTile({required this.error, required this.keyword});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      dense: true,
      title: HighlightedText(
        error.titleZh,
        keyword,
        maxLines: 2,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          height: 1.35,
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          HighlightedText(
            error.explainZh,
            keyword,
            maxLines: 2,
            withBackground: false,
            style: const TextStyle(fontSize: 12, height: 1.45),
          ),
          // 报错原文片段能命中时也展示出来，让用户确认"就是这条"
          if (keyword.isNotEmpty && _sampleHit)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                _hitLine!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamilyFallback: const <String>[
                    'Roboto Mono',
                    'monospace',
                  ],
                  fontSize: 11,
                  color: scheme.primary,
                ),
              ),
            ),
        ],
      ),
      trailing: Text(
        error.toolchainZh,
        style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant),
      ),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => CompileErrorDetailPage(errorId: error.id),
        ),
      ),
    );
  }

  /// 命中的报错原文行（用于在列表里直接展示证据）。
  String? get _hitLine {
    if (keyword.isEmpty) return null;
    final k = keyword.toLowerCase();
    for (final line in error.messageSample.split('\n')) {
      if (line.toLowerCase().contains(k)) return line.trim();
    }
    for (final p in error.messagePatterns) {
      if (p.toLowerCase().contains(k)) return p;
    }
    return null;
  }

  bool get _sampleHit => _hitLine != null;
}

/// 筛选片。
class _FilterChip extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: FilterChip(
        selected: selected,
        onSelected: (_) => onTap(),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        label: Text('$label $count', style: const TextStyle(fontSize: 11.5)),
      ),
    );
  }
}
