import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 应用主题。
///
/// 全部由 Material 3 的 ColorScheme 派生，不引入任何外部主题包或字体包
/// （需求：完全离线，不引入 google_fonts）。
///
/// 阶段 10 的视觉改版把设计参数集中到 [AppTokens] / [AppType] / [AppRadius]
/// 三个常量类里，页面只引用 token，不再各写各的 `BorderRadius.circular(12)`。
/// 这样调一次全局观感就变，也避免出现"这个卡片圆角 10、那个 12"的不一致。
class AppTheme {
  /// 主色种子：嵌入式工具偏冷色调，用蓝灰
  static const Color seed = Color(0xFF2C6BED);

  /// 收藏星标的颜色。
  ///
  /// 刻意不用 colorScheme.primary——星标是"用户标记"而不是"可点击链接"，
  /// 与正文里的蓝色链接区分开，扫列表时一眼能看出哪些是收藏过的。
  static const Color favoriteColor = Color(0xFFF5A524);

  /// 笔记标记的颜色。
  static const Color noteColor = Color(0xFF4C9A5B);

  /// 浅色主题
  static ThemeData light() => _build(Brightness.light);

  /// 深色主题
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;

    // Material 3 的 fromSeed 出的色调偏灰，工具类 App 需要更干净的层次：
    // 背景压暗/提亮一档，让卡片浮起来（而不是靠阴影）。
    final base = ColorScheme.fromSeed(seedColor: seed, brightness: brightness);
    final scheme = base.copyWith(
      surface: isDark ? const Color(0xFF14161A) : const Color(0xFFF7F8FA),
      onSurface: isDark ? const Color(0xFFE6E8EC) : const Color(0xFF1A1D21),
      surfaceContainerHighest:
          isDark ? const Color(0xFF23262C) : const Color(0xFFEDEFF3),
      outlineVariant:
          isDark ? const Color(0xFF303540) : const Color(0xFFE1E4EA),
    );

