import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/function_item.dart';
import '../models/item_ref.dart';
import '../models/peripheral.dart';
import '../models/spl_data.dart';
import '../providers/app_providers.dart';
import '../utils/theme.dart';
import '../widgets/code_block.dart';
import '../widgets/item_actions.dart';
import '../widgets/keyword_text.dart';
import '../widgets/recent_view_recorder.dart';
import '../widgets/section_header.dart';
import '../widgets/section_nav.dart';

/// 函数详情页（需求 5.3，本项目的核心页面）。
///
/// 从上到下的区块：
///   1. 函数名 + 所属外设 + 收藏 + 复制
///   2. 函数原型（可横向滚动、可复制、符号可点击）
///   3. 参数表（参数类型里的枚举/结构体名可点击）
///   4. 返回值说明
///   5. 中文使用说明
///   6. 前置条件清单
///   7. 涉及的寄存器（可展开位域说明）
///   8. 最小示例代码（高亮 + 可复制 + 符号可点击）
///   9. 注意事项 / 常见坑
///  10. 相关函数（可点击跳转）
class FunctionDetailPage extends ConsumerStatefulWidget {
  final String functionId;

  const FunctionDetailPage({super.key, required this.functionId});

  @override
  ConsumerState<FunctionDetailPage> createState() => _FunctionDetailPageState();
}

class _FunctionDetailPageState extends ConsumerState<FunctionDetailPage> {
  /// 按需加载的函数对象
  FunctionItem? _item;

  /// 加载状态
  bool _loading = true;
  Object? _error;

  /// 内容区滚动控制器（用于目录条高亮）
  final ScrollController _scroll = ScrollController();

  /// 当前高亮的区块下标（对应 [_currentAnchors] 里的位置）
  int? _activeSection;

  /// 本次渲染实际存在的锚点（区块内容为空时该区块不进目录）
  List<SectionAnchor> _currentAnchors = const <SectionAnchor>[];

  /// 区块锚点的 GlobalKey。
  ///
  /// 在 initState 里建好、整个页面生命周期内保持同一批实例：
  /// 如果每次 build 都新建 GlobalKey，ensureVisible 会拿到已失效的 context。
  /// 这里用固定的一组 key（覆盖所有可能出现的区块），
  /// 区块不存在时那个 key 的 currentContext 就是 null，跳转时自然被忽略。
  final Map<String, GlobalKey> _sectionKeys = <String, GlobalKey>{
    for (final id in _sectionOrder) id: GlobalKey(),
  };

  /// 区块的展示顺序（决定目录条里的顺序）。
  ///
  /// 顺序按"读函数时的关注顺序"排：先看原型和参数，
  /// 再看怎么用、要注意什么，最后才是来源与相关函数。
  static const List<String> _sectionOrder = <String>[
    'prototype',
    'params',
    'returns',
    'usage',
    'prerequisites',
    'registers',
    'example',
    'notes',
    'related',
  ];

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  /// 按滚动位置更新目录条高亮。
  ///
  /// 判定规则：取"顶端已经越过参考线（内容区顶部 + 一个行高）
  /// 的最后一个区块"。用参考线而不是严格 equality，
  /// 是为了让高亮在区块刚进入视野时就切换，而不是等到完全对齐。
  ///
  /// 这里只读已布局区块的偏移，不做任何布局计算，
  /// 所以在滚动回调里调用开销很小（9 个区块最多 9 次查找）。
  void _onScroll() {
    if (_currentAnchors.isEmpty) return;
    final reference = _scroll.hasClients ? _scroll.offset + 80 : 0.0;

    int? best;
    for (var i = 0; i < _currentAnchors.length; i++) {
      final offset = _currentAnchors[i].offsetInViewport();
      if (offset == null) continue;
      if (offset <= reference) best = i;
    }
    // 还没滚过第一个区块时，高亮第一项
    best ??= 0;
    if (best != _activeSection && mounted) {
      setState(() => _activeSection = best);
    }
  }

