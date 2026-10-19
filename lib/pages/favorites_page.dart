import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/user_database.dart';
import '../models/item_ref.dart';
import '../providers/user_providers.dart';
import '../utils/theme.dart';
import '../widgets/pressable_card.dart';
import 'compile_error_detail_page.dart';
import 'function_detail_page.dart';
import 'peripheral_detail_page.dart';
import 'pin_detail_sheet.dart';
import 'symbol_detail_page.dart';

/// 收藏页。
///
/// 需求 5.5：函数、符号、外设、引脚、编译错误条目都可收藏；
/// 支持按类型筛选、按外设分组。
///
/// 收藏的标题是**收藏当时的快照**（存在库里），所以列表渲染不依赖
/// assets 是否加载完成——即使数据还没读完也能显示列表。
class FavoritesPage extends ConsumerStatefulWidget {
  const FavoritesPage({super.key});

  @override
  ConsumerState<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends ConsumerState<FavoritesPage> {
  /// 当前筛选的类型；null 表示全部
  ItemType? _filter;

  /// 是否按外设分组
  bool _groupByPeripheral = false;

  @override
  Widget build(BuildContext context) {
    final favoritesAsync = ref.watch(favoritesProvider);

    return favoritesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('读取收藏失败：$e', textAlign: TextAlign.center),
        ),
      ),
      data: (all) {
        if (all.isEmpty) return const _EmptyFavorites();

        final visible =
            _filter == null ? all : all.where((r) => r.type == _filter).toList();

        return Column(
          children: <Widget>[
            _FilterBar(
              all: all,
              filter: _filter,
              onFilterChanged: (t) => setState(() => _filter = t),
              groupByPeripheral: _groupByPeripheral,
              onToggleGroup: () =>
                  setState(() => _groupByPeripheral = !_groupByPeripheral),
            ),
            Expanded(
              child: visible.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          const Text('该类型下没有收藏'),
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: () => setState(() => _filter = null),
                            child: const Text('查看全部'),
                          ),
                        ],
                      ),
                    )
                  : _groupByPeripheral
                      ? _GroupedList(records: visible)
                      : _FlatList(records: visible),
            ),
          ],
        );
      },
    );
  }
}

/// 顶部筛选与分组开关。
class _FilterBar extends StatelessWidget {
  final List<UserRecord> all;
  final ItemType? filter;
  final ValueChanged<ItemType?> onFilterChanged;
  final bool groupByPeripheral;
  final VoidCallback onToggleGroup;

