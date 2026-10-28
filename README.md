# STM32 库函数助手

STM32F103C8T6 离线函数查阅 APP，同时收录**四套库**：标准库（SPL V3.5.0）、
HAL 库与 LL 库（STM32CubeF1 V1.8.7）、寄存器直驱（CMSIS）。
Flutter + Android，**完全离线**。

## 下载安装

- 到 **[Releases](../../releases)** 页面下载最新的 `stm32-helper-*.apk`（约 57 MB，Android 7.0+）
- 安装时需在系统设置中允许「安装未知来源应用」
- 每个 Release 附带 `SHA256SUMS.txt`，下载后可自行核对完整性：

  ```powershell
  # Windows
  Get-FileHash .\stm32-helper-2.0.2.apk -Algorithm SHA256
  # macOS / Linux
  sha256sum stm32-helper-2.0.2.apk
  ```

> **APK 不放在仓库里**：单个安装包约 57 MB，若提交进 Git 会让仓库体积不可控
> （历史上提交过的二进制无法真正删除）。官方安装包统一由 Releases 分发。

APK 使用自签名证书（`CN=STM32 Helper`）签发，未上架任何应用商店。
签名密钥与口令**不在本仓库**，自行构建发布版请用 `tools/make_keystore.ps1` 生成自己的密钥。

| 项目 | 值 |
|---|---|
| 包名 | `io.github.laobinghongcha.stm32helper` |
| 最低系统 | Android 7.0（API 24） |
| 目标 SDK | 36 |
| 签名证书指纹（SHA-256） | `6f0cad01074bfc761483dcefc9347c7c7301c8e5bb1e899454caddfa84a1f33b` |

## 这是什么

面向 STM32F103C8T6 的离线速查工具：按外设浏览库函数、查看寄存器与位定义、关键字跳转、
全局搜索、收藏/最近/笔记、引脚速查、编译错误速查。
全部数据随包内置，**运行时不发起任何网络请求**（未申请 Android INTERNET 权限）。

### 四库并存

| 库 | 来源 | 函数数 | 说明 |
|---|---|---:|---|
| 标准库 SPL | STM32F10x_StdPeriph_Lib V3.5.0 | 488 | `GPIO_Init` 这类传统写法 |
| HAL 库 | STM32CubeF1 V1.8.7 | 801 | `HAL_GPIO_Init`，STM32CubeMX 生成的代码用的就是它 |
| LL 库 | STM32CubeF1 V1.8.7 | 1137 | `LL_GPIO_SetPinMode`，比 HAL 更贴近寄存器 |
| 寄存器直驱 | CMSIS `stm32f103xb.h` | 472 | 直接操作 `GPIOA->ODR` 这类寄存器 |

合计 **2898 个函数**（原 488），另含 3167 条位域定义、12830 个符号。

使用要点：

- **设置 → 函数库** 里可自由勾选显示哪几套库（至少保留一个）
- **外设详情页顶部**有库切换条，按库查看函数；每行行尾有库徽标（SPL 蓝 / HAL 绿 / LL 橙 / REG 紫）
- 「使用总览」按调用顺序**逐条分行、序号顶格**显示，不再挤成一行长句
- HAL/LL 的 1938 个函数**全部有中文说明**（简述、用法、参数、示例、坑位）
- 寄存器库每个条目就是**一个寄存器**：给位域表（`GPIO_CRL_MODE0 = bits[1:0]`）与直接读写示例
- HAL 与 SPL 有 12 个同名但成员完全不同的结构体（如 `GPIO_InitTypeDef`），
  详情页按当前阅读的库给出对应那份，并可在两个版本间切换

## 当前进度

| 阶段 | 内容 | 状态 |
|---|---|---|
| 0 | 方案确认（选型 / 数据模型 / 目录结构） | 已完成 |
| 1 | 数据解析脚本 + 中文 overlay 合并 | 已完成 |
| 2 | Flutter 骨架 + 数据层 | 已完成 |
| 3 | 外设浏览 + 函数列表 | 已完成 |
| 4 | 函数详情页 + 关键词跳转 | 已完成 |
| 5 | 全局搜索 | 已完成 |
| 6 | 收藏 / 最近 / 笔记 | 已完成 |
| 7 | 引脚速查表 | 已完成 |
| 8 | 编译错误速查 | 已完成 |
| 9 | 打磨与打包 | 已完成 |
| 10 | 四库支持（HAL / LL / 寄存器）+ 使用总览改版 | 已完成 |
| 11 | 修复 APK 资源打包与同名类型混淆，转为可发布版本 | 已完成 |

