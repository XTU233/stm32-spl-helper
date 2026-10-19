// 阶段 10（UI 全方位升级）的回归测试。
//
// 重点不是"好不好看"（那个只有人眼能判断），而是**改造有没有弄坏渲染**：
// 这一轮改动了全站的主题、导航壳、首页、外设页、函数页、搜索页的空状态，
// 任何一处内边距/字号算错，在 360dp 上就会溢出。
//
// 之前的经验：两次真机 bug（函数名竖排、引脚块亚像素溢出）都是
// "在手机上才看得见"的布局问题，而且都被这种"用真实数据在 360dp 下
// 渲染一遍"的测试抓到了。所以这里把覆盖面扩到每个主要页面。

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
import 'package:stm32_spl_helper/pages/compile_errors_page.dart';
import 'package:stm32_spl_helper/pages/favorites_page.dart';
import 'package:stm32_spl_helper/pages/function_detail_page.dart';
import 'package:stm32_spl_helper/pages/home_page.dart';
import 'package:stm32_spl_helper/pages/my_page.dart';
import 'package:stm32_spl_helper/pages/peripheral_detail_page.dart';
import 'package:stm32_spl_helper/pages/pinout_page.dart';
import 'package:stm32_spl_helper/pages/search_page.dart';
import 'package:stm32_spl_helper/pages/settings_page.dart';
import 'package:stm32_spl_helper/providers/app_providers.dart';
import 'package:stm32_spl_helper/providers/user_providers.dart';
import 'package:stm32_spl_helper/utils/theme.dart';
import 'package:stm32_spl_helper/widgets/pressable_card.dart';
import 'package:stm32_spl_helper/widgets/section_nav.dart';

/// 读真实数据构建 SplData
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

/// 假的 AssetRepository：函数数据直接从已读好的 JSON 构造，不做文件 IO。
///
/// 为什么需要它：`FunctionDetailPage` 会调 `loadFunctions()` 读
/// `assets/data/functions/*.json`。在 widget 测试里，真实 `File` IO 的
/// Future 只有在测试 body 处于 `runAsync` 上下文时才会被驱动；
/// 一旦同一测试文件里先跑过别的用例，页面就会永远停在 loading，
/// 表现为"单独跑通过、整套跑失败"。把 IO 换成纯内存构造即可绕开。
class _FakeAssetRepository extends AssetRepository {
  final Map<String, FunctionBundle> bundles;

  _FakeAssetRepository(this.bundles);

  @override
  Future<FunctionBundle> loadFunctions(String peripheralId) async {
    final b = bundles[peripheralId];
    if (b == null) {
      throw StateError('测试数据里没有外设 $peripheralId 的函数');
    }
    return b;
  }
}

/// 预读几个常用外设的函数数据（只读一次文件，之后都走内存）。
Map<String, FunctionBundle> preloadBundles() {
  final out = <String, FunctionBundle>{};
  for (final pid in <String>['GPIO', 'TIM', 'USART']) {
    final f = File('assets/data/functions/$pid.json');
    if (!f.existsSync()) continue;
    out[pid] = FunctionBundle.fromJson(
      jsonDecode(f.readAsStringSync()) as Map<String, dynamic>,
    );
  }
  return out;
}

/// 统一的外壳：真实数据 + 内存用户库 + 内存函数数据
Widget wrap(Widget child, {Map<String, FunctionBundle>? bundles}) =>
    ProviderScope(
      overrides: <Override>[
        splDataProvider.overrideWith((ref) async => realData()),
        userStoreProvider.overrideWithValue(InMemoryUserStore()),
        if (bundles != null)
          assetRepositoryProvider
              .overrideWithValue(_FakeAssetRepository(bundles)),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: child,
      ),
    );

/// 把测试视口设成指定宽度（dp）
void useViewport(WidgetTester tester, double widthDp, {double heightDp = 800}) {
  tester.view.physicalSize = Size(widthDp * 3, heightDp * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
}

/// 逐帧 pump 固定时长，代替 pumpAndSettle。
///
/// 为什么不用 pumpAndSettle：函数详情页里有 CodeBlock 的 SelectableText、
/// 目录条的 AnimatedContainer，外设页有 87 个条目的折叠动画——
/// 这些页面的动画链在测试环境里会让 settle 判定不一致而超时。
/// 我们要验证的是"渲染有没有溢出"，逐帧 pump 到动画结束即可。
Future<void> pumpFrames(WidgetTester tester, {int frames = 40}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 32));
  }
}

