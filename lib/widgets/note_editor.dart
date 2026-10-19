import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/item_ref.dart';
import '../providers/user_providers.dart';
import '../utils/theme.dart';

/// 弹出笔记编辑弹窗。
///
/// 用底部弹窗而不是独立页面：笔记通常很短（一两句备忘），
/// 弹窗能保留底下的详情页上下文，关掉就回到原位置。
Future<void> showNoteEditor(
  BuildContext context,
  WidgetRef ref,
  ItemRef item,
) async {
  final existing = ref.read(notesProvider.notifier).contentOf(item) ?? '';
  final controller = TextEditingController(text: existing);
  final hadNote = existing.trim().isNotEmpty;

  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) {
      return Padding(
        // 键盘弹起时把内容顶上去，否则输入框被挡住
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
        ),
        child: _NoteEditorSheet(
          controller: controller,
          item: item,
          hadNote: hadNote,
        ),
      );
    },
  );

  controller.dispose();

  if (saved != true) return;
  if (!context.mounted) return;

  final content = controller.text;
  await ref.read(notesProvider.notifier).save(item, content);

  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        content.trim().isEmpty ? '已删除笔记' : '笔记已保存',
      ),
      duration: const Duration(milliseconds: 1200),
    ),
  );
}

class _NoteEditorSheet extends StatelessWidget {
  final TextEditingController controller;
  final ItemRef item;
  final bool hadNote;

  const _NoteEditorSheet({
    required this.controller,
    required this.item,
    required this.hadNote,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // 抓手
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: scheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Row(
            children: <Widget>[
              Icon(Icons.sticky_note_2_outlined,
                  size: 18, color: AppTheme.noteColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  hadNote ? '编辑笔记' : '添加笔记',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${item.type.labelZh} · ${item.title}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamilyFallback: AppFonts.mono,
              fontSize: 12,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            autofocus: true,
            maxLines: 6,
            minLines: 3,
            textInputAction: TextInputAction.newline,
            keyboardType: TextInputType.multiline,
            decoration: const InputDecoration(
              hintText: '记下这个函数的用法要点、踩过的坑、自己的封装习惯…\n'
                  '例如：中断里必须先清标志，否则会反复进中断',
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '笔记保存在本地数据库，重启 APP 后仍在。清空内容再保存即删除笔记。',
            style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 14),
          Row(
            children: <Widget>[
              if (hadNote)
                TextButton.icon(
                  icon: const Icon(Icons.delete_outline, size: 17),
                  label: const Text('删除'),
                  style: TextButton.styleFrom(foregroundColor: scheme.error),
                  onPressed: () {
                    controller.text = '';
                    Navigator.of(context).pop(true);
                  },
                ),
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('取消'),
              ),
              const SizedBox(width: 6),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('保存'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
