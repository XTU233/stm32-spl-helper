// 阶段 6（收藏 / 最近查看 / 笔记）的测试。
//
// 用 InMemoryUserStore 跑业务规则。为什么不测真 sqflite：
// 单元测试里要跑 sqflite 需要 sqflite_common_ffi（依赖 ffi 原生库），
// 该包不在本地 pub cache 里，拉取需要联网——与本项目"完全离线"的
// 约束冲突。所以把 SQL 与业务规则分开：
//   - 业务规则（去重、上限裁剪、排序、空内容即删除）在两种实现里共用，
//     这里用内存实现验证；
//   - SQL 语句本身由真机手工验证覆盖（阶段 6 验收项里跑一遍）。
//
// 这个取舍的代价是"SQL 写错测不出来"，所以 SQL 保持极简，
// 复杂逻辑（比如分组）都放在 Dart 侧。

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stm32_spl_helper/data/note_export.dart';
import 'package:stm32_spl_helper/data/user_database.dart';
import 'package:stm32_spl_helper/models/item_ref.dart';
import 'package:stm32_spl_helper/providers/user_providers.dart';

/// 造一个条目引用
ItemRef refOf(
  String id, {
  ItemType type = ItemType.function,
  String? title,
  String subtitle = '',
}) =>
    ItemRef(
      type: type,
      id: id,
      title: title ?? id,
      subtitle: subtitle,
    );