  /// 首帧布局后算一次高亮。
  ///
  /// 不这么做的话，进页面时控件都还没布局，_onScroll 里所有
  /// offsetInViewport() 都返回 null，activeIndex 就停在 null，
  /// 目录条一个都不亮——用户得先滚一下才看到高亮。
  void _syncActiveAfterLayout() {
    if (!mounted || _currentAnchors.isEmpty) return;
    // 等这一帧布局完成再读偏移
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _onScroll();
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await ref.read(splDataProvider.future);
      final peripheral = _peripheralOf(data);
      if (peripheral == null) {
        throw StateError('找不到函数 ${widget.functionId} 所属的外设');
      }
      final bundle = await ref
          .read(assetRepositoryProvider)
          .loadFunctions(peripheral.id);
      final item = bundle.functions
          .where((f) => f.id == widget.functionId)
          .firstOrNull;
      if (item == null) {
        throw StateError('外设 ${peripheral.id} 里找不到函数 ${widget.functionId}');
      }
      if (!mounted) return;
      setState(() {
        _item = item;
        _loading = false;
      });
      // 数据加载成功后才记「最近查看」（加载失败的页不留记录）
      recordRecentView(
        ref,
        ItemRef(
          type: ItemType.function,
          id: item.id,
          title: item.name,
          subtitle: peripheral.nameZh.isEmpty
              ? peripheral.id
              : peripheral.nameZh,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  /// 从核心数据里找出该函数所属的外设。
  ///
  /// 函数详情是按需加载的，所以靠 peripherals.json 的 functionIds 定位外设。
  /// 用 SplData.peripheralIdOfFunction 而不是自己遍历，保证与跳转判断
  /// 用同一份数据源（早先两边不一致，导致跳转报"未收录符号"）。
  Peripheral? _peripheralOf(SplData data) {
    final pid = data.peripheralIdOfFunction(widget.functionId);
    return pid == null ? null : data.peripheral(pid);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.functionId)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null || _item == null) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.functionId)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(Icons.error_outline, size: 40, color: scheme.error),
                const SizedBox(height: 12),
                Text('${_error ?? '加载失败'}', textAlign: TextAlign.center),
                const SizedBox(height: 14),
                FilledButton(onPressed: _load, child: const Text('重试')),
              ],
            ),
          ),
        ),
      );
    }

    final item = _item!;
    final data = ref.watch(splDataProvider).valueOrNull;
    final peripheral = data?.peripheral(item.peripheral);

    // 白名单：只把该函数真正涉及的符号变成链接，避免满屏蓝色
    final whitelist = <String>{...item.symbolRefs};

    // 组装本次实际存在的区块锚点（内容为空的区块不进目录）
    final anchors = <SectionAnchor>[
      SectionAnchor(
        title: '原型',
        icon: Icons.data_object,
        key: _sectionKeys['prototype']!,
      ),
      if (item.params.isNotEmpty)
        SectionAnchor(
          title: '参数',
          icon: Icons.list_alt,
          key: _sectionKeys['params']!,
        ),
      SectionAnchor(
        title: '返回值',
        icon: Icons.keyboard_return,
        key: _sectionKeys['returns']!,
      ),
      if (item.usageZh.isNotEmpty)
        SectionAnchor(
          title: '说明',
          icon: Icons.lightbulb_outline,
          key: _sectionKeys['usage']!,
        ),
      if (item.prerequisites.isNotEmpty)
        SectionAnchor(
          title: '前置',
          icon: Icons.checklist,
          key: _sectionKeys['prerequisites']!,
        ),
      if (item.registers.isNotEmpty)
        SectionAnchor(
          title: '寄存器',
          icon: Icons.memory,
          key: _sectionKeys['registers']!,
        ),
      if (item.exampleCode.isNotEmpty)
        SectionAnchor(
          title: '示例',
          icon: Icons.terminal,
          key: _sectionKeys['example']!,
        ),
      if (item.notesZh.isNotEmpty || item.remarks.isNotEmpty)
        SectionAnchor(
          title: '注意',
          icon: Icons.warning_amber_rounded,
          key: _sectionKeys['notes']!,
        ),
      if (item.relatedFunctions.isNotEmpty)
        SectionAnchor(
          title: '相关',
          icon: Icons.hub_outlined,
          key: _sectionKeys['related']!,
        ),
    ];

    // 存下来供滚动回调使用（回调不在 build 里，拿不到局部变量）
    _currentAnchors = anchors;
    // 首帧布局后补算一次高亮，否则进页面时目录条一个都不亮
    _syncActiveAfterLayout();

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              item.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppFonts.monoStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (peripheral != null)
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
          IconButton(
            icon: const Icon(Icons.copy_all),
            tooltip: '复制函数名',
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: item.name));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('已复制 ${item.name}')),
                );
              }
            },
          ),
          ItemActions(
            item: ItemRef(
              type: ItemType.function,
              id: item.id,
              title: item.name,
              subtitle: peripheral?.nameZh ?? item.peripheral,
            ),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          // 粘性目录条：10 个区块的长页面靠它快速定位。
          // activeIndex 跟着滚动位置走，用户随时知道自己在哪一块。
          SectionNavBar(anchors: anchors, activeIndex: _activeSection),
          Expanded(
            child: ListView(
              controller: _scroll,
              padding: const EdgeInsets.only(bottom: AppSpace.huge),
              children: <Widget>[
                // ---- 1. 定位信息 ----
                _LocationBar(item: item, header: peripheral?.header ?? ''),

                // ---- 2. 函数原型 ----
                SectionHeader(
                  key: _sectionKeys['prototype'],
                  icon: Icons.data_object,
                  title: '函数原型',
                  subtitle: '点击其中的类型名可跳转',
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
                  child: CodeBlock(
                    code: item.prototype,
                    title: '函数原型',
                    horizontalScroll: true,
                    whitelist: whitelist,
                  ),
                ),

                // ---- 3. 参数表 ----
                if (item.params.isNotEmpty) ...<Widget>[
                  SectionHeader(
                    key: _sectionKeys['params'],
                    icon: Icons.list_alt,
                    title: '参数',
                    subtitle: '${item.params.length} 个参数',
                  ),
                  for (final p in item.params)
                    _ParamTile(param: p, whitelist: whitelist),
                ] else ...<Widget>[
                  SectionHeader(
                    key: _sectionKeys['params'],
                    icon: Icons.list_alt,
                    title: '参数',
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpace.lg,
                    ),
                    child: Text(
                      '该函数没有参数。',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],

                // ---- 4. 返回值 ----
                SectionHeader(
                  key: _sectionKeys['returns'],
                  icon: Icons.keyboard_return,
                  title: '返回值',
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      KeywordText(
                        item.displayReturn,
                        whitelist: whitelist,
                        style: const TextStyle(fontSize: 13, height: 1.65),
                      ),
                      if (item.returnDescEn.isNotEmpty &&
                          item.returnDescZh.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: AppSpace.xs),
                          child: Text(
                            'ST 原文：${item.returnDescEn}',
                            style: TextStyle(
                              fontSize: 11,
                              height: 1.45,
                              fontStyle: FontStyle.italic,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),

                // ---- 5. 中文使用说明 ----
                if (item.usageZh.isNotEmpty) ...<Widget>[
                  SectionHeader(
                    key: _sectionKeys['usage'],
                    icon: Icons.lightbulb_outline,
                    title: '使用说明',
                    subtitle: '什么时候调用、调用顺序、容易踩的坑',
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpace.lg,
                    ),
                    child: KeywordText(
                      item.usageZh,
                      whitelist: whitelist,
                      style: const TextStyle(fontSize: 13, height: 1.75),
                    ),
                  ),
                ],

                // ---- 6. 前置条件 ----
                if (item.prerequisites.isNotEmpty) ...<Widget>[
                  SectionHeader(
                    key: _sectionKeys['prerequisites'],
                    icon: Icons.checklist,
                    title: '前置条件',
                    subtitle: '调用前必须满足',
                  ),
                  for (final pre in item.prerequisites)
                    _BulletLine(
                      text: pre,
                      whitelist: whitelist,
                      icon: Icons.check_circle_outline,
                      color: const Color(0xFF3E9C5A),
                    ),
                ],

                // ---- 7. 涉及的寄存器 ----
                if (item.registers.isNotEmpty) ...<Widget>[
                  SectionHeader(
                    key: _sectionKeys['registers'],
                    icon: Icons.memory,
                    title: '涉及的寄存器',
                    subtitle: '点击展开位域说明',
                  ),
                  for (final reg in item.registers)
                    _RegisterTile(
                      register: reg,
                      peripheralId: item.peripheral,
                    ),
                ],

                // ---- 8. 最小示例代码 ----
                if (item.exampleCode.isNotEmpty) ...<Widget>[
                  SectionHeader(
                    key: _sectionKeys['example'],
                    icon: Icons.terminal,
                    title: '最小示例',
                    subtitle: '可直接复制使用',
                  ),
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: AppSpace.md),
                    child: CodeBlock(
                      code: item.exampleCode,
                      title: '示例代码',
                      whitelist: whitelist,
                    ),
                  ),
                ],

                // ---- 9. 注意事项 / 常见坑 ----
                if (item.notesZh.isNotEmpty || item.remarks.isNotEmpty)
                  ...<Widget>[
                    SectionHeader(
                      key: _sectionKeys['notes'],
                      icon: Icons.warning_amber_rounded,
                      title: '注意事项',
                      color: scheme.error,
                    ),
                    for (final n in item.notesZh)
                      _BulletLine(
                        text: n,
                        whitelist: whitelist,
                        icon: Icons.report_problem_outlined,
                        color: scheme.error,
                      ),
                    for (final r in item.remarks)
                      _BulletLine(
                        text: r,
                        whitelist: whitelist,
                        icon: Icons.info_outline,
                      ),
                  ],

                // ---- 10. 相关函数 ----
                if (item.relatedFunctions.isNotEmpty) ...<Widget>[
                  SectionHeader(
                    key: _sectionKeys['related'],
                    icon: Icons.hub_outlined,
                    title: '相关函数',
                    subtitle: '点击跳转',
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpace.lg,
                    ),
                    child: Wrap(
                      spacing: AppSpace.sm,
                      runSpacing: AppSpace.sm,
                      children: <Widget>[
                        for (final id in item.relatedFunctions)
                          ActionChip(
                            avatar: const Icon(Icons.functions, size: 14),
                            label: Text(
                              id,
                              style: AppFonts.monoStyle(fontSize: 11.5),
                            ),
                            onPressed: () => openSymbol(context, ref, id),
                          ),
                      ],
                    ),
                  ),
                ],

                // ---- 底部：ST 英文原文（折叠） ----
                if (item.briefEn.isNotEmpty) _EnglishOriginal(item: item),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 定位信息条：文件名:行号。
class _LocationBar extends StatelessWidget {
  final FunctionItem item;
  final String header;

  const _LocationBar({required this.item, required this.header});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final parts = <String>[];
    if (header.isNotEmpty && item.headerLine > 0) {
      parts.add('$header:${item.headerLine}');
    }
    if (item.sourceLine > 0) {
      parts.add('实现位于第 ${item.sourceLine} 行');
    }
    if (parts.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: Row(
        children: <Widget>[
          Icon(Icons.description_outlined,
              size: 13, color: scheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              parts.join(' · '),
              style: TextStyle(
                fontSize: 11.5,
                fontFamilyFallback: AppFonts.mono,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 参数表的一行。
///
/// 参数类型里出现的枚举名/结构体名可点击跳转（需求 5.3）。
class _ParamTile extends ConsumerWidget {
  final FunctionParam param;
  final Set<String> whitelist;

  const _ParamTile({required this.param, required this.whitelist});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final hasZh = param.descZh.isNotEmpty;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // 参数名 + 类型（类型可点击）
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: <Widget>[
              Text(
                param.name,
                style: TextStyle(
                  fontFamilyFallback: AppFonts.mono,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: scheme.primary,
                ),
              ),
              // 类型：把其中的类型名渲染成可点击
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: scheme.tertiaryContainer.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: KeywordText(
                  param.type,
                  whitelist: whitelist,
                  style: TextStyle(
                    fontFamilyFallback: AppFonts.mono,
                    fontSize: 11.5,
                    color: scheme.onTertiaryContainer,
                  ),
                ),
              ),
            ],
          ),
          if (hasZh) ...<Widget>[
            const SizedBox(height: 7),
            KeywordText(
              param.descZh,
              whitelist: whitelist,
              style: const TextStyle(fontSize: 13, height: 1.6),
            ),
          ],
          if (param.descEn.isNotEmpty) ...<Widget>[
            const SizedBox(height: 5),
            Text(
              param.descEn,
              style: TextStyle(
                fontSize: 11.5,
                height: 1.5,
                fontStyle: FontStyle.italic,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 带图标的要点行。
class _BulletLine extends StatelessWidget {
  final String text;
  final Set<String> whitelist;
  final IconData icon;
  final Color? color;

  const _BulletLine({
    required this.text,
    required this.whitelist,
    required this.icon,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = color ?? scheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 5, 16, 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 15, color: c),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: KeywordText(
              text,
              whitelist: whitelist,
              style: const TextStyle(fontSize: 13, height: 1.6),
            ),
          ),
        ],
      ),
    );
  }
}

/// 寄存器条目：点击展开位域说明。
///
/// 数据来自 registers.json（2.7 MB，按需加载）。
/// 函数的 registers 字段用的是 `GPIOx_CRL` 这种占位式命名，
/// 而 registers.json 里是按 `GPIO_CRL` 分节的，所以要归一化后再匹配。
class _RegisterTile extends ConsumerStatefulWidget {
  final String register;
  final String peripheralId;

  const _RegisterTile({required this.register, required this.peripheralId});

  @override
  ConsumerState<_RegisterTile> createState() => _RegisterTileState();
}

class _RegisterTileState extends ConsumerState<_RegisterTile> {
  bool _expanded = false;

  /// 把 `GPIOx_CRL` / `TIMx_PSC` 归一化为 `GPIO_CRL` / `TIM_PSC`。
  ///
  /// 规则：去掉小写字母 x 占位符。`TIMx_CCMR1` → `TIM_CCMR1`。
  String get _normalized =>
      widget.register.replaceAll('x_', '_').replaceAll('x', '');

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
              child: Row(
                children: <Widget>[
                  Icon(Icons.memory, size: 15, color: scheme.tertiary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.register,
                      style: TextStyle(
                        fontFamilyFallback: AppFonts.mono,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: scheme.tertiary,
                      ),
                    ),
                  ),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 19,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) _RegisterBits(normalized: _normalized),
        ],
      ),
    );
  }
}

/// 寄存器位域说明（展开后显示）。
class _RegisterBits extends ConsumerWidget {
  final String normalized;

  const _RegisterBits({required this.normalized});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final async = ref.watch(registerSymbolsProvider);

    return async.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(12),
        child: Row(
          children: <Widget>[
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 10),
            Text('正在加载寄存器定义…', style: TextStyle(fontSize: 12)),
          ],
        ),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(12),
        child: Text('寄存器数据加载失败：$e',
            style: const TextStyle(fontSize: 12)),
      ),
      data: (symbols) {
        final bits = symbols
            .where((s) => s.registerName == normalized)
            .toList(growable: false);

        if (bits.isEmpty) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Text(
              '未收录 $normalized 的位域定义（可查阅参考手册）',
              style: TextStyle(
                fontSize: 11.5,
                color: scheme.onSurfaceVariant,
              ),
            ),
          );
        }

        return Container(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '$normalized 位域（${bits.length} 项）',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 6),
              for (final b in bits)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2.5),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      SizedBox(
                        width: 150,
                        child: Text(
                          b.name,
                          style: TextStyle(
                            fontFamilyFallback: AppFonts.mono,
                            fontSize: 11.5,
                            color: scheme.primary,
                          ),
                        ),
                      ),
                      if (b.value != null)
                        SizedBox(
                          width: 96,
                          child: Text(
                            b.value!,
                            style: TextStyle(
                              fontFamilyFallback: AppFonts.mono,
                              fontSize: 11,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      Expanded(
                        child: Text(
                          b.briefZh.isNotEmpty ? b.briefZh : b.briefEn,
                          style: const TextStyle(fontSize: 11.5, height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// ST 英文原文（默认折叠）。
class _EnglishOriginal extends StatefulWidget {
  final FunctionItem item;

  const _EnglishOriginal({required this.item});

  @override
  State<_EnglishOriginal> createState() => _EnglishOriginalState();
}

class _EnglishOriginalState extends State<_EnglishOriginal> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 18, 12, 0),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => setState(() => _open = !_open),
              child: Padding(
                padding: const EdgeInsets.all(11),
                child: Row(
                  children: <Widget>[
                    Icon(Icons.translate, size: 15, color: scheme.onSurfaceVariant),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'ST 原始注释（英文）',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Icon(_open ? Icons.expand_less : Icons.expand_more,
                        size: 19, color: scheme.onSurfaceVariant),
                  ],
                ),
              ),
            ),
            if (_open)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Text(
                  widget.item.briefEn,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.6,
                    fontStyle: FontStyle.italic,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