## 许可

代码与中文说明以 [MIT](LICENSE) 许可开源。内置数据中来自 ST 的
函数原型、英文注释与寄存器定义，版权归 STMicroelectronics 所有，
详见 [LICENSE](LICENSE) 末尾的第三方声明。

## 快速开始

```powershell
# 环境变量（已配置为用户级，新开终端自动生效）
#   JAVA_HOME=D:\Jave  ANDROID_HOME=...\Android\Sdk
#   FLUTTER_ROOT=D:\Android Studio\Flutter\flutter_windows_3.47.7-stable\flutter

cd <PROJECT_ROOT>

flutter pub get
flutter analyze          # 应为 No issues found
flutter test             # 302 个测试应全部通过
flutter build apk --release
```

产物：`build\app\outputs\flutter-apk\app-release.apk`（约 55 MB）

> Gradle 的原始产物在 `build\app\outputs\apk\release\app-release.apk`，
> Flutter 另外复制一份到 `flutter-apk\`。**两者字节完全相同**（同一构建复制两次），
> 用哪个路径都行。

**首次构建若要出正式可分发的包**，先生成签名密钥（只需一次）：

```powershell
$env:JAVA_HOME="D:\Jave"; $env:Path="$env:JAVA_HOME\bin;$env:Path"
powershell -NoProfile -ExecutionPolicy Bypass -File tools\make_keystore.ps1
```

脚本会把口令打印出来，**请连同 `android\release-keystore.jks` 一起备份**——
丢了它就无法用同一个包名发布新版本。没有密钥库时构建会自动回退 debug 签名，
日志里会提示"仅供本机验证，不可分发"。

### 发版（出一个能覆盖安装的新版）

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\release.ps1
```

脚本做四件事：

1. **递增版本号**——`versionCode` 每次 +1，并按 `-Bump` 调整 `versionName`；
   同时同步 `lib/utils/app_info.dart` 的 `appVersion`
2. **构建** release APK
3. **验签**（`apksigner verify --print-certs`），并提示是否为发行签名
4. **回读 APK 内实际的 versionCode/versionName** 与 pubspec 比对

第 4 步是关键：只相信 APK 里真正写进去的值，不相信 pubspec 写对了。

常用参数：`-Bump patch|minor|major|build`（默认 patch）、
`-NoBump`（不改版本号只重构）、`-VerifyOnly`（只校验现有产物）。

升级安装失败的两个原因，脚本分别对应：

| 现象 | 原因 | 脚本如何防 |
|---|---|---|
| `INSTALL_FAILED_UPDATE_INCOMPATIBLE` | 签名与已装版本不一致 | 验签并打印证书指纹 |
| 装完还是旧版 / `DOWNGRADE` | versionCode 没增大 | 每次强制 +1，并回读校验 |

`versionCode` 一旦发布就**不要调小**。手机上已装的 versionCode 必须
严格小于新包的 versionCode 才能升级。

**改动数据或中文说明后**需要重跑数据流水线，见 `tools/README.md`。

**改了图标设计**后重新生成图标：

```powershell
python tools\make_icons.py
```

## 目录结构

```
stm32_spl_helper/
├── assets/data/           打包进 APK 的最终数据（5.04 MB，32 个文件）
├── data/zh_overlay/       中文补充源文件（不进 APK）
├── docs/                  选型、数据模型、依赖、环境说明
├── lib/
│   ├── models/            13 个数据模型（手写 fromJson，宽松解析）
│   ├── data/
│   │   ├── asset_repository.dart   分层加载 + 缓存
│   │   └── search_index.dart       内存搜索索引
│   ├── pages/             7 个页面
│   ├── providers/         Riverpod 状态
│   └── utils/             json_parse / theme
├── tools/                 解析与自检脚本（Python）
└── test/models_test.dart  关键工具函数测试
```

## 数据流

```
SPL 库源码 ──parse_spl.py──┐
                           ├─→ build/base/ ──merge_overlay.py──→ assets/data/
引脚定义.xlsx ─parse_pinout_xlsx.py─┘                  ↑
                                          data/zh_overlay/
```

改了中文**不需要重新解析库**，只跑合并与校验即可。详见 `tools/README.md`。

## 数据规模（实测）

| 项 | 数量 |
|---|---|
| 外设 | 25 个（含 CMSIS / CORTEX 两个符号专用） |
| 库函数 | 488 个 |
| 符号 | 7337 个（API 2450 + 寄存器位定义 4887） |
| 引脚 | 48 个（LQFP48 完整） |
| 编译错误 | 15 条 |
| 中文覆盖 | 外设 25/25、函数 488/488、结构体/枚举成员 663/726、符号简述 129/7337 |

