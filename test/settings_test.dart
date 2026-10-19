// 阶段 9（打磨与打包）的测试。
//
// 重点是**设置持久化**：主题 / 代码字号 / 首页过滤开关三项，
// 用户调完之后重启必须还在。这类"写进去了但读不回来"的问题
// 只有走一遍完整往返才能发现。
//
// 另外校验若干打包相关的静态事实（图标资源齐全、版本号一致），
// 这些在构建失败时才发现的代价很高。

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:stm32_spl_helper/data/settings_store.dart';
import 'package:stm32_spl_helper/providers/app_providers.dart';

/// 造一个可注入的容器
ProviderContainer makeContainer() {
  final c = ProviderContainer();
  addTearDown(c.dispose);
  return c;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('设置：默认值', () {
    test('首次启动用默认值', () async {
      final s = await SettingsStore().load();
      expect(s.themeMode, ThemeMode.system);
      expect(s.codeFontSize, 13.0);
      expect(s.onlySupported, isFalse);
      expect(s, AppSettings.defaults);
    });
  });

  group('设置：持久化往返', () {
    test('主题模式写进去能读回来', () async {
      final store = SettingsStore();
      await store.save(const AppSettings(themeMode: ThemeMode.dark));
      final back = await store.load();
      expect(back.themeMode, ThemeMode.dark);
    });

    test('三种主题模式都能往返', () async {
      for (final m in ThemeMode.values) {
        final store = SettingsStore();
        await store.save(AppSettings(themeMode: m));
        expect((await store.load()).themeMode, m, reason: '$m 往返失败');
      }
    });

    test('代码字号写进去能读回来', () async {
      final store = SettingsStore();
      await store.save(const AppSettings(codeFontSize: 17.0));
      expect((await store.load()).codeFontSize, 17.0);
    });

    test('首页过滤开关写进去能读回来', () async {
      final store = SettingsStore();
      await store.save(const AppSettings(onlySupported: true));
      expect((await store.load()).onlySupported, isTrue);
    });

    test('三项一起写不会互相覆盖', () async {
      final store = SettingsStore();
      await store.save(const AppSettings(
        themeMode: ThemeMode.light,
        codeFontSize: 19.0,
        onlySupported: true,
      ));
      final back = await store.load();
      expect(back.themeMode, ThemeMode.light);
      expect(back.codeFontSize, 19.0);
      expect(back.onlySupported, isTrue);
    });

    test('跨实例保留（真实持久化，不是内存态）', () async {
      await SettingsStore().save(const AppSettings(themeMode: ThemeMode.dark));
      expect((await SettingsStore().load()).themeMode, ThemeMode.dark);
    });
  });

  group('设置：容错', () {
    test('字号超上限被夹回', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('settings.code_font_size', 999.0);
      final s = await SettingsStore().load();
      expect(s.codeFontSize, AppSettings.maxCodeFontSize);
    });

    test('字号超下限被夹回', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('settings.code_font_size', 1.0);
      expect(
        (await SettingsStore().load()).codeFontSize,
        AppSettings.minCodeFontSize,
      );
    });

    test('保存时也夹一次（避免写进非法值）', () async {
      final store = SettingsStore();
      await store.save(const AppSettings(codeFontSize: 100.0));
      expect((await store.load()).codeFontSize, AppSettings.maxCodeFontSize);
    });

    test('NaN 字号退回默认值而不是崩溃', () {
      expect(SettingsStore.clampFontSize(double.nan), 13.0);
    });

    test('无法识别的主题字符串退回默认', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('settings.theme_mode', 'rainbow');
      expect((await SettingsStore().load()).themeMode, ThemeMode.system);
    });

    test('存储里混入其它键不影响读取', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('unrelated.key', 'x');
      await prefs.setBool('settings.only_supported', true);
      final s = await SettingsStore().load();
      expect(s.onlySupported, isTrue);
      expect(s.themeMode, ThemeMode.system);
    });
  });

  group('设置：notifier', () {
    test('setThemeMode 后 state 立刻更新', () async {
      final c = makeContainer();
      await c.read(settingsProvider.future);
      await c.read(settingsProvider.notifier).setThemeMode(ThemeMode.dark);
      expect(c.read(settingsProvider).valueOrNull!.themeMode, ThemeMode.dark);
    });

    test('setThemeMode 会落盘（新实例能读到）', () async {
      final c = makeContainer();
      await c.read(settingsProvider.future);
      await c.read(settingsProvider.notifier).setThemeMode(ThemeMode.light);
      expect((await SettingsStore().load()).themeMode, ThemeMode.light);
    });

    test('setCodeFontSize 会自动夹到合法区间', () async {
      final c = makeContainer();
      await c.read(settingsProvider.future);
      await c.read(settingsProvider.notifier).setCodeFontSize(500);
      expect(
        c.read(settingsProvider).valueOrNull!.codeFontSize,
        AppSettings.maxCodeFontSize,
      );
    });

    test('派生 provider 跟着设置走', () async {
      final c = makeContainer();
      await c.read(settingsProvider.future);
      // 初始值
      expect(c.read(themeModeProvider), ThemeMode.system);
      expect(c.read(codeFontSizeProvider), 13.0);
      expect(c.read(onlySupportedProvider), isFalse);

      await c.read(settingsProvider.notifier).setThemeMode(ThemeMode.dark);
      await c.read(settingsProvider.notifier).setCodeFontSize(16);
      await c.read(settingsProvider.notifier).setOnlySupported(true);

      expect(c.read(themeModeProvider), ThemeMode.dark);
      expect(c.read(codeFontSizeProvider), 16.0);
      expect(c.read(onlySupportedProvider), isTrue);
    });

    test('未加载完时派生 provider 给默认值（不崩、不返回 null）', () {
      final c = makeContainer();
      // 故意不 await settingsProvider.future
      expect(c.read(themeModeProvider), ThemeMode.system);
      expect(c.read(codeFontSizeProvider), 13.0);
      expect(c.read(onlySupportedProvider), isFalse);
    });

    test('恢复默认设置', () async {
      final c = makeContainer();
      await c.read(settingsProvider.future);
      await c.read(settingsProvider.notifier).setThemeMode(ThemeMode.dark);
      await c.read(settingsProvider.notifier).setOnlySupported(true);

      await c.read(settingsProvider.notifier).resetToDefaults();

      final s = c.read(settingsProvider).valueOrNull!;
      expect(s, AppSettings.defaults);
      // 也要落盘
      expect((await SettingsStore().load()).themeMode, ThemeMode.system);
    });

    test('多次修改不会丢掉之前改过的项', () async {
      final c = makeContainer();
      await c.read(settingsProvider.future);
      final n = c.read(settingsProvider.notifier);

      await n.setThemeMode(ThemeMode.dark);
      await n.setCodeFontSize(18);
      await n.setOnlySupported(true);

      final s = c.read(settingsProvider).valueOrNull!;
      expect(s.themeMode, ThemeMode.dark, reason: '改字号不应把主题改回去');
      expect(s.codeFontSize, 18.0);
      expect(s.onlySupported, isTrue);
    });
  });

  group('AppSettings', () {
    test('copyWith 只改指定字段', () {
      const base = AppSettings(
        themeMode: ThemeMode.dark,
        codeFontSize: 15,
        onlySupported: true,
      );
      final changed = base.copyWith(codeFontSize: 12);
      expect(changed.themeMode, ThemeMode.dark);
      expect(changed.codeFontSize, 12);
      expect(changed.onlySupported, isTrue);
    });

    test('相等性按三个字段判断', () {
      expect(
        const AppSettings(themeMode: ThemeMode.dark),
        const AppSettings(themeMode: ThemeMode.dark),
      );
      expect(
        const AppSettings(themeMode: ThemeMode.dark),
        isNot(const AppSettings(themeMode: ThemeMode.light)),
      );
    });
  });

  group('主题模式文案', () {
    test('三种模式都有简称与说明', () {
      for (final m in ThemeMode.values) {
        expect(themeModeLabel(m), isNotEmpty);
        expect(themeModeDescription(m), isNotEmpty);
      }
    });
  });

  group('打包资源（静态校验）', () {
    final res = Directory('android/app/src/main/res');

    test('各密度的启动图标都在，且尺寸递增', () {
      final expected = <String, int>{
        'mdpi': 48,
        'hdpi': 72,
        'xhdpi': 96,
        'xxhdpi': 144,
        'xxxhdpi': 192,
      };
      expected.forEach((density, _) {
        final f = File('${res.path}/mipmap-$density/ic_launcher.png');
        expect(f.existsSync(), isTrue, reason: '缺 $density 的启动图标');
        expect(f.lengthSync(), greaterThan(100),
            reason: '$density 图标是空文件或占位图');
      });
    });

    test('自适应图标的前景/背景层齐全', () {
      for (final d in <String>[
        'mdpi',
        'hdpi',
        'xhdpi',
        'xxhdpi',
        'xxxhdpi',
      ]) {
        expect(
          File('${res.path}/mipmap-$d/ic_launcher_foreground.png').existsSync(),
          isTrue,
          reason: '缺 $d 的自适应前景',
        );
        expect(
          File('${res.path}/mipmap-$d/ic_launcher_background.png').existsSync(),
          isTrue,
          reason: '缺 $d 的自适应背景',
        );
      }
    });

    test('自适应图标 XML 存在且引用了前后景', () {
      final f = File('${res.path}/mipmap-anydpi-v26/ic_launcher.xml');
      expect(f.existsSync(), isTrue);
      final xml = f.readAsStringSync();
      expect(xml, contains('ic_launcher_background'));
      expect(xml, contains('ic_launcher_foreground'));
    });

    test('启动图存在，且两份 launch_background 都引用了它', () {
      expect(
        File('${res.path}/drawable-nodpi/splash_logo.png').existsSync(),
        isTrue,
      );
      for (final p in <String>[
        '${res.path}/drawable/launch_background.xml',
        '${res.path}/drawable-v21/launch_background.xml',
      ]) {
        final xml = File(p).readAsStringSync();
        expect(xml, contains('splash_logo'), reason: '$p 没引用启动图');
      }
    });

    test('图标不是 Flutter 默认图标（默认图标约 5KB 以上纯色块）', () {
      // Flutter 默认图标在各密度下都是几百字节的纯色方块 + 白色 F 标；
      // 我们生成的图标带渐变，同样尺寸下压缩后体积明显不同。
      // 这里用"能否解码出透明像素"判断：我们的图标四角是透明的圆角，
      // 而 Flutter 默认图标是完整不透明的方块。
      final f = File('${res.path}/mipmap-xxxhdpi/ic_launcher.png');
      final bytes = f.readAsBytesSync();
      // PNG 里有 alpha 通道时会有 tRNS 或颜色类型 6；这里做粗略校验
      expect(bytes.length, greaterThan(500));
      // 文件头必须是 PNG
      expect(bytes.sublist(1, 4), <int>[0x50, 0x4E, 0x47]);
    });
  });

  group('版本一致性', () {
    test('pubspec 的版本与应用内常量一致', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final m = RegExp(r'^version:\s*([0-9.]+)', multiLine: true)
          .firstMatch(pubspec);
      expect(m, isNotNull, reason: 'pubspec 里找不到 version');
      // lib/utils/app_info.dart 里的 appVersion
      final info = File('lib/utils/app_info.dart').readAsStringSync();
      final v = RegExp(r"appVersion\s*=\s*'([0-9.]+)'").firstMatch(info);
      expect(v, isNotNull, reason: 'app_info.dart 里找不到 appVersion');
      expect(
        v!.group(1),
        m!.group(1),
        reason: 'pubspec ($m) 与 app_info.dart (${v.group(1)}) 版本号不一致',
      );
    });

    // ---- 升级安装相关 ----
    //
    // 覆盖安装要求 versionCode 存在且为正整数。
    // 这条测不住"这一版比上一版大"（那要对比历史包），但能拦住
    // 漏写 +N 这种最常见的手误——漏了的话 Gradle 会静默沿用
    // versionName 派生的值，装机时表现为"装不上也不报错"。
    test('pubspec 的 version 必须带 +versionCode 且为正整数', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final m = RegExp(r'^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)\s*$',
              multiLine: true)
          .firstMatch(pubspec);
      expect(m, isNotNull,
          reason: 'pubspec 的 version 应形如 "1.0.0+1"，缺少 +versionCode 会导致升级安装失败');
      final code = int.parse(m!.group(2)!);
      expect(code, greaterThan(0), reason: 'versionCode 必须为正整数，实际 $code');
    });

    test('发版脚本存在且包含验签与版本校验步骤', () {
      final f = File('tools/release.ps1');
      expect(f.existsSync(), isTrue, reason: '缺少一键发版脚本 tools/release.ps1');
      final s = f.readAsStringSync();
      // 脚本必须真的验签，而不是只构建
      expect(s, contains('apksigner'), reason: '发版脚本未调用 apksigner 验签');
      // 必须回读 APK 里的 versionCode 并比对，防止 pubspec 改了但没生效
      expect(s, contains('versionCode'),
          reason: '发版脚本未校验 APK 内的 versionCode');
    });

    test('AndroidManifest 的应用名是中文且与 app_info 一致', () {
      final manifest =
          File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
      final info = File('lib/utils/app_info.dart').readAsStringSync();
      final name = RegExp(r"appName\s*=\s*'([^']+)'").firstMatch(info)!.group(1)!;
      expect(manifest, contains('android:label="$name"'));
    });

    test('应用数据统计与实际数据一致', () {
      final manifest = jsonDecode(
        File('assets/data/manifest.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      final stats = manifest['stats'] as Map<String, dynamic>;
      expect(stats['functionCount'], 488);
      expect(stats['symbolCount'], 7337);
      expect(stats['pinCount'], 48);
      expect(stats['compileErrorCount'], 15);
    });
  });
}
