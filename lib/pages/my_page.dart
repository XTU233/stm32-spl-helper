import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/user_database.dart';
import '../models/item_ref.dart';
import '../providers/user_providers.dart';
import '../utils/theme.dart';
import '../widgets/note_editor.dart';
import '../widgets/pressable_card.dart';
import 'favorites_page.dart';

/// 「我的」Tab：收藏 / 最近查看 / 笔记 三个子页。
///
/// 需求 5.5 把三块放在一起（都是"用户自己产生的数据"），
/// 用 TabBar 而不是三个底部 Tab——底部已经占了 5 个位置。
class MyPage extends StatelessWidget {
  const MyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Column(
        children: <Widget>[
          const TabBar(
            tabs: <Widget>[
              Tab(text: '收藏', icon: Icon(Icons.star_border, size: 19)),
              Tab(text: '最近', icon: Icon(Icons.history, size: 19)),
              Tab(text: '笔记', icon: Icon(Icons.sticky_note_2_outlined, size: 19)),
            ],
          ),
          const Expanded(
            child: TabBarView(
              children: <Widget>[
                FavoritesPage(),
                _RecentTab(),
                _NotesTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 最近查看。
class _RecentTab extends ConsumerWidget {
  const _RecentTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recentAsync = ref.watch(recentProvider);
    final scheme = Theme.of(context).colorScheme;

    return recentAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('读取最近查看失败：$e')),
      data: (records) {
        if (records.isEmpty) {
          return _EmptyHint(
            icon: Icons.history,
            title: '还没有浏览记录',
            body: '打开任意函数、符号、外设、引脚或编译错误的详情页，'
                '就会自动记录在这里。最多保留 $recentLimit 条。',
          );
        }
        return Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 8, 4),
              child: Row(
                children: <Widget>[
                  Text(
                    '共 ${records.length} 条（上限 $recentLimit）',
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    icon: const Icon(Icons.delete_sweep_outlined, size: 17),
                    label: const Text('清空', style: TextStyle(fontSize: 12)),
                    onPressed: () async {
                      await ref.read(recentProvider.notifier).clear();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('已清空最近查看')),
                        );
                      }
                    },
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                children: <Widget>[
                  for (final r in records)
                    _RecentTile(record: r),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _RecentTile extends ConsumerWidget {
  final UserRecord record;

  const _RecentTile({required this.record});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      dense: true,
      leading: Icon(
        _typeIcon(record.type),
        size: 18,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
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
          _relativeTime(record.timestamp),
        ].join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 11.5),
      ),
      onTap: () => openItem(context, ref, record.ref),
    );
  }
}

/// 笔记列表。
class _NotesTab extends ConsumerWidget {
  const _NotesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notesAsync = ref.watch(notesProvider);

    return notesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('读取笔记失败：$e')),
      data: (records) {
        if (records.isEmpty) {
          return const _EmptyHint(
            icon: Icons.sticky_note_2_outlined,
            title: '还没有笔记',
            body: '在任意详情页点右上角的便签图标即可记笔记，'
                '比如记下某个函数的用法要点或踩过的坑。'
                '笔记可导出为 Markdown（设置页）。',
          );
        }
        return ListView(
          children: <Widget>[
            for (final r in records) _NoteTile(record: r),
            const SizedBox(height: 24),
          ],
        );
      },
    );
  }
}

class _NoteTile extends ConsumerWidget {
  final UserRecord record;

  const _NoteTile({required this.record});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => showNoteEditor(context, ref, record.ref),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(Icons.sticky_note_2,
                      size: 15, color: AppTheme.noteColor),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      record.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamilyFallback:
                            record.type == ItemType.compileError
                                ? null
                                : AppFonts.mono,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    _relativeTime(record.timestamp),
                    style: TextStyle(
                      fontSize: 10.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 7),
              Text(
                record.content ?? '',
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5, height: 1.55),
              ),
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  Text(
                    <String>[
                      record.type.labelZh,
                      if (record.subtitle.isNotEmpty) record.subtitle,
                    ].join(' · '),
                    style: TextStyle(
                      fontSize: 10.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.open_in_new, size: 16),
                    tooltip: '打开条目',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => openItem(context, ref, record.ref),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 16),
                    tooltip: '删除笔记',
                    visualDensity: VisualDensity.compact,
                    onPressed: () async {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('删除这条笔记？'),
                          content: Text(record.title),
                          actions: <Widget>[
                            TextButton(
                              onPressed: () => Navigator.of(ctx).pop(false),
                              child: const Text('取消'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.of(ctx).pop(true),
                              child: const Text('删除'),
                            ),
                          ],
                        ),
                      );
                      if (ok == true) {
                        await ref
                            .read(notesProvider.notifier)
                            .remove(record.ref);
                      }
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 空状态提示。
///
/// 阶段 10 起改用共享的 [EmptyState]（见 widgets/pressable_card.dart），
/// 六个页面的空状态统一成同一套版式与文案语气。
class _EmptyHint extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const _EmptyHint({
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) => EmptyState(
        icon: icon,
        title: title,
        body: body,
      );
}

IconData _typeIcon(ItemType t) {
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

/// 相对时间（"刚刚"、"3 分钟前"、"2 天前"）。
///
/// 最近查看列表里用绝对时间（如 14:23）意义不大，
/// 用户关心的是"多久之前看的"。
String _relativeTime(int millis) {
  if (millis <= 0) return '';
  final diff = DateTime.now().difference(
    DateTime.fromMillisecondsSinceEpoch(millis),
  );
  if (diff.inSeconds < 60) return '刚刚';
  if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
  if (diff.inHours < 24) return '${diff.inHours} 小时前';
  if (diff.inDays < 30) return '${diff.inDays} 天前';
  return '${(diff.inDays / 30).floor()} 个月前';
}