  const _FilterBar({
    required this.all,
    required this.filter,
    required this.onFilterChanged,
    required this.groupByPeripheral,
    required this.onToggleGroup,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final counts = <ItemType, int>{};
    for (final r in all) {
      counts[r.type] = (counts[r.type] ?? 0) + 1;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 0),
          child: Row(
            children: <Widget>[
              Text(
                '共 ${all.length} 条收藏',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
              const Spacer(),
              TextButton.icon(
                icon: Icon(
                  groupByPeripheral ? Icons.folder_open : Icons.folder_outlined,
                  size: 17,
                ),
                label: Text(
                  groupByPeripheral ? '按类型排列' : '按外设分组',
                  style: const TextStyle(fontSize: 12),
                ),
                onPressed: onToggleGroup,
              ),
            ],
          ),
        ),
        SizedBox(
          height: 38,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: <Widget>[
              _Chip(
                label: '全部',
                count: all.length,
                selected: filter == null,
                onTap: () => onFilterChanged(null),
              ),
              for (final t in ItemType.values)
                if ((counts[t] ?? 0) > 0)
                  _Chip(
                    label: t.labelZh,
                    count: counts[t]!,
                    selected: filter == t,
                    onTap: () => onFilterChanged(filter == t ? null : t),
                  ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  const _Chip({
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

/// 平铺列表（默认）。
class _FlatList extends StatelessWidget {
  final List<UserRecord> records;

  const _FlatList({required this.records});

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: <Widget>[
        for (final r in records) FavoriteTile(record: r),
        const SizedBox(height: 24),
      ],
    );
  }
}

/// 按所属外设/类型分组。
class _GroupedList extends StatelessWidget {
  final List<UserRecord> records;

  const _GroupedList({required this.records});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    // 外设类条目按自身名分组，其余按 "类型 · 所属外设" 分组
    final groups = <String, List<UserRecord>>{};
    for (final r in records) {
      final key = r.type == ItemType.peripheral
          ? r.title
          : (r.subtitle.isEmpty ? r.type.labelZh : r.subtitle);
      groups.putIfAbsent(key, () => <UserRecord>[]).add(r);
    }
    // 分组名排序，保证顺序稳定
    final keys = groups.keys.toList()..sort();

    return ListView(
      children: <Widget>[
        for (final k in keys) ...<Widget>[
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    k,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: scheme.primary,
                    ),
                  ),
                ),
                Text(
                  '${groups[k]!.length}',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          for (final r in groups[k]!) FavoriteTile(record: r),
        ],
        const SizedBox(height: 24),
      ],
    );
  }
}

/// 收藏条目。左滑取消收藏。
class FavoriteTile extends ConsumerWidget {
  final UserRecord record;

  const FavoriteTile({super.key, required this.record});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;

    return Dismissible(
      key: ValueKey<String>(record.ref.key),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: scheme.errorContainer,
        child: Icon(Icons.delete_outline, color: scheme.error),
      ),
      confirmDismiss: (_) async {
        // 取消收藏是可恢复的操作，但仍给一次确认，避免误滑
        return await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('取消收藏？'),
                content: Text(record.title),
                actions: <Widget>[
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    child: const Text('取消'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(ctx).pop(true),
                    child: const Text('取消收藏'),
                  ),
                ],
              ),
            ) ??
            false;
      },
      onDismissed: (_) async {
        // toggle 内部会重新查库并刷新 state，列表随之更新，不必手动通知
        await ref.read(favoritesProvider.notifier).toggle(record.ref);
      },
      child: ListTile(
        dense: true,
        leading: Icon(
          _iconOf(record.type),
          size: 19,
          color: AppTheme.favoriteColor,
        ),
        title: Text(
          record.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamilyFallback:
                record.type == ItemType.compileError ? null : AppFonts.mono,
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          <String>[
            record.type.labelZh,
            if (record.subtitle.isNotEmpty) record.subtitle,
          ].join(' · '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 11.5),
        ),
        trailing: const Icon(Icons.chevron_right, size: 18),
        onTap: () => openItem(context, ref, record.ref),
      ),
    );
  }

  static IconData _iconOf(ItemType t) {
    switch (t) {
      case ItemType.function:
        return Icons.functions;
      case ItemType.symbol:
        return Icons.tag;
      case ItemType.peripheral:
        return Icons.memory;
      case ItemType.pin:
        return Icons.grid_on;
      case ItemType.compileError:
        return Icons.error_outline;
    }
  }
}

/// 按类型打开对应详情页。
///
/// 收藏页与最近查看页共用，避免两处各写一遍 switch 而漏掉某个类型。
void openItem(BuildContext context, WidgetRef ref, ItemRef item) {
  switch (item.type) {
    case ItemType.function:
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => FunctionDetailPage(functionId: item.id),
        ),
      );
    case ItemType.symbol:
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => SymbolDetailPage(symbolId: item.id),
        ),
      );
    case ItemType.peripheral:
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PeripheralDetailPage(peripheralId: item.id),
        ),
      );
    case ItemType.pin:
      final n = int.tryParse(item.id);
      if (n == null) return;
      showPinDetail(
        context,
        n,
        onOpenFunction: (fid) => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => FunctionDetailPage(functionId: fid),
          ),
        ),
      );
    case ItemType.compileError:
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => CompileErrorDetailPage(errorId: item.id),
        ),
      );
  }
}

/// 空状态。用共享的 [EmptyState] 保持与其它页面一致。
class _EmptyFavorites extends StatelessWidget {
  const _EmptyFavorites();

  @override
  Widget build(BuildContext context) {
    return const EmptyState(
      icon: Icons.star_border,
      title: '还没有收藏',
      body: '在函数、符号、外设、引脚、编译错误的详情页点右上角星标即可收藏。'
          '收藏保存在本地数据库，重启 APP 后仍然存在。',
    );
  }
}