    final textTheme = _buildTextTheme(scheme, isDark);

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      textTheme: textTheme,
      visualDensity: VisualDensity.standard,
      scaffoldBackgroundColor: scheme.surface,
      // 页面转场统一用"淡入 + 轻微上移"，比默认的平台转场更轻，
      // 也不受 Android 版本影响（不同版本默认转场不一样，会让 App 观感飘）。
      // 只配置 android：iOS 上保持 Flutter 默认的 Cupertino 转场
      // （引入 CupertinoPageTransitionsBuilder 要多一个 import，没必要）。
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
        },
      ),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        scrolledUnderElevation: 0,
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleTextStyle: textTheme.titleLarge,
        // 状态栏图标跟随主题明暗，深色模式下不会留一条亮色状态栏
        systemOverlayStyle:
            isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: isDark ? const Color(0xFF1C1F24) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.card,
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      listTileTheme: ListTileThemeData(
        dense: false,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpace.lg,
          vertical: 4,
        ),
        shape: RoundedRectangleBorder(borderRadius: AppRadius.row),
      ),
      chipTheme: ChipThemeData(
        side: BorderSide(color: scheme.outlineVariant),
        shape: RoundedRectangleBorder(borderRadius: AppRadius.chip),
        // labelStyle 必须显式带 onSurface 颜色。
        //
        // 早先这里直接给 textTheme.labelMedium，而那个样式没有 color，
        // chip 的 label 于是拿不到前景色 → 在浅色模式下渲染成白字
        // （搜索页"试试这些"的示例 chip 就是这样白底白字看不见）。
        // 所有 chip 变体（ActionChip/InputChip/FilterChip/ChoiceChip）
        // 都从这里取 label 样式，改一处即可全站生效。
        labelStyle: textTheme.labelMedium?.copyWith(color: scheme.onSurface),
        secondaryLabelStyle:
            textTheme.labelMedium?.copyWith(color: scheme.onSecondaryContainer),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        space: 1,
        thickness: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark
            ? const Color(0xFF1F2227)
            : scheme.surfaceContainerHighest.withValues(alpha: 0.7),
        border: OutlineInputBorder(
          borderRadius: AppRadius.field,
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.field,
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.field,
          borderSide: BorderSide(color: scheme.primary, width: 1.6),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpace.lg,
          vertical: 13,
        ),
        hintStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant.withValues(alpha: 0.8),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: isDark ? const Color(0xFF1B1E23) : Colors.white,
        indicatorColor: scheme.primary.withValues(alpha: 0.14),
        elevation: 0,
        height: 64,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => textTheme.labelSmall?.copyWith(
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
            color: states.contains(WidgetState.selected)
                ? scheme.primary
                : scheme.onSurfaceVariant,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 22,
            color: states.contains(WidgetState.selected)
                ? scheme.primary
                : scheme.onSurfaceVariant,
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.chip),
        insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: Colors.white),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: isDark ? const Color(0xFF1C1F24) : Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: AppRadius.dialog),
        surfaceTintColor: Colors.transparent,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: AppRadius.chip),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          textStyle: textTheme.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: AppRadius.chip),
          textStyle: textTheme.labelLarge,
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          selectedBackgroundColor: scheme.primary.withValues(alpha: 0.14),
          selectedForegroundColor: scheme.primary,
          textStyle: textTheme.labelMedium,
          side: BorderSide(color: scheme.outlineVariant),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.chip),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        strokeWidth: 2.4,
      ),
    );
  }

  /// 排版层级。
  ///
  /// 用 Material 的字号阶梯，但把行高调紧一点——嵌入式文档里
  /// 中英混排 + 等宽标识符多，默认行高会显得松散。
  static TextTheme _buildTextTheme(ColorScheme scheme, bool isDark) {
    final onSurface = scheme.onSurface;
    return TextTheme(
      // 页面主标题（AppBar）
      titleLarge: TextStyle(
        fontSize: 18,
        height: 1.25,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
        color: onSurface,
      ),
      // 区块标题
      titleMedium: TextStyle(
        fontSize: 14.5,
        height: 1.35,
        fontWeight: FontWeight.w700,
        color: onSurface,
      ),
      titleSmall: TextStyle(
        fontSize: 13,
        height: 1.4,
        fontWeight: FontWeight.w600,
        color: onSurface,
      ),
      // 正文
      bodyLarge: TextStyle(
        fontSize: 14,
        height: 1.6,
        color: onSurface,
      ),
      bodyMedium: TextStyle(
        fontSize: 13,
        height: 1.6,
        color: onSurface,
      ),
      bodySmall: TextStyle(
        fontSize: 11.5,
        height: 1.5,
        color: scheme.onSurfaceVariant,
      ),
      // 标签（chip、按钮）
      //
      // 三档都必须带 color：Material 组件在没拿到前景色时会回退成白色，
      // 在浅色主题下就是"白字白底看不见"。
      labelLarge: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
        color: onSurface,
      ),
      labelMedium: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
        color: onSurface,
      ),
      labelSmall: TextStyle(
        fontSize: 10.5,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.1,
        color: scheme.onSurfaceVariant,
      ),
    );
  }

  /// 代码块等宽字体族（保留旧名，内部指向 [AppFonts.mono]）。
  static const List<String> monoFontFamily = AppFonts.mono;

  /// 代码块配色（浅色/深色各一套）。
  ///
  /// 自研高亮器用这套颜色，不依赖 flutter_highlight。
  static CodeColors codeColors(Brightness brightness) =>
      brightness == Brightness.dark
          ? const CodeColors(
              background: Color(0xFF17191D),
              plain: Color(0xFFD6D8DB),
              keyword: Color(0xFFC792EA),
              type: Color(0xFF4EC9B0),
              comment: Color(0xFF6A8A5B),
              string: Color(0xFFCE9178),
              number: Color(0xFFB5CEA8),
              preprocessor: Color(0xFF7FBCF0),
              function: Color(0xFFDCDCAA),
              symbolLink: Color(0xFF4FA8FF),
            )
          : const CodeColors(
              background: Color(0xFFFAFBFC),
              plain: Color(0xFF24292F),
              keyword: Color(0xFFCF222E),
              type: Color(0xFF0550AE),
              comment: Color(0xFF6E7781),
              string: Color(0xFF0A3069),
              number: Color(0xFF0550AE),
              preprocessor: Color(0xFF8250DF),
              function: Color(0xFF953800),
              symbolLink: Color(0xFF0969DA),
            );
}