/// 造一个用内存库的 ProviderContainer
ProviderContainer makeContainer([UserStore? store]) {
  final container = ProviderContainer(
    overrides: <Override>[
      userStoreProvider.overrideWithValue(store ?? InMemoryUserStore()),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('收藏：CRUD', () {
    test('收藏后能查到，isFavorite 为真', () async {
      final store = InMemoryUserStore();
      final ref = refOf('GPIO_Init', subtitle: 'GPIO');

      expect(await store.isFavorite(ref), isFalse);
      await store.addFavorite(ref);
      expect(await store.isFavorite(ref), isTrue);

      final list = await store.favorites();
      expect(list.length, 1);
      expect(list.first.id, 'GPIO_Init');
      expect(list.first.title, 'GPIO_Init');
      expect(list.first.subtitle, 'GPIO');
    });

    test('重复收藏同一条不产生两行', () async {
      final store = InMemoryUserStore();
      final ref = refOf('GPIO_Init');
      await store.addFavorite(ref);
      await store.addFavorite(ref);
      expect((await store.favorites()).length, 1);
    });

    test('不同类型但同 id 是两条（function:GPIO 与 peripheral:GPIO）', () async {
      final store = InMemoryUserStore();
      await store.addFavorite(refOf('GPIO', type: ItemType.function));
      await store.addFavorite(refOf('GPIO', type: ItemType.peripheral));
      expect((await store.favorites()).length, 2);
    });

    test('取消收藏', () async {
      final store = InMemoryUserStore();
      final ref = refOf('GPIO_Init');
      await store.addFavorite(ref);
      await store.removeFavorite(ref);
      expect(await store.isFavorite(ref), isFalse);
      expect(await store.favorites(), isEmpty);
    });

    test('清空收藏', () async {
      final store = InMemoryUserStore();
      await store.addFavorite(refOf('A'));
      await store.addFavorite(refOf('B'));
      await store.clearFavorites();
      expect(await store.favorites(), isEmpty);
    });

    test('最近收藏的排在最前', () async {
      final store = InMemoryUserStore();
      await store.addFavorite(refOf('first'));
      await store.addFavorite(refOf('second'));
      await store.addFavorite(refOf('third'));
      final list = await store.favorites();
      expect(list.map((r) => r.id).toList(), <String>['third', 'second', 'first']);
    });
  });

  group('收藏：notifier', () {
    test('toggle 在两种状态间切换并返回新状态', () async {
      final container = makeContainer();
      final notifier = container.read(favoritesProvider.notifier);
      // 等首次 build 完成
      await container.read(favoritesProvider.future);

      final ref = refOf('GPIO_Init');
      expect(await notifier.toggle(ref), isTrue);
      expect(notifier.contains(ref), isTrue);

      expect(await notifier.toggle(ref), isFalse);
      expect(notifier.contains(ref), isFalse);
    });

    test('toggle 后 state 立即更新（UI 不用重新查库）', () async {
      final container = makeContainer();
      await container.read(favoritesProvider.future);
      final ref = refOf('GPIO_Init');

      await container.read(favoritesProvider.notifier).toggle(ref);
      final state = container.read(favoritesProvider).valueOrNull!;
      expect(state.length, 1);
      expect(state.first.id, 'GPIO_Init');
    });
  });

  group('笔记：CRUD', () {
    test('保存后能读回', () async {
      final store = InMemoryUserStore();
      final ref = refOf('GPIO_Init');
      await store.saveNote(ref, '中断里必须先清标志');
      expect(await store.note(ref), '中断里必须先清标志');
    });

    test('再次保存是覆盖而非新增', () async {
      final store = InMemoryUserStore();
      final ref = refOf('GPIO_Init');
      await store.saveNote(ref, '第一版');
      await store.saveNote(ref, '第二版');
      expect(await store.note(ref), '第二版');
      expect((await store.notes()).length, 1);
    });

    test('内容清空视为删除笔记', () async {
      final store = InMemoryUserStore();
      final ref = refOf('GPIO_Init');
      await store.saveNote(ref, '有内容');
      await store.saveNote(ref, '   ');
      expect(await store.note(ref), isNull);
      expect(await store.notes(), isEmpty);
    });

    test('纯空白内容从一开始就不入库', () async {
      final store = InMemoryUserStore();
      await store.saveNote(refOf('A'), '\n\t  ');
      expect(await store.notes(), isEmpty);
    });

    test('按更新时间倒序', () async {
      final store = InMemoryUserStore();
      await store.saveNote(refOf('A'), 'a');
      await store.saveNote(refOf('B'), 'b');
      final list = await store.notes();
      expect(list.map((r) => r.id).toList(), <String>['B', 'A']);
    });

    test('删除笔记', () async {
      final store = InMemoryUserStore();
      final ref = refOf('GPIO_Init');
      await store.saveNote(ref, 'x');
      await store.deleteNote(ref);
      expect(await store.note(ref), isNull);
    });

    test('notifier 的 contentOf 能直接取到内容', () async {
      final container = makeContainer();
      await container.read(notesProvider.future);
      final notifier = container.read(notesProvider.notifier);
      final ref = refOf('GPIO_Init');

      expect(notifier.contentOf(ref), isNull);
      await notifier.save(ref, '要点');
      expect(notifier.contentOf(ref), '要点');
    });
  });

  group('最近查看：记录与裁剪', () {
    test('记录后能查到', () async {
      final store = InMemoryUserStore();
      await store.recordView(refOf('GPIO_Init'));
      final list = await store.recentViews();
      expect(list.length, 1);
      expect(list.first.id, 'GPIO_Init');
    });

    test('同一条重复查看只留一条，且提到最前', () async {
      final store = InMemoryUserStore();
      await store.recordView(refOf('A'));
      await store.recordView(refOf('B'));
      await store.recordView(refOf('A')); // 再看一次 A

      final list = await store.recentViews();
      expect(list.length, 2, reason: '同一条目不应产生两行');
      expect(list.first.id, 'A', reason: '最近看过的应排最前');
    });

    test('超过 100 条时丢掉最旧的', () async {
      final store = InMemoryUserStore();
      for (var i = 0; i < recentLimit + 20; i++) {
        await store.recordView(refOf('fn$i'));
      }
      final list = await store.recentViews();
      expect(list.length, recentLimit);
      // 最新的是最后记录的
      expect(list.first.id, 'fn${recentLimit + 19}');
      // 最旧的 20 条被裁掉
      expect(list.any((r) => r.id == 'fn0'), isFalse);
      expect(list.any((r) => r.id == 'fn19'), isFalse);
      expect(list.any((r) => r.id == 'fn20'), isTrue);
    });

    test('清空最近查看', () async {
      final store = InMemoryUserStore();
      await store.recordView(refOf('A'));
      await store.clearRecentViews();
      expect(await store.recentViews(), isEmpty);
    });

    test('notifier 记录后 state 立即更新', () async {
      final container = makeContainer();
      await container.read(recentProvider.future);
      await container.read(recentProvider.notifier).record(refOf('GPIO_Init'));
      final state = container.read(recentProvider).valueOrNull!;
      expect(state.length, 1);
    });
  });

  group('清空全部用户数据', () {
    test('三张表一起清', () async {
      final store = InMemoryUserStore();
      await store.addFavorite(refOf('A'));
      await store.saveNote(refOf('B'), 'x');
      await store.recordView(refOf('C'));

      await store.clearAll();

      expect(await store.favorites(), isEmpty);
      expect(await store.notes(), isEmpty);
      expect(await store.recentViews(), isEmpty);
    });
  });

  group('ItemRef：库主键', () {
    test('key 拼接与还原', () {
      final ref = refOf('GPIO_Init');
      expect(ref.key, 'function:GPIO_Init');

      final back = ItemRef.fromKey(ref.key);
      expect(back, isNotNull);
      expect(back!.type, ItemType.function);
      expect(back.id, 'GPIO_Init');
    });

    test('id 里含冒号也能正确还原（只切第一个冒号）', () {
      final back = ItemRef.fromKey('compile_error:err.undefined_reference');
      expect(back!.type, ItemType.compileError);
      expect(back.id, 'err.undefined_reference');
    });

    test('非法 key 返回 null 而不是抛异常', () {
      expect(ItemRef.fromKey(''), isNull);
      expect(ItemRef.fromKey('noseparator'), isNull);
      expect(ItemRef.fromKey('unknown_type:xxx'), isNull);
      expect(ItemRef.fromKey('function:'), isNull);
    });

    test('相等性按 type + id，与标题无关', () {
      expect(refOf('A', title: '标题一'), refOf('A', title: '标题二'));
      expect(
        refOf('A'),
        isNot(refOf('A', type: ItemType.symbol)),
      );
    });
  });

  group('笔记导出：Markdown 拼装', () {
    final fixedNow = DateTime(2026, 10, 15, 15, 30);

    UserRecord note(
      String id, {
      ItemType type = ItemType.function,
      String subtitle = '',
      String content = '',
      int ts = 1000,
    }) =>
        UserRecord(
          type: type,
          id: id,
          title: id,
          subtitle: subtitle,
          timestamp: ts,
          content: content,
        );

    test('空笔记列表也能生成合法的 Markdown', () {
      final md = buildNotesMarkdown(<UserRecord>[], now: fixedNow);
      expect(md, contains('# STM32 标准库助手 · 笔记导出'));
      expect(md, contains('笔记条数：0'));
      expect(md, contains('（没有笔记）'));
    });

    test('包含标题、时间与条数', () {
      final md = buildNotesMarkdown(
        <UserRecord>[note('GPIO_Init', content: '要点')],
        now: fixedNow,
      );
      expect(md, contains('2026-10-15 15:30'));
      expect(md, contains('笔记条数：1'));
    });

    test('按类型分组，组标题带数量', () {
      final md = buildNotesMarkdown(
        <UserRecord>[
          note('GPIO_Init'),
          note('GPIO_DeInit'),
          note('GPIO_Mode_Out_PP', type: ItemType.symbol),
        ],
        now: fixedNow,
      );
      expect(md, contains('## 函数（2）'));
      expect(md, contains('## 符号（1）'));
      // 没有笔记的类型不该出现
      expect(md, isNot(contains('## 引脚')));
    });

    test('每条含标题、所属分类、标识与正文', () {
      final md = buildNotesMarkdown(
        <UserRecord>[
          note(
            'GPIO_Init',
            subtitle: '通用输入输出',
            content: '中断里必须清标志',
          ),
        ],
        now: fixedNow,
      );
      expect(md, contains('### GPIO_Init'));
      expect(md, contains('- 分类：通用输入输出'));
      expect(md, contains('- 标识：`GPIO_Init`'));
      expect(md, contains('中断里必须清标志'));
    });

    test('内容里的 Markdown 特殊字符原样保留（不做转义，便于用户自己排版）', () {
      const tricky = '要点：\n- 第一点\n- 第二点\n\n```c\nGPIO_Init();\n```';
      final md = buildNotesMarkdown(
        <UserRecord>[note('A', content: tricky)],
        now: fixedNow,
      );
      expect(md, contains('```c'));
      expect(md, contains('- 第一点'));
    });

    test('导出文件名带时间戳', () {
      expect(notesFileName(fixedNow), 'stm32-notes-20261015-1530.md');
    });

    test('导出文件名补零', () {
      expect(
        notesFileName(DateTime(2026, 1, 5, 9, 7)),
        'stm32-notes-20260105-0907.md',
      );
    });
  });

  group('我的页：分组逻辑', () {
    testWidgets('收藏按外设分组时组名取副标题', (tester) async {
      final store = InMemoryUserStore();
      await store.addFavorite(refOf('GPIO_Init', subtitle: 'GPIO'));
      await store.addFavorite(refOf('USART_Init', subtitle: 'USART'));

      final container = makeContainer(store);
      final records = await container.read(favoritesProvider.future);
      expect(records.length, 2);

      // 与 _GroupedList 相同的分组规则：外设类取自身标题，
      // 其余取副标题（空则退化为类型名）
      final groups = <String, int>{};
      for (final r in records) {
        final key = r.type == ItemType.peripheral
            ? r.title
            : (r.subtitle.isEmpty ? r.type.labelZh : r.subtitle);
        groups[key] = (groups[key] ?? 0) + 1;
      }
      expect(groups.keys.toSet(), <String>{'GPIO', 'USART'});
    });

    testWidgets('副标题为空时归到类型名分组', (tester) async {
      final store = InMemoryUserStore();
      await store.addFavorite(refOf('GPIO_Init')); // 无副标题

      final container = makeContainer(store);
      final records = await container.read(favoritesProvider.future);
      final r = records.first;
      final key = r.type == ItemType.peripheral
          ? r.title
          : (r.subtitle.isEmpty ? r.type.labelZh : r.subtitle);
      expect(key, '函数');
    });
  });
}
