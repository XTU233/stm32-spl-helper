import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/note_export.dart';
import '../data/search_history.dart';
import '../data/settings_store.dart';
import '../data/user_database.dart';
import '../providers/app_providers.dart';
import '../providers/user_providers.dart';
import '../utils/app_info.dart';

/// 设置页（阶段 9 完整实现）。
///
/// 需求 5.8：数据版本与来源、深色模式、代码字号、清除记录、
/// 导出笔记、关于页。
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dataAsync = ref.watch(splDataProvider);
    final themeMode = ref.watch(themeModeProvider);
    final codeSize = ref.watch(codeFontSizeProvider);
    final scheme = Theme.of(context).colorScheme;

    return ListView(
      children: <Widget>[
        // ---- 数据信息 ----
        _SectionTitle('数据'),
        dataAsync.when(
          loading: () => const ListTile(title: Text('加载中…')),
          error: (e, _) => ListTile(title: Text('数据加载失败：$e')),
          data: (data) {
            final m = data.manifest;
            final s = m.stats;
            return Column(
              children: <Widget>[
                ListTile(
                  leading: const Icon(Icons.inventory_2_outlined),
                  title: const Text('数据版本'),
                  subtitle: Text(
                    '${m.dataVersion} · 结构版本 v${m.schemaVersion}\n'
                    '来源：${m.splVersion}\n'
                    '生成于 ${m.generatedAt}',
                  ),
                  isThreeLine: true,
                ),
                ListTile(
                  leading: const Icon(Icons.numbers),
                  title: const Text('数据统计'),
                  subtitle: Text(
                    '${s.peripheralCount} 个外设 · ${s.functionCount} 个函数 · '
                    '${s.symbolCount} 个符号\n'
                    '${s.pinCount} 个引脚 · ${s.compileErrorCount} 条编译错误',
                  ),
                  isThreeLine: true,
                ),
                ListTile(
                  leading: const Icon(Icons.memory),
                  title: const Text('当前芯片'),
                  subtitle: Text('${data.chip.name}\n${data.chip.summary}'),
                  isThreeLine: true,
                ),
              ],
            );
          },
        ),

        const Divider(),

        // ---- 外观 ----
        _SectionTitle('外观'),
        ListTile(
          leading: const Icon(Icons.brightness_6_outlined),
          title: const Text('深色模式'),
          subtitle: Text(themeModeDescription(themeMode)),
          trailing: DropdownButton<ThemeMode>(
            value: themeMode,
            underline: const SizedBox.shrink(),
            items: const <DropdownMenuItem<ThemeMode>>[
              DropdownMenuItem(value: ThemeMode.system, child: Text('跟随系统')),
              DropdownMenuItem(value: ThemeMode.dark, child: Text('强制深色')),
              DropdownMenuItem(value: ThemeMode.light, child: Text('强制浅色')),
            ],
            onChanged: (v) {
              if (v != null) {
                ref.read(settingsProvider.notifier).setThemeMode(v);
              }
            },
          ),
        ),
        ListTile(
          leading: const Icon(Icons.text_fields),
          title: const Text('代码字号'),
          subtitle: Slider(
            value: codeSize,
            min: AppSettings.minCodeFontSize,
            max: AppSettings.maxCodeFontSize,
            divisions:
                (AppSettings.maxCodeFontSize - AppSettings.minCodeFontSize)
                    .round(),
            label: codeSize.toStringAsFixed(0),
            onChanged: (v) =>
                ref.read(settingsProvider.notifier).setCodeFontSize(v),
          ),
          trailing: Text('${codeSize.toStringAsFixed(0)} pt'),
        ),
        Consumer(
          builder: (context, ref, _) {
            final onlySupported = ref.watch(onlySupportedProvider);
            return SwitchListTile(
              secondary: const Icon(Icons.filter_alt_outlined),
              title: const Text('首页仅显示本型号支持的外设'),
              subtitle: Text(
                onlySupported
                    ? '已隐藏 DAC / FSMC / SDIO / CEC 等本型号用不了的外设'
                    : '显示全部外设，用不了的会标记出来',
              ),
              value: onlySupported,
              onChanged: (v) =>
                  ref.read(settingsProvider.notifier).setOnlySupported(v),
            );
          },
        ),
        Consumer(
          builder: (context, ref, _) {
            return ListTile(
              leading: const Icon(Icons.restart_alt),
              title: const Text('恢复默认设置'),
              subtitle: const Text('主题跟随系统、代码字号 13pt、显示全部外设'),
              onTap: () async {
                await ref.read(settingsProvider.notifier).resetToDefaults();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('已恢复默认设置')),
                  );
                }
              },
            );
          },
        ),

        const Divider(),

        // ---- 数据管理 ----
        _SectionTitle('数据管理'),
        Consumer(
          builder: (context, ref, _) {
            final recent = ref.watch(recentProvider).valueOrNull ??
                const <UserRecord>[];
            return ListTile(
              leading: const Icon(Icons.cleaning_services_outlined),
              title: const Text('清除最近查看'),
              subtitle: Text(
                recent.isEmpty ? '暂无记录' : '当前 ${recent.length} 条',
              ),
              enabled: recent.isNotEmpty,
              onTap: recent.isEmpty
                  ? null
                  : () async {
                      await ref.read(recentProvider.notifier).clear();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('已清除最近查看')),
                        );
                      }
                    },
            );
          },
        ),
        // 搜索历史在阶段 5 已实现持久化，这里同步开放清除入口
        Consumer(
          builder: (context, ref, _) {
            final history = ref.watch(searchHistoryProvider).valueOrNull ??
                const <String>[];
            return ListTile(
              leading: const Icon(Icons.history),
              title: const Text('清空搜索历史'),
              subtitle: Text(
                history.isEmpty ? '暂无历史' : '当前 ${history.length} 条',
              ),
              enabled: history.isNotEmpty,
              onTap: history.isEmpty
                  ? null
                  : () async {
                      await ref.read(searchHistoryProvider.notifier).clear();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('已清空搜索历史')),
                        );
                      }
                    },
            );
          },
        ),
        Consumer(
          builder: (context, ref, _) {
            final notes =
                ref.watch(notesProvider).valueOrNull ?? const <UserRecord>[];
            return ListTile(
              leading: const Icon(Icons.ios_share),
              title: const Text('导出全部笔记为 Markdown'),
              subtitle: Text(
                notes.isEmpty ? '暂无笔记' : '将导出 ${notes.length} 条笔记',
              ),
              enabled: notes.isNotEmpty,
              onTap: notes.isEmpty
                  ? null
                  : () => _exportNotes(context, ref, notes),
            );
          },
        ),
        Consumer(
          builder: (context, ref, _) {
            final favorites =
                ref.watch(favoritesProvider).valueOrNull ?? const <UserRecord>[];
            return ListTile(
              leading: const Icon(Icons.delete_forever_outlined),
              title: const Text('清空全部用户数据'),
              subtitle: Text(
                '收藏 ${favorites.length} 条 · 笔记与浏览记录一并清除',
              ),
              onTap: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('清空全部用户数据？'),
                    content: const Text(
                      '将删除所有收藏、笔记与最近查看记录，且不可恢复。\n'
                      'assets 里的库数据不受影响。',
                    ),
                    actions: <Widget>[
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(false),
                        child: const Text('取消'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.of(ctx).pop(true),
                        child: const Text('确认清空'),
                      ),
                    ],
                  ),
                );
                if (ok != true) return;
                await ref.read(userStoreProvider).clearAll();
                // 让三个列表重新从库里读（此时都是空的）
                ref.invalidate(favoritesProvider);
                ref.invalidate(notesProvider);
                ref.invalidate(recentProvider);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('已清空全部用户数据')),
                  );
                }
              },
            );
          },
        ),

        const Divider(),

        // ---- 关于 ----
        _SectionTitle('关于'),
        const ListTile(
          leading: Icon(Icons.info_outline),
          title: Text('STM32 标准库助手'),
          subtitle: Text(
            '完全离线的 STM32F103C8T6 标准外设库（SPL V3.5.0）查阅工具。\n'
            'APP 运行时不发起任何网络请求，也未声明 INTERNET 权限。',
          ),
          isThreeLine: true,
        ),
        const ListTile(
          leading: Icon(Icons.numbers),
          title: Text('应用版本'),
          subtitle: Text('$appVersion  ·  包名 $appPackageName'),
        ),
        const ListTile(
          leading: Icon(Icons.copyright_outlined),
          title: Text('数据来源与版权'),
          subtitle: Text(
            '库函数原型与英文注释来自 ST 官方 STM32F10x 标准外设库 V3.5.0，'
            '版权归 STMicroelectronics 所有。\n'
            '引脚数据来自《STM32F103C8T6引脚定义.xlsx》（DS5319 Table 5 转录）。\n'
            '中文说明、示例代码与排错经验为本项目整理，仅供个人学习查阅使用。',
          ),
          isThreeLine: true,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          child: Text(
            'SPL V3.5.0 · 488 个函数 · 7337 个符号 · 48 个引脚 · 15 条常见错误',
            style: TextStyle(
              fontSize: 11.5,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }

  /// 导出笔记：写临时文件后调起系统分享面板。
  static Future<void> _exportNotes(
    BuildContext context,
    WidgetRef ref,
    List<UserRecord> notes,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final path = await exportNotesToFile(notes);
      messenger.showSnackBar(
        SnackBar(
          content: Text('已生成 ${notes.length} 条笔记的 Markdown：$path'),
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('导出失败：$e')),
      );
    }
  }
}

/// 设置分组标题。
class _SectionTitle extends StatelessWidget {
  final String title;

  const _SectionTitle(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}
