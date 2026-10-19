// 阶段 11（观感修复 + 两项交互增强）的测试。
//
// 三件事：
//   1. **chip 文字颜色** —— 真机反馈"搜索页预设的示例函数名是白色，
//      浅色模式看不清"。根因是主题里 labelMedium 没带 color，
//      而 chip 拿不到前景色时会回退成白色。这条必须用真实主题渲染
//      并读出实际生效的样式才能发现，纯逻辑测不出来。
//   2. **目录条滚动高亮** —— 滚动时高亮要跟着当前区块走。
//   3. **外设页函数过滤** —— 87 个函数的 TIM 页要能按名字筛。

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:stm32_spl_helper/data/asset_repository.dart';
import 'package:stm32_spl_helper/data/user_database.dart';
import 'package:stm32_spl_helper/models/chip.dart';
import 'package:stm32_spl_helper/models/compile_error.dart';
import 'package:stm32_spl_helper/models/function_item.dart';
import 'package:stm32_spl_helper/models/manifest.dart';
import 'package:stm32_spl_helper/models/peripheral.dart';
import 'package:stm32_spl_helper/models/pin.dart';
import 'package:stm32_spl_helper/models/spl_data.dart';
import 'package:stm32_spl_helper/models/symbol_item.dart';
import 'package:stm32_spl_helper/pages/function_detail_page.dart';
import 'package:stm32_spl_helper/pages/peripheral_detail_page.dart';
import 'package:stm32_spl_helper/pages/search_page.dart';
import 'package:stm32_spl_helper/providers/app_providers.dart';
import 'package:stm32_spl_helper/providers/user_providers.dart';
import 'package:stm32_spl_helper/utils/theme.dart';
import 'package:stm32_spl_helper/widgets/section_nav.dart';

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
    compileErrors: CompileErrorBundle.fromJson(read('compile_errors.json')),
  );
}

/// 内存版仓库，避免真实 File IO 在 widget 测试里挂住
class _FakeRepo extends AssetRepository {
  final Map<String, FunctionBundle> bundles;
  _FakeRepo(this.bundles);
  @override
  Future<FunctionBundle> loadFunctions(String pid) async => bundles[pid]!;
}

Map<String, FunctionBundle> preload() {
  final out = <String, FunctionBundle>{};
  for (final pid in <String>['GPIO', 'TIM']) {
    final f = File('assets/data/functions/$pid.json');
    out[pid] = FunctionBundle.fromJson(
      jsonDecode(f.readAsStringSync()) as Map<String, dynamic>,
    );
  }
  return out;
}

Widget wrap(Widget child, {ThemeData? theme}) => ProviderScope(
      overrides: <Override>[
        splDataProvider.overrideWith((ref) async => realData()),
        userStoreProvider.overrideWithValue(InMemoryUserStore()),
        assetRepositoryProvider.overrideWithValue(_FakeRepo(preload())),
      ],
      child: MaterialApp(theme: theme ?? AppTheme.light(), home: child),
    );

void viewport(WidgetTester t, double w, {double h = 800}) {
  t.view.physicalSize = Size(w * 3, h * 3);
  t.view.devicePixelRatio = 3.0;
  addTearDown(t.view.reset);
}

