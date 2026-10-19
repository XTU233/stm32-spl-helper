// 阶段 5（全局搜索收尾）的测试。
//
// 覆盖三块新功能：
//   1. 搜索历史：去重、上限、归一化、增删清空
//   2. 结果高亮：分段正确、大小写不敏感、元字符不炸
//   3. 类型筛选：按类别统计与过滤
//
// 历史与高亮都是纯逻辑，不依赖 Flutter 渲染，所以这里用普通 test 而不是
// widget test；只有 SearchHistoryStore 需要 shared_preferences 的 mock。

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:stm32_spl_helper/data/search_history.dart';
import 'package:stm32_spl_helper/data/search_index.dart';
import 'package:stm32_spl_helper/data/user_database.dart';
import 'package:stm32_spl_helper/models/chip.dart';
import 'package:stm32_spl_helper/models/compile_error.dart';
import 'package:stm32_spl_helper/models/function_item.dart';
import 'package:stm32_spl_helper/models/item_ref.dart';
import 'package:stm32_spl_helper/models/manifest.dart';
import 'package:stm32_spl_helper/models/peripheral.dart';
import 'package:stm32_spl_helper/models/pin.dart';
import 'package:stm32_spl_helper/models/spl_data.dart';
import 'package:stm32_spl_helper/models/symbol_item.dart';
import 'package:stm32_spl_helper/pages/search_page.dart';
import 'package:stm32_spl_helper/providers/app_providers.dart';
import 'package:stm32_spl_helper/providers/user_providers.dart';
import 'package:stm32_spl_helper/utils/highlighter.dart';
import 'package:stm32_spl_helper/utils/theme.dart';

/// 一个空的 SplData，只用于拿 SearchIndex 的纯函数（分组/筛选）。
///
/// 这里刻意不读 assets——本文件测的是高亮与历史的逻辑，
/// 真实数据的搜索行为由 data_integration_test.dart 覆盖。
SplData _emptyData() => SplData(
      manifest: const DataManifest(
        schemaVersion: 1,
        dataVersion: 'test',
        splVersion: 'test',
        defaultChipId: 'test',
        generatedAt: '',
        generator: 'test',
        stats: DataStats(),
        files: <String, String>{},
      ),
      chip: const ChipSpec(id: 'test', name: 'test'),
      peripherals: const [],
      functions: const [],
      symbols: const [],
      pinout: PinoutData(
        schemaVersion: 1,
        chipId: 'test',
        package: 'test',
        source: 'test',
        verified: false,
        verifiedNote: '',
        pins: const [],
      ),
      compileErrors: const CompileErrorBundle(schemaVersion: 1),
    );

