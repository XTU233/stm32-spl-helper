import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/function_item.dart';
import '../models/item_ref.dart';
import '../models/peripheral.dart';
import '../providers/app_providers.dart';
import '../utils/theme.dart';
import '../widgets/item_actions.dart';
import '../widgets/recent_view_recorder.dart';
import 'function_detail_page.dart';

/// 外设详情页：函数列表（按分节分组，可折叠）。
///
/// 需求 5.2：
///   - 顶部：外设名称 + 简介 + 使用总览
///   - 主体：全部库函数，按 section 分组，分组可折叠
///   - 每一项：函数名（等宽）+ 中文简述 + 返回值
///
/// 阶段 10 改版要点：
///   - AppBar 标题随滚动收起为"外设名"，避免长标题在窄屏上被截断
///   - 头部信息改为分区卡片（简介 / 使用总览分色），层次更清楚
///   - 分节头部加左侧色块 + 折叠动画，展开/收起有过渡而不是硬切
///   - 函数条目加悬停/按压底色，行高放宽，读起来不挤
class PeripheralDetailPage extends ConsumerStatefulWidget {
  final String peripheralId;

  const PeripheralDetailPage({super.key, required this.peripheralId});

  @override
  ConsumerState<PeripheralDetailPage> createState() =>
      _PeripheralDetailPageState();
}

class _PeripheralDetailPageState extends ConsumerState<PeripheralDetailPage> {
  /// 折叠状态：section id → 是否展开。默认全展开。
  final Set<String> _collapsed = <String>{};

  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dataAsync = ref.watch(splDataProvider);

    return dataAsync.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(title: Text(widget.peripheralId)),
        body: Center(child: Text('加载失败：$e')),
      ),
      data: (data) {
        final peripheral = data.peripheral(widget.peripheralId);
        if (peripheral == null) {
          return Scaffold(
            appBar: AppBar(title: Text(widget.peripheralId)),
            body: const Center(child: Text('找不到该外设')),
          );
        }

        // 外设数据已就绪，记一次「最近查看」。
        // 放在 when 的 data 分支里而不是 initState，是为了避免
        // "外设 id 不存在"时也留下一条点不开的记录。
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            recordRecentView(
              ref,
              ItemRef(
                type: ItemType.peripheral,
                id: peripheral.id,
                title: peripheral.name,
                subtitle: peripheral.nameZh,
              ),
            );
          }
        });

        return Scaffold(
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  peripheral.name,
                  style: AppFonts.monoStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  peripheral.nameZh,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w400,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            actions: <Widget>[
              ItemActions(
                item: ItemRef(
                  type: ItemType.peripheral,
                  id: peripheral.id,
                  title: peripheral.name,
                  subtitle: peripheral.nameZh,
                ),
              ),
            ],
          ),
          // 函数详情按需加载：进页面时才读该外设的 JSON
          body: _FunctionListBody(
            peripheral: peripheral,
            collapsed: _collapsed,
            scroll: _scroll,
            onToggleSection: (id) => setState(() {
              if (_collapsed.contains(id)) {
                _collapsed.remove(id);
              } else {
                _collapsed.add(id);
              }
            }),
          ),
        );
      },
    );
  }
}

/// 函数列表主体：负责按需加载函数数据。
class _FunctionListBody extends ConsumerStatefulWidget {
  final Peripheral peripheral;
  final Set<String> collapsed;
  final ScrollController scroll;
  final ValueChanged<String> onToggleSection;

  const _FunctionListBody({
    required this.peripheral,
    required this.collapsed,
    required this.scroll,
    required this.onToggleSection,
  });

  @override
  ConsumerState<_FunctionListBody> createState() => _FunctionListBodyState();
}

class _FunctionListBodyState extends ConsumerState<_FunctionListBody> {
  late Future<FunctionBundle> _future;

  /// 函数过滤关键词（按函数名或中文简述匹配）
  final TextEditingController _filter = TextEditingController();

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  Future<FunctionBundle> _load() {
    return ref
        .read(assetRepositoryProvider)
        .loadFunctions(widget.peripheral.id);
  }