/// 间距刻度。
///
/// 只用这七档，避免出现 7、9、11、13 这种随手写的间距。
class AppSpace {
  /// 4
  static const double xs = 4;

  /// 8
  static const double sm = 8;

  /// 12
  static const double md = 12;

  /// 16
  static const double lg = 16;

  /// 20
  static const double xl = 20;

  /// 24
  static const double xxl = 24;

  /// 32
  static const double huge = 32;
}

/// 圆角刻度。
class AppRadius {
  /// 小元素（chip、小标签）6
  static const Radius small = Radius.circular(6);

  /// 中等（输入框、按钮）10
  static const Radius medium = Radius.circular(10);

  /// 卡片 14
  static const Radius large = Radius.circular(14);

  /// 弹窗 20
  static const Radius xlarge = Radius.circular(20);

  static const BorderRadius chip = BorderRadius.all(medium);
  static const BorderRadius row = BorderRadius.all(medium);
  static const BorderRadius card = BorderRadius.all(large);
  static const BorderRadius field = BorderRadius.all(Radius.circular(12));
  static const BorderRadius dialog = BorderRadius.all(xlarge);
}

/// 动效时长。
///
/// 统一在这里定义，避免各处 200/250/300ms 混用——
/// 时长不一致会让界面"节奏散"，这是廉价感的主要来源之一。
class AppDuration {
  /// 快速反馈（选中、图标切换）140ms
  static const Duration fast = Duration(milliseconds: 140);

  /// 常规（展开/折叠、淡入）220ms
  static const Duration normal = Duration(milliseconds: 220);

  /// 页面级（转场、大块区域变化）320ms
  static const Duration slow = Duration(milliseconds: 320);
}

/// 等宽字体族常量。
///
/// 单独抽出来是为了让页面里写 `fontFamilyFallback: AppFonts.mono` 更短，
/// 也避免到处 import theme.dart 里的整个 AppTheme。
class AppFonts {
  /// 代码/符号名用的等宽字体族（按优先级回退）。
  ///
  /// 全部是平台自带字体，不打包字体文件，符合离线要求。
  static const List<String> mono = <String>[
    'Roboto Mono',
    'Droid Sans Mono',
    'monospace',
  ];

  /// 等宽文本样式（符号名、函数名、代码）。
  ///
  /// 带一点字距收紧：等宽字体默认间距偏大，连续大写标识符
  /// （如 GPIO_Mode_Out_PP）在窄屏上容易被撑开换行。
  static TextStyle monoStyle({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? height,
  }) =>
      TextStyle(
        fontFamilyFallback: mono,
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
        height: height,
        letterSpacing: -0.2,
      );
}

/// 代码高亮配色。
class CodeColors {
  final Color background;
  final Color plain;
  final Color keyword;
  final Color type;
  final Color comment;
  final Color string;
  final Color number;
  final Color preprocessor;
  final Color function;
  final Color symbolLink;

  const CodeColors({
    required this.background,
    required this.plain,
    required this.keyword,
    required this.type,
    required this.comment,
    required this.string,
    required this.number,
    required this.preprocessor,
    required this.function,
    required this.symbolLink,
  });
}