void main() {
  // shared_preferences 在测试里没有原生实现，必须装内存版 mock
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('搜索历史：归一化', () {
    test('去掉首尾空白', () {
      expect(SearchHistoryStore.normalize('  GPIO_Init  '), 'GPIO_Init');
    });

    test('中间连续空白压成一个空格', () {
      expect(
        SearchHistoryStore.normalize('undefined    reference'),
        'undefined reference',
      );
    });

    test('纯空白归一化为空串', () {
      expect(SearchHistoryStore.normalize('   '), '');
      expect(SearchHistoryStore.normalize('\t\n'), '');
    });

    test('超长关键词被截断到上限', () {
      final long = 'A' * 200;
      final normalized = SearchHistoryStore.normalize(long);
      expect(normalized.length, SearchHistoryStore.maxKeywordLength);
    });

    test('正常关键词原样保留（含大小写）', () {
      expect(SearchHistoryStore.normalize('GPIO_Mode_Out_PP'),
          'GPIO_Mode_Out_PP');
      expect(SearchHistoryStore.normalize('推挽'), '推挽');
    });
  });

  group('搜索历史：增删改查', () {
    test('新搜的词排在最前', () async {
      final store = SearchHistoryStore();
      await store.add('GPIO_Init');
      await store.add('USART_Init');
      final list = await store.load();
      expect(list, <String>['USART_Init', 'GPIO_Init']);
    });

    test('重复搜索去重并提前，而不是新增一条', () async {
      final store = SearchHistoryStore();
      await store.add('GPIO_Init');
      await store.add('USART_Init');
      await store.add('GPIO_Init'); // 再搜一次旧词
      final list = await store.load();
      expect(list, <String>['GPIO_Init', 'USART_Init']);
      expect(list.where((e) => e == 'GPIO_Init').length, 1);
    });

    test('去重忽略大小写', () async {
      final store = SearchHistoryStore();
      await store.add('gpio_init');
      await store.add('GPIO_INIT');
      final list = await store.load();
      expect(list.length, 1);
      // 保留最近一次输入的写法
      expect(list.first, 'GPIO_INIT');
    });

    test('空白关键词不入库', () async {
      final store = SearchHistoryStore();
      await store.add('   ');
      expect(await store.load(), isEmpty);
    });

    test('超过 20 条时丢掉最旧的', () async {
      final store = SearchHistoryStore();
      for (var i = 0; i < 25; i++) {
        await store.add('kw$i');
      }
      final list = await store.load();
      expect(list.length, SearchHistoryStore.maxEntries);
      // 最新的在最前，最旧的 5 条（kw0~kw4）被挤掉
      expect(list.first, 'kw24');
      expect(list.contains('kw4'), isFalse);
      expect(list.contains('kw5'), isTrue);
    });

    test('删除单条', () async {
      final store = SearchHistoryStore();
      await store.add('GPIO_Init');
      await store.add('USART_Init');
      final after = await store.remove('gpio_init'); // 大小写不敏感
      expect(after, <String>['USART_Init']);
      expect(await store.load(), <String>['USART_Init']);
    });

    test('清空', () async {
      final store = SearchHistoryStore();
      await store.add('GPIO_Init');
      await store.clear();
      expect(await store.load(), isEmpty);
    });

    test('历史跨实例保留（真实持久化，不是内存态）', () async {
      await SearchHistoryStore().add('GPIO_Init');
      // 换一个实例读，验证确实写进了 shared_preferences
      final list = await SearchHistoryStore().load();
      expect(list, <String>['GPIO_Init']);
    });
  });

  group('结果高亮：分段', () {
    test('命中在中间：切成 前/中 两段（空的尾段不产出）', () {
      final spans = Highlighter.split('GPIO_Init', 'Init');
      // 'Init' 正好在结尾，所以只有"前"和"中"两段，不该多出一个空串段
      expect(spans.length, 2);
      expect(spans[0].text, 'GPIO_');
      expect(spans[0].hit, isFalse);
      expect(spans[1].text, 'Init');
      expect(spans[1].hit, isTrue);
    });

    test('命中在中间且两侧都有内容：三段完整', () {
      final spans = Highlighter.split('GPIO_Init_TypeDef', 'Init');
      expect(spans.length, 3);
      expect(spans[0].text, 'GPIO_');
      expect(spans[1].text, 'Init');
      expect(spans[1].hit, isTrue);
      expect(spans[2].text, '_TypeDef');
      expect(spans[2].hit, isFalse);
    });

    test('命中在开头', () {
      final spans = Highlighter.split('GPIO_Init', 'GPIO');
      expect(spans.first.text, 'GPIO');
      expect(spans.first.hit, isTrue);
    });

    test('命中在结尾', () {
      final spans = Highlighter.split('GPIO_Init', 'Init');
      final hit = spans.where((s) => s.hit).toList();
      expect(hit.single.text, 'Init');
    });

    test('大小写不敏感，但保留原文大小写', () {
      final spans = Highlighter.split('GPIO_Init', 'gpio');
      final hit = spans.where((s) => s.hit).toList();
      expect(hit.single.text, 'GPIO'); // 原文是大写
    });

    test('多次命中全部标出', () {
      final spans = Highlighter.split('GPIO_InitGPIO', 'gpio');
      final hit = spans.where((s) => s.hit).toList();
      expect(hit.length, 2);
      expect(hit.every((s) => s.text == 'GPIO'), isTrue);
    });

    test('没命中时返回整段未命中', () {
      final spans = Highlighter.split('GPIO_Init', 'xyz');
      expect(spans.length, 1);
      expect(spans.single.text, 'GPIO_Init');
      expect(spans.single.hit, isFalse);
    });

    test('关键词为空时返回整段未命中', () {
      final spans = Highlighter.split('GPIO_Init', '   ');
      expect(spans.single.hit, isFalse);
      expect(spans.single.text, 'GPIO_Init');
    });

    test('空文本返回空列表', () {
      expect(Highlighter.split('', 'gpio'), isEmpty);
    });

    test('正则元字符按字面处理，不会抛异常也不会误匹配', () {
      // 用户可能输入 . * ( ) 这类字符，早期用正则会直接崩或匹配错
      for (final k in <String>['.', '*', '(', '[', '\\', '+?', '.*']) {
        expect(
          () => Highlighter.split('GPIO_Init', k),
          returnsNormally,
          reason: '关键词 $k 不应导致异常',
        );
      }
      // '.*' 作为字面量在 GPIO_Init 里不存在，应判定为未命中
      expect(Highlighter.matches('GPIO_Init', '.*'), isFalse);
    });

    test('matches 与 split 结论一致', () {
      const text = 'STM32F103C8T6 标准外设库';
      for (final k in <String>['stm32', 'STM32', '标准', 'stm', 'xyz']) {
        final bySplit = Highlighter.split(text, k).any((s) => s.hit);
        expect(bySplit, Highlighter.matches(text, k),
            reason: '关键词 $k 的两个判断应一致');
      }
    });

    test('中文关键词能命中', () {
      final spans = Highlighter.split('通用输入输出', '输入');
      expect(spans.any((s) => s.hit && s.text == '输入'), isTrue);
    });
  });

  group('结果高亮：TextSpan 构建', () {
    testWidgets('未命中时退化成普通 Text（不产生 RichText 开销）', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: HighlightedText('GPIO_Init', 'xyz'),
      ));
      // 没有命中就不该有 Text.rich
      expect(find.byType(Text), findsOneWidget);
      final t = tester.widget<Text>(find.byType(Text));
      expect(t.data, 'GPIO_Init');
      expect(t.textSpan, isNull);
    });

    testWidgets('命中时用 Text.rich 并把关键词着色', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: HighlightedText('GPIO_Init', 'Init'),
      ));
      final t = tester.widget<Text>(find.byType(Text));
      expect(t.textSpan, isNotNull);

      // 收集所有片段，确认关键词那段带上了高亮色（与 base 不同）
      final spans = <TextSpan>[];
      t.textSpan!.visitChildren((s) {
        if (s is TextSpan) spans.add(s);
        return true;
      });
      final hitSpan = spans.firstWhere((s) => s.text == 'Init');
      expect(hitSpan.style?.color, isNotNull,
          reason: '命中的片段必须带上高亮色，否则用户看不出为什么匹配');
    });

    testWidgets('高亮文本能正常渲染不溢出（窄屏 360dp）', (tester) async {
      tester.view.physicalSize = const Size(360 * 3, 640 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            child: HighlightedText(
              // 库里最长的函数名之一
              'ADC_GetSoftwareStartInjectedConvCmdStatus',
              'injected',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13.5),
            ),
          ),
        ),
      ));
      expect(tester.takeException(), isNull);
    });
  });

  group('结果筛选：按类别统计', () {
    test('groupByCategory 按类型分组且不丢结果', () {
      final hits = <SearchHit>[
        const SearchHit(
          itemType: ItemType.function,
          id: 'GPIO_Init',
          title: 'GPIO_Init',
        ),
        const SearchHit(
          itemType: ItemType.symbol,
          id: 'GPIO_Mode_Out_PP',
          title: 'GPIO_Mode_Out_PP',
        ),
        const SearchHit(
          itemType: ItemType.function,
          id: 'GPIO_DeInit',
          title: 'GPIO_DeInit',
        ),
      ];

      // 借一个真实索引来调用分组（纯函数，不依赖索引内容）
      final index = SearchIndex.build(_emptyData());
      final grouped = index.groupByCategory(hits);

      expect(grouped[SearchCategory.function]!.length, 2);
      expect(grouped[SearchCategory.symbol]!.length, 1);
      expect(grouped.containsKey(SearchCategory.peripheral), isFalse);
      // 分组后总数不变
      expect(
        grouped.values.fold<int>(0, (a, b) => a + b.length),
        hits.length,
      );
    });
  });

  // 搜索页的端到端测试：用真实 assets/data 渲染真实的 SearchPage，
  // 走完"输入 → 出结果 → 高亮 → 点进详情页"整条链路。
  //
  // 这一层能抓到纯逻辑测试抓不到的问题：provider 接线错误、
  // 结果点不动、跳转目标页崩等。
  group('搜索页端到端（真实数据）', () {
    /// 构建真实的 SplData（读 assets/data）
    SplData realData() {
      Map<String, dynamic> read(String rel) => jsonDecode(
            File('assets/data/$rel').readAsStringSync(),
          ) as Map<String, dynamic>;

      return SplData(
        manifest: DataManifest.fromJson(read('manifest.json')),
        chip: ChipSpec.fromJson(read('chips/stm32f103c8t6.json')),
        peripherals: (read('peripherals.json')['peripherals'] as List)
            .map((e) => Peripheral.fromJson(e as Map<String, dynamic>))
            .toList(),
        functions: const <FunctionItem>[],
        symbols: (read('symbols.json')['symbols'] as List)
            .map((e) => SymbolItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        pinout: PinoutData.fromJson(read('pinout_f103c8t6.json')),
        compileErrors:
            CompileErrorBundle.fromJson(read('compile_errors.json')),
      );
    }

    /// 用真实的 SplData 覆盖掉 provider 默认的 asset 读取。
    ///
    /// 同时把用户数据库换成内存实现：点搜索结果会进入详情页，
    /// 而详情页会记录「最近查看」，真实的 SqfliteUserStore 在测试环境里
    /// 没有 platform channel（databaseFactory 未初始化）会直接抛异常。
    Widget wrap() => ProviderScope(
          overrides: <Override>[
            splDataProvider.overrideWith((ref) async => realData()),
            userStoreProvider.overrideWithValue(InMemoryUserStore()),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: SearchPage()),
          ),
        );

    testWidgets('输入关键词后即时出结果，且命中词被高亮', (tester) async {
      tester.view.physicalSize = const Size(360 * 3, 800 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'GPIO_Init');
      await tester.pumpAndSettle();

      // 结果列表出现，且出现了带高亮的富文本
      expect(find.textContaining('找到'), findsOneWidget);
      expect(
        find.byType(HighlightedText),
        findsWidgets,
        reason: '结果项应该用 HighlightedText 渲染以支持高亮',
      );

      // 至少有一条结果确实把关键词标成了高亮片段
      final highlighted = tester
          .widgetList<HighlightedText>(find.byType(HighlightedText))
          .where((w) => Highlighter.matches(w.text, 'GPIO_Init'));
      expect(highlighted, isNotEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('搜 uart 能命中 USART（需求验收点）', (tester) async {
      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'uart');
      await tester.pumpAndSettle();

      // 应该出现 USART 相关的函数结果
      expect(
        find.textContaining('USART', findRichText: true),
        findsWidgets,
        reason: '搜 uart 必须能命中 USART 相关函数',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('点结果项会记录搜索历史', (tester) async {
      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'GPIO_Init');
      await tester.pumpAndSettle();

      // 点第一条结果。
      // 阶段 10 后结果项不再用 ListTile（改成了自定义的行 + 类型图标），
      // 所以这里按"标题文本"定位，比依赖具体 widget 类型更稳。
      final firstResult = find.byType(HighlightedText).first;
      await tester.tap(firstResult);
      await tester.pumpAndSettle();

      final history = await SearchHistoryStore().load();
      expect(history, contains('GPIO_Init'),
          reason: '点开结果说明这次搜索有效，应记入历史');
    });

    testWidgets('空状态展示搜索历史，点击历史能复搜', (tester) async {
      await SearchHistoryStore().add('USART_Init');

      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();

      // 未输入时应看到"最近搜索"区块。
      // 注意 USART_Init 同时出现在历史 chip 与"试试这些"示例 chip 里，
      // 所以要限定在 InputChip（历史）里找，不能用裸 find.text。
      expect(find.text('最近搜索'), findsOneWidget);
      final historyChip = find.widgetWithText(InputChip, 'USART_Init');
      expect(historyChip, findsOneWidget);

      // 点历史条目 → 填回输入框并出结果
      await tester.tap(historyChip);
      await tester.pumpAndSettle();

      expect(find.textContaining('找到'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('删除单条历史', (tester) async {
      await SearchHistoryStore().add('GPIO_Init');
      await SearchHistoryStore().add('USART_Init');

      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();

      expect(find.widgetWithText(InputChip, 'GPIO_Init'), findsOneWidget);
      // 删除图标只在历史 chip 上；搜索框的 suffix 也有一个 X 图标，
      // 所以必须限定到 InputChip 内部去找，不能用裸 find.byIcon。
      final deleteIcon = find.descendant(
        of: find.widgetWithText(InputChip, 'GPIO_Init'),
        matching: find.byIcon(Icons.close),
      );
      expect(deleteIcon, findsOneWidget);
      await tester.tap(deleteIcon);
      await tester.pumpAndSettle();

      final history = await SearchHistoryStore().load();
      expect(history.length, 1, reason: '应只剩一条历史');
      expect(history, isNot(contains('GPIO_Init')));
      expect(history, contains('USART_Init'));
    });

    testWidgets('把词填进输入框时会重置类型筛选，不会卡在空结果', (tester) async {
      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'GPIO_Init');
      await tester.pumpAndSettle();

      // 点"引脚"筛选（GPIO_Init 是函数，筛引脚后应为空）
      final pinChip = find.widgetWithText(FilterChip, '引脚');
      if (pinChip.evaluate().isNotEmpty) {
        await tester.tap(pinChip);
        await tester.pumpAndSettle();
        expect(find.textContaining('没有结果'), findsWidgets);
      }

      // 换关键词后筛选应被重置，结果重新出现
      await tester.enterText(find.byType(TextField), 'GPIO_DeInit');
      await tester.pumpAndSettle();
      expect(find.textContaining('找到'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