**全部 488 个库函数都有中文简述、使用说明、前置条件、示例代码与常见坑**，
覆盖 23 个有函数的外设（GPIO、RCC、USART、TIM、MISC、EXTI、SPI、I2C、ADC、
DMA、FLASH、PWR、BKP、IWDG、WWDG、RTC、CRC、DBGMCU、CAN、CEC、DAC、FSMC、SDIO）。
另两个外设（CMSIS、CORTEX）只提供符号、没有函数，因此没有函数级中文。

**结构体与枚举成员的中文覆盖 663/726（91.3%）**。这一块曾经是漏的：
早期只做了函数的中文，`I2C_InitTypeDef`、`SPI_InitTypeDef` 这类结构体
点进去成员说明全是英文。现已补齐 **22 个 Init/Config 结构体、
32 个 CMSIS 寄存器映射结构体、10 个枚举类型**。
唯一豁免的是 `ETH_TypeDef`——STM32F103 全系没有以太网外设，写它没有意义。

符号**简述**只覆盖 129 个高频符号；其余 2300+ 个是未被任何函数引用的
位定义宏，未覆盖的在界面上显示 ST 英文原文。这是成本收益权衡：
用户几乎不会点进去，而逐个写会显著推高维护成本。

CEC / DAC / FSMC / SDIO 四个外设在 C8T6 上**引脚未引出**，界面上标记为
"该型号不支持"并给出原因，但函数说明照常写全（供换型号时查阅）。

## 关键词点击跳转的实现（阶段 4 核心）

需求 5.3 要求"正文、参数表、代码块三处都要能跳转"，实现分三层：

**1. 白名单来源：`symbolRefs`**

解析脚本原本只扫原型、参数与 ST 英文注释来算 `symbolRefs`，但那时中文 overlay
还没合并——**示例代码里的 `GPIO_Mode_Out_PP` 因此不在白名单里，点不了**。
这是实测发现的真问题，修法是在 `merge_overlay.py` 里合并完中文后**重算一次**，
把示例代码、中文说明、前置条件、寄存器名里的库内符号都收进来，并同步重建
符号的 `usedBy` 反向索引。重算后全库共 531 条引用（中文补齐后又新增 4032 条）。

**2. 匹配策略：`SymbolMatcher`**

用"白名单 + 词边界"而不是全局正则，避免把 `int`、`for` 误判成链接。
两个刻意的取舍：

- **拒绝长度 ≤ 2 的名字**（`u8`、`s8`、`OB`），它们在自然语言里出现频率太高，
  误链接的代价大于收益；
- **只匹配完整标识符**，`GPIO_Ini` 不会命中 `GPIO_Init`。

**3. 三处落地**

| 位置 | 实现 |
|---|---|
| 正文（使用说明、注意事项、前置条件） | `KeywordText`，按白名单切段渲染成可点击 TextSpan |
| 参数表 | 参数名用等宽字体，参数**类型**用 `KeywordText`，`GPIO_InitTypeDef*` 里的类型名可点 |
| 代码块 | `CodeBlock` 用自研 `CHighlighter` 先做词法分析，再对标识符类 token 标记符号；**注释与字符串里的同名文字不标记**（点了会很突兀） |

代码高亮没有用 `flutter_highlight`（理由见 `docs/phase0_architecture.md`）：
自研版一次扫描同时满足"高亮 + 跳转"，且能精确控制哪些 token 可点击。

**返回栈**：全部用 `Navigator.push`，跳转后返回即回到原位置，页面状态
（滚动位置、折叠状态）由 Flutter 自动保持。

## 真机反馈修复记录

装到真机后暴露了两个问题，都已修复并加了回归测试。

### 1. 点高亮词提示「未收录符号」

**现象**：`NVIC_Init` 详情页里点示例代码中的 `NVIC_Init`、`NVIC_PriorityGroupConfig`
等函数名，弹出「未收录符号」。

**根因**：数据源不一致。高亮用的白名单来自外设的 `functionIds`
（`peripherals.json`，首屏就有），而跳转判断 `isKnownFunction()` 只查
`functionById`——函数详情是**按需加载**的，首屏时那个 Map 是空的。
于是"能高亮、点了报错"。同时 `MISC`（NVIC/SysTick）根本没有中文 overlay，
`NVIC_Init` 的 `usageZh`/`exampleCode` 都是空的。

