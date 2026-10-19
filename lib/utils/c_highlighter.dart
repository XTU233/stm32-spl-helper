import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'symbol_matcher.dart';
import 'theme.dart';

/// 代码 token 的种类。
enum TokenKind {
  /// 普通标识符与符号
  plain,

  /// C 关键字
  keyword,

  /// 标准类型名（uint8_t、uint32_t 等）
  type,

  /// 注释
  comment,

  /// 字符串或字符字面量
  string,

  /// 数字字面量
  number,

  /// 预处理指令（#define、#include 等）
  preprocessor,

  /// 库内符号（可点击跳转）
  symbol,
}

/// 一个词法 token。
class CodeToken {
  /// token 原文
  final String text;

  /// token 种类
  final TokenKind kind;

  /// 命中的库内符号名（仅 [TokenKind.symbol] 有值）
  final String? symbolName;

  /// 该符号是否为函数
  final bool isFunction;

  const CodeToken(
    this.text,
    this.kind, {
    this.symbolName,
    this.isFunction = false,
  });
}

/// 轻量 C 词法高亮器。
///
/// 为什么自研而不用 flutter_highlight（决策见 docs/phase0_architecture.md）：
/// 需求 5.3 要求示例代码里的库内符号（如 GPIO_Mode_Out_PP）可点击，
/// 而 flutter_highlight 只输出按语法分的 token、不理解"库内符号"这一层，
/// 套上去等于同一段代码解析两遍，还容易破坏高亮边界。
/// 自研版一次扫描同时满足"高亮 + 跳转"两个需求。
class CHighlighter {
  /// C89/C99 关键字（SPL 代码里实际会用到的）
  static const Set<String> _keywords = <String>{
    'auto', 'break', 'case', 'const', 'continue', 'default', 'do', 'else',
    'enum', 'extern', 'for', 'goto', 'if', 'inline', 'register', 'restrict',
    'return', 'sizeof', 'static', 'struct', 'switch', 'typedef', 'union',
    'volatile', 'while', '_Bool', '_Complex', '_Imaginary',
  };

  /// 标准库与 CMSIS 常用类型名
  static const Set<String> _types = <String>{
    'void', 'char', 'short', 'int', 'long', 'float', 'double', 'signed',
    'unsigned', 'bool', 'size_t', 'NULL',
    // CMSIS / ST 的类型别名
    'uint8_t', 'uint16_t', 'uint32_t', 'uint64_t',
    'int8_t', 'int16_t', 'int32_t', 'int64_t',
    'u8', 'u16', 'u32', 's8', 's16', 's32',
    'vu8', 'vu16', 'vu32', 'vs8', 'vs16', 'vs32',
    'FlagStatus', 'ITStatus', 'ErrorStatus', 'FunctionalState',
    'BitAction', 'ENABLE', 'DISABLE', 'SET', 'RESET',
    'SUCCESS', 'ERROR', 'None',
  };

  /// 词法扫描：把源码切成 token 序列。
  ///
  /// 扫描顺序很关键：注释 → 预处理 → 字符串 → 数字 → 标识符 → 其它，
  /// 否则 `//` 里的内容会被当成标识符、`"a//b"` 里的 `//` 会被当成注释。
  static List<CodeToken> tokenize(String source) {
    final tokens = <CodeToken>[];
    final buffer = StringBuffer();
    var i = 0;
    final n = source.length;

    // 把缓冲区内容作为 plain token 落盘
    void flush() {
      if (buffer.isNotEmpty) {
        tokens.add(CodeToken(buffer.toString(), TokenKind.plain));
        buffer.clear();
      }
    }

    while (i < n) {
      final c = source[i];

      // ---- 注释 ----
      if (c == '/' && i + 1 < n && source[i + 1] == '/') {
        flush();
        final end = source.indexOf('\n', i);
        final stop = end < 0 ? n : end;
        tokens.add(CodeToken(source.substring(i, stop), TokenKind.comment));
        i = stop;
        continue;
      }
      if (c == '/' && i + 1 < n && source[i + 1] == '*') {
        flush();
        final end = source.indexOf('*/', i + 2);
        final stop = end < 0 ? n : end + 2;
        tokens.add(CodeToken(source.substring(i, stop), TokenKind.comment));
        i = stop;
        continue;
      }

      // ---- 预处理指令：从 # 到行尾（含续行）----
      if (c == '#') {
        // 只有行首（前面只有空白）的 # 才算预处理指令。
        // 注意 lastIndexOf 的第二个参数不能传负数，i=0 时要单独处理。
        final lineStart = i == 0 ? 0 : source.lastIndexOf('\n', i - 1) + 1;
        final prefix = source.substring(lineStart, i);
        if (prefix.trim().isEmpty) {
          flush();
          var stop = i;
          while (stop < n) {
            final nl = source.indexOf('\n', stop);
            if (nl < 0) {
              stop = n;
              break;
            }
            // 续行：行尾是反斜杠则继续
            final line = source.substring(stop, nl);
            if (line.trimRight().endsWith('\\')) {
              stop = nl + 1;
            } else {
              stop = nl;
              break;
            }
          }
          tokens.add(
            CodeToken(source.substring(i, stop), TokenKind.preprocessor),
          );
          i = stop;
          continue;
        }
      }

      // ---- 字符串 / 字符字面量 ----
      if (c == '"' || c == "'") {
        flush();
        final quote = c;
        var j = i + 1;
        while (j < n) {
          if (source[j] == '\\') {
            j += 2;
            continue;
          }
          if (source[j] == quote) {
            j++;
            break;
          }
          if (source[j] == '\n') break; // 未闭合，止于行尾
          j++;
        }
        tokens.add(CodeToken(source.substring(i, j), TokenKind.string));
        i = j;
        continue;
      }

      // ---- 数字 ----
      if (_isDigit(c) ||
          (c == '.' && i + 1 < n && _isDigit(source[i + 1]))) {
        flush();
        var j = i;
        // 十六进制
        if (c == '0' && i + 1 < n && (source[i + 1] == 'x' || source[i + 1] == 'X')) {
          j = i + 2;
          while (j < n && _isHexDigit(source[j])) {
            j++;
          }
        } else {
          while (j < n && (_isDigit(source[j]) || source[j] == '.')) {
            j++;
          }
        }
        // 后缀 u/U/l/L
        while (j < n && 'uUlL'.contains(source[j])) {
          j++;
        }
        tokens.add(CodeToken(source.substring(i, j), TokenKind.number));
        i = j;
        continue;
      }

      // ---- 标识符 ----
      if (_isIdentStart(c)) {
        var j = i + 1;
        while (j < n && _isIdentPart(source[j])) {
          j++;
        }
        final word = source.substring(i, j);
        flush();
        if (_keywords.contains(word)) {
          tokens.add(CodeToken(word, TokenKind.keyword));
        } else if (_types.contains(word)) {
          tokens.add(CodeToken(word, TokenKind.type));
        } else {
          // 其余标识符先按普通文本记，稍后由符号表决定是否变成链接
          tokens.add(CodeToken(word, TokenKind.plain));
        }
        i = j;
        continue;
      }

      // ---- 其它字符 ----
      buffer.write(c);
      i++;
    }
    flush();
    return tokens;
  }