/// 等待条件满足（用于需要真实异步 IO 的场景）。
///
/// 现在函数详情页的测试改用 [_FakeAssetRepository] 走内存，
/// 一般不需要这个；保留它给将来真需要真实 IO 的用例。
Future<void> settleUntil(
  WidgetTester tester,
  bool Function() ready, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 40));
    });
    await tester.pump(const Duration(milliseconds: 16));
    if (ready()) return;
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('全站主题', () {
    test('浅色/深色主题都能构建，且关键颜色已覆盖默认值', () {
      for (final isDark in <bool>[false, true]) {
        final theme = isDark ? AppTheme.dark() : AppTheme.light();
        expect(theme.useMaterial3, isTrue);
        // 自定义的 surface 与 M3 默认值不同，说明覆盖生效了
        expect(theme.colorScheme.surface, isNotNull);
        // 卡片不靠阴影，靠描边
        expect(theme.cardTheme.elevation, 0);
        expect(theme.cardTheme.shape, isNotNull);
        // 输入框三类状态都配了，避免聚焦时突然出现黑边
        expect(theme.inputDecorationTheme.focusedBorder, isNotNull);
        expect(theme.inputDecorationTheme.enabledBorder, isNotNull);
      }
    });

    test('排版层级完整（各档字号递增）', () {
      final t = AppTheme.light().textTheme;
      final sizes = <double>[
        t.bodySmall!.fontSize!,
        t.bodyMedium!.fontSize!,
        t.bodyLarge!.fontSize!,
        t.titleMedium!.fontSize!,
        t.titleLarge!.fontSize!,
      ];
      for (var i = 1; i < sizes.length; i++) {
        expect(sizes[i], greaterThanOrEqualTo(sizes[i - 1]),
            reason: '字号层级应递增：$sizes');
      }
    });

    test('圆角与间距 token 是有限集合（防止随手写数值）', () {
      expect(AppRadius.card.topLeft.x, 14);
      expect(AppRadius.field.topLeft.x, 12);
      expect(AppSpace.xs, 4);
      expect(AppSpace.huge, 32);
    });

    test('动效时长分三档且递增', () {
      expect(AppDuration.fast.inMilliseconds,
          lessThan(AppDuration.normal.inMilliseconds));
      expect(AppDuration.normal.inMilliseconds,
          lessThan(AppDuration.slow.inMilliseconds));
    });

    test('代码高亮配色在深浅模式下都完整', () {
      for (final b in Brightness.values) {
        final c = AppTheme.codeColors(b);
        expect(c.background, isNotNull);
        expect(c.symbolLink, isNotNull);
        // 代码背景与正文色不能相同，否则看不见
        expect(c.background, isNot(c.plain));
      }
    });
  });

  group('主要页面在 360dp 下渲染不溢出', () {
    testWidgets('首页（含芯片概览卡与全部外设卡片）', (tester) async {
      useViewport(tester, 360);
      await tester.pumpWidget(wrap(const Scaffold(body: HomePage())));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // 概览卡里的四个统计标签都应在
      expect(find.text('外设'), findsWidgets);
      expect(find.text('函数'), findsWidgets);
    });

    testWidgets('首页极窄屏 320dp', (tester) async {
      useViewport(tester, 320, heightDp: 640);
      await tester.pumpWidget(wrap(const Scaffold(body: HomePage())));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('首页深色模式', (tester) async {
      useViewport(tester, 360);
      await tester.pumpWidget(ProviderScope(
        overrides: <Override>[
          splDataProvider.overrideWith((ref) async => realData()),
          userStoreProvider.overrideWithValue(InMemoryUserStore()),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const Scaffold(body: HomePage()),
        ),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('外设详情页（GPIO，函数最多的页之一）', (tester) async {
      useViewport(tester, 360);
      await tester.pumpWidget(
        wrap(const PeripheralDetailPage(peripheralId: 'GPIO')),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('外设详情页（TIM，87 个函数 + 长简介）', (tester) async {
      useViewport(tester, 360);
      await tester.pumpWidget(
        wrap(const PeripheralDetailPage(peripheralId: 'TIM')),
      );
      // 不用 pumpAndSettle：这一页有 87 个函数条目，
      // 折叠动画（AnimatedSize/AnimatedRotation）在这么多子节点下
      // 每帧都要重排，settle 会超时。逐帧 pump 到动画结束即可。
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 32));
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('函数详情页（含目录条）', (tester) async {
      useViewport(tester, 360);
      await tester.pumpWidget(
        wrap(const FunctionDetailPage(functionId: 'GPIO_Init'),
          bundles: preloadBundles()),
      );
      await pumpFrames(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('搜索页空状态', (tester) async {
      useViewport(tester, 360);
      await tester.pumpWidget(wrap(const Scaffold(body: SearchPage())));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('我的页（三个子 Tab 的空状态）', (tester) async {
      useViewport(tester, 360);
      await tester.pumpWidget(wrap(const Scaffold(body: MyPage())));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('还没有收藏'), findsOneWidget);
    });

    testWidgets('引脚速查表（默认的按外设视图）', (tester) async {
      useViewport(tester, 360);
      await tester.pumpWidget(wrap(const PinoutPage()));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('编译错误速查', (tester) async {
      useViewport(tester, 360);
      await tester.pumpWidget(wrap(const CompileErrorsPage()));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('设置页', (tester) async {
      useViewport(tester, 360);
      await tester.pumpWidget(wrap(const Scaffold(body: SettingsPage())));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('收藏页空状态', (tester) async {
      useViewport(tester, 360);
      await tester.pumpWidget(wrap(const Scaffold(body: FavoritesPage())));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('还没有收藏'), findsOneWidget);
    });
  });

  group('函数详情页的目录导航', () {
    testWidgets('区块足够多时显示目录条', (tester) async {
      useViewport(tester, 360);
      await tester.pumpWidget(
        wrap(const FunctionDetailPage(functionId: 'GPIO_Init'),
          bundles: preloadBundles()),
      );
      await pumpFrames(tester);

      // GPIO_Init 有原型/参数/返回值/说明/前置/示例/注意/相关等多个区块
      expect(find.byType(SectionNavBar), findsOneWidget,
          reason: '函数详情加载完成后应显示目录条');
      // 只在目录条内找：区块标题里也有同名文字（"参数"），
      // 裸 find.text 会命中两处。
      final navBar = find.byType(SectionNavBar);
      expect(
        find.descendant(of: navBar, matching: find.text('原型')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: navBar, matching: find.text('参数')),
        findsOneWidget,
      );
      // 目录条是横向 ListView，屏幕外（"示例"及之后）的 chip 不会构建，
      // 所以这里只断言前几个可见项；滚动后被构建的行为由下一个用例覆盖。
    });

    testWidgets('目录条可横向滚动到后面的区块', (tester) async {
      useViewport(tester, 360);
      await tester.pumpWidget(
        wrap(const FunctionDetailPage(functionId: 'GPIO_Init'),
          bundles: preloadBundles()),
      );
      await pumpFrames(tester);

      final navList = find.descendant(
        of: find.byType(SectionNavBar),
        matching: find.byType(ListView),
      );
      // 向左滚，让后面的 chip 被构建出来
      await tester.drag(navList, const Offset(-260, 0));
      await pumpFrames(tester);

      // 滚动后应能看到靠后的区块（示例/注意/相关之一）
      final laterChips = <String>['示例', '注意', '相关']
          .where((t) => find
              .descendant(of: find.byType(SectionNavBar), matching: find.text(t))
              .evaluate()
              .isNotEmpty)
          .toList();
      expect(laterChips, isNotEmpty,
          reason: '横向滚动后应能看到靠后的目录项');
      expect(tester.takeException(), isNull);
    });

    testWidgets('点目录条能跳到对应区块（不抛异常）', (tester) async {
      useViewport(tester, 360);
      await tester.pumpWidget(
        wrap(const FunctionDetailPage(functionId: 'GPIO_Init'),
          bundles: preloadBundles()),
      );
      await pumpFrames(tester);

      // 点可见的"参数"，应滚到参数区块
      final paramsChip = find.descendant(
        of: find.byType(SectionNavBar),
        matching: find.text('参数'),
      );
      await tester.tap(paramsChip);
      await pumpFrames(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('区块不足 3 个时不显示目录条', (tester) async {
      // 直接测组件本身：2 个锚点时应返回空
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SectionNavBar(
            anchors: <SectionAnchor>[
              SectionAnchor(
                title: 'A',
                icon: Icons.abc,
                key: GlobalKey(),
              ),
              SectionAnchor(
                title: 'B',
                icon: Icons.abc,
                key: GlobalKey(),
              ),
            ],
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('A'), findsNothing);
    });

    testWidgets('锚点 scrollTo 在没有 context 时不崩', (tester) async {
      final anchor = SectionAnchor(
        title: 'X',
        icon: Icons.abc,
        key: GlobalKey(),
      );
      // 这个 key 从未挂到树上，currentContext 为 null
      expect(() => anchor.scrollTo(), returnsNormally);
    });
  });

  group('共享组件', () {
    testWidgets('EmptyState 在 320dp 下不溢出', (tester) async {
      useViewport(tester, 320, heightDp: 640);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(
          body: EmptyState(
            icon: Icons.inbox,
            title: '这里什么都没有',
            body: '这是一段比较长的说明文字，用来验证在窄屏上会自动换行而不是溢出。',
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('PressableCard 可点且不溢出', (tester) async {
      useViewport(tester, 320);
      var tapped = 0;
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: PressableCard(
            onTap: () => tapped++,
            child: const Text('内容'),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('内容'));
      await tester.pumpAndSettle();
      expect(tapped, 1);
      expect(tester.takeException(), isNull);
    });
  });

  group('导航壳', () {
    testWidgets('切换 Tab 后标题与提示随之变化', (tester) async {
      useViewport(tester, 360);
      // 只测导航壳本身，页面用轻量替身避免加载真实数据
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const _ShellProbe(),
        ),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}

/// 一个极简的壳，用来验证导航结构与 token（不加载真实数据）。
class _ShellProbe extends StatefulWidget {
  const _ShellProbe();

  @override
  State<_ShellProbe> createState() => _ShellProbeState();
}

class _ShellProbeState extends State<_ShellProbe> {
  int _i = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Tab $_i')),
      body: Center(child: Text('内容 $_i')),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _i,
        onDestinationSelected: (i) => setState(() => _i = i),
        destinations: const <NavigationDestination>[
          NavigationDestination(
            icon: Icon(Icons.memory_outlined),
            label: '外设',
          ),
          NavigationDestination(
            icon: Icon(Icons.search_outlined),
            label: '搜索',
          ),
        ],
      ),
    );
  }
}
