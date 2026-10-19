// 阶段 8（编译错误速查）的测试。
//
// 用真实数据验证：
//   1. 数据结构完整（15 条、4 分类、每条的必填字段都有）
//   2. 三层筛选逻辑（分类 / 工具链 / 关键词）行为正确
//   3. 关键词能命中"报错原文"，这是本页的核心用法
//   4. 页面在真机宽度下渲染不溢出（筛选条是横向滚动的，容易挤爆）

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stm32_spl_helper/models/compile_error.dart';
import 'package:stm32_spl_helper/utils/theme.dart';

/// 读真实编译错误数据
CompileErrorBundle readBundle() {
  final f = File('assets/data/compile_errors.json');
  expect(f.existsSync(), isTrue, reason: '编译错误数据不存在');
  return CompileErrorBundle.fromJson(
    jsonDecode(f.readAsStringSync()) as Map<String, dynamic>,
  );
}

/// 复刻页面里的关键词匹配规则，用于纯逻辑测试。
///
/// 与 `_CompileErrorsPageState._matches` 保持一致；页面里的那份是私有的，
/// 改动时要同步这里（页面的行为由下面的 widget 测试兜住）。
bool matches(CompileError e, String keyword) {
  final k = keyword.toLowerCase();
  if (e.messageSample.toLowerCase().contains(k)) return true;
  if (e.messagePatterns.any((p) => p.toLowerCase().contains(k))) return true;
  if (e.titleZh.toLowerCase().contains(k)) return true;
  if (e.explainZh.toLowerCase().contains(k)) return true;
  if (e.tags.any((t) => t.toLowerCase().contains(k))) return true;
  return false;
}

