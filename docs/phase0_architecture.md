# 阶段 0：方案确认

本文档只做决策与结构定义，不含业务代码。阶段 1 起才开始写解析脚本与 Flutter 代码。

---

## 1. 状态管理选型：Riverpod（`flutter_riverpod`）

结论：选 **Riverpod**，不选 Provider。

理由（针对本项目，不是泛泛而谈）：

1. **本项目的数据流是"一次性加载 → 全局只读索引"**。Riverpod 的 `Provider` / `FutureProvider` 天然表达"异步加载一次、全局共享、自动缓存"，`AsyncValue` 自带 loading / error 三态，正好对应"首屏加载超过 1 秒要显示 loading、加载失败不能白屏"这条硬要求；Provider 需要自己写 `ChangeNotifier` + `FutureBuilder` 组合，代码更多。
2. **加载失败必须友好提示**。Riverpod 的 `AsyncValue.when(error: ...)` 把错误分支变成编译期必须处理的分支，漏写会编译不过；Provider 容易漏。
3. **不需要 `BuildContext`**。`KeywordText` 里点击符号跳转、`user_database` 读写收藏，都要在非 Widget 层拿数据；Riverpod 的 `ref.read` 在任意位置可用，Provider 只能靠 `context.read`，Widget 树一深就得层层传。
4. **细粒度重建**。函数详情页会同时订阅"收藏状态 / 笔记内容 / 代码字号"三份状态，Riverpod 的 `select` 只重建用到该字段的 Widget；Provider 一个 `notifyListeners` 会重建整页。
5. **Provider 作者本人已把 Riverpod 定位为后继方案**，长期维护性更好。

不引入 `riverpod_generator` / `build_runner`：本项目 Provider 数量不超过 15 个，手写 `Provider` 更省事，也符合"不要过度设计"。

Provider 清单（阶段 2 实现，先定名）：

| Provider | 类型 | 职责 |
|---|---|---|
| `assetRepositoryProvider` | `Provider` | 持有 `AssetRepository` 单例 |
| `splDataProvider` | `FutureProvider` | 加载全部 assets JSON，返回 `SplData` 聚合对象 |
| `searchIndexProvider` | `Provider` | 依赖 `splDataProvider`，构建内存倒排索引 |
| `userDatabaseProvider` | `FutureProvider` | 打开 sqflite，建表迁移 |
| `favoritesProvider` | `AsyncNotifierProvider` | 收藏集合，写库后刷新 |
| `recentProvider` | `AsyncNotifierProvider` | 最近查看（上限 100） |
| `notesProvider` | `AsyncNotifierProvider` | 笔记 CRUD |
| `searchHistoryProvider` | `AsyncNotifierProvider` | 搜索历史（上限 20） |
| `settingsProvider` | `AsyncNotifierProvider` | 主题模式 / 代码字号 / 仅显示 C8T6 支持外设 |
| `currentChipProvider` | `Provider` | 当前芯片配置（首期固定 stm32f103c8t6） |

---

## 2. 其它选型决策

| 项 | 决策 | 理由 |
|---|---|---|
| 代码高亮 | **自研轻量 C 词法高亮器**（`lib/utils/c_highlighter.dart`），不用 `flutter_highlight` | 见下方专节 |
| 剪贴板 | `flutter/services.dart` 的 `Clipboard`（Flutter 内置） | 零依赖，无网络 |
| 分享导出 | `share_plus` 的 `Share.shareXFiles` | 纯本地，走系统分享面板 |
| 导出文件落盘 | `path_provider` 的 `getTemporaryDirectory()` | Android 上无需存储权限 |
| 数据库 | `sqflite`（表结构见 `docs/data_model.md` 第 6 节） | 需求指定 |
| 设置存储 | `shared_preferences`（仅存主题/字号/开关三个标量） | 比 sqflite 建表更轻 |
| JSON 序列化 | **手写 `fromJson` / `toJson`**，不用 `json_serializable` + `build_runner` | 模型 10 个左右，手写可控；省掉代码生成链，也方便你直接改字段 |
| 路由 | `Navigator 1.0`（`MaterialPageRoute`） | 关键词跳转要求"点进去能返回原位置"，命名路由 + push 天然满足；不引入 `go_router` |
| 数据版本 | `manifest.json` 里 `dataVersion` + `schemaVersion`，设置页展示 | 以后换 SPL 版本可对比 |

