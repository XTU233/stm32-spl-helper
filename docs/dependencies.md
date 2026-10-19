# pub 依赖清单（逐包标注离线安全性）

判定标准分两层，必须都满足：

- **运行时**：包在 APP 运行期间不发起任何网络 I/O（这是"完全离线"的真正含义）。
- **构建时**：`pub get` 需要联网拉包，但只发生在你的开发机上，产物 APK 不含网络行为。

下表"运行时联网"一列若为"否"，即表示该包不申请 INTERNET 权限、不建 socket。

| 包 | 版本约束 | 用途 | 运行时联网 | 说明 |
|---|---|---|---|---|
| `flutter_riverpod` | `^2.6.1` | 状态管理 | 否 | 纯 Dart，无原生通道 |
| `sqflite` | `^2.4.1` | 收藏/笔记/最近/搜索历史 | 否 | 走 Android SQLite，纯本地 |
| `path` | `^1.9.0` | 拼接数据库与导出文件路径 | 否 | 纯 Dart（`p.join`） |
| `path_provider` | `^2.1.5` | 取临时目录写导出文件 | 否 | 仅访问应用私有目录 |
| `shared_preferences` | `^2.3.3` | 主题模式 / 代码字号 / 显示开关 | 否 | Android SharedPreferences |
| `share_plus` | `^10.1.4` | 导出笔记 Markdown 走系统分享 | 否 | 只调用系统 Intent；**注意**：它不联网，但分享目标 App 可能联网，这与本 APP 无关 |
| `collection` | `^1.19.0` | 索引构建时用 `groupBy`/`firstWhereOrNull` | 否 | 纯 Dart |
| `flutter_highlight` | 不引入 | — | — | 见 `phase0_architecture.md` 第 2 节，改用自研 `c_highlighter.dart` |

开发期依赖（不进 APK）：

| 包 | 用途 |
|---|---|
| `flutter_test` | Widget 测试 |
| `flutter_lints` | 静态检查 |

## 明确排除的包（会被网络行为污染，或与离线目标冲突）

| 包 | 排除原因 |
|---|---|
| `http` / `dio` / `retrofit` | 直接联网 |
| `google_fonts` | 首次运行会去 fonts.gstatic.com 下载字体 |
| `url_launcher` | 可打开任意 URL，且会被静态扫描误判为联网入口 |
| `webview_flutter` | 可加载远程页面 |
| `firebase_*` / `sentry_flutter` | 上报遥测 |
| `package_info_plus` 之外的 `*_plus` 联网类包 | 逐个审查，仅保留 `share_plus` |
| `connectivity_plus` | 无意义（本 APP 不关心网络状态） |
| `json_serializable` / `build_runner` | 非联网问题，仅为省掉代码生成链 |

## Android 侧配置（阶段 2 已落实）

`android/app/src/main/AndroidManifest.xml`：

- 不声明 `android.permission.INTERNET`。
- `<application android:usesCleartextTraffic="false" android:networkSecurityConfig="@xml/network_security_config">`。
- `res/xml/network_security_config.xml` 中 `<base-config cleartextTrafficPermitted="false"/>`。
- 应用名改为「STM32 标准库助手」。

`minSdkVersion` 取 Flutter 3.47.7 默认值 24，与需求一致。

---

## 实测确认（阶段 2 构建验证）

以下结论来自真实构建产物的检查，不是推断。

### 1. `share_plus` 会传递引入 `url_launcher_*`，但**不进 Android APK**

`share_plus 10.1.4` 的 pubspec 声明了 `url_launcher_web` / `url_launcher_windows` /
`url_launcher_linux` 作为依赖（用于在桌面/Web 平台调起分享）。

实测 `.flutter-plugins-dependencies` 的插件注册情况：

| 平台 | url_launcher 是否注册 |
|---|---|
| android | **否** |
| ios | 否 |
| linux | 是 |
| windows | 是 |
| web | 是 |

Android 平台注册的插件只有：`jni`、`jni_flutter`、`path_provider_android`、
`share_plus`、`shared_preferences_android`、`sqflite_android`。

进一步检查 release APK 的 zip 条目，**未发现任何 `url_launcher` 相关类**。

结论：`url_launcher_*` 是桌面/Web 平台的实现，Android 构建不编译它们，
不影响离线目标。需求 5.5 明确要求"通过系统分享"导出笔记，`share_plus` 是必需的，
这个传递依赖无法避免，但可以确认它不产生 Android 侧的网络能力。

### 2. release APK 不含 INTERNET 权限（硬保证成立）

```
> aapt2 dump permissions app-release.apk
package: com.example.stm32_spl_helper
permission: com.example.stm32_spl_helper.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION
uses-permission: name='com.example.stm32_spl_helper.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION'
```

**没有 `android.permission.INTERNET`。** Android 上没有该权限时任何 socket 连接
都会直接抛 `SecurityException`，这是运行期硬保证。

### 3. 关于 debug/profile 构建里的 INTERNET 权限

`android/app/src/debug/AndroidManifest.xml` 与 `android/app/src/profile/AndroidManifest.xml`
是 **Flutter 模板自带**的文件，声明了 INTERNET 权限：

```xml
<!-- The INTERNET permission is required for development. Specifically,
     the Flutter tool needs it to communicate with the running application
     to allow setting breakpoints, to provide hot reload, etc. -->
<uses-permission android:name="android.permission.INTERNET"/>
```

它只用于开发期的热重载与断点调试（Flutter 工具需要与本机进程通信），
**release 构建不包含这两个文件**，已实测确认。

若希望连 debug 包也彻底无网络权限，可以删除这两个文件，代价是 `flutter run`
的热重载与断点功能不可用。当前保留，因为验收标准针对"断网状态下所有功能正常"
与"没有任何网络请求代码"，release 包已满足。

### 4. 资源打包确认

release APK 内含 32 个数据文件（5.04 MB），`data/zh_overlay/` 与 `build/` 中间产物
**均未被打包**（pubspec 的 assets 只声明了 `assets/data/` 及其两个子目录）。

### 5. 实际锁定版本（`flutter pub get` 结果）

| 包 | 实际版本 |
|---|---|
| flutter_riverpod | 2.6.1 |
| sqflite | 2.4.4+2 |
| path_provider | 2.1.5 |
| path | 1.9.0 |
| shared_preferences | 2.3.3 |
| share_plus | 10.1.4 |
| collection | 1.19.0 |

Flutter 3.47.7 / Dart 3.13.5。

### 6. 构建期已知问题与处理

Windows 上编译插件 Kotlin 代码时反复出现
`Could not close incremental caches ... class-fq-name-to-source.tab`
（Kotlin 增量编译缓存被文件锁占用，清理 build 与 Gradle daemon 都无法根治）。
已在 `android/gradle.properties` 中设 `kotlin.incremental=false` 与
`org.gradle.caching=false` 绕过，代价是首次构建慢十几秒，换来构建稳定。

## 版本说明

上表版本为撰写时的稳定版区间，`pubspec.yaml` 用 `^` 约束。阶段 2 执行 `flutter pub get` 后我会把解析到的**实际锁定版本**回填到 `pubspec.lock`，并在此表补一列"实际版本"。若某包在 `flutter pub get` 时提示需要更高 Dart SDK，我会降到兼容版本并告知你。
