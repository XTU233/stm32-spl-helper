import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../data/user_database.dart';
import '../models/item_ref.dart';

/// 把笔记拼成 Markdown 文本。
///
/// 抽成纯函数是为了可测：导出逻辑（分组、转义、时间格式）值得单独验证，
/// 而真实导出要写文件、起系统分享面板，在测试里跑不了。
///
/// [now] 可注入，方便测试断言固定时间。
String buildNotesMarkdown(
  List<UserRecord> notes, {
  DateTime? now,
}) {
  final ts = now ?? DateTime.now();
  final buffer = StringBuffer();

  buffer.writeln('# STM32 标准库助手 · 笔记导出');
  buffer.writeln();
  buffer.writeln('- 导出时间：${_formatDateTime(ts)}');
  buffer.writeln('- 笔记条数：${notes.length}');
  buffer.writeln();
  buffer.writeln('---');
  buffer.writeln();

  if (notes.isEmpty) {
    buffer.writeln('（没有笔记）');
    return buffer.toString();
  }

  // 按类型分组，组内保持传入顺序（已是按更新时间倒序）
  final groups = <ItemType, List<UserRecord>>{};
  for (final n in notes) {
    groups.putIfAbsent(n.type, () => <UserRecord>[]).add(n);
  }

  for (final type in ItemType.values) {
    final list = groups[type];
    if (list == null || list.isEmpty) continue;

    buffer.writeln('## ${type.labelZh}（${list.length}）');
    buffer.writeln();

    for (final n in list) {
      buffer.writeln('### ${n.title}');
      buffer.writeln();
      // 副标题（所属外设等）与条目 id 都写上，方便日后回查
      if (n.subtitle.isNotEmpty) {
        buffer.writeln('- 分类：${n.subtitle}');
      }
      buffer.writeln('- 标识：`${n.id}`');
      final updatedAt = _formatDateTime(
        DateTime.fromMillisecondsSinceEpoch(n.timestamp),
      );
      buffer.writeln('- 更新：$updatedAt');
      buffer.writeln();
      buffer.writeln(n.content ?? '');
      buffer.writeln();
    }
    buffer.writeln('---');
    buffer.writeln();
  }

  return buffer.toString();
}

/// 生成导出文件名，形如 `stm32-notes-20261015-1530.md`。
String notesFileName(DateTime now) {
  String two(int v) => v.toString().padLeft(2, '0');
  return 'stm32-notes-${now.year}${two(now.month)}${two(now.day)}'
      '-${two(now.hour)}${two(now.minute)}.md';
}

/// 把 Markdown 写到临时目录并调起系统分享面板。
///
/// 需求 5.8 要求"导出笔记"。用临时目录 + share_plus：
/// Android 上写临时目录**不需要存储权限**，分享面板也由系统提供，
/// 全程不联网（share_plus 只发本地 Intent）。
///
/// 返回写出的文件路径；失败抛异常由调用方提示。
Future<String> exportNotesToFile(
  List<UserRecord> notes, {
  DateTime? now,
}) async {
  final ts = now ?? DateTime.now();
  final markdown = buildNotesMarkdown(notes, now: ts);
  final dir = await getTemporaryDirectory();
  final file = File(p.join(dir.path, notesFileName(ts)));
  await file.writeAsString(markdown);

  await Share.shareXFiles(
    <XFile>[XFile(file.path, mimeType: 'text/markdown')],
    subject: 'STM32 标准库助手 · 笔记导出',
    text: '共 ${notes.length} 条笔记',
  );
  return file.path;
}

String _formatDateTime(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} '
      '${two(t.hour)}:${two(t.minute)}';
}
