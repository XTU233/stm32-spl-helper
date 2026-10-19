import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 应用设置（主题模式 / 代码字号 / 显示开关）。
///
/// 存 shared_preferences 而不是 sqflite：三项都是标量，
/// 没有查询与关联的需求，键值存储更轻（这也是阶段 0 定的方案）。
///
/// 与收藏/笔记分开的原因：那些是"用户数据"，需要按类型/时间检索；
/// 这些是"配置"，只按 key 读一次。
class AppSettings {
  /// 主题模式
  final ThemeMode themeMode;

  /// 代码块字号
  final double codeFontSize;

  /// 首页是否只显示本型号支持的外设
  final bool onlySupported;

  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.codeFontSize = 13.0,
    this.onlySupported = false,
  });

  /// 代码字号的取值范围（与设置页的 Slider 一致）。
  ///
  /// 在这里定义而不是在页面里，是为了让"读到的值"也能被同一套边界约束：
  /// 万一 prefs 里存了一个 100（手改文件、旧版本写坏），
  /// 直接用它渲染代码块会把布局撑爆。
  static const double minCodeFontSize = 10.0;
  static const double maxCodeFontSize = 20.0;

  /// 默认值，也是"恢复默认"按钮的目标值
  static const AppSettings defaults = AppSettings();

  AppSettings copyWith({
    ThemeMode? themeMode,
    double? codeFontSize,
    bool? onlySupported,
  }) =>
      AppSettings(
        themeMode: themeMode ?? this.themeMode,
        codeFontSize: codeFontSize ?? this.codeFontSize,
        onlySupported: onlySupported ?? this.onlySupported,
      );

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.themeMode == themeMode &&
      other.codeFontSize == codeFontSize &&
      other.onlySupported == onlySupported;

  @override
  int get hashCode => Object.hash(themeMode, codeFontSize, onlySupported);

  @override
  String toString() =>
      'AppSettings(${themeMode.name}, $codeFontSize, onlySupported=$onlySupported)';
}

/// 设置的读写。
class SettingsStore {
  static const String _kThemeMode = 'settings.theme_mode';
  static const String _kCodeFontSize = 'settings.code_font_size';
  static const String _kOnlySupported = 'settings.only_supported';

  /// 读取全部设置。任何一项缺失或非法都退回默认值，不抛异常——
  /// 设置读失败不该让整个 App 起不来。
  Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();

    final themeRaw = prefs.getString(_kThemeMode);
    final theme = _themeModeFromRaw(themeRaw) ?? AppSettings.defaults.themeMode;

    final sizeRaw = prefs.getDouble(_kCodeFontSize);
    final size = sizeRaw == null
        ? AppSettings.defaults.codeFontSize
        : clampFontSize(sizeRaw);

    final onlySupported =
        prefs.getBool(_kOnlySupported) ?? AppSettings.defaults.onlySupported;

    return AppSettings(
      themeMode: theme,
      codeFontSize: size,
      onlySupported: onlySupported,
    );
  }

  /// 保存全部设置。
  Future<void> save(AppSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kThemeMode, settings.themeMode.name);
    await prefs.setDouble(
      _kCodeFontSize,
      clampFontSize(settings.codeFontSize),
    );
    await prefs.setBool(_kOnlySupported, settings.onlySupported);
  }

  /// 把字号夹到合法区间。
  static double clampFontSize(double v) {
    if (v.isNaN) return AppSettings.defaults.codeFontSize;
    if (v < AppSettings.minCodeFontSize) return AppSettings.minCodeFontSize;
    if (v > AppSettings.maxCodeFontSize) return AppSettings.maxCodeFontSize;
    return v;
  }

  /// 字符串 → ThemeMode；无法识别返回 null。
  static ThemeMode? _themeModeFromRaw(String? raw) {
    if (raw == null) return null;
    for (final m in ThemeMode.values) {
      if (m.name == raw) return m;
    }
    return null;
  }
}

/// 主题模式的中文名（设置页与关于页共用）。
String themeModeLabel(ThemeMode mode) {
  switch (mode) {
    case ThemeMode.system:
      return '跟随系统';
    case ThemeMode.dark:
      return '强制深色';
    case ThemeMode.light:
      return '强制浅色';
  }
}

/// 主题模式的完整说明（设置页副标题用）。
String themeModeDescription(ThemeMode mode) {
  switch (mode) {
    case ThemeMode.system:
      return '跟随系统设置';
    case ThemeMode.dark:
      return '始终使用深色主题';
    case ThemeMode.light:
      return '始终使用浅色主题';
  }
}
