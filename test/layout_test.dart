// 列表布局的渲染测试（真机 bug 回归）。
//
// 背景：真机上发现 GPIO「数据读取函数」栏与 USART「中断管理函数」栏的
// 函数名竖排显示。根因是 _FunctionTile 的 Row 里，返回值 Text 没有约束
// 且内容是中文长句（最长 40 字），把 Expanded 里的函数名挤到只剩一两个
// 字符宽，于是英文标识符按字符换行，看起来就是竖排。
//
// 这类问题只有真正渲染一遍才能可靠发现——纯数据测试测不出来。
// 这里用真实数据渲染，并断言：
//   1. 不出现 RenderFlex overflow（溢出会打印错误并被 tester 捕获）
//   2. 函数名没有被压到多行（高度不超过单行）

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stm32_spl_helper/models/function_item.dart';
import 'package:stm32_spl_helper/models/peripheral.dart';
import 'package:stm32_spl_helper/utils/theme.dart';

/// 读真实数据里的某个外设
Peripheral readPeripheral(String id) {
  final f = File('assets/data/peripherals.json');
  final data = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
  final list = (data['peripherals'] as List)
      .map((e) => Peripheral.fromJson(e as Map<String, dynamic>));
  return list.firstWhere((p) => p.id == id);
}

List<FunctionItem> readFunctions(String id) {
  final f = File('assets/data/functions/$id.json');
  final data = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
  return (data['functions'] as List)
      .map((e) => FunctionItem.fromJson(e as Map<String, dynamic>))
      .toList();
}

/// 复刻 _FunctionTile 的布局。
///
/// 刻意与生产代码保持同样的结构（Row + Expanded + Flexible），
/// 这样一旦生产代码退化回"无约束 Text"，这个测试会失败。
Widget buildTile(FunctionItem item) {
  return MaterialApp(
    theme: AppTheme.light(),
    home: Scaffold(
      body: ListView(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(30, 10, 14, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        item.name,
                        softWrap: false,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamilyFallback: AppFonts.mono,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        item.displayReturn,
                        textAlign: TextAlign.right,
                        softWrap: false,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamilyFallback: AppFonts.mono,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  item.displayBrief,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5, height: 1.45),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

/// 把视口设成常见真机宽度。
///
/// 这一步很关键：默认测试视口是 800x600，比手机宽得多，
/// 旧代码在那个宽度下**不会**溢出，测试就抓不到 bug。
/// 实测在 360dp 下旧代码的函数名宽度被压到 0.0、高度 399.0（完全竖排）。
void usePhoneWidth(WidgetTester tester, {double width = 360}) {
  tester.view.physicalSize = Size(width, 720);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

/// 判断函数名是否被压成"竖排"。
///
/// 单行英文标识符高度约等于字号（13.5）乘行高，实测正常约 19dp；
/// 一旦换行就会成倍增长。这里用 40 作为分界，并用宽度兜底：
/// 正常宽度应该大于 60dp，被挤扁时会接近 0。
void expectNameNotSquashed(WidgetTester tester, String name) {
  final size = tester.getSize(find.text(name));
  expect(
    size.height,
    lessThan(40),
    reason: '$name 的函数名被压成多行（竖排），高度 ${size.height}',
  );
  expect(
    size.width,
    greaterThan(60),
    reason: '$name 的函数名被返回值挤得过窄，宽度 ${size.width}',
  );
}

void main() {
  setUpAll(() {
    expect(Directory('assets/data').existsSync(), isTrue,
        reason: 'assets/data 不存在，请先运行 tools/merge_overlay.py');
  });

  group('函数列表渲染（真机 bug 回归）', () {
    testWidgets('GPIO 数据读取函数栏：函数名不竖排、无溢出', (tester) async {
      usePhoneWidth(tester);
      // 这一栏的函数恰好都有 39~40 字的返回值说明，是问题的重灾区
      final funcs =
          readFunctions('GPIO').where((f) => f.id.contains('Read')).toList();
      expect(funcs, isNotEmpty);

      for (final f in funcs) {
        await tester.pumpWidget(buildTile(f));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '${f.id} 渲染时溢出');
        expectNameNotSquashed(tester, f.name);
      }
    });

    testWidgets('USART 中断管理函数栏：函数名不竖排、无溢出', (tester) async {
      usePhoneWidth(tester);
      final funcs =
          readFunctions('USART').where((f) => f.id.contains('IT')).toList();
      expect(funcs, isNotEmpty);

      for (final f in funcs) {
        await tester.pumpWidget(buildTile(f));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '${f.id} 渲染时溢出');
        expectNameNotSquashed(tester, f.name);
      }
    });

    testWidgets('全部 488 个函数在真机宽度下逐个渲染都不竖排、不溢出',
        (tester) async {
      usePhoneWidth(tester);
      final periphs = jsonDecode(
        File('assets/data/peripherals.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      final ids = (periphs['peripherals'] as List)
          .map((e) => (e as Map<String, dynamic>)['id'] as String)
          .toList();

      var checked = 0;
      final bad = <String>[];
      for (final pid in ids) {
        for (final f in readFunctions(pid)) {
          checked++;
          await tester.pumpWidget(buildTile(f));
          await tester.pumpAndSettle();

          final ex = tester.takeException();
          if (ex != null) {
            bad.add('${f.id} 溢出: $ex');
            continue;
          }
          final size = tester.getSize(find.text(f.name));
          if (size.height >= 40 || size.width <= 60) {
            bad.add('${f.id} 竖排(${size.width}x${size.height})');
          }
        }
      }
      expect(checked, 488);
      expect(bad, isEmpty,
          reason: '有 ${bad.length} 个函数显示异常：${bad.take(5)}');
    });

    testWidgets('极窄屏（320dp）下也不竖排', (tester) async {
      usePhoneWidth(tester, width: 320);
      // 挑最长的函数名 + 最长的返回值组合
      final f = readFunctions('GPIO')
          .firstWhere((x) => x.id == 'GPIO_ReadInputDataBit');
      await tester.pumpWidget(buildTile(f));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expectNameNotSquashed(tester, f.name);
    });

    testWidgets('宽屏（800dp）下同样正常', (tester) async {
      // 默认视口，确认修复在宽屏下也没引入回归
      final f = readFunctions('GPIO')
          .firstWhere((x) => x.id == 'GPIO_ReadInputDataBit');
      await tester.pumpWidget(buildTile(f));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expectNameNotSquashed(tester, f.name);
    });
  });
}