**修复**：
- `SplData` 新增 `_allFunctionIds`（由 `peripherals.json` 汇总）与
  `_functionToPeripheral` 反查表；`isKnownFunction()` 回退查前者，
  保证首屏也能正确判定
- 新增 `peripheralIdOfFunction()`，详情页用它定位外设，与跳转判断共用一份数据源
- 补写 `data/zh_overlay/functions/MISC.json`（5 个函数，含 NVIC_Init、
  NVIC_PriorityGroupConfig 等）
- 搜索索引同样的问题：原来只索引已加载的函数，首屏搜不到函数名。
  改为先用 `functionIds` 建条目，进过外设页后用 `withFunctions` **替换**为详情

### 2. 函数名竖排显示

**现象**：GPIO「数据读取函数」栏、USART「中断管理函数」栏的函数名被挤成一列
竖着显示，其他栏正常。

**根因**：`_FunctionTile` 的 `Row` 里，返回值是**无约束的 `Text`**，而它的内容是
`displayReturn` 返回的 `returnDescZh` **全文**——恰好这两个栏的函数返回值说明都
长达 39~40 字（如「返回引脚电平：Bit_SET（1）为高电平，Bit_RESET（0）为低电平。」）。
它抢占了几乎全部宽度，把 `Expanded` 里的函数名压到只剩零宽，英文标识符只能按
字符换行。

实测复现（360dp 真机宽度）：旧代码下函数名尺寸 **0.0 × 399.0**（宽度归零、
高度 399，完全竖排）。

**修复**（两层）：
- `displayReturn` 改为只返回**类型级短标签**（`void` / `uint8_t` / `FlagStatus`），
  不再返回中文长句；长句只在详情页的「返回值」区块展示。新增 `shortReturnZh`
  供需要一句话摘要的地方使用
- 布局加约束：函数名 `Expanded` + `softWrap: false` + `maxLines: 1`，
  返回值 `Flexible` + `maxLines: 1`，两者溢出都省略，任何内容长度都不会挤爆

**同类风险复查**：扫描了全部 15 处「Row 内混排 Expanded 与裸 Text」的位置，
其余都是「图标 + Expanded 文本」或「固定宽 SizedBox + Expanded」的安全写法。
唯一另一处有挤压风险的是搜索结果项的 `trailing`（最长函数名 41 字符，
如 `ADC_GetSoftwareStartInjectedConvCmdStatus`），已给 `trailing` 加
`maxWidth: 56` 约束、`title` 加单行省略。

### 3. 搜索 `uart` 搜不到 USART（写测试时顺带发现）

`USART_Init` 里并**不含**子串 `uart`（`usart` 是 u-s-a-r-t），所以验收标准
「搜索 uart 能搜到 USART 相关函数」实际是失败的。

**修复**：对纯字母查询（长度 ≥ 3）额外做**子序列匹配**——`uart` 是 `usart` 的
子序列（跳过 s）。子序列命中得分（200）低于子串匹配（400），保证精确匹配排前面。

### 4. 除函数名外，点什么都提示「未收录符号」

**现象**：`GPIO_Mode_Out_PP`、`NVIC_InitTypeDef`、`ENABLE`、`GPIOA` 这类宏名、
枚举值、结构体名，点进去一律弹「未收录符号」。只有函数名能正常跳转。

**根因**：解析脚本产出的符号字典**只有 `name`、没有 `id`**。
`tools/parse_spl.py` 里函数的写法是 `"id": rf.name`，但宏/枚举/结构体的构造处
只写了 `"name": ...`。而 `SymbolItem.fromJson` 读的是 `json['id']`，
于是 `id` 全为 `null`，`SplData.symbolById = {for (s in symbols) s.id: s}`
的键全是 `null`、互相覆盖，**最终这个索引里只剩一条**，
`isKnownSymbol()` 对任何名字都返回 `false`。

**修复**：
- `parse_spl.py` 的 5 处符号构造（宏 / 枚举类型 / 枚举值 / 结构体 / typedef）
  统一补上 `"id": <name>`，并在写盘前加兜底
- `merge_overlay.py` 新增 `extraSymbols` 条目时同样补 `id`，并在返回前统一兜底
- `symbol_detail_page.dart` 查寄存器位定义时改用 `id` 匹配，与索引口径一致
- 新增 5 个回归测试（见下），其中一个专门断言
  **「SymbolMatcher 能画成链接的词，SplData 一定能跳转」**——
  这条不变量一旦被破坏就会报错，正是本次 bug 的形状