  /// 过滤后的区块列表。关键词为空时原样返回。
  ///
  /// 匹配范围是函数名 + 中文简述 + 英文简述：用户可能记不住全名，
  /// 只记得"那个读引脚的"或"ITConfig"，两种都能命中。
  List<PeripheralSection> _filterSections(
    String keyword,
    Map<String, FunctionItem> byId,
  ) {
    final k = keyword.trim().toLowerCase();
    if (k.isEmpty) return widget.peripheral.sections;

    final result = <PeripheralSection>[];
    for (final sec in widget.peripheral.sections) {
      final kept = <String>[];
      for (final id in sec.functionIds) {
        final f = byId[id];
        if (f == null) continue;
        final hit = f.name.toLowerCase().contains(k) ||
            f.briefZh.toLowerCase().contains(k) ||
            f.briefEn.toLowerCase().contains(k);
        if (hit) kept.add(id);
      }
      if (kept.isEmpty) continue;
      // 复制一份只保留命中的函数 id，区块标题与数量随之变化
      result.add(PeripheralSection(
        id: sec.id,
        title: sec.title,
        titleEn: sec.titleEn,
        functionIds: kept,
      ));
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<FunctionBundle>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          final scheme = Theme.of(context).colorScheme;
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpace.xxl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(Icons.error_outline, size: 40, color: scheme.error),
                  const SizedBox(height: AppSpace.md),
                  Text(
                    '函数数据加载失败\n${snapshot.error}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12.5, height: 1.5),
                  ),
                  const SizedBox(height: AppSpace.lg),
                  FilledButton(
                    onPressed: () => setState(() => _future = _load()),
                    child: const Text('重试'),
                  ),
                ],
              ),
            ),
          );
        }

        final bundle = snapshot.data!;
        final byId = <String, FunctionItem>{
          for (final f in bundle.functions) f.id: f,
        };

        final keyword = _filter.text;
        final sections = _filterSections(keyword, byId);
        final hitCount = sections.fold<int>(
          0,
          (a, s) => a + s.functionIds.length,
        );

        return Column(
          children: <Widget>[
            _FunctionFilterBar(
              controller: _filter,
              total: widget.peripheral.functionCount,
              hit: hitCount,
              filtering: keyword.trim().isNotEmpty,
              onChanged: (_) => setState(() {}),
              onClear: () {
                _filter.clear();
                setState(() {});
              },
            ),
            Expanded(
              child: ListView(
                controller: widget.scroll,
                padding: const EdgeInsets.only(bottom: AppSpace.xxl),
                children: <Widget>[
                  _PeripheralHeader(peripheral: widget.peripheral),
                  if (sections.isEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpace.lg,
                        AppSpace.xxl,
                        AppSpace.lg,
                        AppSpace.xxl,
                      ),
                      child: Center(
                        child: Text(
                          '没有匹配「${keyword.trim()}」的函数',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  for (final section in sections)
                    _SectionBlock(
                      section: section,
                      byId: byId,
                      // 过滤时强制展开：用户搜了东西却看到折叠的分组会很困惑
                      collapsed: keyword.trim().isEmpty &&
                          widget.collapsed.contains(section.id),
                      onToggle: () => widget.onToggleSection(section.id),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 函数过滤条。
class _FunctionFilterBar extends StatelessWidget {
  final TextEditingController controller;
  final int total;
  final int hit;
  final bool filtering;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  const _FunctionFilterBar({
    required this.controller,
    required this.total,
    required this.hit,
    required this.filtering,
    required this.onChanged,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.md,
        AppSpace.sm,
        AppSpace.md,
        AppSpace.sm,
      ),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: scheme.outlineVariant, width: 1),
        ),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: SizedBox(
              height: 38,
              child: TextField(
                controller: controller,
                onChanged: onChanged,
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpace.md,
                    vertical: 8,
                  ),
                  hintText: '在本外设内搜索函数名或说明…',
                  prefixIcon: const Icon(Icons.filter_list, size: 18),
                  prefixIconConstraints: const BoxConstraints(
                    minWidth: 38,
                    minHeight: 38,
                  ),
                  suffixIcon: filtering
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 17),
                          visualDensity: VisualDensity.compact,
                          onPressed: onClear,
                        )
                      : null,
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpace.sm),
          // 计数让用户知道过滤掉了多少
          Text(
            filtering ? '$hit/$total' : '$total',
            style: AppFonts.monoStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: filtering ? scheme.primary : scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// 外设头部：简介 + 使用总览。
class _PeripheralHeader extends StatelessWidget {
  final Peripheral peripheral;

  const _PeripheralHeader({required this.peripheral});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // ---- 简介卡 ----
        Container(
          margin: const EdgeInsets.fromLTRB(
            AppSpace.md,
            AppSpace.md,
            AppSpace.md,
            AppSpace.sm,
          ),
          padding: const EdgeInsets.all(AppSpace.lg),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1C1F24) : Colors.white,
            borderRadius: AppRadius.card,
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // 头文件与函数数做成一行元信息
              Row(
                children: <Widget>[
                  Icon(Icons.description_outlined,
                      size: 13, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      peripheral.header,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppFonts.monoStyle(
                        fontSize: 11,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpace.sm),
                  _CountPill(
                    text: '${peripheral.functionCount} 个函数',
                    color: scheme.primary,
                  ),
                ],
              ),
              if (peripheral.introZh.isNotEmpty) ...<Widget>[
                const SizedBox(height: AppSpace.md),
                Text(
                  peripheral.introZh,
                  style: const TextStyle(fontSize: 13, height: 1.65),
                ),
              ],
            ],
          ),
        ),

        // ---- 使用总览（左侧竖线与简介卡区分） ----
        if (peripheral.usageOverviewZh.isNotEmpty)
          Container(
            margin: const EdgeInsets.fromLTRB(
              AppSpace.md,
              AppSpace.xs,
              AppSpace.md,
              AppSpace.sm,
            ),
            padding: const EdgeInsets.fromLTRB(
              AppSpace.md,
              AppSpace.md,
              AppSpace.md,
              AppSpace.md,
            ),
            decoration: BoxDecoration(
              color: scheme.tertiaryContainer.withValues(
                alpha: isDark ? 0.16 : 0.3,
              ),
              borderRadius: AppRadius.card,
              border: Border(
                left: BorderSide(color: scheme.tertiary, width: 3),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(Icons.route_outlined, size: 14, color: scheme.tertiary),
                    const SizedBox(width: 6),
                    Text(
                      '使用总览',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: scheme.tertiary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpace.sm),
                Text(
                  peripheral.usageOverviewZh,
                  style: const TextStyle(fontSize: 13, height: 1.7),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// 计数小胶囊。
class _CountPill extends StatelessWidget {
  final String text;
  final Color color;

  const _CountPill({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

/// 一个函数分组（可折叠）。
class _SectionBlock extends StatelessWidget {
  final PeripheralSection section;
  final Map<String, FunctionItem> byId;
  final bool collapsed;
  final VoidCallback onToggle;

  const _SectionBlock({
    required this.section,
    required this.byId,
    required this.collapsed,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // 按 section.functionIds 的顺序取函数，保证与头文件顺序一致
    final items = section.functionIds
        .map((id) => byId[id])
        .whereType<FunctionItem>()
        .toList(growable: false);

    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppSpace.md,
        AppSpace.sm,
        AppSpace.md,
        0,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: AppRadius.card,
        border: Border.all(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // ---- 分节头 ----
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onToggle,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpace.md,
                  AppSpace.md,
                  AppSpace.md,
                  AppSpace.md,
                ),
                child: Row(
                  children: <Widget>[
                    // 左侧色块代替图标，扫列表时靠位置与颜色定位
                    Container(
                      width: 3,
                      height: 26,
                      margin: const EdgeInsets.only(right: AppSpace.md),
                      decoration: BoxDecoration(
                        color: scheme.primary.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            section.title,
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (section.titleEn != null &&
                              section.titleEn!.isNotEmpty) ...<Widget>[
                            const SizedBox(height: 1),
                            Text(
                              section.titleEn!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 10,
                                fontStyle: FontStyle.italic,
                                color: scheme.onSurfaceVariant.withValues(
                                  alpha: 0.85,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpace.sm),
                    Text(
                      '${items.length}',
                      style: AppFonts.monoStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 2),
                    // 折叠箭头带旋转动画
                    AnimatedRotation(
                      turns: collapsed ? 0 : 0.25,
                      duration: AppDuration.fast,
                      child: Icon(
                        Icons.chevron_right,
                        size: 19,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // ---- 函数条目（展开时有过渡） ----
          AnimatedSize(
            duration: AppDuration.normal,
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: collapsed
                ? const SizedBox(width: double.infinity)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Divider(height: 1, color: scheme.outlineVariant),
                      for (var i = 0; i < items.length; i++) ...<Widget>[
                        _FunctionTile(item: items[i]),
                        if (i != items.length - 1)
                          Divider(
                            height: 1,
                            indent: 30,
                            endIndent: AppSpace.md,
                            color: scheme.outlineVariant.withValues(
                              alpha: 0.6,
                            ),
                          ),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// 单个函数条目：函数名（等宽）+ 中文简述 + 返回值。
class _FunctionTile extends StatelessWidget {
  final FunctionItem item;

  const _FunctionTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => FunctionDetailPage(functionId: item.name),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.lg,
            AppSpace.md,
            AppSpace.md,
            AppSpace.md,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // 函数名与返回值并排。
              //
              // 两侧都必须有约束：早先返回值是无约束的 Text 且内容为中文长句
              // （最长 40 字），会把函数名挤到只剩一两个字符宽，表现为
              // "函数名竖向显示"。现在返回值用 Flexible 限宽，函数名用
              // Expanded 占剩余空间，两者都不换行、溢出省略。
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: Text(
                      item.name,
                      // 函数名是英文标识符，禁止换行（换行看起来像竖排）
                      softWrap: false,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppFonts.monoStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: scheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpace.sm),
                  Flexible(
                    child: Text(
                      item.displayReturn,
                      textAlign: TextAlign.right,
                      softWrap: false,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppFonts.monoStyle(
                        fontSize: 10.5,
                        color: scheme.onSurfaceVariant.withValues(alpha: 0.9),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                item.displayBrief,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
