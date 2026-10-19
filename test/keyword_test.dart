// 关键词匹配与 C 词法高亮的单元测试。
//
// 这两块是需求 5.3（关键词点击跳转）的核心逻辑，
// 出错会直接导致"该链接的没链接"或"不该链接的乱链接"，所以重点测。

import 'package:flutter_test/flutter_test.dart';

import 'package:stm32_spl_helper/utils/c_highlighter.dart';
import 'package:stm32_spl_helper/utils/symbol_matcher.dart';

/// 构造一个用于测试的匹配器。
SymbolMatcher buildMatcher() => SymbolMatcher(
      functions: <String>[
        'GPIO_Init',
        'GPIO_StructInit',
        'GPIO_ReadInputDataBit',
        'RCC_APB2PeriphClockCmd',
      ],
      symbols: <String>[
        'GPIO_Mode_Out_PP',
        'GPIO_InitTypeDef',
        'GPIO_TypeDef',
        'RCC_APB2Periph_GPIOC',
        'ENABLE',
        'DISABLE',
        'GPIOC',
        // 超短符号，应被过滤
        'u8',
        'OB',
      ],
    );

void main() {
  // -------------------------------------------------------------------------
  group('SymbolMatcher 符号匹配', () {
    test('识别文本中的库内符号', () {
      final m = buildMatcher();
      final matches = m.findMatches(
        '调用 GPIO_Init(GPIOC, &GPIO_InitTypeDef) 前先开时钟',
      );
      final names = matches.map((x) => x.name).toList();
      expect(names, contains('GPIO_Init'));
      expect(names, contains('GPIOC'));
      expect(names, contains('GPIO_InitTypeDef'));
    });

    test('区分函数与符号', () {
      final m = buildMatcher();
      final matches = m.findMatches('GPIO_Init 与 GPIO_Mode_Out_PP');
      final fn = matches.firstWhere((x) => x.name == 'GPIO_Init');
      final sym = matches.firstWhere((x) => x.name == 'GPIO_Mode_Out_PP');
      expect(fn.isFunction, isTrue);
      expect(sym.isFunction, isFalse);
    });

    test('长度小于 3 的名字不参与链接', () {
      final m = buildMatcher();
      // u8 / OB 在构造时已被过滤掉
      expect(m.canResolve('u8'), isFalse);
      expect(m.canResolve('OB'), isFalse);
      final matches = m.findMatches('u8 x; OB y;');
      expect(matches, isEmpty);
    });

    test('前缀匹配不作为链接（只匹配完整标识符）', () {
      final m = buildMatcher();
      // GPIO_Init 是已知的，GPIO_Ini 不是
      final matches = m.findMatches('GPIO_Ini 不是完整名字');
      expect(matches.map((x) => x.name), isNot(contains('GPIO_Init')));
    });

    test('whitelist 限定可链接范围', () {
      final m = buildMatcher();
      final text = 'GPIO_Init 与 GPIO_Mode_Out_PP 都在文本里';
      // 只允许 GPIO_Init
      final limited = m.findMatches(text, whitelist: <String>{'GPIO_Init'});
      expect(limited.length, 1);
      expect(limited.first.name, 'GPIO_Init');
      // 不传 whitelist 则都链接
      expect(m.findMatches(text).length, 2);
    });

    test('segment 切分出普通片段与链接片段', () {
      final m = buildMatcher();
      final segs = m.segment('用 GPIO_Init 配置');
      expect(segs.length, 3);
      expect(segs[0].isLink, isFalse);
      expect(segs[0].text, '用 ');
      expect(segs[1].isLink, isTrue);
      expect(segs[1].name, 'GPIO_Init');
      expect(segs[2].isLink, isFalse);
      expect(segs[2].text, ' 配置');
    });

    test('无匹配时 segment 返回单个普通片段', () {
      final m = buildMatcher();
      final segs = m.segment('这里没有任何库内符号');
      expect(segs.length, 1);
      expect(segs.first.isLink, isFalse);
    });

    test('空文本不崩', () {
      final m = buildMatcher();
      expect(m.findMatches(''), isEmpty);
      expect(m.segment('').length, 1);
    });

    test('extractNames 去重并保持出现顺序', () {
      final m = buildMatcher();
      final names = m.extractNames('GPIO_Init 然后 GPIO_Init 又 GPIO_Mode_Out_PP');
      expect(names, <String>['GPIO_Init', 'GPIO_Mode_Out_PP']);
    });
  });

  // -------------------------------------------------------------------------
  group('CHighlighter 词法分析', () {
    test('识别关键字', () {
      final tokens = CHighlighter.tokenize('void f(void) { return; }');
      final keywords = tokens
          .where((t) => t.kind == TokenKind.keyword)
          .map((t) => t.text)
          .toList();
      expect(keywords, contains('return'));
    });

    test('识别类型名', () {
      final tokens = CHighlighter.tokenize('uint16_t a; uint32_t b;');
      final types = tokens
          .where((t) => t.kind == TokenKind.type)
          .map((t) => t.text)
          .toList();
      expect(types, containsAll(<String>['uint16_t', 'uint32_t']));
    });

    test('识别注释（行注释与块注释）', () {
      final tokens = CHighlighter.tokenize(
        'int a; // 行注释\nint b; /* 块\n注释 */',
      );
      final comments = tokens
          .where((t) => t.kind == TokenKind.comment)
          .map((t) => t.text)
          .toList();
      expect(comments.length, 2);
      expect(comments[0], '// 行注释');
      expect(comments[1], startsWith('/*'));
    });

    test('字符串里的 // 不被当作注释', () {
      final tokens = CHighlighter.tokenize('char* s = "http://x"; int a;');
      final comments =
          tokens.where((t) => t.kind == TokenKind.comment).toList();
      expect(comments, isEmpty);
      final strings =
          tokens.where((t) => t.kind == TokenKind.string).toList();
      expect(strings.length, 1);
      expect(strings.first.text, '"http://x"');
    });

    test('识别预处理指令（含续行）', () {
      final tokens = CHighlighter.tokenize(
        '#define A(x) ((x) + \\\n  1)\nint y;',
      );
      final pp = tokens
          .where((t) => t.kind == TokenKind.preprocessor)
          .map((t) => t.text)
          .toList();
      expect(pp.length, 1);
      // 续行应被合并进同一条预处理指令
      expect(pp.first, contains('1)'));
    });

    test('识别数字（十进制与十六进制）', () {
      final tokens = CHighlighter.tokenize('a = 0x1F; b = 42; c = 0x10;');
      final nums = tokens
          .where((t) => t.kind == TokenKind.number)
          .map((t) => t.text)
          .toList();
      expect(nums, containsAll(<String>['0x1F', '42', '0x10']));
    });

    test('数字后缀 u/l 被吞进同一个 token', () {
      final tokens = CHighlighter.tokenize('x = 100UL;');
      final nums = tokens
          .where((t) => t.kind == TokenKind.number)
          .map((t) => t.text)
          .toList();
      expect(nums, contains('100UL'));
    });

    test('markSymbols 把库内符号标成 symbol', () {
      final m = buildMatcher();
      var tokens = CHighlighter.tokenize(
        'GPIO_Init(GPIOC, &GPIO_InitTypeDef);',
      );
      tokens = CHighlighter.markSymbols(tokens, m);
      final syms = tokens
          .where((t) => t.kind == TokenKind.symbol)
          .map((t) => t.symbolName)
          .toList();
      expect(syms, contains('GPIO_Init'));
      expect(syms, contains('GPIOC'));
      expect(syms, contains('GPIO_InitTypeDef'));
    });

    test('markSymbols 不改注释与字符串里的同名文字', () {
      final m = buildMatcher();
      var tokens = CHighlighter.tokenize(
        '// 调用 GPIO_Init 即可\nchar* s = "GPIO_Init";',
      );
      tokens = CHighlighter.markSymbols(tokens, m);
      final syms = tokens.where((t) => t.kind == TokenKind.symbol).toList();
      // 注释与字符串里的 GPIO_Init 不应变成链接
      expect(syms, isEmpty);
    });

    test('markSymbols 遵守 whitelist', () {
      final m = buildMatcher();
      var tokens = CHighlighter.tokenize('GPIO_Init 与 GPIOC');
      tokens = CHighlighter.markSymbols(
        tokens,
        m,
        whitelist: <String>{'GPIO_Init'},
      );
      final syms = tokens
          .where((t) => t.kind == TokenKind.symbol)
          .map((t) => t.symbolName)
          .toList();
      expect(syms, <String>['GPIO_Init']);
    });

    test('token 拼接后能还原原文（不丢字符）', () {
      const src = 'GPIO_InitTypeDef s;\n'
          'RCC_APB2PeriphClockCmd(RCC_APB2Periph_GPIOC, ENABLE);\n'
          's.GPIO_Mode = GPIO_Mode_Out_PP;  /* 推挽 */\n';
      final tokens = CHighlighter.tokenize(src);
      final rebuilt = tokens.map((t) => t.text).join();
      expect(rebuilt, src);
    });
  });
}