  /// 在已分词的 token 上叠加"库内符号"标记。
  ///
  /// 只处理 [TokenKind.plain] 的 token——注释、字符串、数字里的同名文字
  /// 不该变成链接（那样点进去会很突兀）。
  static List<CodeToken> markSymbols(
    List<CodeToken> tokens,
    SymbolMatcher matcher, {
    Set<String>? whitelist,
  }) {
    final result = <CodeToken>[];
    for (final t in tokens) {
      if (t.kind != TokenKind.plain) {
        result.add(t);
        continue;
      }
      // 一个 plain token 本身就是一个标识符（tokenize 里已单独切出），
      // 但连续符号（如 `->`、`&`）会合并成 plain，所以要按标识符再切一次。
      if (!_isIdentStart(t.text[0]) || t.text.length < SymbolMatcher.minNameLength) {
        result.add(t);
        continue;
      }
      if (whitelist != null && !whitelist.contains(t.text)) {
        result.add(t);
        continue;
      }
      final isFn = matcher.functionNames.contains(t.text);
      final isSym = matcher.symbolNames.contains(t.text);
      if (isFn || isSym) {
        result.add(CodeToken(
          t.text,
          TokenKind.symbol,
          symbolName: t.text,
          isFunction: isFn,
        ));
      } else {
        result.add(t);
      }
    }
    return result;
  }

  /// 把 token 转成带颜色的 TextSpan 序列。
  ///
  /// [onSymbolTap] 为 null 时符号不可点击（只着色）。
  static List<InlineSpan> toSpans(
    List<CodeToken> tokens,
    CodeColors colors, {
    required TextStyle baseStyle,
    void Function(String name)? onSymbolTap,
  }) {
    return <InlineSpan>[
      for (final t in tokens)
        TextSpan(
          text: t.text,
          style: baseStyle.copyWith(color: _colorOf(t.kind, colors)),
          recognizer: (t.kind == TokenKind.symbol && onSymbolTap != null)
              ? (TapGestureRecognizer()
                ..onTap = () => onSymbolTap(t.symbolName!))
              : null,
        ),
    ];
  }

  static Color _colorOf(TokenKind kind, CodeColors colors) {
    switch (kind) {
      case TokenKind.keyword:
        return colors.keyword;
      case TokenKind.type:
        return colors.type;
      case TokenKind.comment:
        return colors.comment;
      case TokenKind.string:
        return colors.string;
      case TokenKind.number:
        return colors.number;
      case TokenKind.preprocessor:
        return colors.preprocessor;
      case TokenKind.symbol:
        return colors.symbolLink;
      case TokenKind.plain:
        return colors.plain;
    }
  }

  // ---- 字符判定 ----

  static bool _isDigit(String c) {
    final code = c.codeUnitAt(0);
    return code >= 0x30 && code <= 0x39;
  }

  static bool _isHexDigit(String c) {
    final code = c.codeUnitAt(0);
    return (code >= 0x30 && code <= 0x39) ||
        (code >= 0x41 && code <= 0x46) ||
        (code >= 0x61 && code <= 0x66);
  }

  static bool _isIdentStart(String c) {
    final code = c.codeUnitAt(0);
    return (code >= 0x41 && code <= 0x5A) ||
        (code >= 0x61 && code <= 0x7A) ||
        code == 0x5F;
  }

  static bool _isIdentPart(String c) {
    return _isIdentStart(c) || _isDigit(c);
  }
}