### 为什么不用 `flutter_highlight`

1. `flutter_highlight` 依赖 `highlight` 包，后者长期未跟进 Dart 3 空安全/语言版本，在较新的 Flutter 稳定版上存在解析失败风险。
2. **更关键的是需求 5.3 的关键词跳转**：示例代码里的 `GPIO_Mode_Out_PP` 必须可点击。`flutter_highlight` 只输出按语言语法分的 token，不理解"库内符号"这一层语义，要再包一层文本二次扫描，等于把同一段代码解析两遍，还容易破坏高亮边界。
3. 自研版只要 300 行左右：先做 C 词法切分（注释 / 字符串 / 预处理指令 / 数字 / 关键字 / 类型名 / 标识符 / 运算符），再对"标识符"这一类做符号表匹配，命中即渲染成可点击 `TextSpan`。一次扫描同时满足"高亮 + 跳转"两个需求。
4. 纯 Dart，无原生依赖，真机行为与模拟器一致。

保留退路：若阶段 4 你验收后觉得高亮效果不够，可随时替换 `CodeBlock` 内部的渲染实现，对外接口不变。

---

## 3. 完全离线的保证措施（可验证）

1. `pubspec.yaml` 的 `dependencies` 中**不含** `http`、`dio`、`google_fonts`、`url_launcher`、`webview_flutter`、任何 `*_web` 包（见 `docs/dependencies.md` 逐包说明）。
2. `android/app/src/main/AndroidManifest.xml` **不声明** `android.permission.INTERNET`。Android 上无此权限，任何 socket 连接都会直接抛异常，这是运行期的硬保证。
3. 同文件配置 `android:usesCleartextTraffic="false"`，并加 `networkSecurityConfig` 全量禁止明文流量（双保险，防止未来某个依赖偷偷联网）。
4. 加一条 CI 式的自检命令（阶段 9 写进 `tools/README.md`）：在项目根目录 grep 网络相关标识符，命中即失败。
5. 所有数据来自 `assets/data/`，所有用户数据来自 sqflite，无后端。

---

## 4. 目录结构（相对需求第 6 节的调整及理由）

```text
stm32_spl_helper/
├── assets/data/                  # 打包进 APP 的静态数据（解析产物 + 中文 overlay 合并结果）
│   ├── manifest.json
│   ├── peripherals.json
│   ├── functions/<PERIPHERAL>.json
│   ├── symbols.json
│   ├── pinout_f103c8t6.json
│   ├── compile_errors.json
│   └── chips/stm32f103c8t6.json
├── data/zh_overlay/              # 【新增】中文补充源文件，只进仓库不进 APK
│   ├── peripherals.json
│   ├── functions/{GPIO,RCC,USART,TIM}.json
│   ├── symbols.json
│   ├── pinout_notes.json         # 【新增】引脚中文备注与 JTAG/5V 标注
│   └── compile_errors_zh.json    # 【新增】编译错误中文条目（纯人工内容，无解析来源）
├── docs/                         # 【新增】阶段 0 产出：选型、数据模型、依赖清单
├── lib/
│   ├── main.dart
│   ├── app.dart
│   ├── models/                   # 已在本阶段完成
│   ├── data/
│   ├── pages/
│   ├── widgets/
│   ├── providers/                # 【新增】Riverpod Provider 集中放置，避免散落在各页面
│   └── utils/
├── tools/
│   ├── parse_spl.py
│   ├── merge_overlay.py
│   ├── schemas/                  # 【新增】JSON Schema，校验解析产物
│   ├── validate_data.py          # 【新增】合并后的数据完整性检查（断链、重复 id）
│   └── README.md
├── test/
└── pubspec.yaml
```

四处调整的理由：

- `data/zh_overlay/` 放在 `assets/` **外面**：它是"源文件"，不是"运行时数据"，放进 assets 会白白增大 APK，也容易被误当成最终数据改。
- `docs/`：需求里没写，但阶段 0 要交付选型与模型文档，必须有落点。
- `lib/providers/`：Provider 定义若分散在各页面文件里，`user_database` 的读写会互相 import 成环，集中放最省事。
- `tools/schemas/` + `tools/validate_data.py`：需求要求"解析失败打印警告不要静默跳过"，Schema 校验能在合并阶段再兜一次底。

---

## 5. 与需求不一致 / 需要你拍板的点

见 `docs/questions.md`，请逐条回复后再进入阶段 1。