**为什么之前没测出来**：`models_test.dart` 用的是手写的假数据，假数据里 `id`
是齐的；而真实数据的问题只有读 `assets/data/` 才能发现。所以回归测试加在了
`data_integration_test.dart`（读真实 JSON）里。

## 阶段 5：全局搜索

搜索的索引层（`lib/data/search_index.dart`）在阶段 2 就建好了，本阶段补的是
交互层与几个缺口。

**搜索历史**（`lib/data/search_history.dart`）

存 `shared_preferences` 而不是 sqflite：历史就是"最近用过的 20 个短字符串"，
没有查询、没有关联、不需要事务。sqflite 留给阶段 6 的收藏/笔记
（那些要按外设分组、按时间排序、可全文检索）。

两个容易忽略的点：
- **只在"确认搜索"时记录**（回车、点结果、点历史），不在每次 `onChanged` 时记。
  否则打 `GPIO_Init` 会往历史里塞 9 条前缀垃圾（`G`、`GP`、`GPI`…）。
- **去重忽略大小写**，`gpio_init` 与 `GPIO_INIT` 是同一条，只保留最近一次的写法。

**结果高亮**（`lib/utils/highlighter.dart`）

不用正则做匹配。用户输入里可能有 `.`、`*`、`(`、`\` 这些元字符，直接进正则
要么抛异常要么匹配到意外内容。改成大小写不敏感的逐位置比较，行为可预期；
测试里专门拿 `.*`、`[`、`\` 这些串跑了一遍。

标题的命中片段加粗 + 主题色 + 浅色背景块（让人一眼看出"为什么搜出这条"），
副标题只加粗着色不加背景（否则整行花掉）。

**类型筛选**

结果摘要栏下加一排筛选片（全部/函数/符号/外设/引脚/编译错误），带每类数量角标。
只显示有结果的类别，避免空状态下堆一排灰按钮。换关键词时自动重置筛选——
不重置的话会出现"上次筛了引脚、这次搜函数却一片空白"的困惑。

**顺带补的缺口**
- 搜索框的示例 chips（`GPIO_In`、`uart`…）以前点了没反应，现在会填进输入框并立即搜索
- 「包含内部断言宏」开关以前只在 provider 里，现在接到搜索框右上角的眼睛图标
- 新增 `compile_error_detail_page.dart`：搜索结果里的"编译错误"类别以前点了只弹
  "阶段 8 实现"的提示，现在有真正的详情页（错误原文可复制、原因、解决步骤、
  相关代码、可跳转的相关函数/符号/外设）。阶段 8 只需在此基础上加分类筛选

## 阶段 6：收藏 / 最近查看 / 笔记

三张表在 `lib/data/user_database.dart`，结构与 `docs/data_model.md` 第 10 节一致，
只有一处补充：`notes` 表加了 `title` / `subtitle` 快照字段——
笔记列表要显示"这条笔记是关于哪个函数的"，存快照就不必回查 assets，
与 favorites 表的理由相同。

**一个绕不开的测试取舍**

单元测试里跑真 sqflite 需要 `sqflite_common_ffi`（提供桌面/测试用的
`databaseFactory`）。该包不在本地 pub cache 里，拉取要联网，
与项目"完全离线"的约束直接冲突。所以把**业务规则与 SQL 分开**：

- `UserStore` 抽成接口，`SqfliteUserStore` 与 `InMemoryUserStore` 两个实现
- 业务规则（去重、上限裁剪、排序、空内容即删除）在两种实现里语义一致，
  用内存实现跑 34 个测试
- SQL 语句由 `tools/sql_check.py` 用 Python 内置 sqlite3 逐条执行真实校验
  （DDL 合法性、`INSERT OR REPLACE` 去重、裁剪语句保留最新 N 条）

这个取舍的代价是"SQL 写错测不出来"，所以 SQL 保持极简，
分组之类的复杂逻辑都放在 Dart 侧。

**几个刻意的设计**

- **只在数据加载成功后记「最近查看」**。若在 `initState` 里记，
  一个 id 写错的页面（加载失败）也会留下记录，用户点进去却打不开。
- **最近查看用唯一索引 + `INSERT OR REPLACE`**，同一条目只留一行，
  重复查看自动提到最前，不必先查后写。
- **笔记清空内容即删除**，避免库里积累一堆空笔记。
- **收藏的标题是收藏当时的快照**，所以收藏/笔记列表的渲染完全不依赖
  assets 是否加载完成。
- **`ItemActions` 组件被五个详情页共用**。阶段 4/5 时星标是在每个页面里
  各写一遍的假按钮，很容易漏掉某个页面；收敛成一个组件后不会再漏。

**「我的」Tab**（`lib/pages/my_page.dart`）用 3 个子 Tab 装收藏/最近/笔记。
底部导航本来就占满 5 个位置，三块又都是"用户自己产生的数据"，合在一处。

## 阶段 7：引脚速查表

**数据已核对**。用户确认 `<PINOUT_XLSX>`
完全正确（该表是 DS5319 Table 5 的转录），因此 `verified` 改为 `true`。
重新解析该表与线上数据逐字段比对，**48 个引脚的引脚号、名称、默认功能、
复用功能列表、5V 容忍标记全部一致，差异为 0**。
`verifiedNote` 里写明了来源与确认日期，便于日后追溯。

**封装几何**（`lib/utils/chip_layout.dart`）

QFP 的引脚号是**逆时针**排列的：第 1 脚在左上角，沿左边向下到 12 脚，
下边从左到右到 24 脚，**右边从下往上**到 36 脚，上边从右到左到 48 脚。

右边与上边是"逆序"的，这是最容易写错的地方——写成顺序的话，
引脚号和物理位置会整体错位，而界面上看起来"方块都摆好了"，很难发现。
所以这块逻辑抽成纯函数，并用测试逐个断言坐标：
第 1 脚在左上、13 脚在左下、25 脚在右下、37 脚在右上，
以及"48 个引脚号落在唯一的（边 + 序号）上，不重叠"。

**三种交互**

- **排布图 / 列表**双视图：图看物理位置关系，列表看信息密度
- **按功能反查**：输入 `USART1_TX` → 高亮 PA9 与 PB6；
  图上未命中的引脚变暗，一眼看出"哪些脚能用这个功能"
- **按功能类别筛选**：电源 / 地 / 复位 / BOOT / 晶振 / 调试口 / 普通 GPIO / 复用功能，
  图例同时是筛选器（点击选中，再点取消）

分类的优先级是刻意的：一个引脚常常同时属于 `gpio`，但用户更关心
"它是电源脚"，所以电源/地/复位/BOOT/晶振/调试口都排在普通 GPIO 之前。

**测试抓到的问题**：排布图的引脚块在 360dp 下 `Column` 溢出 0.92 像素
（两行文字放不下）。这类亚像素溢出在真机上表现为黄黑条纹，
肉眼容易忽略。改用 `FittedBox` 整体缩放，360dp 与 320dp 都不再溢出。

### 改版：新增「按外设看引脚」视图

阶段 7 做完后暴露了一个方向性错误：那一版是**引脚为中心**的
（"这个脚能干什么"），而真实使用场景是**外设为中心**的——
"我要接一个 SPI Flash，SPI1 该接哪几根线"。

原来的做法要用户先在反查框里输 `SPI1_` 才能看到引脚，很别扭。
现在改成三种视图，分别回答三个问题：

| 视图 | 回答的问题 | 典型场景 |
|---|---|---|
| **按外设**（默认） | SPI1 要接哪几个脚 | 定好外设、开始接线 |
| 排布图 | 这个脚在芯片什么位置 | 画板子、对照封装 |
| 列表 | 第 30 脚是什么 | 手上有板子、看丝印 |

默认进"按外设"，因为"先定外设再找脚"是更常见的顺序，
而"这是哪个脚"通常从板子上直接就能看到。

**分组方式**：从复用功能名里解析实例——`SPI1_SCK` → 实例 `SPI1`、信号 `SCK`。
按**实例**而不是类别分组是关键：SPI1 与 SPI2 的引脚完全不重叠，
按"SPI"聚合反而没法用。数据里 86 个复用功能归成 14 个实例。

每个信号下列出全部可选引脚，并用颜色区分**默认引脚**（绿，直接用）
与**需重映射**（橙，要先调 `GPIO_PinRemapConfig`）。
SPI1 的视图因此长这样：

```
SCK  → PA5（默认）  |  PB3（需重映射 + 配置说明）
MISO → PA6（默认）  |  PB4（需重映射 + 配置说明）
MOSI → PA7（默认）  |  PB5（需重映射 + 配置说明）
NSS  → PA4（默认）  |  PA15（需重映射 + 配置说明）
```

**顺带补上的数据缺口**：写测试时发现 21 个"需重映射"的复用功能里，
**只有 4 个写了配置说明**，其余 17 个只标了"需重映射"却不说调哪个宏。
用户看到"需重映射"却不知道该做什么，等于没说。已在
`data/zh_overlay/pinout_notes.json` 里补齐全部 21 条具体配置
（如 PB3 的 SPI1_SCK 要同时关 JTAG 和开 SPI1 重映射）。
新增两条守门人测试：需重映射的功能必须带说明，且说明里必须出现
`GPIO_PinRemapConfig` 之类的具体宏名。

## 阶段 8：编译错误速查

15 条错误、4 个分类（编译 / 链接 / 下载 / 运行时）、4 种工具链全覆盖。

**搜索框按"报错现象"设计**

这一页的搜索框与全局搜索是两回事：用户遇到问题时手上有的是一段
编译器输出，所以这里的匹配范围刻意覆盖**报错原文**
（`messageSample` 全文 + `messagePatterns` 片段），此外才是中文标题、
解释与标签。粘 `L6218E`、`undefined reference`、`cannot open` 都能直接命中。

命中报错原文时，列表项里会**额外显示命中的那一行原文**，
让用户确认"就是这条"，而不是只看到一条中文标题就点进去。

**三层筛选**：分类 → 工具链 → 关键词，逐层收窄。
分类筛选的角标数字是**按当前工具链与关键词动态计算**的，
所以筛选后角标会跟着变，不会出现"显示 6 条、点进去只有 1 条"的矛盾。

**工具链显示中文**：数据里存的是 `keil` / `gcc-arm` / `st-link` / `generic`，
直接显示英文对不熟悉的人没意义（`generic` 尤其费解），
在 `CompileError.toolchainZh` 里统一翻译，避免界面各处自己拼字符串。

**这一页最有价值的测试**是「每条错误至少能被自己的一个原文片段命中」——
它保证 15 条都**可被检索到**。文案写得再好，如果用户手上的报错搜不到，
这一页就等于不存在。

## 阶段 9：打磨与打包

### 设置持久化

主题模式、代码字号、首页"仅显示本型号支持的外设"三项存
`shared_preferences`（`lib/data/settings_store.dart`）。

两个细节：
- **读取时也要夹边界**。字号从存储读出来时同样走 `clampFontSize`，
  因为 prefs 里可能被写进 999（手改文件、旧版本 bug）。不夹的话
  用 999pt 渲染代码块会把布局撑爆。
- **读取失败退回默认值而不是抛异常**。设置读不出来不该让 App 起不来。

顺带把首页的"仅显示支持的外设"开关也放进了设置页（两处改同一个值）。

### 应用图标与启动图

不引入 `flutter_launcher_icons`（要联网拉包），改为
`tools/make_icons.py` 用 Pillow 直接画：蓝色渐变底 + 白色芯片轮廓
（方框 + 四边各 3 根引脚 + 中心方块）。同时生成：

- 5 个密度的传统启动图标（48~192px）
- 自适应图标的前景层（透明底，芯片只占 38%，系统裁成任何形状都不会切到图案）
  与背景层（纯渐变）
- 启动图（`drawable-nodpi/splash_logo.png`，两份 `launch_background.xml` 都引用）

图标不用文字：缩到 48px 时文字会糊成一团。

### release 签名

`tools/make_keystore.ps1` 生成密钥库并写 `android/key.properties`。
两者都已在 `.gitignore` 里，不进版本库。

**没有密钥库时回退到 debug 签名**，这样别人拿到代码也能
`flutter build apk --release` 验证功能，只是构建日志里会明确打出
"仅供本机验证，不可分发"。

这一步踩了两个坑，都记在脚本注释里：

1. **`storeFile` 的解析基准**。`file()` 默认相对**模块目录**（`android/app/`），
   而密钥库在 `android/` 下，直接用会报 "file ... doesn't exist"。
   改成 `rootProject.file(...)` 显式相对根项目解析。
2. **`key.properties` 必须是无 BOM 的 UTF-8**。PowerShell 5.1 的
   `Set-Content -Encoding UTF8` 会写 BOM，Java 的 `Properties.load`
   把 BOM 当成第一个键名的一部分，读到的是 `\uFEFFstorePassword`，
   于是 Gradle 报 "SigningConfig release is missing required property
   storePassword"。改用 .NET API 显式指定 `UTF8Encoding($false)`。

确认签名真的生效（而不是悄悄用了 debug key）：

```powershell
apksigner verify --print-certs build\app\outputs\flutter-apk\app-release.apk
# Signer #1 certificate DN: CN=STM32 SPL Helper, ...
```

### 打包相关的静态校验

`test/settings_test.dart` 除了设置持久化的往返测试，还校验了若干
"错了要到构建或装机时才发现"的事实：各密度图标存在且非空、
自适应图标的前景/背景层齐全、两份 `launch_background.xml` 都引用了启动图、
`pubspec.yaml` 的版本号与 `lib/utils/app_info.dart` 的 `appVersion` 一致、
`AndroidManifest` 的应用名与 `appName` 一致。

## 测试

```powershell
flutter test    # 275 个测试
```

| 文件 | 内容 |
|---|---|
| `test/models_test.dart` | 模型的宽松解析与容错、**跳转判定与返回值摘要的回归测试** |
| `test/keyword_test.dart` | 符号匹配与 C 词法分析 |
| `test/data_integration_test.dart` | 用**真实生成的数据**验证跳转无死链、首屏可搜、寄存器能匹配、引脚正确、中文完整、编译错误齐全、**符号 id 索引完整** |
| `test/search_test.dart` | **搜索历史**的去重/上限/持久化、**高亮**分段与元字符安全、类型分组统计，以及**用真实数据渲染真实搜索页的端到端测试** |
| `test/user_data_test.dart` | **收藏/笔记/最近查看**的 CRUD、去重、上限裁剪、`ItemRef` 主键往返、Markdown 导出拼装 |
| `test/pinout_test.dart` | **LQFP48 封装几何**（逆时针引脚号方向的坐标断言）、引脚分类、按功能反查、排布图在 360/320dp 下不溢出 |
| `test/peripheral_pin_test.dart` | **按外设看引脚**：实例分组（SPI1/SPI2 不混）、信号与引脚映射、默认 vs 重映射、**重映射说明完整性守门人** |
| `test/compile_error_test.dart` | 15 条错误的数据完整性、**按报错原文的可检索性**、三层筛选组合、工具链中文名、窄屏不溢出 |
| `test/settings_test.dart` | **设置持久化往返**（含越界夹回、脏数据容错）、派生 provider、**打包资源静态校验**、版本一致性 |
| `test/layout_test.dart` | **真机宽度（360dp）下渲染全部 488 个函数**，断言不溢出、函数名不竖排 |

`layout_test.dart` 是这次修复的关键：默认测试视口是 800×600，比手机宽得多，
旧代码在那个宽度下**不会**溢出，普通测试抓不到这个 bug。所以测试里显式把视口
设成 360dp 与 320dp，并断言函数名宽度 > 60dp、高度 < 40dp。

## 离线保证（已实测验证）

运行 `python tools/check_offline.py --apk <apk路径>` 可一键自检，当前 11 项全通过。

三道防线：

1. **AndroidManifest 不声明 INTERNET 权限**。Android 上没有该权限时任何 socket
   连接都会抛 `SecurityException`，这是运行期硬保证。release APK 已用 `aapt2`
   实测确认无此权限。
2. **`usesCleartextTraffic=false` + `networkSecurityConfig` 全禁明文流量**。
3. **源码级自检**：`lib/` 非注释代码中无任何网络 API 引用，pubspec 直接依赖
   不含任何网络包。

关于 `share_plus` 传递引入 `url_launcher_*`：那是桌面/Web 平台的实现，
**Android 构建不注册也不编译**（已检查 APK 无相关类）。详见 `docs/dependencies.md`。

## 环境

| 组件 | 版本 | 路径 |
|---|---|---|
| Flutter | 3.47.7 stable | `D:\Android Studio\Flutter\flutter_windows_3.47.7-stable\flutter` |
| Dart | 3.13.5 | 同上 |
| JDK | 17.0.12 LTS | `D:\Jave` |
| Android SDK | build-tools 36.0.0 | `<ANDROID_SDK>` |
| NDK | 28.2.13676358 | 同上 |

Python 脚本用 DSH 自带运行时：
`<PYTHON>`

环境配置详情与回滚方法见 `docs/环境配置说明.md`。

## 数据源

| 用途 | 路径 |
|---|---|
| SPL V3.5.0 库（规范布局） | `<SPL_ROOT>` |
| SPL V3.5.0 库（Keil 扁平布局，脚本兼容） | `D:\32 keil project\2-1stm32工程模版` |
| 引脚定义表（LQFP48） | `<PINOUT_XLSX>` |

## 数据来源声明

库函数原型与英文注释来自 ST 官方 STM32F10x 标准外设库 V3.5.0，版权归
STMicroelectronics 所有。本项目仅用于个人学习查阅，不分发库源码本身，
只分发解析后的结构化数据。

引脚复用数据来自本地引脚定义表（DS5319 Table 5 的转录），当前
`verified: false`，**尚未逐条对照数据手册核对**，APP 引脚页顶部常驻提示。
