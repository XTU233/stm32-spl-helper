import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/item_ref.dart';
import '../providers/user_providers.dart';
import '../utils/theme.dart';
import 'note_editor.dart';

/// 详情页右上角的「收藏 + 笔记」按钮组。
///
/// 需求 5.5：函数、符号、外设、引脚、编译错误都可收藏。
/// 五个详情页共用这一个组件，避免五处各写一遍星标逻辑
/// （早先在阶段 4/5 的页面里各写各的，很容易漏掉某一个页面）。
class ItemActions extends ConsumerWidget {
  /// 要操作的条目引用
  final ItemRef item;

  /// AppBar 上用的紧凑样式（图标按钮）
  final bool compact;

  const ItemActions({super.key, required this.item, this.compact = true});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favoritesAsync = ref.watch(favoritesProvider);
    final notesAsync = ref.watch(notesProvider);

    // 数据未就绪时按"未收藏"渲染，点的时候再由 notifier 决定
    final isFav = favoritesAsync.valueOrNull
            ?.any((r) => r.ref == item) ??
        false;
    final hasNote =
        (notesAsync.valueOrNull ?? const []).any((r) => r.ref == item);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        IconButton(
          icon: Icon(
            hasNote ? Icons.sticky_note_2 : Icons.sticky_note_2_outlined,
          ),
          tooltip: hasNote ? '编辑笔记' : '添加笔记',
          onPressed: () => showNoteEditor(context, ref, item),
        ),
        IconButton(
          icon: Icon(isFav ? Icons.star : Icons.star_border),
          color: isFav ? AppTheme.favoriteColor : null,
          tooltip: isFav ? '取消收藏' : '收藏',
          onPressed: () async {
            final nowFav = await ref.read(favoritesProvider.notifier).toggle(item);
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(nowFav ? '已收藏 ${item.title}' : '已取消收藏'),
                duration: const Duration(milliseconds: 1200),
              ),
            );
          },
        ),
      ],
    );
  }
}