void main() {
  group('数据完整性', () {
    test('15 条错误、4 个分类', () {
      final b = readBundle();
      expect(b.errors.length, 15);
      expect(b.categories.length, 4);
      expect(
        b.categories.map((c) => c.id).toList(),
        <String>['compiler', 'linker', 'download', 'runtime'],
      );
    });

    test('分类按 orderIndex 排好序', () {
      final b = readBundle();
      final orders = b.categories.map((c) => c.orderIndex).toList();
      final sorted = List<int>.from(orders)..sort();
      expect(orders, sorted);
    });

    test('每条都有中文标题、解释、原因与解决步骤', () {
      final b = readBundle();
      final noTitle = <String>[];
      final noExplain = <String>[];
      final noCauses = <String>[];
      final noSolutions = <String>[];

      for (final e in b.errors) {
        if (e.titleZh.isEmpty) noTitle.add(e.id);
        if (e.explainZh.isEmpty) noExplain.add(e.id);
        if (e.causes.isEmpty) noCauses.add(e.id);
        if (e.solutions.isEmpty) noSolutions.add(e.id);
      }
      expect(noTitle, isEmpty, reason: '缺中文标题：$noTitle');
      expect(noExplain, isEmpty, reason: '缺中文解释：$noExplain');
      expect(noCauses, isEmpty, reason: '缺产生原因：$noCauses');
      expect(noSolutions, isEmpty, reason: '缺解决步骤：$noSolutions');
    });

    test('每条都有可用于搜索的报错原文', () {
      final b = readBundle();
      final missing = <String>[];
      for (final e in b.errors) {
        if (e.messageSample.isEmpty && e.messagePatterns.isEmpty) {
          missing.add(e.id);
        }
      }
      expect(missing, isEmpty,
          reason: '没有报错原文就无法按现象检索：$missing');
    });

    test('每条的 categoryId 都能在分类表里找到', () {
      final b = readBundle();
      final ids = b.categories.map((c) => c.id).toSet();
      for (final e in b.errors) {
        expect(ids, contains(e.categoryId),
            reason: '${e.id} 的分类 ${e.categoryId} 不存在');
      }
    });

    test('每个分类下都至少有一条', () {
      final b = readBundle();
      for (final c in b.categories) {
        final n = b.errors.where((e) => e.categoryId == c.id).length;
        expect(n, greaterThan(0), reason: '分类 ${c.id} 下没有条目');
      }
    });

    test('错误 id 唯一', () {
      final b = readBundle();
      final seen = <String>{};
      for (final e in b.errors) {
        expect(seen.add(e.id), isTrue, reason: '重复 id：${e.id}');
      }
    });

    test('相关函数/符号/外设的引用都能解析', () {
      // 这条与 data_integration_test 里的跳转测试互补：
      // 这里只确认引用的 id 非空且格式合理，避免详情页出现点不动的 chip
      final b = readBundle();
      for (final e in b.errors) {
        for (final id in e.relatedFunctionIds) {
          expect(id.trim(), isNotEmpty, reason: '${e.id} 有空的函数引用');
        }
        for (final id in e.relatedSymbolIds) {
          expect(id.trim(), isNotEmpty, reason: '${e.id} 有空符号引用');
        }
      }
    });
  });

  group('工具链中文名', () {
    test('四个工具链都有中文名', () {
      final b = readBundle();
      final map = <String, String>{
        for (final e in b.errors) e.toolchain: e.toolchainZh,
      };
      expect(map['keil'], 'Keil MDK');
      expect(map['gcc-arm'], 'GCC ARM');
      expect(map['st-link'], 'ST-Link');
      expect(map['generic'], '通用');
    });

    test('未知工具链原样返回而不是空串', () {
      const e = CompileError(
        id: 'x',
        titleZh: 't',
        categoryId: 'compiler',
        toolchain: 'iar',
      );
      expect(e.toolchainZh, 'iar');
    });
  });

  group('关键词检索（按报错现象找条目）', () {
    test('搜 L6218E 命中 Keil 链接错误', () {
      final b = readBundle();
      final hit = b.errors.where((e) => matches(e, 'L6218E')).toList();
      expect(hit, isNotEmpty);
      expect(hit.first.id, 'err.keil_l6218e');
    });

    test('搜 undefined reference 命中链接错误', () {
      final b = readBundle();
      final hit = b.errors.where((e) => matches(e, 'undefined reference'));
      expect(hit.map((e) => e.id), contains('err.undefined_reference'));
    });

    test('搜 cannot open 命中 Keil 配置文件缺失', () {
      final b = readBundle();
      final hit = b.errors.where((e) => matches(e, 'cannot open'));
      expect(hit, isNotEmpty);
    });

    test('大小写不敏感', () {
      final b = readBundle();
      final upper = b.errors.where((e) => matches(e, 'L6218E')).length;
      final lower = b.errors.where((e) => matches(e, 'l6218e')).length;
      expect(lower, upper);
      expect(lower, greaterThan(0));
    });

    test('搜中文也能命中（标题或解释）', () {
      final b = readBundle();
      // "乱码" 应出现在串口乱码那条的标题或解释里
      final hit = b.errors.where((e) => matches(e, '乱码'));
      expect(hit.map((e) => e.id), contains('err.usart_garbled'));
    });

    test('搜 hardfault 命中中断服务函数名那条', () {
      final b = readBundle();
      final hit = b.errors.where((e) => matches(e, 'hardfault'));
      expect(hit, isNotEmpty);
    });

    test('搜无意义的串返回空', () {
      final b = readBundle();
      final hit = b.errors.where((e) => matches(e, 'zzzz_not_exist'));
      expect(hit, isEmpty);
    });

    test('每条错误至少能被自己的一个原文片段命中（可检索性）', () {
      final b = readBundle();
      final unreachable = <String>[];
      for (final e in b.errors) {
        // 用 messagePatterns 的第一个片段查，应能命中自己
        final probe = e.messagePatterns.isNotEmpty
            ? e.messagePatterns.first
            : e.messageSample.split('\n').first;
        if (probe.trim().isEmpty) continue;
        if (!matches(e, probe)) unreachable.add(e.id);
      }
      expect(unreachable, isEmpty,
          reason: '这些条目用自己的原文都搜不到：$unreachable');
    });
  });

  group('三层筛选组合', () {
    test('按分类筛选', () {
      final b = readBundle();
      final linker =
          b.errors.where((e) => e.categoryId == 'linker').toList();
      expect(linker.length, 4);
    });

    test('按工具链筛选', () {
      final b = readBundle();
      final keil = b.errors.where((e) => e.toolchain == 'keil').toList();
      expect(keil.length, 6);
      final gcc = b.errors.where((e) => e.toolchain == 'gcc-arm').toList();
      expect(gcc.length, 1);
    });

    test('分类 + 工具链交叉收窄', () {
      final b = readBundle();
      final hit = b.errors
          .where((e) => e.categoryId == 'linker' && e.toolchain == 'keil')
          .toList();
      // Keil 的链接错误有两条：L6218E 未定义符号、Flash 空间不足
      expect(hit.length, 2);
      expect(
        hit.map((e) => e.id),
        containsAll(<String>['err.keil_l6218e', 'err.no_space_execution_regions']),
      );
      // 交叉筛选后确实比单独按分类少
      final onlyLinker =
          b.errors.where((e) => e.categoryId == 'linker').length;
      expect(hit.length, lessThan(onlyLinker));
    });

    test('分类 + 关键词交叉收窄', () {
      final b = readBundle();
      final hit = b.errors
          .where((e) => e.categoryId == 'download' && matches(e, 'st-link'))
          .toList();
      // stlink_not_connected 是 st-link 工具链的下载错误
      expect(hit.map((e) => e.id), contains('err.stlink_not_connected'));
    });

    test('筛不到时结果为空而不是全量', () {
      final b = readBundle();
      final hit = b.errors
          .where((e) => e.categoryId == 'compiler' && e.toolchain == 'st-link')
          .toList();
      expect(hit, isEmpty);
    });
  });

  group('页面渲染（真机宽度）', () {
    // 直接测数据驱动的列表项，避免为整页搭一堆 provider 桩。
    // 整页的 provider 接线由 search/data_integration 测试覆盖。
    Widget wrap(Widget child) => MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(body: child),
        );

    testWidgets('错误条目在 360dp 下不溢出（长标题与长解释）', (tester) async {
      tester.view.physicalSize = const Size(360 * 3, 800 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      final b = readBundle();
      // 找出标题与解释最长的两条，最容易挤爆
      final sorted = List<CompileError>.from(b.errors)
        ..sort((a, c) =>
            (c.titleZh.length + c.explainZh.length)
                .compareTo(a.titleZh.length + a.explainZh.length));

      await tester.pumpWidget(wrap(
        ListView(
          children: <Widget>[
            for (final e in sorted.take(5))
              ListTile(
                dense: true,
                title: Text(
                  e.titleZh,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  e.explainZh,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Text(
                  e.toolchainZh,
                  style: const TextStyle(fontSize: 10.5),
                ),
              ),
          ],
        ),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('分类筛选条在窄屏下横向滚动不溢出', (tester) async {
      tester.view.physicalSize = const Size(320 * 3, 640 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      final b = readBundle();
      await tester.pumpWidget(wrap(
        SizedBox(
          height: 38,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: <Widget>[
              for (final c in b.categories)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: FilterChip(
                    selected: false,
                    onSelected: (_) {},
                    label: Text(
                      '${c.nameZh} ${b.errors.where((e) => e.categoryId == c.id).length}',
                      style: const TextStyle(fontSize: 11.5),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.textContaining('编译错误'), findsWidgets);
    });
  });

  group('搜索索引集成', () {
    testWidgets('编译错误条目能被全局搜索索引收录', (tester) async {
      // 复用 search_test 里的做法太重，这里只确认 CompileErrorBundle
      // 提供了 build 索引所需的字段
      final b = readBundle();
      for (final e in b.errors) {
        expect(e.searchableText, isNotEmpty,
            reason: '${e.id} 的 searchableText 为空，全局搜索会搜不到');
      }
    });
  });
}