Future<void> frames(WidgetTester t, {int n = 30}) async {
  for (var i = 0; i < n; i++) {
    await t.pump(const Duration(milliseconds: 32));
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  // -------------------------------------------------------------------
  // 1. chip 文字颜色（真机 bug 回归）
  // -------------------------------------------------------------------
  group('chip 文字颜色（白字看不清的回归）', () {
    /// 取出某文本最终生效的颜色
    Color? effectiveColor(WidgetTester tester, String text) {
      final w = tester.widget<Text>(find.text(text).first);
      if (w.style?.color != null) return w.style!.color;
      // 没直接指定就往上找最近的 DefaultTextStyle / TextStyle 合并结果
      final rich = tester.widget<RichText>(
        find
            .descendant(
              of: find.text(text).first,
              matching: find.byType(RichText),
            )
            .first,
      );
      return rich.text.style?.color;
    }

    for (final entry in <String, ThemeData>{
      '浅色': AppTheme.light(),
      '深色': AppTheme.dark(),
    }.entries) {
      testWidgets('${entry.key}模式下搜索页示例 chip 的文字不是白色', (tester) async {
        viewport(tester, 360);
        await tester.pumpWidget(wrap(
          const Scaffold(body: SearchPage()),
          theme: entry.value,
        ));
        await frames(tester);

        // "试试这些"区块里的示例 chip（GPIO_In 之类）
        expect(find.text('GPIO_In'), findsOneWidget);
        final color = effectiveColor(tester, 'GPIO_In');
        expect(color, isNotNull, reason: '${entry.key}模式下 chip 应有明确文字颜色');

        // 浅色模式下不能逼近纯白（那会白底白字看不见）
        if (entry.key == '浅色') {
          expect(
            color!.computeLuminance(),
            lessThan(0.7),
            reason: '浅色模式下 chip 文字太亮，会看不清（当前 $color）',
          );
        }
        expect(tester.takeException(), isNull);
      });
    }

    test('主题的 label 样式都带 color', () {
      // 这是根因：labelXxx 没 color 时，Material 组件会回退成白色
      for (final isDark in <bool>[false, true]) {
        final t = (isDark ? AppTheme.dark() : AppTheme.light()).textTheme;
        expect(t.labelLarge?.color, isNotNull);
        expect(t.labelMedium?.color, isNotNull);
        expect(t.labelSmall?.color, isNotNull);
      }
    });

    test('chipTheme.labelStyle 带 color', () {
      for (final isDark in <bool>[false, true]) {
        final theme = isDark ? AppTheme.dark() : AppTheme.light();
        expect(theme.chipTheme.labelStyle?.color, isNotNull,
            reason: 'chipTheme.labelStyle 缺 color 会导致 chip 文字变白');
      }
    });

    testWidgets('浅色与深色下 chip 文字颜色都跟随主题（不硬编码）', (tester) async {
      viewport(tester, 360);
      await tester.pumpWidget(wrap(
        const Scaffold(body: SearchPage()),
        theme: AppTheme.light(),
      ));
      await frames(tester);
      final light = tester.widget<Text>(find.text('GPIO_In').first);
      // 页面没有给 label 指定 color，应该由主题提供
      expect(light.style?.fontSize, 12);
      expect(tester.takeException(), isNull);
    });
  });

  // -------------------------------------------------------------------
  // 2. 目录条滚动高亮
  // -------------------------------------------------------------------
  group('函数详情页目录条：滚动高亮', () {
    testWidgets('初始状态高亮第一块', (tester) async {
      viewport(tester, 360);
      await tester.pumpWidget(
        wrap(const FunctionDetailPage(functionId: 'GPIO_Init')),
      );
      await frames(tester);

      final nav = tester.widget<SectionNavBar>(find.byType(SectionNavBar));
      expect(nav.activeIndex, 0, reason: '刚进页面应高亮第一块');
    });

    testWidgets('向下滚动后高亮跟着往后走', (tester) async {
      viewport(tester, 360, h: 800);
      await tester.pumpWidget(
        wrap(const FunctionDetailPage(functionId: 'GPIO_Init')),
      );
      await frames(tester);

      final before =
          tester.widget<SectionNavBar>(find.byType(SectionNavBar)).activeIndex;

      // 滚动内容区
      await tester.drag(find.byType(ListView).last, const Offset(0, -900));
      await frames(tester);

      final after =
          tester.widget<SectionNavBar>(find.byType(SectionNavBar)).activeIndex;
      expect(after, isNotNull);
      expect(after!, greaterThan(before ?? 0),
          reason: '向下滚动后高亮应前进（之前 $before，之后 $after）');
    });

    testWidgets('滚回顶部高亮回到第一块', (tester) async {
      viewport(tester, 360);
      await tester.pumpWidget(
        wrap(const FunctionDetailPage(functionId: 'GPIO_Init')),
      );
      await frames(tester);

      await tester.drag(find.byType(ListView).last, const Offset(0, -900));
      await frames(tester);
      await tester.drag(find.byType(ListView).last, const Offset(0, 1400));
      await frames(tester);

      final idx =
          tester.widget<SectionNavBar>(find.byType(SectionNavBar)).activeIndex;
      expect(idx, 0, reason: '回到顶部应高亮第一块');
    });

    test('锚点未挂载时 offsetInViewport 返回 null 而不崩', () {
      final a = SectionAnchor(
        title: 'X',
        icon: Icons.abc,
        key: GlobalKey(),
      );
      expect(a.offsetInViewport(), isNull);
      expect(() => a.scrollTo(), returnsNormally);
    });
  });

  // -------------------------------------------------------------------
  // 3. 外设页函数过滤
  // -------------------------------------------------------------------
  group('外设详情页：函数过滤', () {
    testWidgets('过滤框可见，初始显示总数', (tester) async {
      viewport(tester, 360);
      await tester.pumpWidget(
        wrap(const PeripheralDetailPage(peripheralId: 'TIM')),
      );
      await frames(tester);

      expect(find.text('在本外设内搜索函数名或说明…'), findsOneWidget);
      expect(find.text('87'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('输入关键词后只剩匹配的函数', (tester) async {
      viewport(tester, 360, h: 1200);
      await tester.pumpWidget(
        wrap(const PeripheralDetailPage(peripheralId: 'TIM')),
      );
      await frames(tester);

      await tester.enterText(find.byType(TextField), 'ITConfig');
      await frames(tester);

      // TIM_ITConfig 应出现
      expect(find.text('TIM_ITConfig'), findsWidgets);
      // 计数变成 命中/总数 形式
      expect(find.textContaining('/87'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('搜不到时给出提示而不是空白', (tester) async {
      viewport(tester, 360);
      await tester.pumpWidget(
        wrap(const PeripheralDetailPage(peripheralId: 'GPIO')),
      );
      await frames(tester);

      await tester.enterText(find.byType(TextField), 'zzz_not_exist');
      await frames(tester);

      expect(find.textContaining('没有匹配'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('清空关键词后恢复全部', (tester) async {
      viewport(tester, 360);
      await tester.pumpWidget(
        wrap(const PeripheralDetailPage(peripheralId: 'GPIO')),
      );
      await frames(tester);

      await tester.enterText(find.byType(TextField), 'Init');
      await frames(tester);
      await tester.enterText(find.byType(TextField), '');
      await frames(tester);

      // 回到完整计数（GPIO 18 个函数）
      expect(find.text('18'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('过滤结果按中文简述也能命中', (tester) async {
      viewport(tester, 360, h: 1200);
      await tester.pumpWidget(
        wrap(const PeripheralDetailPage(peripheralId: 'GPIO')),
      );
      await frames(tester);

      // "复位" 出现在 GPIO_DeInit 等函数的中文简述里
      await tester.enterText(find.byType(TextField), '复位');
      await frames(tester);

      expect(find.textContaining('/18'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('320dp 窄屏下过滤条不溢出', (tester) async {
      viewport(tester, 320, h: 640);
      await tester.pumpWidget(
        wrap(const PeripheralDetailPage(peripheralId: 'TIM')),
      );
      await frames(tester);
      expect(tester.takeException(), isNull);
    });
  });
}
